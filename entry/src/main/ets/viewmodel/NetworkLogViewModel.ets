import { adBlockEngine } from '../common/utils/AdBlockEngine';

/**
 * 网络日志单条请求记录
 * status: load=已请求 | error=加载失败 | http=HTTP错误(4xx/5xx) | blocked=已拦截
 * kind: main=主文档 | js | css | image | other
 */
@ObservedV2
export class NetLogEntry {
  @Trace status: string = 'load'
  readonly seq: number
  readonly tabId: number
  readonly time: string
  readonly url: string
  readonly kind: string

  constructor(tabId: number, time: string, url: string, kind: string, status: string, seq: number) {
    this.tabId = tabId
    this.time = time
    this.url = url
    this.kind = kind
    this.status = status
    this.seq = seq
  }
}

/** 网络日志过滤器与标签（与 Via 一致用英文短标签） */
const NET_LOG_FILTERS: string[] = ['all', 'js', 'css', 'image', 'blocked', 'other']
const NET_LOG_FILTER_LABELS: string[] = ['All', 'JS', 'CSS', 'Image', 'Blocked', 'Other']

/**
 * 网络日志：记录每个标签页的页面请求（onInterceptRequest 轻量上报），
 * 主文档请求到达时重置该标签日志；错误/拦截状态由各回写接口标记
 */
@ObservedV2
export class NetworkLogViewModel {

  /** 全部请求记录（超上限丢弃最旧） */
  @Trace entries: NetLogEntry[] = []
  private static readonly MAX_ENTRIES: number = 1000
  /** 条目自增序号（Repeat 唯一键，避免同秒同 URL 键碰撞） */
  private static nextSeq: number = 0

  private static readonly JS_EXTS: string[] = ['.js', '.mjs']
  private static readonly CSS_EXTS: string[] = ['.css']
  private static readonly IMAGE_EXTS: string[] =
    ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.svg', '.ico', '.avif']

  /** 记录一条请求（onInterceptRequest 内调用，必须轻量）；主文档请求重置该标签日志 */
  recordRequest(tabId: number, request: WebResourceRequest, isMain: boolean): void {
    if (isMain) {
      this.clearTab(tabId)
    }
    const url: string = request.getRequestUrl()
    // 请求头取分类依据：Sec-Fetch-Dest（内核注入的精确资源类型）/ Accept
    let dest: string = ''
    let accept: string = ''
    const headers: Array<Header> = request.getRequestHeader()
    for (const h of headers) {
      const k: string = h.headerKey.toLowerCase()
      if (k === 'sec-fetch-dest') {
        dest = h.headerValue.toLowerCase()
      } else if (k === 'accept') {
        accept = h.headerValue
      }
    }
    this.append(tabId, url, isMain ? 'main' : NetworkLogViewModel.kindOf(url, dest, accept), 'load')
  }

  /** 标记加载失败（onErrorReceive） */
  markError(tabId: number, url: string): void {
    const e = this.findLast(tabId, url)
    if (e !== null && e.status === 'load') {
      e.status = 'error'
    }
  }

  /** 标记 HTTP 错误（onHttpErrorReceive，4xx/5xx） */
  markHttpError(tabId: number, url: string): void {
    const e = this.findLast(tabId, url)
    if (e !== null && e.status === 'load') {
      e.status = 'http'
    }
  }

  /** 批量标记已拦截（onAdsBlocked 周期上报）；未记录过的补录为已拦截条目 */
  markBlocked(tabId: number, urls: Array<string>): void {
    for (const url of urls) {
      const e = this.findLast(tabId, url)
      if (e !== null) {
        e.status = 'blocked'
      } else {
        this.append(tabId, url, NetworkLogViewModel.kindOf(url), 'blocked')
      }
    }
  }

  /** 清空指定标签的请求记录（新主文档导航时） */
  clearTab(tabId: number): void {
    this.entries = this.entries.filter((e: NetLogEntry): boolean => e.tabId !== tabId)
  }

  /**
   * 补记网页图标请求（onFaviconReceived 触发；favicon 由内核浏览器进程获取，
   * 不经过 onInterceptRequest）：按惯例记 origin + /favicon.ico，已存在则跳过
   */
  recordFavicon(tabId: number, pageUrl: string): void {
    const origin = NetworkLogViewModel.originOf(pageUrl)
    if (origin === '') {
      return
    }
    const favUrl = `${origin}/favicon.ico`
    if (this.findLast(tabId, favUrl) !== null) {
      return
    }
    this.append(tabId, favUrl, 'image', 'load')
  }

