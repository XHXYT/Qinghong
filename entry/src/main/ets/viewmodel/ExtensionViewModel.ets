import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { _QhState } from '../entryability/AppState';
import { createLogger } from '../common/utils/Logger';
import { toastUtil } from '../common/utils/ToastUtils';
import { ExtensionEngine, ExtManifestModel, ExtContentScript, CrxTarget, ExtLocaleMessage } from '../common/utils/ExtensionEngine';
import { ExtensionResources, EXT_RES_HOST, EXT_SCHEME_PREFIX } from '../common/utils/ExtensionResources';
import { ChromeShim, ExtStorageGetRaw, ExtStorageSetRaw, ExtStorageRemoveRaw, ExtStorageClearRaw,
  ExtSendMsgRaw, ExtRespondRaw, ExtSendMsgBgRaw, ExtTabQueryRaw, ExtTabSendMsgRaw, ExtTabCreateRaw,
  ExtTabUpdateRaw, ExtExecuteScriptRaw,
  ExtNotifyRaw, ExtStoreInstallRaw, ExtPortConnectRaw, ExtPortMsgRaw, ExtPortDisconnectRaw } from '../common/utils/ChromeShim';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { HttpDownloader, StreamOptions } from '../common/utils/HttpDownloader';
import { ExtensionDao } from '../common/utils/database/impl/ExtensionDao';
import { ExtensionValueDao } from '../common/utils/database/impl/ExtensionValueDao';
import ExtensionInfo from '../common/entity/ExtensionInfo';
import { appSettings } from '../common/entity/SettingsModel';
import { TabInfo, tabsVM } from './TabsViewModel';

const logger = createLogger('ExtensionVM')

/**
 * 消息响应挂起项：响应到达（extRespond）后派发回发起方 Web
 */
class ExtPendingRespond {
  readonly target: webview.WebviewController | null
  readonly cbId: number

  constructor(target: webview.WebviewController | null, cbId: number) {
    this.target = target
    this.cbId = cbId
  }
}

/**
 * Port（runtime.connect 长连接）通道：portId → 两端控制器路由；
 * 消息/断开按 portId 找对端投递
 */
class ExtPortRoute {
  readonly extId: string
  /** 发起端（runtime.connect 一侧） */
  readonly aSide: webview.WebviewController
  /** 接收端（runtime.onConnect 触发一侧） */
  readonly bSide: webview.WebviewController

  constructor(extId: string, aSide: webview.WebviewController, bSide: webview.WebviewController) {
    this.extId = extId
    this.aSide = aSide
    this.bSide = bSide
  }
}

/**
 * 浏览器扩展仓库 + chrome.* 兼容引擎（应用层模拟，非内核扩展）：
 * - 扩展元数据存 qinghong.db extension 表，chrome.storage 值存 extension_value 表；
 * - CRX/ZIP 安装：下载 → CRX 头定位 → zlib 解包到沙箱 → manifest 解析（含 i18n）；
 * - content_scripts：document_start 经 javaScriptOnDocumentStart 注入，
 *   document_end/document_idle 在 onPageEnd 按 URL 匹配注入；
 * - chrome.storage 经 window.__qhNative.gmRequest 桥接原生（异步，无值烘焙）。
 */
@ObservedV2
export class ExtensionViewModel {
  /** 已安装扩展 */
  @Trace extensions: ExtensionInfo[] = []

  private db: ExtensionDao | null = null
  private valueDb: ExtensionValueDao | null = null

  /** 沙箱代码缓存：extId#csIndex → 注入代码 */
  private sandboxCache: Map<string, string> = new Map()

  /** manifest 解析缓存：extId → 清洗模型 */
  private manifestCache: Map<string, ExtManifestModel> = new Map()

  /** storage 值内存缓存：extId → (key → JSON 原文) */
  private valuesCache: Map<string, Map<string, string>> = new Map()

  /** 值缓存已装载的扩展 */
  private valuesLoaded: Set<string> = new Set()

  /** background 隐藏 Web 宿主：extId → 控制器 */
  private bgHosts: Map<string, webview.WebviewController> = new Map()

  /** 消息响应挂起表：respondId → 派发目标 */
  private pendingResponds: Map<number, ExtPendingRespond> = new Map()

  /** 响应序号 */
  private respondSeq: number = 0

  /** background 注入代码缓存：extId → 代码（'' = 无 background） */
  private bgCodeCache: Map<string, string> = new Map()

  /** executeScript 注入代码缓存：extId#files → 代码 */
  private executeScriptCache: Map<string, string> = new Map()

  /** popup 面板打开的扩展（null = 关闭；驱动 ExtPopupView 挂载） */
  @Trace popupExt: ExtensionInfo | null = null

  /** popup 面板自适应背景色（探测自页面实际背景；'' = 未探测，用系统默认） */
  @Trace popupBg: string = ''

  /** popup 开关同步回调：Index 以 @Local 布尔驱动 bindSheet isShow（文档标准模式） */
  onPopupVisibilityChanged: ((open: boolean) => void) | null = null

  /** popup 面板宿主控制器 */
  private popupHost: webview.WebviewController | null = null

  /** popup 注入代码缓存：extId → 代码 */
  private popupCodeCache: Map<string, string> = new Map()

  /** 商店直装浮层注入代码缓存 */
  private storeCodeCache: string = ''

  /** Port 通道注册表：portId → 路由（popup/内容脚本 ↔ bg 双向） */
  private portRoutes: Map<string, ExtPortRoute> = new Map()

  private edgeStoreCodeCache: string = ''

  /** crxsoso.com 站点注入代码缓存 */
  private crxsosoCodeCache: string = ''

  /** 进行中的安装任务（防并发重入） */
  private installing: boolean = false

  /** 商店直装全流程进行中（含下载阶段；防连点并发互相顶掉） */
  private storeInstalling: boolean = false

  constructor() {
    // 标签生命周期事件源挂钩：TabsViewModel → chrome.tabs.onCreated/onUpdated/onActivated/onRemoved
    tabsVM.tabEventSink = (event: string, tab: TabInfo): void => {
      this.onTabLifecycleEvent(event, tab)
    }
  }

  private getDB(): ExtensionDao {
    if (!this.db) {
      this.db = new ExtensionDao(_QhState.Context)
    }
    return this.db
  }

  private getValueDB(): ExtensionValueDao {
    if (!this.valueDb) {
      this.valueDb = new ExtensionValueDao(_QhState.Context)
    }
    return this.valueDb
  }

  /** 启动时装载全部扩展 */
  async loadAll(): Promise<void> {
    try {
      this.extensions = await this.getDB().queryAll()
    } catch (e) {
      logger.error(`loadAll: ${e}`)
    }
  }

  // ==================== 安装/卸载 ====================

  /**
   * 从链接安装：CRX/ZIP 直链、Chrome Web Store / Edge Add-ons 详情页
   * @param url 安装来源链接
   * @param extIdHint 32 位扩展 ID 提示（crxsoso 等站点路径 ID，保 ID 稳定可覆盖安装；空则按 URL 推导）
   */
  async installFromUrl(url: string, extIdHint: string = ''): Promise<boolean> {
    const target: CrxTarget = ExtensionEngine.resolveCrxUrl(url)
    if (target.crxUrl === '') {
      logger.warn(`installFromUrl: 无法解析 CRX 下载链接: ${url}`)
      return false
    }
    const bytes: Uint8Array | null = await this.downloadBytes(target.crxUrl)
    if (bytes === null) {
      return false
    }
    return this.installFromBytes(bytes, extIdHint !== '' ? extIdHint : target.extIdHint, url)
  }

