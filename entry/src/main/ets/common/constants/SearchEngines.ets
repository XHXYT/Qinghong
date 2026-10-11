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

  static readonly BING: SearchEngine = new SearchEngine(
    'bing', '必应',
    'https://www.bing.com/search?q=%s',
    'https://www.bing.com',
    'https://api.bing.com/osjson.aspx?query=%s'
  )

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

  static readonly DUCKDUCKGO: SearchEngine = new SearchEngine(
    'duckduckgo', 'DuckDuckGo',
    'https://duckduckgo.com/?q=%s',
    'https://duckduckgo.com',
    'https://duckduckgo.com/ac/?q=%s&type=list'
  )

  static readonly BUILT_INS: SearchEngine[] = [
    SearchEngines.BING,
    SearchEngines.BAIDU,
    SearchEngines.GOOGLE,
    SearchEngines.DUCKDUCKGO
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
   * 按 id 获取引擎，找不到回退必应
   */
  static getEngine(id: string): SearchEngine {
    for (const e of SearchEngines.BUILT_INS) {
      if (e.id === id) return e
    }
    for (const ce of appSettings.custom_engines) {
      if (ce.id === id) return new SearchEngine(ce.id, ce.name, ce.url, '')
    }
    return SearchEngines.BING
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
