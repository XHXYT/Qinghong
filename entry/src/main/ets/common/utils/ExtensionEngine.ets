import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { i18n } from '@kit.LocalizationKit';
import { appSettings } from '../entity/SettingsModel';
import { createLogger } from './Logger';

const logger = createLogger('ExtensionEngine')

/**
 * Chrome 扩展 manifest content_scripts 单项声明（清洗后模型）
 */
export class ExtContentScript {
  matches: string[] = []
  excludeMatches: string[] = []
  includeGlobs: string[] = []
  excludeGlobs: string[] = []
  js: string[] = []
  css: string[] = []
  runAt: string = 'document_idle'
  allFrames: boolean = false
}

/**
 * Chrome 扩展 manifest 清洗后模型
 */
export class ExtManifestModel {
  manifestVersion: number = 3
  name: string = ''
  version: string = ''
  description: string = ''
  defaultLocale: string = ''
  contentScripts: ExtContentScript[] = []
  backgroundScripts: string[] = []
  backgroundServiceWorker: string = ''
  backgroundPage: string = ''
  actionPopup: string = ''
  permissions: string[] = []
  hostPermissions: string[] = []
  /** 图标声明：尺寸字符串（"16"/"48"/"128"）→ 相对路径 */
  icons: Record<string, string> = {}
}

/** ---- JSON.parse 一次转型的 raw 模型 ---- */

export class ExtPlaceholderRaw {
  content: string = ''
}

export class ExtLocaleMessageRaw {
  message: string = ''
  placeholders: Record<string, ExtPlaceholderRaw> = {}
}

export class ExtContentScriptRaw {
  matches: string[] = []
  exclude_matches: string[] = []
  include_globs: string[] = []
  exclude_globs: string[] = []
  js: string[] = []
  css: string[] = []
  run_at: string = ''
  all_frames: boolean = false
  match_about_blank: boolean = false
}

export class ExtBackgroundRaw {
  scripts: string[] = []
  service_worker: string = ''
  page: string = ''
}

export class ExtActionRaw {
  default_popup: string = ''
  default_title: string = ''
}

export class ExtOptionsUiRaw {
  open_in_tab: boolean = false
  page: string = ''
}

export class ExtManifestRaw {
  manifest_version: number = 0
  name: string = ''
  version: string = ''
  description: string = ''
  default_locale: string = ''
  content_scripts: ExtContentScriptRaw[] = []
  background: ExtBackgroundRaw | null = null
  action: ExtActionRaw | null = null
  browser_action: ExtActionRaw | null = null
  options_ui: ExtOptionsUiRaw | null = null
  options_page: string = ''
  homepage_url: string = ''
  permissions: string[] = []
  host_permissions: string[] = []
  icons: Record<string, string> = {}
}

/** i18n 消息（清洗后） */
export class ExtLocaleMessage {
  message: string = ''
  placeholders: Record<string, ExtPlaceholderRaw> = {}
}

/** CRX 下载目标（直链或商店页解析结果） */
export class CrxTarget {
  crxUrl: string = ''
  extIdHint: string = ''
}

/**
 * Chrome 扩展兼容引擎：
 * - manifest 解析（MV2/MV3）+ Chrome match pattern / glob 匹配；
 * - CRX2/CRX3 头解析定位 ZIP 起始偏移；
 * - 商店页 URL → CRX 更新端点解析（Chrome Web Store / Edge Add-ons）；
 * - _locales messages 读取与 __MSG_ 解析。
 */
export class ExtensionEngine {

  /** Chrome Web Store 更新端点内核版本号（与 ArkWeb M114 对齐） */
  static readonly PROD_VERSION: string = '114.0.5735.196'

  /** Chrome Web Store 首页 */
  static readonly CWS_HOME: string = 'https://chromewebstore.google.com/'

  /** Microsoft Edge Add-ons 首页 */
  static readonly EDGE_ADDONS_HOME: string = 'https://microsoftedge.microsoft.com/addons'

  /** match pattern 正则缓存 */
  private static matchCache: Map<string, RegExp> = new Map()

  /** 随机 32 位扩展 ID */
  static randomExtId(): string {
    try {
      return util.generateRandomUUID(false).replace(/-/g, '')
    } catch (e) {
      return Date.now().toString(16).padStart(32, '0')
    }
  }

  // ==================== manifest 解析 ====================