  /**
   * 长按条目切换拦截：把完整 URL 加入/移出广告拦截自定义规则并同步内核；
   * 返回切换后的状态（true=已拦截）。放行需刷新页面后生效
   */
  async toggleBlock(entry: NetLogEntry): Promise<boolean> {
    const current = adBlockEngine.loadCustomRulesSync()
    const lines: string[] = current.split('\n')
    let index = -1
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim() === entry.url) {
        index = i
        break
      }
    }
    if (index >= 0) {
      lines.splice(index, 1)
      await adBlockEngine.saveCustomRules(lines.join('\n'))
      entry.status = 'load'
      return false
    }
    const next = current.trim() !== ''
      ? `${current.replace(/\s+$/, '')}\n${entry.url}\n`
      : `${entry.url}\n`
    await adBlockEngine.saveCustomRules(next)
    entry.status = 'blocked'
    return true
  }

  /**
   * 长按条目切换域名拦截：把 ||host^ 加入/移出广告拦截自定义规则并同步内核，
   * 同时更新该标签下同域名全部条目状态；返回 true=已拦截
   */
  async toggleBlockDomain(entry: NetLogEntry): Promise<boolean> {
    const host = NetworkLogViewModel.hostOf(entry.url)
    if (host === '' || host === entry.url) {
      return false
    }
    const rule = `||${host}^`
    const current = adBlockEngine.loadCustomRulesSync()
    const lines: string[] = current.split('\n')
    let index = -1
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim() === rule) {
        index = i
        break
      }
    }
    let blocked: boolean
    if (index >= 0) {
      lines.splice(index, 1)
      await adBlockEngine.saveCustomRules(lines.join('\n'))
      blocked = false
    } else {
      const next = current.trim() !== ''
        ? `${current.replace(/\s+$/, '')}\n${rule}\n`
        : `${rule}\n`
      await adBlockEngine.saveCustomRules(next)
      blocked = true
    }
    for (const e of this.entries) {
      if (e.tabId === entry.tabId && NetworkLogViewModel.hostOf(e.url) === host) {
        e.status = blocked ? 'blocked' : 'load'
      }
    }
    return blocked
  }

  /** 域名拦截规则 ||host^ 是否已存在（菜单文案用） */
  isDomainBlocked(entry: NetLogEntry): boolean {
    const host = NetworkLogViewModel.hostOf(entry.url)
    if (host === '' || host === entry.url) {
      return false
    }
    const rule = `||${host}^`
    const lines: string[] = adBlockEngine.loadCustomRulesSync().split('\n')
    for (const line of lines) {
      if (line.trim() === rule) {
        return true
      }
    }
    return false
  }

  /** 过滤器选项与标签 */
  static filters(): string[] {
    return NET_LOG_FILTERS
  }

  static filterLabel(f: string): string {
    const index = NET_LOG_FILTERS.indexOf(f)
    return index >= 0 ? NET_LOG_FILTER_LABELS[index] : f
  }

  /** 条目类型徽标文案 */
  static kindBadge(kind: string): string {
    if (kind === 'main') {
      return 'DOC'
    }
    if (kind === 'js') {
      return 'JS'
    }
    if (kind === 'css') {
      return 'CSS'
    }
    if (kind === 'image') {
      return 'IMG'
    }
    return 'OTHER'
  }

  /** 从 URL 提取 host（副标显示用） */
  static hostOf(url: string): string {
    const rest: string = url.indexOf('://') >= 0 ? url.substring(url.indexOf('://') + 3) : url
    const host: string = rest.split('/')[0]
    return host !== '' ? host : url
  }

  /** 从 URL 提取 origin（scheme://host[:port]） */
  private static originOf(url: string): string {
    const m = url.indexOf('://')
    if (m < 0) {
      return ''
    }
    const rest = url.substring(m + 3)
    const hostPart = rest.split('/')[0]
    return hostPart !== '' ? `${url.substring(0, m + 3)}${hostPart}` : ''
  }

  private append(tabId: number, url: string, kind: string, status: string): void {
    this.entries.push(new NetLogEntry(tabId, NetworkLogViewModel.now(), url, kind, status,
      NetworkLogViewModel.nextSeq++))
    if (this.entries.length > NetworkLogViewModel.MAX_ENTRIES) {
      this.entries.splice(0, this.entries.length - NetworkLogViewModel.MAX_ENTRIES)
    }
  }

  /** 从尾部找该标签下此 URL 的最近记录 */
  private findLast(tabId: number, url: string): NetLogEntry | null {
    for (let i = this.entries.length - 1; i >= 0; i--) {
      const e = this.entries[i]
      if (e.tabId === tabId && e.url === url) {
        return e
      }
    }
    return null
  }

  /** HH:mm:ss */
  private static now(): string {
    const d = new Date()
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
  }

  /**
   * 请求类型判定（无扩展名 URL 归类为 other 的根因修复）：
   * Sec-Fetch-Dest（内核按资源类型注入，精确）> Accept 头 > URL 后缀兜底
   */
  private static kindOf(url: string, dest: string = '', accept: string = ''): string {
    if (dest === 'image') {
      return 'image'
    }
    if (dest === 'script') {
      return 'js'
    }
    if (dest === 'style') {
      return 'css'
    }
    if (dest === 'document') {
      return 'main'
    }
    const a: string = accept.trim().toLowerCase()
    if (a.startsWith('image/')) {
      return 'image'
    }
    if (a.startsWith('text/css')) {
      return 'css'
    }
    if (a.startsWith('text/html') || a.startsWith('application/xhtml')) {
      return 'main'
    }
    // URL 后缀兜底（无请求头信息时，如 onAdsBlocked 补录）
    const lower: string = url.split('?')[0].split('#')[0].toLowerCase()
    for (const ext of NetworkLogViewModel.JS_EXTS) {
      if (lower.endsWith(ext)) {
        return 'js'
      }
    }
    for (const ext of NetworkLogViewModel.CSS_EXTS) {
      if (lower.endsWith(ext)) {
        return 'css'
      }
    }
    for (const ext of NetworkLogViewModel.IMAGE_EXTS) {
      if (lower.endsWith(ext)) {
        return 'image'
      }
    }
    return 'other'
  }
}

export const netLogVM: NetworkLogViewModel = new NetworkLogViewModel()
