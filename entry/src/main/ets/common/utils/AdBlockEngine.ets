import { fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { _QhState } from '../../entryability/AppState';
import { appSettings } from '../entity/SettingsModel';
import { adBlockSubsStore } from './AdBlockSubs';
import { createLogger } from './Logger';
import { abpRuleToRegexSrc } from './AbpRuleParse';
import { parseSubRulesTask, SubParseRaw } from './SubsParseTask';

const logger = createLogger('AdBlockEngine')

/**
 * 网络过滤规则（编译为正则）
 */
class NetworkRule {
  readonly regex: RegExp

  constructor(regex: RegExp) {
    this.regex = regex
  }
}

/**
 * 元素隐藏规则（domains 为逗号分隔域名，空串表示全部域名）
 */
class ElementRule {
  readonly domains: string
  readonly selector: string

  constructor(domains: string, selector: string) {
    this.domains = domains
    this.selector = selector
  }
}

interface ParsedNetwork {
  blocks: NetworkRule[]
  exceptions: NetworkRule[]
}

interface ParsedElements {
  rules: ElementRule[]
  exceptions: ElementRule[]
}

/**
 * Adblock Plus 过滤引擎：
 * - 网络规则：onInterceptRequest 中按 URL 匹配拦截（支持 ||、|、^、*、@@ 例外、/正则/、$选项忽略）
 * - 元素规则：生成文档开始注入脚本隐藏元素（支持 domain##selector、domain#@#selector 例外、~域名排除）
 * - 内建规则随引擎编译；自定义规则存沙箱 filesDir/adblock/custom_rules.txt
 */
@ObservedV2
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

  /** 内建网络规则（常见广告/统计域名） */
  private static readonly BUILTIN_RULES: string[] = [
    // 国际广告网络
    '||doubleclick.net^',
    '||googlesyndication.com^',
    '||googleadservices.com^',
    '||google-analytics.com^',
    '||googletagmanager.com^',
    '||adnxs.com^',
    '||adsrvr.org^',
    '||criteo.com^',
    '||criteo.net^',
    '||scorecardresearch.com^',
    '||quantserve.com^',
    '||moatads.com^',
    '||pubmatic.com^',
    '||rubiconproject.com^',
    '||openx.net^',
    '||smartadserver.com^',
    '||adform.net^',
    '||adroll.com^',
    '||taboola.com^',
    '||outbrain.com^',
    '||revcontent.com^',
    '||mgid.com^',
    '||amazon-adsystem.com^',
    '||ads.yahoo.com^',
    '||advertising.com^',
    '||yieldmo.com^',
    '||popads.net^',
    '||popcash.net^',
    '||inmobi.com^',
    '||mopub.com^',
    '||chartboost.com^',
    '||vungle.com^',
    '||adcolony.com^',
    // 国内广告与统计
    '||pos.baidu.com^',
    '||cpro.baidu.com^',
    '||eclick.baidu.com^',
    '||hm.baidu.com^',
    '||tanx.com^',
    '||mmstat.com^',
    '||adsmind.ugdtimg.com^',
    '||pgdt.ugdtimg.com^',
    '||gdt.qq.com^',
    '||l.qq.com^',
    '||cnzz.com^',
    '||umeng.com^',
    '||umeng.co^',
    '||51.la^',
    '||miaozhen.com^'
  ]

  /** 自定义规则版本号（重载后自增，触发注入脚本重建） */
  @Trace customVersion: number = 0

  private builtinBlocks: NetworkRule[] = []
  private builtinExceptions: NetworkRule[] = []
  private customBlocks: NetworkRule[] = []
  private customExceptions: NetworkRule[] = []
  private customElements: ElementRule[] = []
  private customElementExceptions: ElementRule[] = []
  private subBlocks: NetworkRule[] = []
  private subExceptions: NetworkRule[] = []
  private subElements: ElementRule[] = []
  private subElementExceptions: ElementRule[] = []
  /** 订阅规则解析中（分块解析防重入） */
  private reloading: boolean = false
  private reloadQueued: boolean = false

  /** 自定义规则沙箱文件 */
  static customRulesFile(): string {
    return `${_QhState.Context.filesDir}/adblock/custom_rules.txt`
  }

  /** 启动时初始化：编译内建规则并加载自定义规则 */
  init(): void {
    const parsed: ParsedNetwork = AdBlockEngine.parseNetwork(AdBlockEngine.BUILTIN_RULES.join('\n'))
    this.builtinBlocks = parsed.blocks
    this.builtinExceptions = parsed.exceptions
    this.reloadCustom()
    // 订阅规则下载/更新成功后自动重载
    adBlockSubsStore.onRulesChanged = (): void => {
      this.reloadSubscriptions()
    }
  }

  /** 读取自定义规则文件内容（编辑页回显用） */
  loadCustomRulesSync(): string {
    try {
      const path: string = AdBlockEngine.customRulesFile()
      if (fileIo.accessSync(path)) {
        return fileIo.readTextSync(path)
      }
    } catch (e) {
      logger.error(`loadCustomRulesSync 失败: ${e}`)
    }
    return ''
  }

  /** 保存自定义规则并重新编译 */
  async saveCustomRules(text: string): Promise<void> {
    try {
      const path: string = AdBlockEngine.customRulesFile()
      const dir: string = `${_QhState.Context.filesDir}/adblock`
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
      await this.reloadCustom()
    } catch (e) {
      logger.error(`saveCustomRules 失败: ${e}`)
    }
  }

  /** 重新加载自定义规则文件 */
  async reloadCustom(): Promise<void> {
    try {
      const text: string = this.loadCustomRulesSync()
      const net: ParsedNetwork = AdBlockEngine.parseNetwork(text)
      const els: ParsedElements = AdBlockEngine.parseElements(text)
      this.customBlocks = net.blocks
      this.customExceptions = net.exceptions
      this.customElements = els.rules
      this.customElementExceptions = els.exceptions
      this.customVersion++
    } catch (e) {
      logger.error(`reloadCustom 失败: ${e}`)
    }
  }

  /**
   * 重新加载订阅规则文件（订阅增删改/开关/更新后调用）
   * 文件读取与逐行解析在 taskpool 子线程执行（RegExp 不可跨线程，主线程按源码构造，分块让出）
   */
  async reloadSubscriptions(): Promise<void> {
    if (this.reloading) {
      this.reloadQueued = true
      return
    }
    this.reloading = true
    try {
      const t0: number = Date.now()
      this.subBlocks = []
      this.subExceptions = []
      this.subElements = []
      this.subElementExceptions = []
      for (const sub of adBlockSubsStore.subs) {
        if (!sub.enabled) {
          continue
        }
        const subT0: number = Date.now()
        // 子线程读取并解析规则文件（几万条规则的解析不占主线程）
        const task: taskpool.Task = new taskpool.Task(parseSubRulesTask, adBlockSubsStore.rulesPath(sub))
        const raw: SubParseRaw = await taskpool.execute(task) as SubParseRaw
        // 主线程根据源码构造 RegExp（分块让出，避免长任务阻塞 UI）
        for (let i = 0; i < raw.blockSrcs.length; i++) {
          const regex: RegExp | null = AdBlockEngine.regexFromSrc(raw.blockSrcs[i])
          if (regex !== null) {
            this.subBlocks.push(new NetworkRule(regex))
          }
          if ((i & 1023) === 1023) {
            await AdBlockEngine.yieldToUI()
          }
        }
        for (let i = 0; i < raw.exceptionSrcs.length; i++) {
          const regex: RegExp | null = AdBlockEngine.regexFromSrc(raw.exceptionSrcs[i])
          if (regex !== null) {
            this.subExceptions.push(new NetworkRule(regex))
          }
          if ((i & 1023) === 1023) {
            await AdBlockEngine.yieldToUI()
          }
        }
        for (let i = 0; i < raw.hideSelectors.length; i++) {
          this.subElements.push(new ElementRule(raw.hideDomains[i], raw.hideSelectors[i]))
        }
        for (let i = 0; i < raw.hideExcSelectors.length; i++) {
          this.subElementExceptions.push(new ElementRule(raw.hideExcDomains[i], raw.hideExcSelectors[i]))
        }
        logger.info(`reloadSubscriptions 订阅 ${sub.name} 解析完成: ` +
          `拦截 ${raw.blockSrcs.length} / 例外 ${raw.exceptionSrcs.length} / 元素 ${raw.hideSelectors.length} 条, ` +
          `耗时 ${Date.now() - subT0}ms`)
      }
      this.customVersion++
      logger.info(`reloadSubscriptions 全部完成, 总耗时 ${Date.now() - t0}ms`)
    } catch (e) {
      logger.error(`reloadSubscriptions 失败: ${e}`)
    } finally {
      this.reloading = false
      if (this.reloadQueued) {
        this.reloadQueued = false
        this.reloadSubscriptions()
      }
    }
  }

  /** 由正则源码构造 RegExp（空串或非法源码返回 null） */
  private static regexFromSrc(src: string): RegExp | null {
    if (src === '') {
      return null
    }
    try {
      return new RegExp(src, 'i')
    } catch (e) {
      return null
    }
  }

  /** 让出主线程一拍（分块解析间隙给渲染任务插队） */
  private static yieldToUI(): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout((): void => {
        resolve()
      }, 0)
    })
  }

  /**
   * 判断请求 URL 是否应被拦截（主框架请求由调用方放行）
   * @param enabled 调用方（含站点级覆盖）广告拦截是否生效
   */
  shouldBlock(url: string, enabled: boolean = true): boolean {
    if (!enabled) {
      return false
    }
    const useBuiltin: boolean = appSettings.ad_block_builtin
    // 例外规则优先
    if (useBuiltin) {
      for (const rule of this.builtinExceptions) {
        if (rule.regex.test(url)) {
          return false
        }
      }
    }
    for (const rule of this.subExceptions) {
      if (rule.regex.test(url)) {
        return false
      }
    }
    for (const rule of this.customExceptions) {
      if (rule.regex.test(url)) {
        return false
      }
    }
    if (useBuiltin) {
      for (const rule of this.builtinBlocks) {
        if (rule.regex.test(url)) {
          return true
        }
      }
    }
    for (const rule of this.subBlocks) {
      if (rule.regex.test(url)) {
        return true
      }
    }
    for (const rule of this.customBlocks) {
      if (rule.regex.test(url)) {
        return true
      }
    }
    return false
  }

  /**
   * 生成元素隐藏注入脚本（无规则或未启用返回空串）
   */
  hideScript(): string {
    if (!appSettings.ad_block_enabled) {
      return ''
    }
    // 读取版本号以建立渲染依赖（规则重载后脚本重建）
    if (this.customVersion < 0) {
      return ''
    }
    if (this.subElements.length === 0 && this.subElementExceptions.length === 0
      && this.customElements.length === 0 && this.customElementExceptions.length === 0) {
      return ''
    }
    const rulesArr: string[][] = []
    for (const r of this.subElements.concat(this.customElements)) {
      rulesArr.push([r.domains, r.selector])
    }
    const excArr: string[][] = []
    for (const r of this.subElementExceptions.concat(this.customElementExceptions)) {
      excArr.push([r.domains, r.selector])
    }
    return '(function(){try{' +
      `var R=${JSON.stringify(rulesArr)},X=${JSON.stringify(excArr)};` +
      'var h=location.hostname,css=\'\';' +
      'function m(list){var s=list.split(\',\');for(var j=0;j<s.length;j++){var d=s[j];if(!d)continue;' +
      'if(d[0]==\'~\'){if(h==d.slice(1)||h.endsWith(\'.\'+d.slice(1)))return false;}' +
      'else if(h==d||h.endsWith(\'.\'+d))return true;}return false;}' +
      'var ex=\'\';for(var i=0;i<X.length;i++){if(m(X[i][0]))ex+=X[i][1]+\'\\n\';}' +
      'for(var i2=0;i2<R.length;i2++){var sel=R[i2][1];' +
      'if(ex.indexOf(sel+\'\\n\')>=0)continue;' +
      'if(!R[i2][0]||m(R[i2][0]))css+=sel+\'{display:none !important;}\';}' +
      'if(css){var s2=document.createElement(\'style\');s2.textContent=css;' +
      '(document.head||document.documentElement).appendChild(s2);}}catch(e){}})()'
  }

  /**
   * 解析文本中的网络规则
   */
  private static parseNetwork(text: string): ParsedNetwork {
    const result: ParsedNetwork = { blocks: [], exceptions: [] }
    const lines: string[] = text.split('\n')
    for (let line of lines) {
      line = line.trim()
      if (line.length === 0) {
        continue
      }
      const first: string = line[0]
      if (first === '!' || first === '[') {
        continue
      }
      // 元素隐藏规则不参与网络匹配
      if (line.includes('##') || line.includes('#@#')) {
        continue
      }
      let isException: boolean = false
      if (line.startsWith('@@')) {
        isException = true
        line = line.substring(2).trim()
      }
      const regex: RegExp | null = AdBlockEngine.compileNetworkRule(line)
      if (regex !== null) {
        if (isException) {
          result.exceptions.push(new NetworkRule(regex))
        } else {
          result.blocks.push(new NetworkRule(regex))
        }
      }
    }
    return result
  }

  /**
   * 解析文本中的元素隐藏规则
   */
  private static parseElements(text: string): ParsedElements {
    const result: ParsedElements = { rules: [], exceptions: [] }
    const lines: string[] = text.split('\n')
    for (let line of lines) {
      line = line.trim()
      if (line.length === 0) {
        continue
      }
      const first: string = line[0]
      if (first === '!' || first === '[') {
        continue
      }
      let sepIndex: number = line.indexOf('#@#')
      let isException: boolean = true
      if (sepIndex < 0) {
        sepIndex = line.indexOf('##')
        isException = false
      }
      if (sepIndex < 0) {
        continue
      }
      const domains: string = line.substring(0, sepIndex).trim()
      const selector: string = line.substring(sepIndex + (isException ? 3 : 2)).trim()
      if (selector.length === 0) {
        continue
      }
      const rule: ElementRule = new ElementRule(domains, selector)
      if (isException) {
        result.exceptions.push(rule)
      } else {
        result.rules.push(rule)
      }
    }
    return result
  }

  /**
   * 编译单条网络规则为正则（源码生成逻辑见 AbpRuleParse，主/子线程共用）
   */
  private static compileNetworkRule(rule: string): RegExp | null {
    return AdBlockEngine.regexFromSrc(abpRuleToRegexSrc(rule))
  }
}

export const adBlockEngine: AdBlockEngine = new AdBlockEngine()
