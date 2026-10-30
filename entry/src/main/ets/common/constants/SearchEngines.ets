import { appSettings, CustomSearchEngine } from "../entity/SettingsModel";

/**
 * 搜索引擎定义
 */
export class SearchEngine {
  id: string
  name: string
  /** 搜索模板，%s 为关键词占位 */
  searchUrl: string
  /** 主页地址 */
  home: string
  /** 联想接口模板，空串表示不支持联网联想 */
  suggestUrl: string

  constructor(id: string, name: string, searchUrl: string, home: string, suggestUrl: string = '') {
    this.id = id
    this.name = name
    this.searchUrl = searchUrl
    this.home = home
    this.suggestUrl = suggestUrl
  }
}

export class SearchEngines {

  static readonly BAIDU: SearchEngine = new SearchEngine(
    'baidu', '百度',
    'https://www.baidu.com/s?wd=%s',
    'https://www.baidu.com',
    ''
  )

  static readonly GOOGLE: SearchEngine = new SearchEngine(
    'google', '谷歌',
    'https://www.google.com/search?q=%s',
    'https://www.google.com',
    'https://suggestqueries.google.com/complete/search?client=firefox&q=%s'
  )

  static readonly BING: SearchEngine = new SearchEngine(
    'bing', '必应',
    'https://www.bing.com/search?q=%s',
    'https://www.bing.com',
    ''
  )

  static readonly SOGOU: SearchEngine = new SearchEngine(
    'sogou', '搜狗',
    'https://www.sogou.com/web?query=%s',
    'https://www.sogou.com',
    ''
  )

  static readonly SO360: SearchEngine = new SearchEngine(
    'so360', '360',
    'https://www.so.com/s?q=%s',
    'https://www.so.com',
    ''
  )

  static readonly TOUTIAO: SearchEngine = new SearchEngine(
    'toutiao', '头条',
    'https://so.toutiao.com/search?dvpf=pc&source=input&keyword=%s',
    'https://so.toutiao.com',
    ''
  )

  static readonly SHENMA: SearchEngine = new SearchEngine(
    'shenma', '神马',
    'https://m.sm.cn/s?q=%s',
    'https://m.sm.cn',
    ''
  )

  static readonly BUILT_INS: SearchEngine[] = [
    SearchEngines.BAIDU,
    SearchEngines.GOOGLE,
    SearchEngines.BING,
    SearchEngines.SOGOU,
    SearchEngines.SO360,
    SearchEngines.TOUTIAO,
    SearchEngines.SHENMA
  ]

  /**
   * 全部引擎（内置 + 自定义）
   */
  static getAllEngines(): SearchEngine[] {
    const result: SearchEngine[] = []
    for (const e of SearchEngines.BUILT_INS) {
      result.push(e)
    }
    for (const ce of appSettings.custom_engines) {
      result.push(new SearchEngine(ce.id, ce.name, ce.url, ''))
    }
    return result
  }

  /**
   * 按 id 获取引擎，找不到返回必应
   */
  static getEngine(id: string): SearchEngine {
    const found = SearchEngines.getEngineOrNull(id)
    return found ?? SearchEngines.BAIDU
  }

  /**
   * 按 id 获取引擎，找不到返回 null
   */
  static getEngineOrNull(id: string): SearchEngine | null {
    for (const e of SearchEngines.BUILT_INS) {
      if (e.id === id) return e
    }
    for (const ce of appSettings.custom_engines) {
      if (ce.id === id) return new SearchEngine(ce.id, ce.name, ce.url, '')
    }
    return null
  }

  /**
   * 当前搜索引擎
   */
  static getCurrentEngine(): SearchEngine {
    return SearchEngines.getEngine(appSettings.search_engine_id)
  }

  /**
   * 构造搜索 URL
   */
  static buildSearchUrl(engine: SearchEngine, keyword: string): string {
    return engine.searchUrl.replace('%s', encodeURIComponent(keyword))
  }

  /**
   * 构造联想请求 URL，不支持联想返回空串
   */
  static buildSuggestUrl(engine: SearchEngine, keyword: string): string {
    if (!engine.suggestUrl) return ''
    return engine.suggestUrl.replace('%s', encodeURIComponent(keyword))
  }
}

/**
 * 搜索工具栏引擎条目（id + 是否显示）
 */