  /**
   * 从本地文件导入（.crx / .zip，≤50MB）
   */
  async importFromUri(uri: string): Promise<boolean> {
    try {
      const src: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const stat: fileIo.Stat = fileIo.statSync(src.fd)
        if (stat.size <= 0 || stat.size > 50 * 1024 * 1024) {
          return false
        }
        const buf: ArrayBuffer = new ArrayBuffer(stat.size)
        fileIo.readSync(src.fd, buf)
        return await this.installFromBytes(new Uint8Array(buf), '', '')
      } finally {
        fileIo.closeSync(src)
      }
    } catch (e) {
      logger.error(`importFromUri: ${e}`)
      return false
    }
  }

  /**
   * 从字节流安装：CRX 头定位 → 解包 → manifest 解析（含 i18n）→ 入库（同 ID 覆盖）
   */
  async installFromBytes(bytes: Uint8Array, extIdHint: string, updateUrl: string): Promise<boolean> {
    if (this.installing) {
      return false
    }
    this.installing = true
    try {
      const zipOffset: number = ExtensionEngine.crxZipOffset(bytes)
      if (zipOffset < 0) {
        logger.warn('installFromBytes: 非法的 CRX/ZIP')
        return false
      }
      const extId: string = extIdHint !== '' ? extIdHint : ExtensionEngine.randomExtId()
      const rootDir: string = `${_QhState.Context.filesDir}/extensions`
      const extDir: string = `${rootDir}/${extId}`
      // 覆盖安装：清理旧目录
      ExtensionViewModel.removeDirQuiet(extDir)
      ExtensionViewModel.ensureDir(rootDir)
      ExtensionViewModel.ensureDir(extDir)
      // ZIP 部分写临时文件后解压
      const zipPart: Uint8Array = bytes.subarray(zipOffset)
      const outBuf: ArrayBuffer = new ArrayBuffer(zipPart.byteLength)
      new Uint8Array(outBuf).set(zipPart)
      const tmpZip: string = `${rootDir}/_tmp_${Date.now()}.zip`
      const f: fileIo.File = fileIo.openSync(tmpZip,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(f.fd, outBuf)
      fileIo.closeSync(f)
      try {
        await zlib.decompressFile(tmpZip, extDir)
      } finally {
        ExtensionViewModel.unlinkQuiet(tmpZip)
      }
      // manifest 解析
      const manifestJson: string =
        ExtensionEngine.readTextFile(`${extDir}/manifest.json`, 2 * 1024 * 1024)
      if (manifestJson === '') {
        logger.warn('installFromBytes: manifest.json 缺失')
        ExtensionViewModel.removeDirQuiet(extDir)
        return false
      }
      const model: ExtManifestModel | null = ExtensionEngine.parseManifest(manifestJson)
      if (model === null) {
        ExtensionViewModel.removeDirQuiet(extDir)
        return false
      }
      // i18n 解析（name/description __MSG_，Chrome 语义：UI 语言优先，回退 default_locale）
      const messages: Map<string, ExtLocaleMessage> = ExtensionEngine.readLocaleMessages(extDir,
        ExtensionEngine.chromeUiLocale(), model.defaultLocale !== '' ? model.defaultLocale : 'en')
      const name: string = ExtensionEngine.resolveI18nValue(model.name, messages)
      const desc: string = ExtensionEngine.resolveI18nValue(model.description, messages)
      // 入库（同 extId 覆盖）
      const existing: ExtensionInfo | null = await this.getDB().queryByExtId(extId)
      const info: ExtensionInfo = existing !== null ? existing : new ExtensionInfo()
      info.extId = extId
      info.name = name !== '' ? name : model.name
      info.version = model.version
      info.description = desc
      info.manifestVersion = model.manifestVersion
      info.enabled = true
      info.path = `extensions/${extId}`
      info.manifest = manifestJson
      info.updateUrl = updateUrl
      info.updateTime = Date.now()
      if (existing === null) {
        info.createTime = Date.now()
        await this.getDB().insert(info)
      } else {
        await this.getDB().update(info)
      }
      this.sandboxCache.clear()
      this.manifestCache.clear()
      this.bgCodeCache.clear()
      this.executeScriptCache.clear()
      this.popupCodeCache.clear()
      // 覆盖安装：popup 打开中同扩展刷新，关闭避免旧面板引用旧代码
      if (this.popupExt !== null && this.popupExt.extId === extId) {
        this.closePopup()
      }
      await this.loadAll()
      logger.info(`installFromBytes: ${info.name} v${info.version} 安装成功`)
      return true
    } catch (e) {
      logger.error(`installFromBytes: ${e}`)
      return false
    } finally {
      this.installing = false
    }
  }

  /** 启用/禁用（重查列表驱动宿主/列表刷新；禁用中扩展的 popup 同步关闭） */
  async toggle(info: ExtensionInfo, enabled: boolean): Promise<void> {
    info.enabled = enabled
    await this.getDB().update(info)
    if (!enabled && this.popupExt !== null && this.popupExt.extId === info.extId) {
      this.closePopup()
    }
    await this.loadAll()
  }

  /** 卸载（连带 storage 值、Web origin DOM 存储与解包目录） */
  async deleteExt(info: ExtensionInfo): Promise<void> {
    if (info.id !== null) {
      await this.getDB().deleteById(info.id)
    }
    await this.getValueDB().clearByExt(info.extId)
    this.clearWebOriginStorage(info.extId)
    ExtensionViewModel.removeDirQuiet(`${_QhState.Context.filesDir}/${info.path}`)
    this.valuesCache.delete(info.extId)
    this.valuesLoaded.delete(info.extId)
    this.sandboxCache.clear()
    this.manifestCache.clear()
    this.bgCodeCache.clear()
    this.executeScriptCache.clear()
    this.popupCodeCache.clear()
    if (this.popupExt !== null && this.popupExt.extId === info.extId) {
      this.closePopup()
    }
    await this.loadAll()
  }

  /**
   * 清理扩展各 Web origin 的 DOM 存储（bg/popup/options 页的 localStorage/Web SQL 等）。
   * scheme 页与 legacy 虚拟域子域各为一个独立 origin；卸载后残留会让重装扩展读到旧状态。
   */
  private clearWebOriginStorage(extId: string): void {
    const origins: string[] = [
      `${EXT_SCHEME_PREFIX}${extId}`,
      `https://${extId}.${EXT_RES_HOST}`
    ]
    for (const o of origins) {
      try {
        webview.WebStorage.deleteOrigin(o)
      } catch (e) {
        logger.warn(`clearWebOriginStorage 跳过 ${o}: ${(e as BusinessError).message}`)
      }
    }
  }

  // ==================== 下载 ====================

  /**
   * 下载安装包字节（≤50MB）：
   * 走 HttpDownloader 流式管线（与「仅下载」同路：浏览器 UA + 代理分流 + 20 秒无数据看门狗快速失败），
   * 替代一次性 request——其 readTimeout 为请求总时长且响应有大小上限，crxsoso dlink 等境外源
   * 高丢包慢速（c2.crxsoso.com 为美国机房，直连丢包 60%+）极易超时；
   * 失败按已落盘字节 Range 断点续传重试（服务器不支持 Range 时自动从头重写），完成后整文件读回内存。
   */
  private async downloadBytes(url: string): Promise<Uint8Array | null> {
    const tmpPath: string = `${_QhState.Context.cacheDir}/ext_dl_${Date.now()}.tmp`
    try {
      for (let attempt = 0; attempt < 3; attempt++) {
        let offset: number = 0
        try {
          if (fileIo.accessSync(tmpPath)) {
            offset = fileIo.statSync(tmpPath).size
          }
        } catch (e) {
          offset = 0
        }
        const opts: StreamOptions = new StreamOptions()
        opts.startOffset = offset
        opts.resume = attempt > 0
        try {
          await HttpDownloader.downloadToFile(url, tmpPath, opts)
          const size: number = fileIo.statSync(tmpPath).size
          if (size <= 0) {
            // clients2 在扩展不可用或 prodversion 低于扩展要求时回 204 空响应
            logger.warn(`downloadBytes 空响应: ${url}`)
            return null
          }
          if (size > 50 * 1024 * 1024) {
            logger.warn(`downloadBytes 超限: ${url}`)
            return null
          }
          const file: fileIo.File = fileIo.openSync(tmpPath, fileIo.OpenMode.READ_ONLY)
          try {
            const buf: ArrayBuffer = new ArrayBuffer(size)
            fileIo.readSync(file.fd, buf)
            return new Uint8Array(buf)
          } finally {
            fileIo.closeSync(file)
          }
        } catch (e) {
          logger.warn(`downloadBytes 第 ${attempt + 1} 次失败: ${url}, ${(e as BusinessError).message}`)
        }
      }
      return null
    } finally {
      try {
        if (fileIo.accessSync(tmpPath)) {
          fileIo.unlinkSync(tmpPath)
        }
      } catch (e) {
        logger.debug(`downloadBytes 清理临时文件失败: ${(e as BusinessError).message}`)
      }
    }
  }

  // ==================== 注入代码生成 ====================

  /**
   * document-start 注入项：每个启用的 document_start content_script 一项，
   * 每项携带 ext core（幂等安装——各项 scriptRules 不同，某项命中的页面未必命中携 core 的首项），
   * scriptRules 用 matches 规范化预过滤
   */
  docStartScriptItems(): ScriptItem[] {
    // 扩展总开关关闭：不注入任何扩展内容脚本
    if (!appSettings.extension_enabled) {
      return []
    }
    const items: ScriptItem[] = []
    for (const ext of this.extensions) {
      if (!ext.enabled) {
        continue
      }
      const model: ExtManifestModel | null = this.manifestOf(ext)
      if (model === null) {
        continue
      }
      for (let i: number = 0; i < model.contentScripts.length; i++) {
        const cs: ExtContentScript = model.contentScripts[i]
        if (cs.runAt !== 'document_start' || (cs.js.length === 0 && cs.css.length === 0)) {
          continue
        }
        const code: string = ChromeShim.buildCoreJs() + this.sandboxOf(ext, i, cs, model)
        items.push({
          script: code,
          scriptRules: ExtensionViewModel.rulesOf(cs.matches)
        })
      }
    }
    return items
  }

  /**
   * document-start 注入项：商店站页面原生安装按钮接管（crxsoso.com）。
   * 页面原生「安装到浏览器」在 dlink 就绪后即可点击，而 PC 布局广告资源重，
   * onPageEnd（window.load）可能晚于用户点击（PC UA 实证：点击先于注入 →
   * 走原生下载进确认弹窗）——提前到文档开始注入保证监听先于按钮可用。
   * scriptRules 精确命中 www.crxsoso.com origin，脚本内 hostname + 路由双重守卫。
   */
  storePageStartItems(): ScriptItem[] {
    // 扩展总开关关闭：不注入商店页按钮接管
    if (!appSettings.extension_enabled) {
      return []
    }
    if (this.crxsosoCodeCache === '') {
      this.crxsosoCodeCache = ChromeShim.buildCrxsosoInstallJs()
    }
    return [{
      script: this.crxsosoCodeCache,
      scriptRules: ['https://www.crxsoso.com']
    }]
  }

  /**
   * document-start 注入项：扩展页面标签页（虚拟域打开的 post-install/options 等）
   * 注入宿主沙箱（popup 同款，scriptUrls: []，页面 HTML 自行加载脚本）；
   * 每项自带 core，scriptRules 只命中本扩展虚拟域（子域 + 旧路径格式兼容）
   */
  extPageScriptItems(): ScriptItem[] {
    // 扩展总开关关闭：扩展页面标签页不注入宿主沙箱（与 popup/后台宿主同步停用）
    if (!appSettings.extension_enabled) {
      return []
    }
    const items: ScriptItem[] = []
    for (const ext of this.extensions) {
      if (!ext.enabled) {
        continue
      }
      const code: string = this.popupCodeOf(ext)
      if (code === '') {
        continue
      }
      items.push({
        script: code,
        // 全放行：ArkWeb scriptRules 对自定义协议（qinghong-extension://）实测不命中，
        // scheme 标签页收不到宿主沙箱（options/post-install 页 chrome.* undefined、页面空白）；
        // 精确性由宿主沙箱内 location.host === EXTID 守卫保证，普通页面注入后立即 return
        scriptRules: ['*']
      })
    }
    return items
  }

  /**
   * document-end/document_idle 注入代码：native 侧按 URL 匹配后拼接（onPageEnd 执行）
   */
  onPageEndCode(url: string): string {
    // 扩展总开关关闭：不注入任何扩展内容脚本
    if (!appSettings.extension_enabled) {
      return ''
    }
    let code: string = ''
    let coreIncluded: boolean = false
    for (const ext of this.extensions) {
      if (!ext.enabled) {
        continue
      }
      const model: ExtManifestModel | null = this.manifestOf(ext)
      if (model === null) {
        continue
      }
      for (let i: number = 0; i < model.contentScripts.length; i++) {
        const cs: ExtContentScript = model.contentScripts[i]
        if (cs.runAt === 'document_start' || (cs.js.length === 0 && cs.css.length === 0)) {
          continue
        }
        if (!ExtensionEngine.contentScriptMatches(url, cs)) {
          continue
        }
        if (!coreIncluded) {
          code += ChromeShim.buildCoreJs()
          coreIncluded = true
        }
        code += this.sandboxOf(ext, i, cs, model) + '\n'
      }
    }
    return code
  }

  /** manifest 解析缓存 */
  private manifestOf(ext: ExtensionInfo): ExtManifestModel | null {
    const cached: ExtManifestModel | undefined = this.manifestCache.get(ext.extId)
    if (cached !== undefined) {
      return cached
    }
    const model: ExtManifestModel | null = ExtensionEngine.parseManifest(ext.manifest)
    if (model !== null) {
      this.manifestCache.set(ext.extId, model)
    }
    return model
  }

  /** 单 content_script 沙箱代码（含 CSS/JS 文件读取，带缓存） */
  private sandboxOf(ext: ExtensionInfo, csIndex: number, cs: ExtContentScript, model: ExtManifestModel): string {
    const key: string = `${ext.extId}#${csIndex}`
    const cached: string | undefined = this.sandboxCache.get(key)
    if (cached !== undefined) {
      return cached
    }
    const extDir: string = `${_QhState.Context.filesDir}/${ext.path}`
    const locale: string = ExtensionEngine.chromeUiLocale()
    const messages: Map<string, ExtLocaleMessage> = ExtensionEngine.readLocaleMessages(extDir, locale,
      model.defaultLocale !== '' ? model.defaultLocale : 'en')
    const messagesJson: string = ExtensionEngine.messagesJson(messages)
    // CSS 文件
    let cssCode: string = ''
    for (const f of cs.css) {
      const css: string = ExtensionEngine.readTextFile(`${extDir}/${f}`, 1024 * 1024)
      if (css !== '') {
        cssCode += ChromeShim.cssInjectJs(css) + '\n'
      }
    }
    // JS 文件（同序共享作用域，对齐 Chrome content_scripts 同 isolated world 语义）
    let jsCode: string = ''
    for (const f of cs.js) {
      const code: string = ExtensionEngine.readTextFile(`${extDir}/${f}`, 5 * 1024 * 1024)
      if (code !== '') {
        jsCode += `/* ${f} */\n` + code + '\n;\n'
      }
    }
    const sandbox: string = ChromeShim.buildContentSandbox(ext.extId, ext.manifest, ext.name,
      ext.description, messagesJson, locale, cssCode, jsCode, cs.allFrames, cs.matches)
    this.sandboxCache.set(key, sandbox)
    return sandbox
  }

  /** matches → javaScriptOnDocumentStart 合法 scriptRules（'*' 全来源、精确 origin、
   *  模糊匹配 scheme 通配子域、自定义协议前缀四种合法形式）；
   *  规范依据 web.d.ts ScriptItem：裸 '*' host、'*' 通配 scheme、带路径通配均为非法，
   *  一条非法整组不生效（真机实证 http 任意 host 形式整组失效 → 内容沙箱从未注入）；
   *  收窄由沙箱内 Chrome match pattern 精确匹配兜底） */
  private static rulesOf(matches: string[]): string[] {
    const rules: string[] = []
    for (const m of matches) {
      for (const r of ExtensionViewModel.normalizeRule(m)) {
        if (rules.indexOf(r) < 0) {
          rules.push(r)
        }
      }
    }
    return rules.length > 0 ? rules : ['*']
  }

  /** 单条 Chrome match pattern → 0..n 条合法 scriptRule */
  private static normalizeRule(m: string): string[] {
    if (m === '<all_urls>') {
      return ['*']
    }
    const idx: number = m.indexOf('://')
    if (idx <= 0) {
      return []
    }
    const scheme: string = m.substring(0, idx)
    const rest: string = m.substring(idx + 3)
    const slash: number = rest.indexOf('/')
    const host: string = slash < 0 ? rest : rest.substring(0, slash)
    if (host === '*' || host === '') {
      // 任意 host（http://*/* 等）：无合法对应形式，退化为 '*'（全来源），沙箱内精确匹配收窄
      return ['*']
    }
    if (scheme === 'https' || scheme === 'http') {
      return [`${scheme}://${host}`]
    }
    if (scheme === '*') {
      return [`https://${host}`, `http://${host}`]
    }
    // 其他协议（file 等）：按规则 5 只支持协议前缀
    return [`${scheme}://`]
  }

  // ==================== chrome.storage 原生执行 ====================

  /** storage.get（keys：null=全部 / 字符串数组 / 带默认值对象） */
  extStorageGet(json: string, controller: webview.WebviewController | null): void {
    try {
      const raw: ExtStorageGetRaw = JSON.parse(json) as ExtStorageGetRaw
      if (typeof raw.extId !== 'string' || typeof raw.cbId !== 'number') {
        return
      }
      this.storageGet(raw.extId, raw.keysJson).then((resultJson: string): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', resultJson)
      }).catch((): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, 'storage error', '{}')
      })
    } catch (e) {
      logger.warn(`extStorageGet: ${e}`)
    }
  }

  private async storageGet(extId: string, keysJson: string): Promise<string> {
    await this.ensureValues(extId)
    const m: Map<string, string> | undefined = this.valuesCache.get(extId)
    const values: Map<string, string> = m === undefined ? new Map() : m
    let keysSpec: Object | null = null
    if (keysJson !== '' && keysJson !== 'null') {
      try {
        keysSpec = JSON.parse(keysJson) as Object
      } catch (e) {
        keysSpec = null
      }
    }
    let out: string = '{'
    let first: boolean = true
    const emit = (k: string, raw: string): void => {
      if (!first) {
        out += ','
      }
      out += JSON.stringify(k) + ':' + raw
      first = false
    }
    if (keysSpec === null) {
      values.forEach((raw: string, k: string): void => {
        emit(k, raw)
      })
    } else if (keysSpec instanceof Array) {
      const arr: Object[] = keysSpec
      for (let idx: number = 0; idx < arr.length; idx++) {
        const k: Object = arr[idx]
        if (typeof k === 'string') {
          const raw: string | undefined = values.get(k)
          if (raw !== undefined) {
            emit(k, raw)
          }
        }
      }
    } else if (typeof keysSpec === 'string') {
      const k: string = keysSpec
      const raw: string | undefined = values.get(k)
      if (raw !== undefined) {
        emit(k, raw)
      }
    } else if (typeof keysSpec === 'object') {
      const defaults: Record<string, Object> = keysSpec as Record<string, Object>
      const keys: string[] = Object.keys(defaults)
      for (const k of keys) {
        const raw: string | undefined = values.get(k)
        if (raw !== undefined) {
          emit(k, raw)
        } else {
          let dj: string = 'null'
          try {
            dj = JSON.stringify(defaults[k])
          } catch (e) {
            dj = 'null'
          }
          emit(k, dj)
        }
      }
    }
    return out + '}'
  }

  /** storage.set */
  extStorageSet(json: string, controller: webview.WebviewController | null): void {
    try {
      const raw: ExtStorageSetRaw = JSON.parse(json) as ExtStorageSetRaw
      if (typeof raw.extId !== 'string' || typeof raw.cbId !== 'number') {
        return
      }
      this.storageSet(raw.extId, raw.itemsJson).then((): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', 'null')
      }).catch((): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, 'storage error', 'null')
      })
    } catch (e) {
      logger.warn(`extStorageSet: ${e}`)
    }
  }

  private async storageSet(extId: string, itemsJson: string): Promise<void> {
    await this.ensureValues(extId)
    const m: Map<string, string> | undefined = this.valuesCache.get(extId)
    const values: Map<string, string> = m === undefined ? new Map() : m
    let items: Record<string, Object> = {}
    try {
      items = JSON.parse(itemsJson === '' ? '{}' : itemsJson) as Record<string, Object>
    } catch (e) {
      items = {}
    }
    const keys: string[] = Object.keys(items)
    let changesJson: string = '{'
    let chgFirst: boolean = true
    for (const k of keys) {
      let vj: string = 'null'
      try {
        vj = JSON.stringify(items[k])
      } catch (e) {
        vj = 'null'
      }
      const oldRaw: string | undefined = values.get(k)
      if (!chgFirst) {
        changesJson += ','
      }
      changesJson += JSON.stringify(k) + ':{' + '"newValue":' + vj
      if (oldRaw !== undefined) {
        changesJson += ',"oldValue":' + oldRaw
      }
      changesJson += '}'
      chgFirst = false
      values.set(k, vj)
      this.getValueDB().upsert(extId, k, vj).catch((e: BusinessError): void => {
        logger.error(`storageSet 持久化失败: ${e.message}`)
      })
    }
    this.broadcastStorageChange(extId, changesJson + '}')
  }

  /** storage.remove */
  extStorageRemove(json: string, controller: webview.WebviewController | null): void {
    try {
      const raw: ExtStorageRemoveRaw = JSON.parse(json) as ExtStorageRemoveRaw
      if (typeof raw.extId !== 'string' || typeof raw.cbId !== 'number') {
        return
      }
      this.storageRemove(raw.extId, raw.keysJson).then((): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', 'null')
      }).catch((): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, 'storage error', 'null')
      })
    } catch (e) {
      logger.warn(`extStorageRemove: ${e}`)
    }
  }

  private async storageRemove(extId: string, keysJson: string): Promise<void> {
    await this.ensureValues(extId)
    const m: Map<string, string> | undefined = this.valuesCache.get(extId)
    if (m === undefined) {
      return
    }
    let keys: string[] = []
    try {
      const spec: Object = JSON.parse(keysJson === '' ? 'null' : keysJson) as Object
      if (spec instanceof Array) {
        keys = spec
      } else if (typeof spec === 'string') {
        keys = [spec]
      }
    } catch (e) {
      keys = []
    }
    let changesJson: string = '{'
    let chgFirst: boolean = true
    for (const k of keys) {
      if (typeof k !== 'string') {
        continue
      }
      const oldRaw: string | undefined = m.get(k)
      if (oldRaw === undefined) {
        continue
      }
      if (!chgFirst) {
        changesJson += ','
      }
      changesJson += JSON.stringify(k) + ':{' + '"oldValue":' + oldRaw + '}'
      chgFirst = false
      m.delete(k)
      this.getValueDB().deleteByKey(extId, k).catch((): void => {
      })
    }
    this.broadcastStorageChange(extId, changesJson + '}')
  }

  /** storage.clear */
  extStorageClear(json: string, controller: webview.WebviewController | null): void {
    try {
      const raw: ExtStorageClearRaw = JSON.parse(json) as ExtStorageClearRaw
      if (typeof raw.extId !== 'string' || typeof raw.cbId !== 'number') {
        return
      }
      this.storageClear(raw.extId).then((): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', 'null')
      }).catch((): void => {
        ExtensionViewModel.fireTarget(controller, raw.cbId, 'storage error', 'null')
      })
    } catch (e) {
      logger.warn(`extStorageClear: ${e}`)
    }
  }

  private async storageClear(extId: string): Promise<void> {
    await this.ensureValues(extId)
    const m: Map<string, string> | undefined = this.valuesCache.get(extId)
    let changesJson: string = '{'
    if (m !== undefined) {
      let chgFirst: boolean = true
      m.forEach((raw: string, k: string): void => {
        changesJson += (chgFirst ? '' : ',') + JSON.stringify(k) + ':{' + '"oldValue":' + raw + '}'
        chgFirst = false
      })
      m.clear()
    }
    await this.getValueDB().clearByExt(extId)
    this.broadcastStorageChange(extId, changesJson + '}')
  }

  /**
   * content_script runtime.sendMessage：路由到 background 隐藏宿主；
   * 无宿主按「无接收者」语义回应（Chrome：无监听时回调立即收到 undefined）
   */
  extSendMessage(json: string, tab: TabInfo): void {
    try {
      const raw: ExtSendMsgRaw = JSON.parse(json) as ExtSendMsgRaw
      if (typeof raw.cbId !== 'number' || typeof raw.extId !== 'string') {
        return
      }
      const host: webview.WebviewController | undefined = this.bgHosts.get(raw.extId)
      if (host === undefined) {
        ExtensionViewModel.fireTarget(tab.controller, raw.cbId, '', '')
        return
      }
      const tabRec: Record<string, Object> = { 'id': tab.id, 'url': tab.url, 'title': tab.title }
      const sender: Record<string, Object> = { 'id': raw.extId, 'tab': tabRec }
      const respondId: number = ++this.respondSeq
      const origin: webview.WebviewController | null = tab.controller
      this.pendingResponds.set(respondId, new ExtPendingRespond(origin, raw.cbId))
      const js: string = `window.__qhExtCore && window.__qhExtCore.fireMessage(${JSON.stringify(raw.extId)},`
        + ` ${JSON.stringify(raw.msgJson)}, ${JSON.stringify(JSON.stringify(sender))}, ${respondId});`
      host.runJavaScript(js).catch((): void => {
        this.pendingResponds.delete(respondId)
        ExtensionViewModel.fireTarget(tab.controller, raw.cbId, '', '')
      })
    } catch (e) {
      logger.warn(`extSendMessage: ${e}`)
    }
  }

  /** background runtime.sendMessage：popup 面板打开中路由 popup 宿主，否则按无接收者回应 */
  extSendMsgFromBg(json: string, controller: webview.WebviewController): void {
    try {
      const raw: ExtSendMsgBgRaw = JSON.parse(json) as ExtSendMsgBgRaw
      if (typeof raw.cbId !== 'number' || typeof raw.extId !== 'string') {
        return
      }
      let target: webview.WebviewController | null = null
      if (this.popupExt !== null && this.popupExt.extId === raw.extId && this.popupHost !== null) {
        target = this.popupHost
      }
      if (target === null) {
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', '')
        return
      }
      const sender: Record<string, Object> = { 'id': raw.extId }
      const respondId: number = ++this.respondSeq
      this.pendingResponds.set(respondId, new ExtPendingRespond(controller, raw.cbId))
      const js: string = `window.__qhExtCore && window.__qhExtCore.fireMessage(${JSON.stringify(raw.extId)},`
        + ` ${JSON.stringify(raw.msgJson)}, ${JSON.stringify(JSON.stringify(sender))}, ${respondId});`
      target.runJavaScript(js).catch((): void => {
        this.pendingResponds.delete(respondId)
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', '')
      })
    } catch (e) {
      logger.warn(`extSendMsgFromBg: ${e}`)
    }
  }

  /** 消息响应统一派发：respondId → 发起方回调 */
  extRespond(json: string): void {
    try {
      const raw: ExtRespondRaw = JSON.parse(json) as ExtRespondRaw
      if (typeof raw.respondId !== 'number') {
        return
      }
      const pending: ExtPendingRespond | undefined = this.pendingResponds.get(raw.respondId)
      if (pending === undefined) {
        // 过期/已派发响应：静默丢弃（bg 宿主重挂等场景的迟到响应属正常）
        return
      }
      this.pendingResponds.delete(raw.respondId)
      ExtensionViewModel.fireTarget(pending.target, pending.cbId, '', raw.respJson)
    } catch (e) {
      logger.warn(`extRespond: ${e}`)
    }
  }

  // ==================== Port 通道（runtime.connect） ====================

  /**
   * runtime.connect 发起路由：接收端触发 onConnect 并注册双向通道。
   * kind：'popup'（popup 面板发起）、'tab'（内容脚本/扩展页标签发起）、'bg'（bg 宿主发起）；
   * 接收端选择：bg/popup/tab 发起 → bg 宿主；bg 发起 → popup（若打开）。
   * 无接收端按 Chrome 语义立即对端断开（onDisconnect）。
   */
  extPortConnect(json: string, from: webview.WebviewController, kind: string, tab: TabInfo | null): void {
    try {
      const raw: ExtPortConnectRaw = JSON.parse(json) as ExtPortConnectRaw
      if (raw.extId === '' || raw.portId === '' || this.portRoutes.has(raw.portId)) {
        return
      }
      let receiver: webview.WebviewController | null = null
      if (kind === 'bg') {
        if (this.popupExt !== null && this.popupExt.extId === raw.extId && this.popupHost !== null) {
          receiver = this.popupHost
        }
      } else {
        const host: webview.WebviewController | undefined = this.bgHosts.get(raw.extId)
        if (host !== undefined) {
          receiver = host
        }
      }
      if (receiver === null) {
        logger.info(`extPortConnect kind=${kind} pid=${raw.portId} recv=false`)
        ExtensionViewModel.firePortJs(from, raw.portId, 'firePortDisconnect')
        return
      }
      logger.info(`extPortConnect kind=${kind} pid=${raw.portId} recv=true`)
      const sender: Record<string, Object> = {
        'id': raw.extId,
        'url': raw.url,
        'origin': raw.origin,
        'frameId': 0
      }
      if (tab !== null) {
        sender['tab'] = this.portTabRecord(tab)
      }
      this.portRoutes.set(raw.portId, new ExtPortRoute(raw.extId, from, receiver))
      const js: string = `window.__qhExtCore && window.__qhExtCore.firePortConnect(${JSON.stringify(raw.portId)},`
        + ` ${JSON.stringify(JSON.stringify(raw.name))}, ${JSON.stringify(JSON.stringify(sender))});`
      receiver.runJavaScript(js).catch((): void => {
        const route: ExtPortRoute | undefined = this.portRoutes.get(raw.portId)
        if (route !== undefined && ExtensionViewModel.sameController(from, route.aSide)) {
          this.portRoutes.delete(raw.portId)
          ExtensionViewModel.firePortJs(from, raw.portId, 'firePortDisconnect')
        }
      })
    } catch (e) {
      logger.warn(`extPortConnect: ${e}`)
    }
  }

  /** chrome.tabs.Tab 记录（Port sender.tab 用，Record 形式便于并入 sender） */
  private portTabRecord(tab: TabInfo): Record<string, Object> {
    const active: boolean = tab.id === tabsVM.activeTabId
    let index: number = 0
    let seq: number = 0
    for (const t of tabsVM.tabs) {
      if (t.id === tab.id) {
        index = seq
        break
      }
      seq++
    }
    const rec: Record<string, Object> = {
      'id': tab.id,
      'index': index,
      'windowId': 1,
      'active': active,
      'highlighted': active,
      'incognito': tab.isIncognito,
      'url': tab.url,
      'title': tab.title
    }
    return rec
  }

  /** Port.postMessage 双向路由：按 portId 找通道，投递对端 firePortMessage */
  extPortMsg(json: string, from: webview.WebviewController): void {
    try {
      const raw: ExtPortMsgRaw = JSON.parse(json) as ExtPortMsgRaw
      if (raw.portId === '') {
        return
      }
      const route: ExtPortRoute | undefined = this.portRoutes.get(raw.portId)
      logger.info(`extPortMsg pid=${raw.portId} hit=${route !== undefined} len=${raw.msgJson.length}`)
      if (route === undefined) {
        return
      }
      const target: webview.WebviewController | null = ExtensionViewModel.otherSide(route, from)
      if (target === null) {
        logger.warn(`extPortMsg pid=${raw.portId} sender not in route`)
        return
      }
      const js: string = `window.__qhExtCore && window.__qhExtCore.firePortMessage(${JSON.stringify(raw.portId)},`
        + ` ${JSON.stringify(raw.msgJson)});`
      target.runJavaScript(js).catch((): void => {
      })
    } catch (e) {
      logger.warn(`extPortMsg: ${e}`)
    }
  }

  /** Port.disconnect 路由：移除通道，对端触发 onDisconnect */
  extPortDisconnect(json: string, from: webview.WebviewController): void {
    try {
      const raw: ExtPortDisconnectRaw = JSON.parse(json) as ExtPortDisconnectRaw
      if (raw.portId === '') {
        return
      }
      const route: ExtPortRoute | undefined = this.portRoutes.get(raw.portId)
      if (route === undefined) {
        logger.info(`extPortDisconnect pid=${raw.portId} no-route`)
        return
      }
      logger.info(`extPortDisconnect pid=${raw.portId} routed`)
      this.portRoutes.delete(raw.portId)
      const other: webview.WebviewController | null = ExtensionViewModel.otherSide(route, from)
      if (other !== null) {
        ExtensionViewModel.firePortJs(other, raw.portId, 'firePortDisconnect')
      }
    } catch (e) {
      logger.warn(`extPortDisconnect: ${e}`)
    }
  }

  /** 通道中 from 的对端控制器（不匹配任一端返回 null） */
  private static otherSide(route: ExtPortRoute, from: webview.WebviewController): webview.WebviewController | null {
    if (ExtensionViewModel.sameController(from, route.aSide)) {
      return route.bSide
    }
    if (ExtensionViewModel.sameController(from, route.bSide)) {
      return route.aSide
    }
    return null
  }

  private static sameController(a: webview.WebviewController, b: webview.WebviewController): boolean {
    return a === b
  }

  /** 向指定端注入 __qhExtCore 单参调用（firePortMessage/firePortDisconnect） */
  private static firePortJs(target: webview.WebviewController, portId: string, fn: string): void {
    const js: string = `window.__qhExtCore && window.__qhExtCore.${fn}(${JSON.stringify(portId)});`
    target.runJavaScript(js).catch((): void => {
    })
  }

  /** 断开与指定控制器相关的全部 Port 通道（宿主卸载/弹窗关闭/标签关闭），通知对端 onDisconnect */
  private teardownPortsOf(controller: webview.WebviewController | null): void {
    if (controller === null) {
      return
    }
    const dead: string[] = []
    this.portRoutes.forEach((route: ExtPortRoute, portId: string): void => {
      if (ExtensionViewModel.sameController(controller, route.aSide)
        || ExtensionViewModel.sameController(controller, route.bSide)) {
        dead.push(portId)
      }
    })
    for (const portId of dead) {
      const route: ExtPortRoute | undefined = this.portRoutes.get(portId)
      this.portRoutes.delete(portId)
      if (route === undefined) {
        continue
      }
      const other: webview.WebviewController | null = ExtensionViewModel.otherSide(route, controller)
      if (other !== null) {
        ExtensionViewModel.firePortJs(other, portId, 'firePortDisconnect')
      }
    }
  }

  /** background chrome.tabs.query：返回打开标签列表（active/url 模式过滤） */
  extTabQuery(json: string, from: webview.WebviewController): void {
    try {
      const raw: ExtTabQueryRaw = JSON.parse(json) as ExtTabQueryRaw
      if (typeof raw.cbId !== 'number') {
        return
      }
      let activeOnly: boolean = false
      let urlPatterns: string[] = []
      try {
        const q: Record<string, Object> =
          JSON.parse(raw.queryJson === '' ? '{}' : raw.queryJson) as Record<string, Object>
        if (q['active'] === true) {
          activeOnly = true
        }
        const u: Object | undefined = q['url']
        if (u !== undefined && typeof u === 'string' && u !== '') {
          urlPatterns.push(u)
        } else if (u !== undefined && u instanceof Array) {
          const arr: Object[] = u
          for (let idx: number = 0; idx < arr.length; idx++) {
            const p: Object = arr[idx]
            if (typeof p === 'string' && p !== '') {
              urlPatterns.push(p)
            }
          }
        }
      } catch (e) {
        urlPatterns = []
      }
      const out: Record<string, Object>[] = []
      let index: number = 0
      for (const t of tabsVM.tabs) {
        let matched: boolean = true
        if (activeOnly && t.id !== tabsVM.activeTabId) {
          matched = false
        }
        if (matched && urlPatterns.length > 0) {
          matched = false
          for (const p of urlPatterns) {
            if (ExtensionEngine.matchPattern(p, t.url)) {
              matched = true
              break
            }
          }
        }
        if (matched) {
          const rec: Record<string, Object> = {
            'id': t.id,
            'url': t.url,
            'title': t.title,
            'active': t.id === tabsVM.activeTabId,
            'incognito': t.isIncognito,
            'index': index
          }
          out.push(rec)
        }
        index++
      }
      ExtensionViewModel.fireTarget(from, raw.cbId, '', JSON.stringify(out))
    } catch (e) {
      logger.warn(`extTabQuery: ${e}`)
    }
  }

  /** background chrome.tabs.sendMessage：路由到目标标签 content_script onMessage */
  extTabSendMsg(json: string, from: webview.WebviewController): void {
    try {
      const raw: ExtTabSendMsgRaw = JSON.parse(json) as ExtTabSendMsgRaw
      if (typeof raw.cbId !== 'number' || typeof raw.tabId !== 'number' || typeof raw.extId !== 'string') {
        return
      }
      let target: TabInfo | null = null
      for (const t of tabsVM.tabs) {
        if (t.id === raw.tabId) {
          target = t
          break
        }
      }
      if (target === null || target.controller === null) {
        ExtensionViewModel.fireTarget(from, raw.cbId, '', '')
        return
      }
      const sender: Record<string, Object> = { 'id': raw.extId, 'url': `chrome-extension://${raw.extId}/` }
      const respondId: number = ++this.respondSeq
      this.pendingResponds.set(respondId, new ExtPendingRespond(from, raw.cbId))
      const js: string = `window.__qhExtCore && window.__qhExtCore.fireMessage(${JSON.stringify(raw.extId)},`
        + ` ${JSON.stringify(raw.msgJson)}, ${JSON.stringify(JSON.stringify(sender))}, ${respondId});`
      target.controller.runJavaScript(js).catch((): void => {
        this.pendingResponds.delete(respondId)
        ExtensionViewModel.fireTarget(from, raw.cbId, '', '')
      })
    } catch (e) {
      logger.warn(`extTabSendMsg: ${e}`)
    }
  }

  /** background chrome.tabs.create：新开标签页 */
  extTabCreate(json: string, from: webview.WebviewController): void {
    try {
      const raw: ExtTabCreateRaw = JSON.parse(json) as ExtTabCreateRaw
      if (typeof raw.cbId !== 'number') {
        return
      }
      if (raw.url !== '') {
        tabsVM.newTab(raw.url, false)
        // Chrome 语义：popup 打开新标签时焦点离开弹窗，popup 自动关闭；
        // 仅收 sheet，内容卸载延迟到 onDisappear（sheet 打开期间卸载内容会卡死 sheet）
        setTimeout((): void => {
          this.requestPopupDismiss()
        }, 0)
      }
      ExtensionViewModel.fireTarget(from, raw.cbId, '', 'null')
    } catch (e) {
      logger.warn(`extTabCreate: ${e}`)
    }
  }

  /** background chrome.tabs.update：导航指定标签 / active:true 激活（如 openSettingsPage focus 既有设置标签） */
  extTabUpdate(json: string, from: webview.WebviewController): void {
    try {
      const raw: ExtTabUpdateRaw = JSON.parse(json) as ExtTabUpdateRaw
      if (typeof raw.cbId !== 'number') {
        return
      }
      let target: TabInfo | null = null
      if (typeof raw.tabId === 'number' && raw.tabId > 0) {
        for (const t of tabsVM.tabs) {
          if (t.id === raw.tabId) {
            target = t
            break
          }
        }
      }
      if (target !== null) {
        if (raw.url !== '') {
          tabsVM.navigate(target, raw.url)
          // Chrome 语义：post-install 标签导航感谢页时处于前台；多轮重装残留旧标签时
          // findOne 命中的可能不是当前可见标签，导航后切前台保证用户可见
          tabsVM.switchTab(target.id)
        }
        if (raw.active === 1) {
          tabsVM.switchTab(target.id)
        }
        // Chrome 语义：popup 打开/激活标签时焦点离开弹窗，popup 自动关闭；
        // 仅收 sheet，内容卸载延迟到 onDisappear（sheet 打开期间卸载内容会卡死 sheet）
        if (raw.url !== '' || raw.active === 1) {
          setTimeout((): void => {
            this.requestPopupDismiss()
          }, 0)
        }
      }
      ExtensionViewModel.fireTarget(from, raw.cbId, '', 'null')
    } catch (e) {
      logger.warn(`extTabUpdate: ${e}`)
    }
  }

  // ==================== scripting.executeScript ====================

  /**
   * background chrome.scripting.executeScript（files 变体）：
   * 读扩展文件 → 内容沙箱包装 → runJavaScript 注入目标标签主帧，完成后回调 []；
   * func 变体沙箱侧已静默成功，不达此处；
   * 注入与后续 extTabSendMsg（fireMessage initAssistant）同控制器 FIFO，顺序有保证
   */
  extExecuteScript(json: string, from: webview.WebviewController): void {
    try {
      const raw: ExtExecuteScriptRaw = JSON.parse(json) as ExtExecuteScriptRaw
      if (typeof raw.cbId !== 'number' || typeof raw.extId !== 'string' || typeof raw.tabId !== 'number') {
        return
      }
      let files: string[] = []
      try {
        const arr: Object[] = JSON.parse(raw.filesJson === '' ? '[]' : raw.filesJson) as Object[]
        for (let i: number = 0; i < arr.length; i++) {
          const f: Object = arr[i]
          if (typeof f === 'string' && f !== '' && f.indexOf('..') < 0) {
            files.push(f)
          }
        }
      } catch (e) {
        files = []
      }
      let target: TabInfo | null = null
      for (const t of tabsVM.tabs) {
        if (t.id === raw.tabId) {
          target = t
          break
        }
      }
      if (target === null || target.controller === null || files.length === 0) {
        ExtensionViewModel.fireTarget(from, raw.cbId, '', '[]')
        return
      }
      let ext: ExtensionInfo | null = null
      for (const e of this.extensions) {
        if (e.extId === raw.extId) {
          ext = e
          break
        }
      }
      const code: string = ext === null ? '' : this.executeScriptCodeOf(ext, files)
      if (code === '') {
        ExtensionViewModel.fireTarget(from, raw.cbId, '', '[]')
        return
      }
      const controller: webview.WebviewController = target.controller
      controller.runJavaScript(code).then((): void => {
        ExtensionViewModel.fireTarget(from, raw.cbId, '', '[]')
      }).catch((e: BusinessError): void => {
        logger.warn(`extExecuteScript run: ${e.message}`)
        ExtensionViewModel.fireTarget(from, raw.cbId, 'executeScript failed', '[]')
      })
    } catch (e) {
      logger.warn(`extExecuteScript: ${e}`)
    }
  }

  /**
   * executeScript 注入代码（core + 内容沙箱包装目标文件；按 extId#files 缓存）；
   * 重复注入幂等性由目标脚本自带守卫保证（assistant-inject 的 window.assistantMessageListener）；
   * allFrames=false（executeScript 默认主帧）、matches=<all_urls>（http/https 页面注入）
   */
  private executeScriptCodeOf(ext: ExtensionInfo, files: string[]): string {
    const key: string = `${ext.extId}#${files.join(',')}`
    const cached: string | undefined = this.executeScriptCache.get(key)
    if (cached !== undefined) {
      return cached
    }
    const model: ExtManifestModel | null = this.manifestOf(ext)
    if (model === null) {
      return ''
    }
    const extDir: string = `${_QhState.Context.filesDir}/${ext.path}`
    const locale: string = ExtensionEngine.chromeUiLocale()
    const messages: Map<string, ExtLocaleMessage> = ExtensionEngine.readLocaleMessages(extDir, locale,
      model.defaultLocale !== '' ? model.defaultLocale : 'en')
    const messagesJson: string = ExtensionEngine.messagesJson(messages)
    let jsCode: string = ''
    for (const f of files) {
      const code: string = ExtensionEngine.readTextFile(`${extDir}/${f.replace(/^\/+/, '')}`, 5 * 1024 * 1024)
      if (code !== '') {
        jsCode += `/* ${f} */\n` + code + '\n;\n'
      }
    }
    if (jsCode === '') {
      return ''
    }
    const sandbox: string = ChromeShim.buildContentSandbox(ext.extId, ext.manifest, ext.name,
      ext.description, messagesJson, locale, '', jsCode, false, ['<all_urls>'])
    const out: string = ChromeShim.buildCoreJs() + sandbox
    this.executeScriptCache.set(key, out)
    return out
  }

  // ==================== tabs 事件分发 ====================

  /** 标签生命周期事件 → background 宿主 chrome.tabs.onCreated/onUpdated/onActivated/onRemoved */
  private onTabLifecycleEvent(event: string, tab: TabInfo): void {
    if (event === 'removed') {
      // 标签关闭：断开该标签控制器（内容脚本侧）的全部 Port 通道（不受 bgHosts 早退影响）
      this.teardownPortsOf(tab.controller)
    }
    if (this.bgHosts.size === 0) {
      return
    }
    if (event === 'created') {
      this.fireTabEvent('created', `[${this.tabRecordJson(tab)}]`)
      return
    }
    if (event === 'activated') {
      this.fireTabEvent('activated', `[{"tabId":${tab.id},"windowId":1}]`)
      return
    }
    if (event === 'removed') {
      this.fireTabEvent('removed', `[${tab.id},{"windowId":1,"isWindowClosing":false}]`)
      return
    }
    // 'updated'：Chrome 签名 (tabId, changeInfo, tab)
    this.fireTabEvent('updated', `[${tab.id},{"status":"complete","url":${JSON.stringify(tab.url)},`
      + `"title":${JSON.stringify(tab.title)}},${this.tabRecordJson(tab)}]`)
  }

  /** chrome.tabs.Tab 记录 JSON（bg tabContext.info 数据源） */
  private tabRecordJson(tab: TabInfo): string {
    const active: boolean = tab.id === tabsVM.activeTabId
    return `{"id":${tab.id},"index":0,"windowId":1,"highlighted":${active},"active":${active},`
      + `"pinned":false,"incognito":${tab.isIncognito},"discarded":false,`
      + `"status":"complete","url":${JSON.stringify(tab.url)},"title":${JSON.stringify(tab.title)}}`
  }

  /** 标签事件 JS 分发到全部 background 宿主（host 沙箱 window.__qhFireTabEvent） */
  private fireTabEvent(name: string, argsJson: string): void {
    if (this.bgHosts.size === 0) {
      return
    }
    const js: string = `window.__qhFireTabEvent && window.__qhFireTabEvent(${JSON.stringify(name)}, `
      + `${JSON.stringify(argsJson)});`
    this.bgHosts.forEach((c: webview.WebviewController): void => {
      // 宿主 aboutToAppear 注册早于 Web 组件绑定，未绑定 controller 的 runJavaScript 会同步抛
      // 17100001（.catch 只能接异步拒绝），必须 try/catch 防止炸断标签创建/关闭等核心流程
      try {
        c.runJavaScript(js).catch((): void => {
        })
      } catch (e) {
        logger.warn(`fireTabEvent runJavaScript 失败(${name}): ${e}`)
      }
    })
  }

  /** 存量标签同步（bg 宿主注入完成后调用）：会话恢复/宿主重挂的标签无 onCreated，
   *  经沙箱 __qhSyncTabs 轮询等待宿主注册 tabs 监听器后补投 created（active 标签附 activated） */
  syncTabsToBg(controller: webview.WebviewController): void {
    const recs: string[] = []
    for (const t of tabsVM.tabs) {
      recs.push(this.tabRecordJson(t))
    }
    if (recs.length === 0) {
      return
    }
    const js: string = `window.__qhSyncTabs && window.__qhSyncTabs(${JSON.stringify(`[${recs.join(',')}]`)});`
    controller.runJavaScript(js).catch((): void => {
    })
  }

  // ==================== 商店直装 ====================

  /** 商店站点页注入代码（含首页/列表，SPA 可达详情页；非商店站点返回 ''，带缓存；Edge 版附加不兼容状态行隐藏） */
  storePageCode(url: string): string {
    if (!ExtensionEngine.isStoreSite(url)) {
      return ''
    }
    if (url.toLowerCase().includes('microsoftedge.microsoft.com')) {
      if (this.edgeStoreCodeCache === '') {
        const label: string = ResourceUtils.getString($r('app.string.ext_store_install'))
        const listLabel: string = ResourceUtils.getString($r('app.string.ext_store_install_short'))
        const installedLabel: string = ResourceUtils.getString($r('app.string.ext_store_installed'))
        this.edgeStoreCodeCache = ChromeShim.buildEdgeBannerHideJs()
          + ChromeShim.buildEdgeGetReplaceJs(label, listLabel, installedLabel)
          + ChromeShim.buildStoreInstallJs(label, '!window.__qhEdgeGetOk')
      }
      return this.edgeStoreCodeCache
    }
    if (url.toLowerCase().includes('crxsoso.com')) {
      if (this.crxsosoCodeCache === '') {
        this.crxsosoCodeCache = ChromeShim.buildCrxsosoInstallJs()
      }
      return this.crxsosoCodeCache
    }
    if (this.storeCodeCache === '') {
      // CWS：原位改写「添加至Chrome」为「安装」并拦截点击，未扫到页面按钮时浮层兜底
      this.storeCodeCache = ChromeShim.buildCwsInstallJs(
        ResourceUtils.getString($r('app.string.ext_store_install_short')))
        + ChromeShim.buildStoreInstallJs(
          ResourceUtils.getString($r('app.string.ext_store_install')), '!window.__qhCwsOk')
    }
    return this.storeCodeCache
  }

  /** 已安装扩展商店 ID 集合（JSON 数组字符串，小写；商店页注入 JS 用以显示已安装状态） */
  installedExtIdsJson(): string {
    const ids: string[] = []
    for (const ext of this.extensions) {
      if (ext.extId !== '') {
        ids.push(ext.extId.toLowerCase())
      }
    }
    return JSON.stringify(ids)
  }

  /** 商店页直装（商店按钮 → extStoreInstall）：Toast 进度反馈，CRX 下载安装复用 installFromUrl */
  extStoreInstall(json: string): void {
    try {
      const raw: ExtStoreInstallRaw = JSON.parse(json) as ExtStoreInstallRaw
      if (raw.url === '') {
        return
      }
      // 全流程串行（含下载阶段）：进行中提示等待而非报失败，防连点并发互相顶掉
      if (this.storeInstalling) {
        toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.ext_installing')) })
        return
      }
      this.storeInstalling = true
      toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.ext_installing')) })
      const hint: string = typeof raw.extId === 'string' ? raw.extId : ''
      this.installFromUrl(raw.url, hint).then((ok: boolean): void => {
        if (!ok) {
          logger.warn(`extStoreInstall 失败: url=${raw.url}`)
        }
        const res: Resource = ok ? $r('app.string.ext_install_success') : $r('app.string.ext_install_fail')
        toastUtil.showToast({ message: ResourceUtils.getString(res) })
      }).catch((e: BusinessError): void => {
        logger.warn(`extStoreInstall 异常: ${e.message}`)
        toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.ext_install_fail')) })
      }).finally((): void => {
        this.storeInstalling = false
      })
    } catch (e) {
      logger.warn(`extStoreInstall: ${e}`)
    }
  }

  // ==================== popup 面板 ====================

  /** manifest 是否声明 action/browser_action 弹出页 */
  hasPopup(ext: ExtensionInfo): boolean {
    const model: ExtManifestModel | null = this.manifestOf(ext)
    return model !== null && model.actionPopup !== ''
  }

  /** 打开扩展 popup 面板（挂载 ExtPopupView）；扩展总开关关闭时不打开 */
  openPopup(ext: ExtensionInfo): void {
    if (!appSettings.extension_enabled) {
      return
    }
    this.popupExt = ext
    this.popupBg = ''
    if (this.onPopupVisibilityChanged !== null) {
      this.onPopupVisibilityChanged(true)
    }
  }

  /** 关闭 popup 面板 */
  closePopup(): void {
    // 先断开 popup 侧 Port 通道（对端 bg 触发 onDisconnect），再卸载宿主
    this.teardownPortsOf(this.popupHost)
    this.popupExt = null
    this.popupBg = ''
    this.popupHost = null
    if (this.onPopupVisibilityChanged !== null) {
      this.onPopupVisibilityChanged(false)
    }
  }

  /**
   * 请求收起 popup 半模态：仅切 isShow，不卸载内容；
   * 内容卸载由 bindSheet onDisappear → closePopup 在收起动画结束后完成。
   * sheet 打开期间卸载其 builder 内容（popupExt=null）会把 sheet 卡在打开态（真机实证）。
   */
  requestPopupDismiss(): void {
    if (this.onPopupVisibilityChanged !== null) {
      this.onPopupVisibilityChanged(false)
    }
  }

  /** 注册 popup 宿主（ExtPopupView 挂载时调用） */
  registerPopupHost(controller: webview.WebviewController): void {
    this.popupHost = controller
  }

  /** 注销 popup 宿主（组件销毁时调用；仅同控制器才清除，并断开其 Port 通道） */
  unregisterPopupHost(controller: webview.WebviewController): void {
    if (this.popupHost === controller) {
      this.popupHost = null
      this.teardownPortsOf(controller)
    }
  }

  /** popup 主文档地址（虚拟域，扩展文件经 onInterceptRequest 服务） */
  popupUrlOf(ext: ExtensionInfo): string {
    const model: ExtManifestModel | null = this.manifestOf(ext)
    const path: string = model !== null ? model.actionPopup : ''
    return ExtensionResources.extUrl(ext.extId, path === '' ? 'index.html' : path)
  }

  /** popup 文档启动注入代码（core + popup 宿主沙箱；页面脚本由 popup HTML 自行引用，带缓存） */
  popupCodeOf(ext: ExtensionInfo): string {
    const cached: string | undefined = this.popupCodeCache.get(ext.extId)
    if (cached !== undefined) {
      return cached
    }
    let code: string = ''
    const model: ExtManifestModel | null = this.manifestOf(ext)
    if (model !== null) {
      const extDir: string = `${_QhState.Context.filesDir}/${ext.path}`
      const locale: string = ExtensionEngine.chromeUiLocale()
      const messages: Map<string, ExtLocaleMessage> = ExtensionEngine.readLocaleMessages(extDir, locale,
        model.defaultLocale !== '' ? model.defaultLocale : 'en')
      const messagesJson: string = ExtensionEngine.messagesJson(messages)
      const sandbox: string = ChromeShim.buildHostSandbox(ext.extId, ext.manifest, ext.name,
        ext.description, messagesJson, locale, [], 'popup')
      code = ChromeShim.buildCoreJs() + sandbox
    }
    this.popupCodeCache.set(ext.extId, code)
    return code
  }

  /** popup runtime.sendMessage：路由到 background 宿主；无宿主按无接收者回应 */
  extSendMsgFromPopup(json: string, controller: webview.WebviewController): void {
    try {
      const raw: ExtSendMsgBgRaw = JSON.parse(json) as ExtSendMsgBgRaw
      if (typeof raw.cbId !== 'number' || typeof raw.extId !== 'string') {
        return
      }
      const host: webview.WebviewController | undefined = this.bgHosts.get(raw.extId)
      if (host === undefined) {
        // 无 bg 宿主：按 Chrome 无接收者语义空响应
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', '')
        return
      }
      /* sender.url 用 Chrome 规范形态（chrome-extension://<id>/<页面路径>）：
         跨浏览器扩展（如篡改猴）以 chrome-extension: 前缀判定 sender 是否扩展页
         （extpage gate），传内部 scheme（qinghong-extension://）会被拒收
         → loadTree 等消息静默失败 → popup 空白（真机实证） */
      const pagePath: string = typeof raw.page === 'string' && raw.page.startsWith('/') ? raw.page : ''
      const sender: Record<string, Object> = {
        'id': raw.extId,
        'url': `chrome-extension://${raw.extId}${pagePath}`
      }
      const respondId: number = ++this.respondSeq
      this.pendingResponds.set(respondId, new ExtPendingRespond(controller, raw.cbId))
      const js: string = `window.__qhExtCore && window.__qhExtCore.fireMessage(${JSON.stringify(raw.extId)},`
        + ` ${JSON.stringify(raw.msgJson)}, ${JSON.stringify(JSON.stringify(sender))}, ${respondId});`
      host.runJavaScript(js).catch((): void => {
        this.pendingResponds.delete(respondId)
        ExtensionViewModel.fireTarget(controller, raw.cbId, '', '')
      })
    } catch (e) {
      logger.warn(`extSendMsgFromPopup: ${e}`)
    }
  }

  /** popup 宿主 gmRequest 路由（__qhNative.gmRequest）：sendMessage/Port 连接走 popup 专用路由，其余与 background 宿主一致 */
  handlePopupRequest(api: string, json: string, extId: string, controller: webview.WebviewController): void {
    if (api === 'extSendMsgPopup') {
      this.extSendMsgFromPopup(json, controller)
      return
    }
    if (api === 'extPortConnect') {
      this.extPortConnect(json, controller, 'popup', null)
      return
    }
    if (api === 'extWindowClose') {
      /* popup 内容 window.close()（AdGuard 规则上限通知/手动拦截等操作收尾）→ 关面板；
         延迟销毁避免在 javaScriptProxy 回调内卸载 Web */
      setTimeout((): void => {
        this.requestPopupDismiss()
      }, 0)
      return
    }
    this.handleBgRequest(api, json, extId, controller)
  }

  /** 扩展图标绝对路径（manifest icons 最佳项；'' = 无图标声明） */
  iconPathOf(ext: ExtensionInfo): string {
    const model: ExtManifestModel | null = this.manifestOf(ext)
    if (model === null) {
      return ''
    }
    const rel: string = ExtensionEngine.bestIconOf(model.icons)
    return rel === '' ? '' : `${_QhState.Context.filesDir}/${ext.path}/${rel.replace(/^\/+/, '')}`
  }

  // ==================== background 隐藏宿主 ====================

  /** 注册 background 宿主（ExtBackgroundHost 挂载时调用） */
  registerBgHost(extId: string, controller: webview.WebviewController): void {
    this.bgHosts.set(extId, controller)
  }

  /** 注销 background 宿主（组件销毁时调用；仅同控制器才移除，并断开其 Port 通道） */
  unregisterBgHost(extId: string, controller: webview.WebviewController): void {
    const c: webview.WebviewController | undefined = this.bgHosts.get(extId)
    if (c === controller) {
      this.bgHosts.delete(extId)
      this.teardownPortsOf(controller)
    }
  }

  /** background 宿主 gmRequest 路由（__qhNative.gmRequest） */
  handleBgRequest(api: string, json: string, extId: string, controller: webview.WebviewController): void {
    try {
      /* 诊断：记录 bg 侧每个原生请求（其它扩展卡点定位保留） */
      logger.info(`bgReq ${api} len=${json.length}`)
      switch (api) {
        case 'extStorageGet':
          this.extStorageGet(json, controller)
          break
        case 'extStorageSet':
          this.extStorageSet(json, controller)
          break
        case 'extStorageRemove':
          this.extStorageRemove(json, controller)
          break
        case 'extStorageClear':
          this.extStorageClear(json, controller)
          break
        case 'extRespond':
          this.extRespond(json)
          break
        case 'extTabQuery':
          this.extTabQuery(json, controller)
          break
        case 'extTabSendMsg':
          this.extTabSendMsg(json, controller)
          break
        case 'extTabCreate':
          this.extTabCreate(json, controller)
          break
        case 'extTabUpdate':
          this.extTabUpdate(json, controller)
          break
        case 'extExecuteScript':
          this.extExecuteScript(json, controller)
          break
        case 'extSendMsgBg':
          this.extSendMsgFromBg(json, controller)
          break
        case 'extPortConnect':
          this.extPortConnect(json, controller, 'bg', null)
          break
        case 'extPortMsg':
          this.extPortMsg(json, controller)
          break
        case 'extPortDisconnect':
          this.extPortDisconnect(json, controller)
          break
        case 'extNotify': {
          const raw: ExtNotifyRaw = JSON.parse(json) as ExtNotifyRaw
          if (raw.text !== '') {
            toastUtil.showToast({ message: raw.text })
          }
          break
        }
        default:
          break
      }
    } catch (e) {
      logger.warn(`handleBgRequest ${api}: ${e}`)
    }
  }

  /** 扩展是否声明 background / service_worker */
  hasBackground(ext: ExtensionInfo): boolean {
    const model: ExtManifestModel | null = this.manifestOf(ext)
    if (model === null) {
      return false
    }
    return model.backgroundServiceWorker !== '' || model.backgroundScripts.length > 0
  }

  /** background 注入代码（core + 背景沙箱 + 脚本；'' = 无可执行内容，带缓存） */
  backgroundCodeOf(ext: ExtensionInfo): string {
    const cached: string | undefined = this.bgCodeCache.get(ext.extId)
    if (cached !== undefined) {
      return cached
    }
    let code: string = ''
    const model: ExtManifestModel | null = this.manifestOf(ext)
    if (model !== null) {
      const files: string[] = []
      if (model.backgroundServiceWorker !== '') {
        files.push(model.backgroundServiceWorker)
      }
      for (const s of model.backgroundScripts) {
        files.push(s)
      }
      if (files.length === 0 && model.backgroundPage !== '') {
        logger.warn(`backgroundCodeOf: background.page 暂不支持 (${ext.name})`)
      }
      // 经虚拟域 script 标签加载（绕开 runJavaScript/文件读取大小限制，AdGuard bg 8.7MB）
      const scriptUrls: string[] = []
      for (const f of files) {
        scriptUrls.push(ExtensionResources.extUrl(ext.extId, f))
      }
      if (scriptUrls.length > 0) {
        const locale: string = ExtensionEngine.chromeUiLocale()
        const extDir: string = `${_QhState.Context.filesDir}/${ext.path}`
        const messages: Map<string, ExtLocaleMessage> = ExtensionEngine.readLocaleMessages(extDir, locale,
          model.defaultLocale !== '' ? model.defaultLocale : 'en')
        const messagesJson: string = ExtensionEngine.messagesJson(messages)
        const sandbox: string = ChromeShim.buildHostSandbox(ext.extId, ext.manifest, ext.name,
          ext.description, messagesJson, locale, scriptUrls, 'background')
        code = ChromeShim.buildCoreJs() + sandbox
      }
    }
    this.bgCodeCache.set(ext.extId, code)
    return code
  }

  /** storage 变更广播：background 宿主 + 全部标签页 */
  private broadcastStorageChange(extId: string, changesJson: string): void {
    if (changesJson.length <= 2) {
      return
    }
    const js: string = `window.__qhExtCore && window.__qhExtCore.fireStorageChange(${JSON.stringify(extId)},`
      + ` ${JSON.stringify(changesJson)}, 'local');`
    this.bgHosts.forEach((c: webview.WebviewController): void => {
      c.runJavaScript(js).catch((): void => {
      })
    })
    if (this.popupHost !== null) {
      this.popupHost.runJavaScript(js).catch((): void => {
      })
    }
    for (const t of tabsVM.tabs) {
      if (t.controller !== null) {
        t.controller.runJavaScript(js).catch((): void => {
        })
      }
    }
  }

  /** 值缓存懒装载 */
  private async ensureValues(extId: string): Promise<void> {
    if (this.valuesLoaded.has(extId)) {
      return
    }
    const m: Map<string, string> = new Map()
    try {
      const dao: ExtensionValueDao = this.getValueDB()
      const rows = await dao.queryByExt(extId)
      for (const row of rows) {
        m.set(row.key, row.value)
      }
    } catch (e) {
      logger.warn(`ensureValues: ${e}`)
    }
    this.valuesCache.set(extId, m)
    this.valuesLoaded.add(extId)
  }

  /** 回调派发回发起方 Web */
  private static fireTarget(controller: webview.WebviewController | null, cbId: number,
    err: string, payloadJson: string): void {
    if (controller === null || cbId <= 0) {
      return
    }
    const js: string = `window.__qhExtCore && window.__qhExtCore.fire(${cbId},`
      + ` ${err === '' ? 'null' : JSON.stringify(err)}, ${JSON.stringify(payloadJson)});`
    controller.runJavaScript(js).catch((): void => {
    })
  }

  // ==================== 文件工具 ====================

  private static ensureDir(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        fileIo.mkdirSync(path)
      }
    } catch (e) {
      logger.warn(`ensureDir ${path}: ${e}`)
    }
  }

  private static removeDirQuiet(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.rmdirSync(path)
      }
    } catch (e) {
      logger.warn(`removeDirQuiet ${path}: ${e}`)
    }
  }

  private static unlinkQuiet(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (e) {
      logger.warn(`unlinkQuiet ${path}: ${e}`)
    }
  }
}

export const extensionVM = new ExtensionViewModel()