  /**
   * 解析 manifest.json 文本；结构非法返回 null
   */
  static parseManifest(json: string): ExtManifestModel | null {
    let raw: ExtManifestRaw
    try {
      raw = JSON.parse(json) as ExtManifestRaw
    } catch (e) {
      logger.warn(`parseManifest: JSON 解析失败`)
      return null
    }
    if (raw === null || typeof raw !== 'object') {
      return null
    }
    const model: ExtManifestModel = new ExtManifestModel()
    model.manifestVersion = typeof raw.manifest_version === 'number' ? raw.manifest_version : 3
    if (model.manifestVersion !== 2 && model.manifestVersion !== 3) {
      logger.warn(`parseManifest: 不支持的 manifest_version ${model.manifestVersion}`)
      return null
    }
    model.name = typeof raw.name === 'string' ? raw.name : ''
    model.version = typeof raw.version === 'string' ? raw.version : ''
    model.description = typeof raw.description === 'string' ? raw.description : ''
    model.defaultLocale = typeof raw.default_locale === 'string' ? raw.default_locale : ''
    if (raw.content_scripts instanceof Array) {
      for (const item of raw.content_scripts) {
        if (item === null || typeof item !== 'object') {
          continue
        }
        const cs: ExtContentScript = new ExtContentScript()
        cs.matches = ExtensionEngine.stringArray(item.matches)
        cs.excludeMatches = ExtensionEngine.stringArray(item.exclude_matches)
        cs.includeGlobs = ExtensionEngine.stringArray(item.include_globs)
        cs.excludeGlobs = ExtensionEngine.stringArray(item.exclude_globs)
        cs.js = ExtensionEngine.stringArray(item.js)
        cs.css = ExtensionEngine.stringArray(item.css)
        cs.runAt = typeof item.run_at === 'string' ? item.run_at : 'document_idle'
        cs.allFrames = item.all_frames === true
        model.contentScripts.push(cs)
      }
    }
    if (raw.background !== null && typeof raw.background === 'object') {
      model.backgroundScripts = ExtensionEngine.stringArray(raw.background.scripts)
      model.backgroundServiceWorker = typeof raw.background.service_worker === 'string' ? raw.background.service_worker : ''
      model.backgroundPage = typeof raw.background.page === 'string' ? raw.background.page : ''
    }
    let action: ExtActionRaw | null = null
    if (raw.action !== null && typeof raw.action === 'object') {
      action = raw.action
    } else if (raw.browser_action !== null && typeof raw.browser_action === 'object') {
      action = raw.browser_action
    }
    if (action !== null && typeof action.default_popup === 'string' && action.default_popup !== '') {
      model.actionPopup = action.default_popup
    }
    model.permissions = ExtensionEngine.stringArray(raw.permissions)
    model.hostPermissions = ExtensionEngine.stringArray(raw.host_permissions)
    if (raw.icons !== undefined && raw.icons !== null && typeof raw.icons === 'object') {
      const sizeKeys: string[] = Object.keys(raw.icons)
      for (const sk of sizeKeys) {
        const p: Object | undefined = raw.icons[sk]
        if (typeof p === 'string' && p !== '') {
          model.icons[sk] = p
        }
      }
    }
    if (model.name === '' || model.version === '') {
      logger.warn('parseManifest: 缺少 name/version')
      return null
    }
    return model
  }

  /** 从 icons 声明选最佳图标路径（≤128 内最大优先，超 128 取最小；'' = 无图标） */
  static bestIconOf(icons: Record<string, string>): string {
    const keys: string[] = Object.keys(icons)
    let best: string = ''
    let bestScore: number = -1
    for (const k of keys) {
      const size: number = Number(k)
      if (!Number.isFinite(size) || size <= 0) {
        continue
      }
      const path: string | undefined = icons[k]
      if (path === undefined || path === '') {
        continue
      }
      // ≤128：越大越好；>128：越接近 128 越好（倒序分）
      const score: number = size <= 128 ? size : 1000 - size
      if (score > bestScore) {
        bestScore = score
        best = path
      }
    }
    return best
  }

  /** raw 字段 → 字符串数组（非法项丢弃） */
  private static stringArray(src: string[] | undefined): string[] {
    const out: string[] = []
    if (src === undefined || src === null || !(src instanceof Array)) {
      return out
    }
    for (const it of src) {
      if (typeof it === 'string' && it !== '') {
        out.push(it)
      }
    }
    return out
  }