@ObservedV2
export class ToolbarEngineEntry {
  @Trace id: string
  @Trace name: string
  @Trace enabled: boolean

  constructor(id: string, name: string, enabled: boolean) {
    this.id = id
    this.name = name
    this.enabled = enabled
  }
}

/**
 * 搜索工具栏引擎列表（持久化 + 全量引擎同步）
 */
export class SearchToolbarEngines {

  /**
   * 读取工具栏引擎列表：
   * - 顺序与开关存于 search_toolbar_engines（'id:1,id:0' 形式）
   * - 新增引擎（含自定义）自动追加且默认显示
   * - 已删除的引擎条目自动剔除
   */
  static list(): ToolbarEngineEntry[] {
    const all = SearchEngines.getAllEngines()
    const saved: Record<string, boolean> = {}
    const order: string[] = []
    const raw = appSettings.search_toolbar_engines
    if (raw) {
      for (const part of raw.split(',')) {
        const seg = part.trim()
        if (!seg) continue
        const idx = seg.lastIndexOf(':')
        if (idx <= 0) continue
        const id = seg.substring(0, idx)
        const flag = seg.substring(idx + 1) === '1'
        saved[id] = flag
        order.push(id)
      }
    }
    const result: ToolbarEngineEntry[] = []
    for (const id of order) {
      const engine = SearchEngines.getEngineOrNull(id)
      if (engine) {
        result.push(new ToolbarEngineEntry(engine.id, engine.name, saved[id] === true))
      }
    }
    // 引擎列表中出现但未记录的（新增内置/自定义），追加在末尾并默认显示
    for (const e of all) {
      if (!order.includes(e.id)) {
        result.push(new ToolbarEngineEntry(e.id, e.name, true))
      }
    }
    return result
  }

  /**
   * 持久化工具栏引擎列表
   */
  static save(entries: ToolbarEngineEntry[]): void {
    const parts: string[] = []
    for (const e of entries) {
      parts.push(`${e.id}:${e.enabled ? '1' : '0'}`)
    }
    appSettings.search_toolbar_engines = parts.join(',')
  }

  /**
   * 已启用（显示在工具菜单）的引擎
   */
  static enabledEngines(): ToolbarEngineEntry[] {
    return SearchToolbarEngines.list().filter((e: ToolbarEngineEntry): boolean => e.enabled)
  }
}

/**
 * URL 启发式判断
 */
export class UrlUtils {

  /**
   * 输入是否更像一个 URL
   */
  static isLikelyUrl(input: string): boolean {
    const t = input.trim()
    if (!t || t.length === 0) return false
    if (/\s/.test(t)) return false
    if (/^https?:\/\//i.test(t)) return true
    if (/^localhost(:\d+)?(\/|$)/i.test(t)) return true
    if (/^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/|$)/.test(t)) return true
    return /^[a-zA-Z0-9][a-zA-Z0-9.\-]*\.[a-zA-Z]{2,}(:\d+)?([\/?#].*)?$/.test(t)
  }

  /**
   * 补全协议头
   */
  static normalizeUrl(input: string): string {
    const t = input.trim()
    if (/^https?:\/\//i.test(t)) return t
    return 'https://' + t
  }

  /**
   * 从 URL 提取展示用主机名
   */
  static hostOf(url: string): string {
    try {
      const match = url.match(/^(https?:\/\/)([^\/?#]+)/i)
      if (match && match.length > 2) {
        return match[2]
      }
      return url
    } catch (e) {
      return url
    }
  }

  /**
   * 连接安全状态：https=secure / http=insecure / 其他 scheme（file:、data: 等）=unknown
   */
  static secureStateOf(url: string): string {
    if (/^https:\/\//i.test(url)) {
      return 'secure'
    }
    if (/^http:\/\//i.test(url)) {
      return 'insecure'
    }
    return 'unknown'
  }

  /**
   * 从 URL 提取文件名（下载用）
   */
  static fileNameOf(url: string): string {
    try {
      const noQuery = url.split('?')[0].split('#')[0]
      const segs = noQuery.split('/')
      const last = segs[segs.length - 1]
      if (last && /[.]/.test(last)) {
        return decodeURIComponent(last)
      }
      return ''
    } catch (e) {
      return ''
    }
  }
}
