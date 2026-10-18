import { fileIo } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { _QhState } from '../../entryability/AppState';
import { appSettings } from '../entity/SettingsModel';
import { adBlockSubsStore } from './AdBlockSubs';
import { createLogger } from './Logger';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { SitePolicy, siteSettingsVM, SiteSettingsViewModel } from '../../viewmodel/SiteSettingsViewModel';

const logger = createLogger('AdBlockEngine')

/**
 * 广告拦截（ArkWeb 原生 AdsBlock 引擎托管）：
 * - 「内建规则」开关控制系统 Web 组件云端下发的内置 easylist 规则：
 *   开 → setAdsBlockRules(file, false)，云端内建与自定义规则共存；
 *   关 → setAdsBlockRules(file, true)，仅用自定义 + 订阅规则
 * - 自定义 + 订阅（easylist 格式）合并写入沙箱文件交内核解析拦截；
 *   网络拦截与 ## 元素隐藏均由内核原生完成，不走 onInterceptRequest
 * - 哈希守卫（内容 + replace 标记）：未变化不重复设置，利用内核持久化避免冷启动重复编译
 * - Web 实例级开关由 TabWeb 调 controller.enableAdsBlock 控制（站点策略）
 */
export class AdBlockEngine {

  /** 每条被拦截请求的预估节省流量（无法得知实际响应大小，按 URL 特征差异化估算） */
  static readonly ESTIMATED_BYTES_PER_AD: number = 16 * 1024

  /** 追踪像素/打点类关键词（命中按 1KB 估算） */
  private static readonly PIXEL_KEYWORDS: string[] = [
    '1x1', 'pixel', 'beacon', 'analytics', 'collect', 'track', 'telemetry', 'statistic', 'ping'
  ]

  /** 媒体/视频后缀（按 300KB 估算） */
  private static readonly MEDIA_EXTS: string[] = ['.mp4', '.m3u8', '.flv', '.webm', '.avi', '.mov', '.m4v']

  /** 图片后缀（按 30KB 估算） */
  private static readonly IMAGE_EXTS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.svg', '.ico']