  // ==================== URL 匹配 ====================

  /**
   * content_script 声明是否命中 URL：
   * exclude_matches/exclude_globs 任一命中即不生效；
   * matches 任一命中（空视为全部）后，include_globs 非空时任一命中才生效
   */
  static contentScriptMatches(url: string, cs: ExtContentScript): boolean {
    if (url === '') {
      return false
    }
    for (const p of cs.excludeMatches) {
      if (ExtensionEngine.matchPattern(p, url)) {
        return false
      }
    }
    for (const g of cs.excludeGlobs) {
      if (ExtensionEngine.globMatch(g, url)) {
        return false
      }
    }
    let matched: boolean = cs.matches.length === 0
    for (const p of cs.matches) {
      if (ExtensionEngine.matchPattern(p, url)) {
        matched = true
        break
      }
    }
    if (!matched) {
      return false
    }
    if (cs.includeGlobs.length > 0) {
      let globOk: boolean = false
      for (const g of cs.includeGlobs) {
        if (ExtensionEngine.globMatch(g, url)) {
          globOk = true
          break
        }
      }
      if (!globOk) {
        return false
      }
    }
    return true
  }

  /**
   * Chrome match pattern 匹配（<all_urls> / scheme://host/path，* 通配）
   */
  static matchPattern(pattern: string, url: string): boolean {
    if (pattern === '' || url === '') {
      return false
    }
    let re: RegExp | undefined = ExtensionEngine.matchCache.get(pattern)
    if (re === undefined) {
      const built: RegExp | null = ExtensionEngine.buildPatternRegex(pattern)
      if (built === null) {
        return false
      }
      ExtensionEngine.matchCache.set(pattern, built)
      re = built
    }
    try {
      return re.test(url)
    } catch (e) {
      return false
    }
  }

  /** match pattern → 正则（缓存前构建） */
  private static buildPatternRegex(pattern: string): RegExp | null {
    try {
      if (pattern === '<all_urls>') {
        return new RegExp('^(https?|file|ftp|wss?):', 'i')
      }
      const sep: number = pattern.indexOf('://')
      if (sep <= 0) {
        return null
      }
      const scheme: string = pattern.substring(0, sep)
      const rest: string = pattern.substring(sep + 3)
      const slash: number = rest.indexOf('/')
      const host: string = slash < 0 ? rest : rest.substring(0, slash)
      const path: string = slash < 0 ? '/' : rest.substring(slash)
      let schemeRe: string
      if (scheme === '*') {
        schemeRe = 'https?'
      } else if (scheme === 'http' || scheme === 'https' || scheme === 'file' || scheme === 'ftp') {
        schemeRe = scheme
      } else {
        // 未知 scheme 宽松字面处理
        schemeRe = ExtensionEngine.escapeLiteral(scheme)
      }
      let hostRe: string
      if (host === '*') {
        hostRe = '[^/]*'
      } else if (host.startsWith('*.')) {
        hostRe = '([^/]+\\.)?' + ExtensionEngine.escapeLiteral(host.substring(2))
      } else {
        hostRe = ExtensionEngine.escapeLiteral(host)
      }
      return new RegExp('^' + schemeRe + '://' + hostRe + ExtensionEngine.escapeGlobPath(path), 'i')
    } catch (e) {
      logger.warn(`buildPatternRegex: ${pattern}, ${e}`)
      return null
    }
  }

  /**
   * Chrome glob 匹配（include_globs/exclude_globs）：
   * 含 * 时通配匹配（* → 任意序列），否则子串匹配
   */
  static globMatch(glob: string, url: string): boolean {
    if (glob === '') {
      return true
    }
    if (glob.indexOf('*') < 0) {
      return url.indexOf(glob) >= 0
    }
    try {
      const parts: string[] = glob.split('*')
      let re: string = ''
      for (let i: number = 0; i < parts.length; i++) {
        re += ExtensionEngine.escapeLiteral(parts[i])
        if (i < parts.length - 1) {
          re += '.*'
        }
      }
      return new RegExp(re, 'i').test(url)
    } catch (e) {
      return false
    }
  }

  /** 正则字面转义 */
  private static escapeLiteral(s: string): string {
    let re: string = ''
    for (let i: number = 0; i < s.length; i++) {
      const c: string = s.charAt(i)
      if ('\\^$.|?+()[]{}'.indexOf(c) >= 0) {
        re += '\\' + c
      } else {
        re += c
      }
    }
    return re
  }

