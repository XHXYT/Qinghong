import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { tabsVM, TabInfo } from './TabsViewModel';
import { netLogVM, NetLogEntry, NetworkLogViewModel } from './NetworkLogViewModel';
import { downloadVM } from './DownloadViewModel';
import { WebScripts } from '../common/utils/scripts/WebScripts';
import { toastUtil } from '../common/utils/ui/ToastUtils';

/** 嗅探到的媒体资源条目（kind: video | audio | image） */
export class SniffResource {
  readonly url: string
  readonly kind: string
  readonly fileName: string
  readonly host: string

  constructor(url: string, kind: string) {
    this.url = url
    this.kind = kind
    this.fileName = ResourceSniffViewModel.fileNameOf(url)
    this.host = NetworkLogViewModel.hostOf(url)
  }
}

/** 嗅探面板类型筛选 */
const SNIFF_FILTERS: string[] = ['all', 'video', 'audio', 'image']

/** JS 采集结果原始条目 */
class SniffRawItem {
  u: string = ''
  k: string = ''
}

/**
 * 资源嗅探：双数据源合并当前标签页的媒体资源——
 * 1) 网络日志（onInterceptRequest 轻量记录，Sec-Fetch-Dest/后缀分类；无痕标签不记录）
 * 2) 打开面板时页面 JS 按需扫描（DOM 媒体元素 + performance 条目，补 <video> 元素等）
 * HLS 聚合：存在 m3u8 时丢弃 .ts 分片；排序视频 > 音频 > 图片
 */
@ObservedV2
export class ResourceSniffViewModel {

  /** 嗅探面板显隐（Toolbar/MergedActionBar bindSheet 绑定） */
  @Trace showPanel: boolean = false
  @Trace resources: SniffResource[] = []
  @Trace filter: string = 'all'
  @Trace collecting: boolean = false

  static filters(): string[] {
    return SNIFF_FILTERS
  }

  /** 类型徽标文案 */
  static kindBadge(kind: string): string {
    if (kind === 'video') {
      return 'VID'
    }
    if (kind === 'audio') {
      return 'AUD'
    }
    return 'IMG'
  }

  /** 打开嗅探面板：采集当前页媒体资源后弹出（内部全捕获，不会 reject） */
  async open(): Promise<void> {
    try {
      await this.collect()
    } catch (e) {
      // 采集失败也弹出（至少展示网络日志来源的条目）
    }
    this.showPanel = true
  }

  /** 采集当前标签页媒体资源：网络日志 + 页面 JS 扫描合并去重 */
  async collect(): Promise<void> {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      this.resources = []
      return
    }
    this.collecting = true
    this.filter = 'all'
    const seen: Set<string> = new Set<string>()
    const list: SniffResource[] = []
    // 数据源 1：网络日志当前标签的媒体请求（无痕标签不记录）
    for (const e of netLogVM.entries as NetLogEntry[]) {
      if (e.tabId === tab.id && e.status !== 'blocked'
        && (e.kind === 'video' || e.kind === 'audio' || e.kind === 'image')
        && !seen.has(e.url)) {
        seen.add(e.url)
        list.push(new SniffResource(e.url, e.kind))
      }
    }
    // 数据源 2：页面 JS 按需扫描
    if (tab.controller !== null) {
      const controller: webview.WebviewController = tab.controller
      try {
        const raw: string = await controller.runJavaScript(WebScripts.sniffCollectJs())
        const inner: string = ResourceSniffViewModel.unwrapJsString(raw)
        const arr: Object[] = JSON.parse(inner) as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const url: string = (rec['u'] as string) ?? ''
          const kind: string = (rec['k'] as string) ?? ''
          if (url === '' || seen.has(url)) {
            continue
          }
          if (kind === 'video' || kind === 'audio' || kind === 'image') {
            seen.add(url)
            list.push(new SniffResource(url, kind))
          }
        }
      } catch (e) {
        // JS 采集失败（阅读模式/源码页等无常规 DOM 环境）忽略，保留网络日志来源
      }
    }
    // HLS 聚合：页面存在 m3u8 清单时丢弃 .ts 分片条目
    let hasM3u8: boolean = false
    for (const r of list) {
      if (r.url.split('?')[0].toLowerCase().endsWith('.m3u8')) {
        hasM3u8 = true
        break
      }
    }
    let result: SniffResource[] = list
    if (hasM3u8) {
      result = list.filter((r: SniffResource): boolean =>
        !r.url.split('?')[0].toLowerCase().endsWith('.ts'))
    }
    // 排序：视频 > 音频 > 图片（同类保持采集顺序）
    result.sort((a: SniffResource, b: SniffResource): number =>
      ResourceSniffViewModel.kindOrder(a.kind) - ResourceSniffViewModel.kindOrder(b.kind))
    this.resources = result
    this.collecting = false
  }

  /** 当前筛选下的条目 */
  filtered(): SniffResource[] {
    if (this.filter === 'all') {
      return this.resources
    }
    return this.resources.filter((r: SniffResource): boolean => r.kind === this.filter)
  }

  /** 指定标签是否检测到视频/音频（悬浮嗅探按钮显隐；读 @Trace 数据保持响应） */
  hasMedia(tabId: number): boolean {
    for (const e of netLogVM.entries as NetLogEntry[]) {
      if (e.tabId === tabId && e.status !== 'blocked'
        && (e.kind === 'video' || e.kind === 'audio')) {
        return true
      }
    }
    return false
  }

  /** 下载资源（复用统一下载管线；带来源页面 Referer 防盗链） */
  download(r: SniffResource): void {
    const tab: TabInfo | null = tabsVM.activeTab
    downloadVM.download(r.url, tab !== null ? tab.url : '')
  }

  /** 复制资源链接 */
  copyLink(r: SniffResource): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, r.url)
    pasteboard.getSystemPasteboard().setData(data)
    toastUtil.showToast({ message: $r('app.string.link_copied') })
  }

  private static kindOrder(kind: string): number {
    if (kind === 'video') {
      return 0
    }
    if (kind === 'audio') {
      return 1
    }
    return 2
  }

  /** runJavaScript 字符串结果可能再包一层引号，剥开后才是脚本返回的 JSON 文本 */
  private static unwrapJsString(raw: string): string {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return JSON.parse(raw) as string
    }
    return raw
  }

  /** 从 URL 提取文件名（末段去参，URI 解码失败则原样返回） */
  static fileNameOf(url: string): string {
    const path: string = url.split('?')[0].split('#')[0]
    const seg: string = path.substring(path.lastIndexOf('/') + 1)
    if (seg === '') {
      return url
    }
    try {
      return decodeURIComponent(seg)
    } catch (e) {
      return seg
    }
  }
}

export const sniffVM: ResourceSniffViewModel = new ResourceSniffViewModel()
