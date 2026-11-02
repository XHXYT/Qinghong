import { webview } from '@kit.ArkWeb';
import { tabsVM, TabInfo } from './TabsViewModel';
import { netLogVM } from './NetworkLogViewModel';
import { WebScripts } from '../common/utils/WebScripts';
import { WebHostedPlayerSession } from '../components/browser/WebHostedPlayer';
import { toastUtil } from '../common/utils/ToastUtils';

/** 网页播放中视频的原始采集结果（JS JSON，字段经 typeof 校验后拷入模型） */
interface PlayingVideoRaw {
  u?: string
  p?: number
  d?: number
  m?: boolean
  r?: number
  w?: boolean
}

/** 网页播放中视频信息（已校验） */
class PlayingVideoInfo {
  url: string = ''
  position: number = 0
  duration: number = 0
  muted: boolean = false
  readyState: number = 0
  wasPlaying: boolean = false
}

/**
 * 网页助手：悬浮按钮点击弹出助手菜单（资源嗅探/视频托管/投屏播放/下载视频）。
 * 视频托管走快速路径（免刷新秒接管，参考 AnimeZ 捕获引擎双通道）：
 * 1. DOM 探测网页播放中视频状态（主文档 + 同源 iframe，非侵入）；
 * 2. 直链缺失（MSE/blob src）或 DOM 不可达（跨域 iframe）时，用网络日志嗅探到的
 *    m3u8/mp4 直链补位（原生网络层 + iframe 嗅探上报双源，覆盖 hls.js/MSE 型播放器）；
 * 3. 拿到地址后暂停网页视频（打 __qhHosted 标记）→ 独立 AVPlayer 全屏托管续播；
 *    跨域 iframe 视频无法触碰则托管期间整页静音，关闭时恢复；
 * 4. 归还时 JS 凭标记定位网页视频恢复续播（不刷新页面）。
 */
@ObservedV2
export class WebAssistantViewModel {

  /** 助手菜单显隐（悬浮按钮点击开，菜单项/遮罩点击关） */
  @Trace showMenu: boolean = false
  /** 捕获到的可下载视频直链（DOM 严格采集 + 网络日志嗅探兜底；空 = 无可下载视频） */
  @Trace playingUrl: string = ''

  /** 打开助手菜单：先采集正在播放的视频直链（内部全捕获，不会 reject） */
  async openMenu(): Promise<void> {
    this.playingUrl = await WebAssistantViewModel.probePlayingUrl()
    this.showMenu = true
  }

  /** 关闭菜单 */
  closeMenu(): void {
    this.showMenu = false
  }