  /** path 段转义（* 还原为 .*） */
  private static escapeGlobPath(p: string): string {
    const parts: string[] = p.split('*')
    let re: string = ''
    for (let i: number = 0; i < parts.length; i++) {
      re += ExtensionEngine.escapeLiteral(parts[i])
      if (i < parts.length - 1) {
        re += '.*'
      }
    }
    return re
  }

  // ==================== CRX 解析 ====================

  /**
   * 定位 ZIP 数据起始偏移：
   * 纯 ZIP（PK 头）→ 0；CRX2/CRX3（Cr24 魔数）→ 按头部长度计算；
   * 校验失败在头部附近扫描 PK 头兜底；非 CRX/ZIP 返回 -1
   */
  static crxZipOffset(bytes: Uint8Array): number {
    const len: number = bytes.byteLength
    if (len < 16) {
      return -1
    }
    if (bytes[0] === 0x50 && bytes[1] === 0x4B && bytes[2] === 0x03 && bytes[3] === 0x04) {
      return 0
    }
    if (!(bytes[0] === 0x43 && bytes[1] === 0x72 && bytes[2] === 0x32 && bytes[3] === 0x34)) {
      return -1
    }
    const version: number = ExtensionEngine.readU32LE(bytes, 4)
    if (version === 3) {
      const headerLen: number = ExtensionEngine.readU32LE(bytes, 8)
      const off: number = 12 + headerLen
      if (ExtensionEngine.isZipAt(bytes, off)) {
        return off
      }
      return ExtensionEngine.scanZipHeader(bytes, 12)
    }
    if (version === 2) {
      const pkLen: number = ExtensionEngine.readU32LE(bytes, 8)
      const sigLen: number = ExtensionEngine.readU32LE(bytes, 12)
      const off: number = 16 + pkLen + sigLen
      if (ExtensionEngine.isZipAt(bytes, off)) {
        return off
      }
      return ExtensionEngine.scanZipHeader(bytes, 16)
    }
    return -1
  }