  /**
   * 按资源类型预估一条被拦截请求的响应大小：
   * 追踪像素 1KB / 媒体 300KB / 图片 30KB / 脚本 15KB / 其他 16KB
   */
  static estimateBytes(url: string): number {
    // 去查询参数与锚点后取路径
    const noQuery: string = url.split('?')[0].split('#')[0]
    const lower: string = noQuery.toLowerCase()
    for (const kw of AdBlockEngine.PIXEL_KEYWORDS) {
      if (lower.includes(kw)) {
        return 1024
      }
    }
    for (const ext of AdBlockEngine.MEDIA_EXTS) {
      if (lower.endsWith(ext)) {
        return 300 * 1024
      }
    }
    for (const ext of AdBlockEngine.IMAGE_EXTS) {
      if (lower.endsWith(ext)) {
        return 30 * 1024
      }
    }
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 15 * 1024
    }
    return AdBlockEngine.ESTIMATED_BYTES_PER_AD
  }

  /** 同步中标记（防重入，期间触发的同步排队执行） */
  private syncing: boolean = false
  private syncQueued: boolean = false

  /** 自定义规则沙箱文件 */
  static customRulesFile(): string {
    return `${_QhState.Context.filesDir}/adblock/custom_rules.txt`
  }

  /** 合并规则文件（传给 AdsBlockManager 的 easylist 规则文件） */
  static webRulesFile(): string {
    return `${_QhState.Context.filesDir}/adblock/web_rules.txt`
  }

  /** 最近一次已应用的规则内容哈希标记文件 */
  private static webRulesHashFile(): string {
    return `${_QhState.Context.filesDir}/adblock/web_rules.hash`
  }

  /** 启动时初始化：装载规则到内核（订阅加载完成经回调再次同步） */
  init(): void {
    this.syncToWebEngine()
    // 订阅规则下载/更新成功后自动同步到内核
    adBlockSubsStore.onRulesChanged = (): void => {
      this.syncToWebEngine()
    }
  }

  /** 读取自定义规则文件内容（编辑页回显用） */
  loadCustomRulesSync(): string {
    return this.readTextFile(AdBlockEngine.customRulesFile())
  }

  /** 保存自定义规则并同步到内核 */
  async saveCustomRules(text: string): Promise<void> {
    try {
      this.writeTextFile(AdBlockEngine.customRulesFile(), text)
      await this.syncToWebEngine()
    } catch (e) {
      logger.error(`saveCustomRules 失败: ${e}`)
    }
  }

  /**
   * 合并自定义 + 订阅规则写入沙箱文件并交给 ArkWeb 原生 AdsBlock 引擎：
   * 「内建规则」开 → replace=false（系统云端内置规则与自定义共存）；
   * 关 → replace=true（禁用云端内置规则，仅用自定义规则）。
   * 哈希与上次一致（含 replace 标记）时跳过（内核持久化配置，冷启动无需重复设置）
   */
  async syncToWebEngine(): Promise<void> {
    if (this.syncing) {
      this.syncQueued = true
      return
    }
    this.syncing = true
    try {
      const t0: number = Date.now()
      const parts: string[] = []
      parts.push(this.loadCustomRulesSync())
      for (const sub of adBlockSubsStore.subs) {
        if (!sub.enabled) {
          continue
        }
        parts.push(this.readTextFile(adBlockSubsStore.rulesPath(sub)))
        await AdBlockEngine.yieldToUI()
      }
      let content: string = parts.join('\n')
      if (content.trim() === '') {
        // 空内容时写注释行，保证文件非空可解析
        content = '!'
      }
      const replace: boolean = !appSettings.ad_block_builtin
      const hash: string = `${AdBlockEngine.hashStr(content)}_${replace ? '1' : '0'}`
      if (hash === this.readTextFile(AdBlockEngine.webRulesHashFile()).trim()) {
        logger.info(`syncToWebEngine 规则未变化，跳过（长度 ${content.length}）`)
        return
      }
      this.writeTextFile(AdBlockEngine.webRulesFile(), content)
      webview.AdsBlockManager.setAdsBlockRules(AdBlockEngine.webRulesFile(), replace)
      this.writeTextFile(AdBlockEngine.webRulesHashFile(), hash)
      logger.info(`syncToWebEngine 规则已更新: 哈希 ${hash} replace ${replace} 长度 ${content.length} 耗时 ${Date.now() - t0}ms`)
    } catch (e) {
      logger.error(`syncToWebEngine 失败: ${e}`)
    } finally {
      this.syncing = false
      if (this.syncQueued) {
        this.syncQueued = false
        this.syncToWebEngine()
      }
    }
  }

  /** 站点策略 → 该 Web 实例广告拦截开关 */
  static policyOn(p: SitePolicy): boolean {
    return p.adBlock === 'app' ? appSettings.ad_block_enabled : p.adBlock === 'on'
  }

  /** 全局开关变化后，向所有已创建 Web 实例重新应用 enableAdsBlock */
  static async applyEnableToAll(): Promise<void> {
    for (const tab of tabsVM.tabs) {
      const host: string = SiteSettingsViewModel.hostOf(tab.url)
      if (host === '') {
        continue
      }
      try {
        const p: SitePolicy = await siteSettingsVM.resolvePolicy(host)
        const c = tab.controller
        if (c !== null && c !== undefined) {
          c.enableAdsBlock(AdBlockEngine.policyOn(p))
        }
      } catch (e) {
        logger.error(`applyEnableToAll 失败: ${e}`)
      }
    }
  }

  /** 读文本文件（不存在或失败返回空串） */
  private readTextFile(path: string): string {
    try {
      if (fileIo.accessSync(path)) {
        return fileIo.readTextSync(path)
      }
    } catch (e) {
      logger.error(`readTextFile 失败: ${e}`)
    }
    return ''
  }

  /** 写文本文件（目录不存在时自动创建） */
  private writeTextFile(path: string, text: string): void {
    const dir: string = path.substring(0, path.lastIndexOf('/'))
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true)
    }
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, text)
    } finally {
      fileIo.closeSync(file)
    }
  }

  /** 32 位滚动哈希（规则变化检测用，非加密） */
  private static hashStr(s: string): number {
    let h: number = 5381
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) + h + s.charCodeAt(i)) | 0
    }
    return h >>> 0
  }

  /** 让出主线程一拍（合并大订阅文件间隙给渲染任务插队） */
  private static yieldToUI(): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout((): void => {
        resolve()
      }, 0)
    })
  }
}

export const adBlockEngine: AdBlockEngine = new AdBlockEngine()