  /**
   * 视频托管触发（菜单项点击，免刷新秒接管）：
   * 1. 已有托管会话 → 直接唤起全屏托管播放器；
   * 2. DOM 探测播放中视频 → 直链或网络日志嗅探的 m3u8/mp4 补位；
   * 3. 暂停网页视频（可触及时）→ 独立 AVPlayer 全屏托管续播；跨域 iframe 视频改为整页静音；
   * 4. 无任何可播地址 → toast 提示，不动页面。
   */
  async triggerVideoHosting(): Promise<void> {
    this.closeMenu()
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.isIncognito || tab.isPopupWindow || tab.controller === null) {
      return
    }
    const controller: webview.WebviewController = tab.controller
    if (tab.hostedSession !== null) {
      // 已有托管会话：直接唤起全屏托管播放器
      tab.hostedSession.play()
      return
    }
    // 探测网页播放中视频状态（非侵入；MSE/blob 时直链为空）
    const info: PlayingVideoInfo | null = await WebAssistantViewModel.probeTakeoverInfo(controller)
    // 直链优先，MSE/blob 或 DOM 不可达时用网络日志嗅探的直链补位（覆盖跨域 iframe）
    let url: string = info !== null ? info.url : ''
    if (url === '') {
      url = netLogVM.latestVideoUrl(tab.id)
    }
    if (url === '') {
      toastUtil.showToast({ message: $r('app.string.video_hosting_not_found') })
      return
    }
    if (info !== null) {
      // 暂停网页视频并打标记（归还时凭标记恢复续播）
      try {
        controller.runJavaScript(WebScripts.pauseVideoJs())
          .catch((): void => {
          })
      } catch (e) {
        // 暂停失败不阻塞接管（网页视频与托管短暂并行）
      }
    } else {
      // DOM 不可达（跨域 iframe）：托管期间整页静音，关闭时恢复
      try {
        controller.setAudioMuted(true)
      } catch (e) {
      }
    }
    const session: WebHostedPlayerSession = this.createStandaloneSession(tab, url, info, controller)
    tab.hostedSession = session
    session.play()
    if (info !== null && info.position > 1) {
      // 起播定位：prepared 后立即 seek，起播 300ms 后校验未达再补 seek（HLS 早 seek 偶发被吞）
      session.setStartPos(info.position)
      session.seekTo(info.position)
    }
  }

  /** 建独立托管会话（handler=null，免内核直采网页视频）；关闭时恢复网页视频续播或解除静音 */
  private createStandaloneSession(tab: TabInfo, url: string, info: PlayingVideoInfo | null,
    controller: webview.WebviewController): WebHostedPlayerSession {
    // 模拟浏览器请求头（UA + Referer）提高 CDN 兼容性；获取失败仅退化为无 UA
    let ua: string = ''
    try {
      ua = webview.WebviewController.getDefaultUserAgent()
    } catch (e) {
      ua = ''
    }
    const headers: Record<string, string> = {}
    if (ua !== '') {
      headers['User-Agent'] = ua
    }
    if (tab.url !== '') {
      headers['Referer'] = tab.url
    }
    const session: WebHostedPlayerSession = new WebHostedPlayerSession(url,
      (): void => {
        if (tab.hostedSession === session) {
          tab.hostedSession = null
        }
      },
      (): void => {
        if (tab.hostedSession === session) {
          tab.hostedSession = null
        }
        if (info !== null) {
          this.restorePageVideo(session, info, controller)
        } else {
          WebAssistantViewModel.unmuteWebAudio(controller)
        }
      },
      null, `local_${Date.now()}`, headers, info !== null && info.muted)
    return session
  }

  /**
   * 归还网页视频：托管结束后按会话进度恢复网页内播放（JS 定位 + 恢复播放，不刷新页面）；
   * 会话进度无效（<1s，起播 seek 被吞等）时回退接管时网页进度；
   * 托管出错时播放态回退接管前网页播放态
   */
  private restorePageVideo(session: WebHostedPlayerSession, info: PlayingVideoInfo,
    controller: webview.WebviewController): void {
    const hostedPos: number = session.state.currentTime
    const pos: number = hostedPos > 1 ? hostedPos : info.position
    const wasPlaying: boolean = session.state.error ? info.wasPlaying : session.state.playing
    try {
      controller.runJavaScript(WebScripts.restoreVideoJs(pos, wasPlaying))
        .catch((): void => {
        })
    } catch (e) {
      // 页面已销毁等场景恢复失败，保持现状（网页后续操作自恢复）
    }
  }

  /** 采集当前标签正在播放的视频直链：DOM 严格采集，MSE/跨域 iframe 用网络日志嗅探兜底 */
  private static async probePlayingUrl(): Promise<string> {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null) {
      return ''
    }
    const controller: webview.WebviewController = tab.controller
    const info: PlayingVideoInfo | null = await WebAssistantViewModel.probePlayingInfo(controller)
    if (info !== null) {
      return info.url
    }
    return netLogVM.latestVideoUrl(tab.id)
  }

  /** 严格采集正在播放的直链视频信息（!paused && !ended && readyState>=2 且 http 直链；失败返回 null） */
  private static async probePlayingInfo(controller: webview.WebviewController): Promise<PlayingVideoInfo | null> {
    try {
      const raw: string = WebAssistantViewModel.unwrapJsString(
        await controller.runJavaScript(WebScripts.playingVideoInfoJs()))
      if (!raw.startsWith('{')) {
        return null
      }
      return WebAssistantViewModel.parseVideoInfo(raw, true)
    } catch (e) {
      return null
    }
  }

  /** 接管探测：播放中视频优先、暂停视频兜底，MSE/blob 保留（直链为空由网络日志补位；失败返回 null） */
  private static async probeTakeoverInfo(controller: webview.WebviewController): Promise<PlayingVideoInfo | null> {
    try {
      const raw: string = WebAssistantViewModel.unwrapJsString(
        await controller.runJavaScript(WebScripts.takeoverProbeJs()))
      if (!raw.startsWith('{')) {
        return null
      }
      return WebAssistantViewModel.parseVideoInfo(raw, false)
    } catch (e) {
      return null
    }
  }

  /** 解析采集 JSON 为已校验模型（requireUrl=false 时允许直链为空——MSE/blob 场景；格式非法返回 null） */
  private static parseVideoInfo(raw: string, requireUrl: boolean): PlayingVideoInfo | null {
    try {
      const obj: PlayingVideoRaw = JSON.parse(raw) as PlayingVideoRaw
      if (typeof obj.u !== 'string' || (requireUrl && obj.u === '')) {
        return null
      }
      const info: PlayingVideoInfo = new PlayingVideoInfo()
      info.url = obj.u
      info.position = typeof obj.p === 'number' && obj.p > 0 ? obj.p : 0
      info.duration = typeof obj.d === 'number' && obj.d > 0 ? obj.d : 0
      info.muted = obj.m === true
      info.readyState = typeof obj.r === 'number' ? obj.r : 0
      info.wasPlaying = obj.w === true
      return info
    } catch (e) {
      return null
    }
  }

  /** 跨域 iframe 视频托管结束时解除网页静音 */
  private static unmuteWebAudio(controller: webview.WebviewController): void {
    try {
      controller.setAudioMuted(false)
    } catch (e) {
      // 页面已销毁等场景忽略
    }
  }

  /** runJavaScript 字符串结果可能再包一层引号，剥开后才是脚本返回值 */
  private static unwrapJsString(raw: string): string {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return JSON.parse(raw) as string
    }
    return raw
  }
}

export const assistantVM: WebAssistantViewModel = new WebAssistantViewModel()