  private static readU32LE(b: Uint8Array, off: number): number {
    if (off + 4 > b.byteLength) {
      return -1
    }
    return (b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)) >>> 0
  }

  private static isZipAt(b: Uint8Array, off: number): boolean {
    return off >= 0 && off + 4 <= b.byteLength
      && b[off] === 0x50 && b[off + 1] === 0x4B && b[off + 2] === 0x03 && b[off + 3] === 0x04
  }

  private static scanZipHeader(b: Uint8Array, from: number): number {
    const limit: number = Math.min(b.byteLength - 4, from + 8192)
    for (let i: number = from; i <= limit; i++) {
      if (b[i] === 0x50 && b[i + 1] === 0x4B && b[i + 2] === 0x03 && b[i + 3] === 0x04) {
        return i
      }
    }
    return -1
  }

  // ==================== 商店 URL 解析 ====================

  /**
   * 安装链接 → CRX 下载目标：
   * - CRX/ZIP 直链原样；
   * - Chrome Web Store / Edge Add-ons 详情页 → 官方 CRX 更新端点
   */
  static resolveCrxUrl(url: string): CrxTarget {
    const target: CrxTarget = new CrxTarget()
    const lower: string = url.toLowerCase()
    if (lower.includes('clients2.google.com/service/update2/crx')
      || lower.includes('edge.microsoft.com/extensionwebstorebase')
      || lower.endsWith('.crx') || lower.endsWith('.zip')) {
      target.crxUrl = url
      return target
    }
    // Chrome Web Store 详情页
    const cwsId: string = ExtensionEngine.storeIdOf(url, ['chromewebstore.google.com', 'chrome.google.com'])
    if (cwsId !== '') {
      target.crxUrl = 'https://clients2.google.com/service/update2/crx?response=redirect'
        + `&acceptformat=crx2,crx3&prodversion=${ExtensionEngine.PROD_VERSION}`
        + `&x=id%3D${cwsId}%26installsource%3Dondemand%26uc`
      target.extIdHint = cwsId
      return target
    }
    // Edge Add-ons 详情页（installsource%3Dondemand 必须编入 x= 内，否则端点 500）
    const edgeId: string = ExtensionEngine.storeIdOf(url, ['microsoftedge.microsoft.com'])
    if (edgeId !== '') {
      target.crxUrl = 'https://edge.microsoft.com/extensionwebstorebase/v1/crx?response=redirect'
        + `&x=id%3D${edgeId}%26installsource%3Dondemand%26uc`
      target.extIdHint = edgeId
      return target
    }
    // 其它链接按直链尝试
    target.crxUrl = url
    return target
  }

  /** 商店详情页 URL 中提取 32 位扩展 ID（path 末段匹配） */
  private static storeIdOf(url: string, hosts: string[]): string {
    const lower: string = url.toLowerCase()
    let hit: boolean = false
    for (const h of hosts) {
      if (lower.includes(h)) {
        hit = true
        break
      }
    }
    if (!hit) {
      return ''
    }
    const path: string = url.split('?')[0]
    const segs: string[] = path.split('/')
    for (let i: number = segs.length - 1; i >= 0; i--) {
      const seg: string = segs[i]
      if (/^[a-p]{32}$/.test(seg)) {
        return seg
      }
    }
    return ''
  }

  /** 商店详情页 URL → 32 位扩展 ID（CWS / Edge Add-ons；非详情页返回 ''） */
  static storeExtIdOf(url: string): string {
    const cwsId: string =
      ExtensionEngine.storeIdOf(url, ['chromewebstore.google.com', 'chrome.google.com'])
    if (cwsId !== '') {
      return cwsId
    }
    return ExtensionEngine.storeIdOf(url, ['microsoftedge.microsoft.com'])
  }

  /** 商店站点页（含首页/列表，SPA 可达详情页）→ 是否注入直装浮层 */
  static isStoreSite(url: string): boolean {
    const lower: string = url.toLowerCase()
    return lower.includes('chromewebstore.google.com') || lower.includes('chrome.google.com')
      || lower.includes('microsoftedge.microsoft.com') || lower.includes('crxsoso.com')
  }

  // ==================== i18n ====================

  /**
   * Chrome 风格 UI 语言（chrome.i18n.getUILanguage 返回值）：
   * 跟随应用语言设置（zh→zh-CN，en→en，system→系统语言；中文按文字系统分简繁）
   */
  static chromeUiLocale(): string {
    if (appSettings.language === 'zh') {
      return 'zh-CN'
    }
    if (appSettings.language === 'en') {
      return 'en'
    }
    try {
      const sys: string = i18n.System.getSystemLanguage()
      if (sys.startsWith('zh')) {
        return sys.includes('Hant') ? 'zh-TW' : 'zh-CN'
      }
      const primary: string = sys.split('-')[0]
      return primary !== '' ? primary.toLowerCase() : 'en'
    } catch (e) {
      logger.warn(`chromeUiLocale: ${e}`)
      return 'en'
    }
  }

  /**
   * 读取 _locales/<locale>/messages.json（键转小写；文件缺失返回空表）。
   * Chrome 语义回退链：先 UI 语言（zh-CN→zh_CN、zh），再 manifest default_locale
   * @param extDir 扩展解包目录
   * @param locale UI 语言（chromeUiLocale()）
   * @param fallback manifest default_locale（缺省 'en'）
   */
  static readLocaleMessages(extDir: string, locale: string, fallback: string): Map<string, ExtLocaleMessage> {
    const candidates: string[] = []
    ExtensionEngine.pushLocaleCandidate(candidates, locale)
    ExtensionEngine.pushLocaleCandidate(candidates, fallback)
    for (const c of candidates) {
      const map: Map<string, ExtLocaleMessage> = ExtensionEngine.readLocaleMessagesExact(extDir, c)
      if (map.size > 0) {
        return map
      }
    }
    return new Map()
  }

  /** 语言候选入列（- 转 _，附基础语言；去重保序） */
  private static pushLocaleCandidate(out: string[], locale: string): void {
    const clean: string = locale.replace(/-/g, '_').replace(/^_+|_+$/g, '')
    if (clean !== '' && !out.includes(clean)) {
      out.push(clean)
    }
    const base: string = clean.split('_')[0]
    if (base !== '' && !out.includes(base)) {
      out.push(base)
    }
  }

  /** 精确读取单语言目录 messages.json */
  private static readLocaleMessagesExact(extDir: string, locale: string): Map<string, ExtLocaleMessage> {
    const map: Map<string, ExtLocaleMessage> = new Map()
    const text: string = ExtensionEngine.readTextFile(`${extDir}/_locales/${locale}/messages.json`, 512 * 1024)
    if (text === '') {
      return map
    }
    try {
      const raw: Record<string, ExtLocaleMessageRaw> = JSON.parse(text) as Record<string, ExtLocaleMessageRaw>
      const keys: string[] = Object.keys(raw)
      for (const k of keys) {
        const item: ExtLocaleMessageRaw | undefined = raw[k]
        if (item === undefined || item === null || typeof item !== 'object') {
          continue
        }
        const msg: ExtLocaleMessage = new ExtLocaleMessage()
        msg.message = typeof item.message === 'string' ? item.message : ''
        if (item.placeholders !== undefined && item.placeholders !== null && typeof item.placeholders === 'object') {
          const phKeys: string[] = Object.keys(item.placeholders)
          for (const pk of phKeys) {
            const ph: ExtPlaceholderRaw | undefined = item.placeholders[pk]
            if (ph === undefined || ph === null || typeof ph !== 'object') {
              continue
            }
            const clean: ExtPlaceholderRaw = new ExtPlaceholderRaw()
            clean.content = typeof ph.content === 'string' ? ph.content : ''
            msg.placeholders[pk.toUpperCase()] = clean
          }
        }
        if (msg.message !== '') {
          map.set(k.toLowerCase(), msg)
        }
      }
    } catch (e) {
      logger.warn(`readLocaleMessages 解析失败: ${e}`)
    }
    return map
  }

  /**
   * __MSG_key__ 值解析（manifest name/description 安装期解析用）
   */
  static resolveI18nValue(value: string, messages: Map<string, ExtLocaleMessage>): string {
    if (!value.startsWith('__MSG_')) {
      return value
    }
    const key: string = value.substring(6).replace(/__$/, '').toLowerCase()
    const msg: ExtLocaleMessage | undefined = messages.get(key)
    if (msg === undefined) {
      return ''
    }
    let s: string = msg.message
    const phKeys: string[] = Object.keys(msg.placeholders)
    for (const pk of phKeys) {
      const ph: ExtPlaceholderRaw | undefined = msg.placeholders[pk]
      s = s.split('$' + pk + '$').join(ph === undefined ? '' : ph.content)
    }
    return s
  }

  /**
   * i18n 消息表 → 页面注入 JSON（{"key":{"message":"..","placeholders":{"K":{"content":".."}}}}）
   */
  static messagesJson(messages: Map<string, ExtLocaleMessage>): string {
    if (messages.size === 0) {
      return '{}'
    }
    let s: string = '{'
    let first: boolean = true
    messages.forEach((msg: ExtLocaleMessage, key: string): void => {
      if (!first) {
        s += ','
      }
      s += JSON.stringify(key) + ':{' + JSON.stringify('message') + ':' + JSON.stringify(msg.message)
      const phKeys: string[] = Object.keys(msg.placeholders)
      if (phKeys.length > 0) {
        s += ',' + JSON.stringify('placeholders') + ':{'
        let phFirst: boolean = true
        for (const pk of phKeys) {
          const ph: ExtPlaceholderRaw | undefined = msg.placeholders[pk]
          if (ph === undefined) {
            continue
          }
          if (!phFirst) {
            s += ','
          }
          s += JSON.stringify(pk) + ':{' + JSON.stringify('content') + ':' + JSON.stringify(ph.content) + '}'
          phFirst = false
        }
        s += '}'
      }
      s += '}'
      first = false
    })
    return s + '}'
  }

  // ==================== 文件读取 ====================

  /**
   * 同步读取 UTF-8 文本（超限/缺失返回 ''；上限字节）
   */
  static readTextFile(path: string, maxBytes: number): string {
    try {
      if (!fileIo.accessSync(path)) {
        return ''
      }
      const src: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      try {
        const stat: fileIo.Stat = fileIo.statSync(src.fd)
        if (stat.size <= 0 || stat.size > maxBytes) {
          return ''
        }
        const buf: ArrayBuffer = new ArrayBuffer(stat.size)
        fileIo.readSync(src.fd, buf)
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        return decoder.decodeToString(new Uint8Array(buf))
      } finally {
        fileIo.closeSync(src)
      }
    } catch (e) {
      logger.warn(`readTextFile ${path}: ${e}`)
      return ''
    }
  }
}
