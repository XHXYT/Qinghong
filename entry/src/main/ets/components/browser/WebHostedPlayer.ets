import { webview } from '@kit.ArkWeb';
import { media } from '@kit.MediaKit';
import { window, PiPWindow } from '@kit.ArkUI';
import { avSession, AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { createLogger } from '../../common/utils/app/Logger';
import { ResourceUtils } from '../../common/utils/app/ResourceUtil';
import { toastUtil } from '../../common/utils/ui/ToastUtils';
import { VideoFullScreen } from '../../common/utils/ui/VideoFullScreen';
import { QhState, _QhState } from '../../entryability/AppState';
import { appSettings } from '../../common/entity/SettingsModel';
import { VIDEO_KB_SHORTCUTS, parseVideoKbOverrides, kbKeyNameOf } from '../../common/constants/KbShortcuts';

const logger = createLogger('WebHostedPlayer')

/** AVPlayer 支持的倍速档位（无 1.5 档） */
const HOSTED_SPEEDS: number[] = [0.75, 1, 1.25, 1.75, 2]

/** 秒数格式化 mm:ss（超 1 小时 h:mm:ss） */
function formatHostedTime(seconds: number): string {
  const s: number = Math.max(0, Math.floor(seconds))
  const m: number = Math.floor(s / 60)
  const h: number = Math.floor(m / 60)
  if (h > 0) {
    return `${h}:${m % 60 < 10 ? '0' : ''}${m % 60}:${s % 60 < 10 ? '0' : ''}${s % 60}`
  }
  return `${m}:${s % 60 < 10 ? '0' : ''}${s % 60}`
}

/** 托管播放器 UI 状态（全屏视图渲染） */
@ObservedV2
export class WebHostedState {
  /** 全屏托管播放器显隐 */
  @Trace show: boolean = false
  /** AVPlayer 播放中 */
  @Trace playing: boolean = false
  /** 缓冲中（显示加载指示器） */
  @Trace buffering: boolean = true
  /** 解码/播放出错（显示错误提示） */
  @Trace error: boolean = false
  /** 当前播放位置（秒） */
  @Trace currentTime: number = 0
  /** 总时长（秒） */
  @Trace duration: number = 0
  /** 当前倍速（0.75/1/1.25/1.75/2） */
  @Trace speed: number = 1
  /** 播放比例模式（0=适应留黑边、1=填充裁剪、2=拉伸） */
  @Trace scaleMode: number = 0
  /** 循环播放 */
  @Trace looping: boolean = false
  /** 视频宽（px，videoSizeChange 上报；0=未知） */
  @Trace videoWidth: number = 0
  /** 视频高（px，videoSizeChange 上报；0=未知） */
  @Trace videoHeight: number = 0
}

/** 播控命令（prepared 前入队，prepared 后按序执行） */
interface WebHostedCommand {
  run: () => void
}

/**
 * 视频托管会话（官方 enableNativeMediaPlayer 内核级接管）：
 * 内核 onCreateNativeMediaPlayer 创建 → 全屏托管播放器（应用窗口沉浸层）→
 * AVPlayer 播放 → 内核播控命令（NativeMediaPlayerBridge）→ 状态回报（NativeMediaPlayerHandler）。
 * 播控命令经队列等 prepared 后按序执行；MSE/blob 由创建侧过滤返回 null 交回内核。
 */
export class WebHostedPlayerSession implements webview.NativeMediaPlayerBridge {
  readonly state: WebHostedState = new WebHostedState()
  readonly embedId: string
  readonly surfaceKey: string
  readonly xComponentController: XComponentController = new XComponentController()

  private readonly handler: webview.NativeMediaPlayerHandler | null
  private readonly url: string
  private readonly headers: Record<string, string>
  private readonly onReleased: () => void
  private readonly onClose: () => void
  private avPlayer: media.AVPlayer | null = null
  private surfaceId: string = ''
  private prepared: boolean = false
  private released: boolean = false
  private commands: WebHostedCommand[] = []
  private lastVolume: number = 1
  private muted: boolean = false
  private speedIdx: number = 1
  private boosting: boolean = false
  private speedBeforeBoost: number = 1
  private rewindTimer: number = -1
  private rewindTarget: number = 0
  private startSeekTarget: number = -1
  private startSeekTimer: number = -1

  /**
   * 会话构造：handler 为 null 时为「独立接管」模式（JS 直采网页视频，无内核回调），
   * 所有内核播控回报（NativeMediaPlayerHandler）静默跳过
   */
  constructor(url: string, onReleased: () => void, onClose: () => void,
    handler: webview.NativeMediaPlayerHandler | null, embedId: string,
    headers: Record<string, string>, muted: boolean) {
    this.url = url
    this.onReleased = onReleased
    this.onClose = onClose
    this.handler = handler
    this.embedId = embedId
    this.headers = headers
    this.muted = muted
    this.surfaceKey = `web_hosted_${embedId}`
    logger.info(`session created, embedId[${this.embedId}] url[${this.url}] standalone[${handler === null}]`)
  }

  /** XComponent surface 就绪（onLoad）：启动底层 AVPlayer；视图重挂载换 surface 时重绑 */
  onSurfaceReady(): void {
    if (this.released) {
      return
    }
    this.surfaceId = this.xComponentController.getXComponentSurfaceId()
    const p: media.AVPlayer | null = this.avPlayer
    if (p !== null) {
      try {
        p.surfaceId = this.surfaceId
      } catch (e) {
        logger.error(`rebind surface failed: ${e}`)
      }
      return
    }
    this.setupPlayer()
  }

  /** 返回/关闭托管播放器：释放会话并回调宿主刷新页面（恢复网页内播放） */
  close(): void {
    if (this.released) {
      return
    }
    this.release()
    this.onClose()
  }

  /** 退出全屏（页面主动请求）：暂停并隐藏，会话保留可再唤起 */
  hide(): void {
    this.pause()
    this.state.show = false
  }

  /** 媒体直链（投屏远端拉流源；托管模式创建侧已过滤 MSE/blob，恒为 http(s)） */
  getUrl(): string {
    return this.url
  }

  /** 控制栏：播放/暂停切换 */
  togglePlay(): void {
    if (this.state.playing) {
      this.pause()
    } else {
      this.play()
    }
  }

  /** 控制栏：进度拖拽定位（秒） */
  seekTo(targetTime: number): void {
    this.seek(targetTime)
  }

  /** 独立接管：设置起播定位目标（秒）——prepared 后立即 seek，起播 300ms 后校验未达再补 seek */
  setStartPos(pos: number): void {
    if (pos > 1) {
      this.startSeekTarget = pos
    }
  }

  /** 控制栏：倍速循环切换（0.75X → 1X → 1.25X → 1.75X → 2X） */
  cycleSpeed(): void {
    this.speedIdx = (this.speedIdx + 1) % HOSTED_SPEEDS.length
    this.applySpeed(HOSTED_SPEEDS[this.speedIdx])
  }

  /** 相对跳转（秒，正值快进/负值快退），返回跳转目标位置；不可跳返回 -1 */
  seekBy(deltaSec: number): number {
    const duration: number = this.state.duration
    if (this.released || duration <= 0) {
      return -1
    }
    const base: number = this.state.currentTime
    const target: number = Math.min(duration, Math.max(0, base + deltaSec))
    if (Math.abs(target - base) < 0.5) {
      return -1
    }
    this.seek(target)
    return target
  }

  /** 当前音量（0-1，纵滑调节基线） */
  currentVolume(): number {
    return this.lastVolume
  }

  /** 当前是否静音（M 键切换用） */
  isMuted(): boolean {
    return this.muted
  }

  /** 长按右半屏：临时 2X 倍速（AVPlayer 无 3X 档），松手恢复原倍速；返回是否已启动 */
  speedBoost(): boolean {
    if (this.released || this.boosting || !this.state.playing) {
      return false
    }
    this.boosting = true
    this.speedBeforeBoost = this.state.speed
    this.applySpeed(2)
    return true
  }

  /** 结束临时倍速，恢复原倍速 */
  speedBoostEnd(): void {
    if (!this.boosting) {
      return
    }
    this.boosting = false
    this.applySpeed(this.speedBeforeBoost)
  }

  /** 长按左半屏：2X 连续快退（播放器不支持倒放，循环后退跳转实现）；返回是否已启动 */
  rewindStart(): boolean {
    if (this.released || this.state.duration <= 0 || this.rewindTimer !== -1) {
      return false
    }
    this.rewindTarget = this.state.currentTime
    this.rewindTick()
    this.rewindTimer = setInterval((): void => {
      this.rewindTick()
    }, 500)
    return true
  }

  /** 结束连续快退 */
  rewindStop(): void {
    if (this.rewindTimer !== -1) {
      clearInterval(this.rewindTimer)
      this.rewindTimer = -1
    }
  }

  /** 播放失败重试：重置状态并重建底层 AVPlayer，从头播放 */
  retry(): void {
    if (this.released) {
      return
    }
    const p: media.AVPlayer | null = this.avPlayer
    this.avPlayer = null
    this.prepared = false
    this.commands = []
    this.rewindStop()
    this.boosting = false
    this.speedIdx = 1
    this.startSeekTarget = -1
    if (this.startSeekTimer !== -1) {
      clearTimeout(this.startSeekTimer)
      this.startSeekTimer = -1
    }
    this.state.error = false
    this.state.buffering = true
    this.state.playing = false
    this.state.currentTime = 0
    this.state.speed = 1
    if (p !== null) {
      p.release().catch((): void => {
      })
    }
    this.setupPlayer()
    this.play()
  }

  /** 内核 embed 位置变化：全屏托管无原位渲染，忽略 */
  updateRect(_x: number, _y: number, _width: number, _height: number): void {
  }

  play(): void {
    if (this.released) {
      return
    }
    this.state.show = true
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.play().catch((): void => {
        })
      }
    })
  }

  pause(): void {
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.pause().catch((): void => {
        })
      }
    })
  }

  seek(targetTime: number): void {
    if (this.handler !== null) {
      this.handler.handleSeeking()
    }
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.seek(Math.max(0, Math.floor(targetTime * 1000)))
      }
    })
  }

  setVolume(volume: number): void {
    this.lastVolume = Math.min(1, Math.max(0, volume))
    if (this.muted) {
      return
    }
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.setVolume(this.lastVolume)
      }
    })
  }

  setMuted(muted: boolean): void {
    this.muted = muted
    const volume: number = muted ? 0 : this.lastVolume
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.setVolume(volume)
      }
    })
  }

  setPlaybackRate(playbackRate: number): void {
    const snapped: number = WebHostedPlayerSession.snapRate(playbackRate)
    for (let i = 0; i < HOSTED_SPEEDS.length; i++) {
      if (HOSTED_SPEEDS[i] === snapped) {
        this.speedIdx = i
        break
      }
    }
    this.applySpeed(snapped)
  }

  /** 设置面板：播放比例（0=适应留黑边、1=填充裁剪、2=拉伸） */
  setScaleMode(mode: number): void {
    this.state.scaleMode = mode
    const scale: media.VideoScaleType = WebHostedPlayerSession.scaleEnumOf(mode)
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.videoScaleType = scale
      }
    })
  }

  /** 设置面板：循环播放开关 */
  setLooping(on: boolean): void {
    this.state.looping = on
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.loop = on
      }
    })
  }

  release(): void {
    if (this.released) {
      return
    }
    this.released = true
    this.rewindStop()
    this.boosting = false
    this.startSeekTarget = -1
    if (this.startSeekTimer !== -1) {
      clearTimeout(this.startSeekTimer)
      this.startSeekTimer = -1
    }
    this.state.show = false
    this.commands = []
    const p: media.AVPlayer | null = this.avPlayer
    this.avPlayer = null
    this.prepared = false
    if (p !== null) {
      p.release().catch((): void => {
      })
    }
    logger.info(`session released, embedId[${this.embedId}]`)
    this.onReleased()
  }

  /** 页面请求视频全屏：托管播放器即全窗口，唤起并回报页面 */
  enterFullscreen(): void {
    if (this.released) {
      return
    }
    this.state.show = true
    if (this.handler !== null) {
      this.handler.handleFullscreenChanged(true)
    }
  }

  /** 页面退出视频全屏：隐藏托管播放器并回报页面（会话保留） */
  exitFullscreen(): void {
    this.hide()
    if (this.handler !== null) {
      this.handler.handleFullscreenChanged(false)
    }
  }

  /** 连续快退步进：每 500ms 后退 1 秒（2X 快退） */
  private rewindTick(): void {
    if (this.released) {
      this.rewindStop()
      return
    }
    this.rewindTarget = Math.max(0, this.rewindTarget - 1)
    this.state.currentTime = this.rewindTarget
    this.seek(this.rewindTarget)
  }

  /** 应用倍速（更新显示 + 命令队列下发） */
  private applySpeed(rate: number): void {
    this.state.speed = rate
    const speed: media.PlaybackSpeed = WebHostedPlayerSession.speedEnumOf(rate)
    this.enqueue((): void => {
      const p: media.AVPlayer | null = this.avPlayer
      if (p !== null) {
        p.setSpeed(speed)
      }
    })
  }

  /** 播控命令入队（prepared 前挂起，prepared 后按序执行） */
  private enqueue(run: () => void): void {
    if (this.released) {
      return
    }
    const cmd: WebHostedCommand = { run: run }
    this.commands.push(cmd)
    this.drain()
  }

  private drain(): void {
    if (this.released || !this.prepared || this.avPlayer === null) {
      return
    }
    const cmd: WebHostedCommand | undefined = this.commands.shift()
    if (cmd === undefined) {
      return
    }
    cmd.run()
    if (this.commands.length > 0) {
      setTimeout((): void => {
        this.drain()
      }, 0)
    }
  }

  private async setupPlayer(): Promise<void> {
    let p: media.AVPlayer | null = null
    try {
      p = await media.createAVPlayer()
    } catch (e) {
      logger.error(`createAVPlayer failed: ${e}`)
      return
    }
    if (this.released) {
      const created: media.AVPlayer = p
      created.release().catch((): void => {
      })
      return
    }
    const avp: media.AVPlayer = p
    this.avPlayer = avp
    avp.on('stateChange', (state: string): void => {
      this.onPlayerState(avp, state)
    })
    avp.on('error', (err: BusinessError): void => {
      if (this.avPlayer !== avp) {
        return
      }
      logger.error(`AVPlayer error ${err.code}: ${err.message}`)
      this.state.buffering = false
      this.state.error = true
      if (this.handler !== null) {
        this.handler.handleError(webview.MediaError.DECODE_ERROR, err.message)
      }
    })
    avp.on('timeUpdate', (t: number): void => {
      if (this.avPlayer !== avp) {
        return
      }
      this.state.currentTime = t / 1000
      if (this.handler !== null) {
        this.handler.handleTimeUpdate(t / 1000)
      }
    })
    avp.on('durationUpdate', (d: number): void => {
      if (this.avPlayer !== avp) {
        return
      }
      this.state.duration = d / 1000
      if (this.handler !== null) {
        this.handler.handleDurationChanged(d / 1000)
      }
    })
    avp.on('seekDone', (): void => {
      if (this.avPlayer !== avp) {
        return
      }
      if (this.handler !== null) {
        this.handler.handleSeekFinished()
      }
    })
    avp.on('videoSizeChange', (w: number, h: number): void => {
      if (this.avPlayer !== avp) {
        return
      }
      this.state.videoWidth = w
      this.state.videoHeight = h
      // 全屏托管展示中：尺寸已知后按视频方向补转横屏（挂载时尺寸未知只隐藏了系统栏）
      if (this.state.show && w > h) {
        VideoFullScreen.enter(w, h)
      }
      if (this.handler !== null) {
        this.handler.handleVideoSizeChanged(w, h)
      }
    })
    avp.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number): void => {
      if (this.avPlayer !== avp) {
        return
      }
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.state.buffering = true
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.state.buffering = false
        if (this.handler !== null) {
          this.handler.handleBufferedEndTimeChanged(value / 1000)
        }
      }
    })
    try {
      const source: media.MediaSource = media.createMediaSourceWithUrl(this.url, this.headers)
      await avp.setMediaSource(source, { preferredBufferDuration: 20 })
    } catch (e) {
      logger.error(`setMediaSource failed: ${e}`)
      if (this.avPlayer === avp) {
        this.state.buffering = false
        this.state.error = true
      }
    }
  }

  /** AVPlayer 状态机推进（回调校验当前实例，防旧实例串扰；状态回报内核保持网页状态同步） */
  private onPlayerState(avp: media.AVPlayer, state: string): void {
    if (this.avPlayer !== avp) {
      return
    }
    if (state === 'initialized') {
      avp.surfaceId = this.surfaceId
      avp.prepare().catch((): void => {
      })
    } else if (state === 'prepared') {
      this.prepared = true
      this.state.buffering = false
      // 应用设置面板参数：播放比例（默认 FIT 为拉伸铺满窗口，竖屏播横屏视频会变形）
      avp.videoScaleType = WebHostedPlayerSession.scaleEnumOf(this.state.scaleMode)
      avp.loop = this.state.looping
      if (this.muted) {
        avp.setVolume(0)
      } else if (this.lastVolume !== 1) {
        avp.setVolume(this.lastVolume)
      }
      this.drain()
    } else if (state === 'playing') {
      this.state.playing = true
      this.state.buffering = false
      this.checkStartSeek()
      if (this.handler !== null) {
        this.handler.handleStatusChanged(webview.PlaybackStatus.PLAYING)
      }
    } else if (state === 'paused') {
      this.state.playing = false
      if (this.handler !== null) {
        this.handler.handleStatusChanged(webview.PlaybackStatus.PAUSED)
      }
    } else if (state === 'completed') {
      this.state.playing = false
      this.state.currentTime = this.state.duration
      this.state.buffering = false
      if (this.handler !== null) {
        this.handler.handleStatusChanged(webview.PlaybackStatus.PAUSED)
        this.handler.handleEnded()
      }
    }
  }

  /**
   * 起播定位校验（一次性）：HLS 起播瞬间 seek 偶发被吞导致从 0 开始播放，
   * 起播 300ms 后仍在目标 2 秒外则补 seek（AVPlayer seek 后自动恢复播放）
   */
  private checkStartSeek(): void {
    if (this.startSeekTimer !== -1 || this.startSeekTarget < 0) {
      return
    }
    const target: number = this.startSeekTarget
    this.startSeekTimer = setTimeout((): void => {
      this.startSeekTimer = -1
      if (this.released || this.startSeekTarget < 0) {
        return
      }
      this.startSeekTarget = -1
      const cur: number = this.state.currentTime
      if (Math.abs(cur - target) > 2) {
        logger.info(`start pos missed, target[${target.toFixed(1)}] current[${cur.toFixed(1)}], re-seek`)
        this.seek(target)
      }
    }, 300)
  }

  /** 播放速率归档到 AVPlayer 支持的枚举档位（无 1.5 档，就近映射） */
  private static speedEnumOf(rate: number): media.PlaybackSpeed {
    if (rate < 1) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X
    }
    if (rate < 1.25) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X
    }
    if (rate < 1.75) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X
    }
    if (rate < 2) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_75_X
    }
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X
  }

  /** 页面设定倍速就近归档到支持档位 */
  private static snapRate(rate: number): number {
    let best: number = HOSTED_SPEEDS[0]
    for (const s of HOSTED_SPEEDS) {
      if (Math.abs(s - rate) < Math.abs(best - rate)) {
        best = s
      }
    }
    return best
  }

  /** 播放比例模式 → AVPlayer 缩放枚举（0=适应留黑边、1=填充裁剪、2=拉伸） */
  private static scaleEnumOf(mode: number): media.VideoScaleType {
    if (mode === 1) {
      return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP
    }
    if (mode === 2) {
      return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT
    }
    return media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT
  }
}

/**
 * 托管播放器全屏视图（挂 Index 根层，覆盖整个应用窗口）：
 * XComponent 承载 AVPlayer 画面 + 控制面板（参考 VideoPlayerController 布局）——
 * 顶部渐变栏（返回 + 页面标题 + 设置齿轮）、底部渐变栏（进度行 + 控件行：播放/暂停、倍速）、
 * 中部 缓冲/错误重试/暂停标识；设置面板（右上角齿轮唤起：播放比例、循环播放）；
 * 手势：单击切显、双击三等分快进快退/播放切换、
 * 横滑拖动进度（浮层提示）、长按左半屏 2X 快退 / 右半屏 2X 倍速、
 * 纵滑左半屏调亮度/右半屏调音量（与网页视频手势一致）；
 * 键盘快捷键（与网页视频共用键位设置：Space 播放暂停、←/→ ±5s、J/L ±10s、
 * ↑/↓ 音量、M 静音、F 全屏为空操作——托管播放器本就全屏）；
 * 控制面板 5 秒无操作自动隐藏（暂停/错误/设置面板打开时常显），控制栏区域手势屏蔽。
 */
@ComponentV2
export struct WebHostedPlayerView {
  @Require @Param session: WebHostedPlayerSession
  /** 页面标题（顶部栏展示） */
  @Require @Param title: string

  /** 控制面板显隐（5 秒无操作自动隐藏；暂停/错误态常显） */
  @Local controlsVisible: boolean = true
  /** 底部进度条拖拽中 */
  @Local sliderDragging: boolean = false
  @Local sliderValue: number = 0
  /** 横滑/双击跳转提示浮层显隐 */
  @Local seekDragging: boolean = false
  /** 浮层预览目标位置（秒） */
  @Local seekPreviewPos: number = 0
  /** 长按快退中 */
  @Local rewinding: boolean = false
  /** 长按临时倍速中 */
  @Local boosting: boolean = false
  /** 设置面板显隐（右上角齿轮唤起） */
  @Local settingsVisible: boolean = false
  /** 纵滑调节中（左半屏亮度/右半屏音量） */
  @Local slideDragging: boolean = false
  /** 纵滑目标：true=亮度（左半屏）、false=音量（右半屏） */
  @Local slideIsBrightness: boolean = true
  /** 纵滑当前值（0-1） */
  @Local slideValue: number = 1
  /** 播放区尺寸（手势分区分母） */
  @Local areaWidth: number = 0
  @Local areaHeight: number = 0
  /** 上/下控制栏高度（手势屏蔽区） */
  @Local topBarHeight: number = 0
  @Local bottomBarHeight: number = 0

  private hideTimer: number = -1
  private seekOverlayTimer: number = -1
  private slideHideTimer: number = -1
  private slideBase: number = 1
  /** 本次会话亮度记忆（纵滑起点续接上次值，组件卸载即重置） */
  private curBrightness: number = 1
  private panAxis: number = 0
  /** 键位名 → 动作 id（与网页视频共用设置，含用户自定义覆盖） */
  private keyActions: Record<string, string> = {}
  private panStartX: number = 0
  private panStartY: number = 0
  private gestureBlocked: boolean = false
  private seekDragStartPos: number = 0
  /** 原生画中画控制器（PiPWindow；null = 未创建） */
  private pipController: PiPWindow.PiPController | null = null
  /** 设备支持画中画（aboutToAppear 探测，按钮显隐依据） */
  @Local pipSupported: boolean = false
  /** 画中画窗口进行中（stateChange 上报） */
  @Local pipActive: boolean = false
  /** 投屏 AVSession（懒建；null = 未创建） */
  private castSession: avSession.AVSession | null = null
  /** 投屏设备选择器（bindSheet）显隐 */
  @Local castPickerVisible: boolean = false
  /** 投屏已连接远端（outputDeviceChange 上报） */
  @Local castingActive: boolean = false

  aboutToAppear(): void {
    this.scheduleAutoHide()
    // 原生画中画能力探测（PiPWindow：按钮显隐依据）
    this.pipSupported = PiPWindow.isPiPEnabled()
    // 进入全屏托管：隐藏系统状态栏/导航栏，视频尺寸已知且为横屏时转横屏
    // （尺寸起播后才上报，videoSizeChange 回调补转；竖屏视频保持当前方向）
    VideoFullScreen.enter(this.session.state.videoWidth, this.session.state.videoHeight)
    // 键位映射（归一化键名 → 动作 id），与网页视频注入脚本同一套设置
    if (appSettings.video_keyboard_shortcuts) {
      const ov: Record<string, string> = parseVideoKbOverrides(appSettings.video_kb_keys)
      for (const d of VIDEO_KB_SHORTCUTS) {
        let name: string = d.defKeyName
        const o: string = ov[d.id]
        if (o !== undefined && o !== '') {
          name = o
        }
        this.keyActions[name] = d.id
      }
    }
  }

  aboutToDisappear(): void {
    this.cancelHideTimer()
    this.clearSeekOverlay()
    this.cancelSlideHide()
    this.resetBrightness()
    // 退出全屏托管：恢复系统状态栏/导航栏与应用设置的屏幕方向
    VideoFullScreen.exit()
    this.session.rewindStop()
    this.session.speedBoostEnd()
    // 原生小窗/投屏资源释放（停 PiP 窗口 + 停投销毁会话）
    this.releasePip()
    this.releaseCast()
  }

  /** 暂停标识可见（可恢复的暂停态：已就绪、未出错、未在缓冲且未播放） */
  private isPauseMarkVisible(): boolean {
    const s: WebHostedState = this.session.state
    return !s.buffering && !s.error && s.duration > 0 && !s.playing
  }

  /** 控制面板可见时，y 坐标是否落在上/下控制栏手势屏蔽区（留 10px 容差） */
  private isInControlBarArea(y: number): boolean {
    return this.controlsVisible
      && (y < this.topBarHeight + 10 || y > this.areaHeight - this.bottomBarHeight - 10)
  }

  private cancelHideTimer(): void {
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer)
      this.hideTimer = -1
    }
  }

  /** 控制面板自动隐藏：可见期间 5 秒无操作隐藏（暂停/错误/设置面板打开时常显） */
  private scheduleAutoHide(): void {
    this.cancelHideTimer()
    if (this.settingsVisible || this.isPauseMarkVisible() || this.session.state.error) {
      this.controlsVisible = true
      return
    }
    this.hideTimer = setTimeout((): void => {
      this.controlsVisible = false
      this.hideTimer = -1
    }, 5000)
  }

  /** 单击：切换控制面板显隐（暂停/错误态保持常显） */
  private toggleControls(): void {
    if (this.isPauseMarkVisible() || this.session.state.error) {
      this.controlsVisible = true
      this.scheduleAutoHide()
      return
    }
    this.controlsVisible = !this.controlsVisible
    if (this.controlsVisible) {
      this.scheduleAutoHide()
    } else {
      this.cancelHideTimer()
    }
  }

  /** 打开设置面板（打开期间控制面板常显） */
  private openSettings(): void {
    this.settingsVisible = true
    this.cancelHideTimer()
    this.controlsVisible = true
  }

  /** 关闭设置面板，恢复控制面板自动隐藏计时 */
  private closeSettings(): void {
    this.settingsVisible = false
    this.scheduleAutoHide()
  }

  private clearSeekOverlay(): void {
    if (this.seekOverlayTimer !== -1) {
      clearTimeout(this.seekOverlayTimer)
      this.seekOverlayTimer = -1
    }
  }

  private cancelSlideHide(): void {
    if (this.slideHideTimer !== -1) {
      clearTimeout(this.slideHideTimer)
      this.slideHideTimer = -1
    }
  }

  /** 亮度恢复跟随系统（托管播放器卸载时，与网页视频退出全屏行为一致） */
  private resetBrightness(): void {
    const win: window.Window | undefined = _QhState.window
    if (win) {
      win.setWindowBrightness(-1).catch((): void => {
      })
    }
  }

  /** 纵滑应用：左半屏窗口亮度、右半屏播放器音量（0-1，滑到底静音） */
  private applySlide(value: number): void {
    const v: number = Math.min(1, Math.max(0, value))
    this.slideValue = v
    if (this.slideIsBrightness) {
      const win: window.Window | undefined = _QhState.window
      if (win) {
        win.setWindowBrightness(Math.max(0.02, v)).catch((): void => {
        })
      }
      this.curBrightness = v
    } else {
      this.session.setVolume(v)
      this.session.setMuted(v === 0)
    }
  }

  /** 音量浮层短暂显示（键盘 ↑/↓/M 用） */
  private showVolumeIndicator(v: number): void {
    this.slideIsBrightness = false
    this.slideValue = v
    this.slideDragging = true
    this.cancelSlideHide()
    this.slideHideTimer = setTimeout((): void => {
      this.slideDragging = false
      this.slideHideTimer = -1
    }, 400)
  }

  /** 键盘：音量步进 ±0.1 并浮层显示 */
  private nudgeVolume(delta: number): void {
    const v: number = Math.min(1, Math.max(0, this.session.currentVolume() + delta))
    this.session.setVolume(v)
    this.session.setMuted(v === 0)
    this.showVolumeIndicator(v)
  }

  /** 键盘快捷键分发（键位随设置与网页视频一致；返回是否消费） */
  private onHostedKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false
    }
    const name: string = kbKeyNameOf(event.keyCode)
    if (name === '') {
      return false
    }
    const act: string = this.keyActions[name]
    if (act === undefined || act === '') {
      return false
    }
    if (this.session.state.error) {
      return false
    }
    let used: boolean = true
    if (act === 'play') {
      this.session.togglePlay()
    } else if (act === 'back5') {
      this.showSeekDelta(-5)
    } else if (act === 'fwd5') {
      this.showSeekDelta(5)
    } else if (act === 'back10') {
      this.showSeekDelta(-10)
    } else if (act === 'fwd10') {
      this.showSeekDelta(10)
    } else if (act === 'volup') {
      this.nudgeVolume(0.1)
    } else if (act === 'voldown') {
      this.nudgeVolume(-0.1)
    } else if (act === 'mute') {
      const m: boolean = !this.session.isMuted()
      this.session.setMuted(m)
      this.showVolumeIndicator(m ? 0 : this.session.currentVolume())
    } else {
      // fullscreen：托管播放器本就全屏，空操作
      used = false
    }
    if (used) {
      // 唤起控制面板反馈并重新计时自动隐藏
      this.controlsVisible = true
      this.scheduleAutoHide()
      return true
    }
    return false
  }

  /** 双击左/右三分区：快退/快进 10 秒，浮层短暂提示 */
  private seekByDoubleTap(rewind: boolean): void {
    this.showSeekDelta(rewind ? -10 : 10)
  }

  /** 相对跳转并短暂显示浮层（双击 ±10s / 键盘 ±5s、±10s 共用） */
  private showSeekDelta(deltaSec: number): void {
    const s: WebHostedState = this.session.state
    if (s.error || s.duration <= 0) {
      return
    }
    const base: number = s.currentTime
    const target: number = this.session.seekBy(deltaSec)
    if (target < 0) {
      return
    }
    this.seekDragStartPos = base
    this.seekPreviewPos = target
    this.seekDragging = true
    this.clearSeekOverlay()
    this.seekOverlayTimer = setTimeout((): void => {
      this.seekDragging = false
      this.seekOverlayTimer = -1
    }, 600)
  }

  /** 拖动/双击跳转偏移描述文本 */
  private seekDeltaText(): Resource {
    const deltaSec: number = Math.round(this.seekPreviewPos - this.seekDragStartPos)
    if (deltaSec >= 0) {
      return $r('app.string.video_hosting_seek_fwd', deltaSec)
    }
    return $r('app.string.video_hosting_seek_back', -deltaSec)
  }

  /** 纵滑提示文案（资源取标签、代码拼 % 号——资源格式化的 %% 会原样输出两个百分号） */
  private slideLabelText(): string {
    const label: string = ResourceUtils.getString(this.slideIsBrightness
      ? $r('app.string.video_hosting_brightness')
      : $r('app.string.video_hosting_volume'))
    return `${label} ${Math.round(this.slideValue * 100)}%`
  }

  /** 进度条显示值：底部拖拽显示拖拽值，横滑显示预览值 */
  private sliderDisplayValue(): number {
    if (this.sliderDragging) {
      return this.sliderValue
    }
    if (this.seekDragging) {
      return this.seekPreviewPos
    }
    return this.session.state.currentTime
  }

  /** 原生画中画切换（进行中→停止；未启动→复用 XComponent surface 起 PiP 窗口） */
  private togglePiP(): void {
    logger.info(`togglePiP active=${this.pipActive} supported=${this.pipSupported}`)
    if (this.pipActive) {
      this.stopPipWindow()
      return
    }
    this.startPipWindow()
  }

  private startPipWindow(): void {
    logger.info('startPipWindow enter')
    const existing: PiPWindow.PiPController | null = this.pipController
    if (existing !== null) {
      logger.info('startPipWindow restart existing')
      existing.startPiP().catch((e: BusinessError): void => {
        logger.warn(`pip restart failed: ${e}`)
      })
      return
    }
    const config: PiPWindow.PiPConfiguration = {
      context: _QhState.Context,
      componentController: this.session.xComponentController,
      templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY
    }
    PiPWindow.create(config)
      .then((controller: PiPWindow.PiPController): void => {
        controller.on('stateChange', (state: PiPWindow.PiPState, reason: string): void => {
          logger.info(`pip state ${state} reason ${reason}`)
          if (state === PiPWindow.PiPState.STARTED) {
            this.pipActive = true
          } else if (state === PiPWindow.PiPState.STOPPED) {
            this.pipActive = false
          }
        })
        controller.on('controlEvent', (param: PiPWindow.ControlEventParam): void => {
          if (param.controlType === PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
            this.session.togglePlay()
          } else if (param.controlType === PiPWindow.PiPControlType.FAST_FORWARD) {
            this.session.seekTo(this.session.state.currentTime + 10)
          } else if (param.controlType === PiPWindow.PiPControlType.FAST_BACKWARD) {
            this.session.seekTo(Math.max(0, this.session.state.currentTime - 10))
          }
        })
        this.pipController = controller
        controller.startPiP().catch((e: BusinessError): void => {
          logger.error(`pip start failed: ${e}`)
          toastUtil.showToast({ message: $r('app.string.video_pip_fail') })
        })
      })
      .catch((e: BusinessError): void => {
        logger.error(`pip create failed: ${e}`)
        toastUtil.showToast({ message: $r('app.string.video_pip_fail') })
      })
  }

  private stopPipWindow(): void {
    const controller: PiPWindow.PiPController | null = this.pipController
    if (controller !== null) {
      controller.stopPiP().catch((e: BusinessError): void => {
        logger.warn(`pip stop failed: ${e}`)
      })
    }
  }

  /** 画中画资源释放（组件卸载：解注册 + 停窗口） */
  private releasePip(): void {
    const controller: PiPWindow.PiPController | null = this.pipController
    if (controller === null) {
      return
    }
    this.pipController = null
    this.pipActive = false
    controller.off('stateChange')
    controller.off('controlEvent')
    controller.stopPiP().catch((): void => {
    })
  }

  /** 原生投屏：懒建 AVSession（video）+ 激活后弹系统设备选择器（AVCastPicker） */
  private async startCast(): Promise<void> {
    logger.info('startCast enter (cast btn tapped)')
    try {
      if (this.castSession === null) {
        logger.info('cast: creating AVSession')
        const session: avSession.AVSession =
          await avSession.createAVSession(_QhState.Context, 'qinghong_video', 'video')
        this.castSession = session
        const meta: avSession.AVMetadata = {
          assetId: this.session.embedId,
          title: this.title,
          duration: Math.round(this.session.state.duration * 1000)
        }
        await session.setAVMetadata(meta)
        await session.setAVQueueItems([this.buildCastItem()])
        session.on('outputDeviceChange',
          (state: avSession.ConnectionState, device: avSession.OutputDeviceInfo): void => {
            this.onCastDeviceChange(state, device)
          })
        await session.activate()
        logger.info('cast: AVSession ready')
      }
      this.castPickerVisible = true
    } catch (e) {
      logger.error(`cast session init failed: ${e}`)
      toastUtil.showToast({ message: $r('app.string.video_cast_fail') })
    }
  }

  /** 投屏播放队列项（mediaUri 直链为远端拉流源） */
  private buildCastItem(): avSession.AVQueueItem {
    const desc: avSession.AVMediaDescription = {
      assetId: this.session.embedId,
      title: this.title,
      mediaUri: this.session.getUrl(),
      mediaType: 'video'
    }
    return { itemId: 0, description: desc }
  }

  /** 投屏设备连接变化：连接成功取 AVCastController 启动远端播放并暂停本地（防双端同播）；断开复位标记 */
  private onCastDeviceChange(state: avSession.ConnectionState, device: avSession.OutputDeviceInfo): void {
    logger.info(`cast device change state=${state} count=${device.devices.length}`)
    if (state === avSession.ConnectionState.STATE_CONNECTED) {
      this.castingActive = true
      this.castPickerVisible = false
      const session: avSession.AVSession | null = this.castSession
      if (session !== null) {
        session.getAVCastController()
          .then((controller: avSession.AVCastController): Promise<void> => controller.start(this.buildCastItem()))
          .catch((e: BusinessError): void => {
            logger.error(`cast start failed: ${e}`)
            toastUtil.showToast({ message: $r('app.string.video_cast_fail') })
          })
        this.session.pause()
      }
    } else if (state === avSession.ConnectionState.STATE_DISCONNECTED) {
      this.castingActive = false
    }
  }

  /** 投屏资源释放（组件卸载：停投 + 销毁会话；未投屏时 stopCasting 报 6600109 忽略） */
  private async releaseCast(): Promise<void> {
    const session: avSession.AVSession | null = this.castSession
    if (session === null) {
      return
    }
    this.castSession = null
    this.castingActive = false
    try {
      await session.stopCasting()
    } catch (e) {
      // 未建立投屏连接时忽略（6600109）
    }
    try {
      await session.destroy()
    } catch (e) {
      logger.warn(`cast session destroy failed: ${e}`)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: this.session.surfaceKey,
        type: XComponentType.SURFACE,
        controller: this.session.xComponentController
      })
        .onLoad(() => {
          // surface 就绪即启动/重绑底层 AVPlayer（缺失此接线会话永远停在缓冲中）
          this.session.onSurfaceReady()
        })
        .width('100%')
        .height('100%')

      // 拖动进度 / 长按快退快进提示浮层
      this.GestureIndicatorBuilder()

      // 控制面板（缓冲中也渲染，含中部加载/错误提示）
      if (this.controlsVisible || this.session.state.buffering) {
        this.ControlPanelBuilder()
      }

      // 设置面板（右上角齿轮唤起，点遮罩关闭）
      if (this.settingsVisible) {
        this.SettingsPanelBuilder()
      }

      // 暂停时中部暂停标识（点击恢复播放）
      this.CenterPauseMarkBuilder()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .key('webHostedPlayerRoot')
    .focusable(true)
    .onAppear(() => {
      // 抢占焦点：托管期间键盘事件不再进入底层网页（避免网页内视频误响应）
      try {
        this.getUIContext().getFocusController().requestFocus('webHostedPlayerRoot')
      } catch (e) {
      }
    })
    .onKeyEvent((event: KeyEvent): boolean => this.onHostedKey(event))
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 2 })
          .onAction((event: GestureEvent) => {
            const s: WebHostedState = this.session.state
            if (s.error) {
              return
            }
            const x: number = event.fingerList[0]?.localX ?? 0
            const y: number = event.fingerList[0]?.localY ?? 0
            if (this.isInControlBarArea(y)) {
              return
            }
            // 屏幕三等分：左 1/3 双击快退、右 1/3 双击快进、中间双击播放/暂停
            const third: number = this.areaWidth / 3
            if (x < third) {
              this.seekByDoubleTap(true)
            } else if (x > third * 2) {
              this.seekByDoubleTap(false)
            } else {
              this.session.togglePlay()
            }
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            this.toggleControls()
          })
      )
    )
    .onTouch(() => {
      // 控制面板可见期间的任意触摸（含子组件）重置自动隐藏计时
      if (this.controlsVisible) {
        this.scheduleAutoHide()
      }
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const w: Length = newArea.width
      const h: Length = newArea.height
      if (typeof w === 'number') {
        this.areaWidth = w
      }
      if (typeof h === 'number') {
        this.areaHeight = h
      }
    })
    .gesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart((event: GestureEvent) => {
          const s: WebHostedState = this.session.state
          this.panAxis = 0
          this.panStartX = event.fingerList[0]?.localX ?? 0
          this.panStartY = event.fingerList[0]?.localY ?? 0
          // 出错/无时长或起点落在控制栏屏蔽区时不响应本次滑动
          this.gestureBlocked = s.error || s.duration <= 0 || this.isInControlBarArea(this.panStartY)
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.gestureBlocked) {
            return
          }
          const currentX: number = event.fingerList[0]?.localX ?? 0
          const currentY: number = event.fingerList[0]?.localY ?? 0
          // 首次有效位移时判定轴向：横向 → 进度拖动，纵向 → 左半屏亮度/右半屏音量
          if (this.panAxis === 0) {
            const deltaX: number = currentX - this.panStartX
            const deltaY: number = currentY - this.panStartY
            if (Math.abs(deltaX) < 10 && Math.abs(deltaY) < 10) {
              return
            }
            if (Math.abs(deltaX) > Math.abs(deltaY)) {
              this.panAxis = 2
              this.seekDragging = true
              this.seekDragStartPos = this.session.state.currentTime
              this.seekPreviewPos = this.seekDragStartPos
              this.clearSeekOverlay()
            } else {
              this.panAxis = 1
              this.slideIsBrightness = this.panStartX < this.areaWidth / 2
              this.slideBase = this.slideIsBrightness ? this.curBrightness : this.session.currentVolume()
              this.slideDragging = true
              this.cancelSlideHide()
              this.applySlide(this.slideBase)
            }
          }
          if (this.panAxis === 2) {
            const width: number = this.areaWidth
            const duration: number = this.session.state.duration
            if (width <= 0 || duration <= 0) {
              return
            }
            // 滑过整个播放区宽度对应总时长，实时预览目标位置
            let target: number = this.seekDragStartPos + (currentX - this.panStartX) / width * duration
            target = Math.min(duration, Math.max(0, target))
            this.seekPreviewPos = target
          } else if (this.panAxis === 1) {
            // 上滑增大、下滑减小；滑过屏高 70% 对应全量程（与网页视频手势系数一致）
            this.applySlide(this.slideBase - (currentY - this.panStartY) / (this.areaHeight * 0.7))
          }
        })
        .onActionEnd(() => {
          if (!this.gestureBlocked && this.panAxis === 2) {
            // 松手才执行真正跳转，浮层短暂停留后消失
            this.session.seekTo(this.seekPreviewPos)
            this.clearSeekOverlay()
            this.seekOverlayTimer = setTimeout((): void => {
              this.seekDragging = false
              this.seekOverlayTimer = -1
            }, 600)
          }
          if (!this.gestureBlocked && this.panAxis === 1) {
            // 数值已实时生效，浮层短暂停留后消失
            this.cancelSlideHide()
            this.slideHideTimer = setTimeout((): void => {
              this.slideDragging = false
              this.slideHideTimer = -1
            }, 400)
          }
          this.gestureBlocked = false
          this.panAxis = 0
        })
    )
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction((event: GestureEvent) => {
          const s: WebHostedState = this.session.state
          if (s.error || s.duration <= 0) {
            return
          }
          const x: number = event.fingerList[0]?.localX ?? 0
          const y: number = event.fingerList[0]?.localY ?? 0
          if (this.isInControlBarArea(y)) {
            return
          }
          if (x < this.areaWidth / 2) {
            // 左半屏长按：2X 连续快退
            if (this.session.rewindStart()) {
              this.rewinding = true
            }
          } else {
            // 右半屏长按：临时 2X 倍速
            if (this.session.speedBoost()) {
              this.boosting = true
            }
          }
        })
        .onActionEnd(() => {
          if (this.rewinding) {
            this.rewinding = false
            this.session.rewindStop()
          }
          if (this.boosting) {
            this.boosting = false
            this.session.speedBoostEnd()
          }
        })
    )
    .bindSheet(this.castPickerVisible, this.CastPickerBuilder, {
      // 任意方式关闭（下滑/点外部）写回状态，避免残留导致下次不弹
      onDisappear: () => {
        this.castPickerVisible = false
      }
    })
  }

  /** 投屏设备选择器（系统 AVCastPicker，video 会话） */
  @Builder
  CastPickerBuilder() {
    Column() {
      AVCastPicker({
        sessionType: 'video',
        onStateChange: (state: AVCastPickerState): void => {
          logger.info(`cast picker state ${state}`)
        }
      })
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
  }

  /** 拖动进度 / 纵滑调节 / 长按快退快进提示浮层 */
  @Builder
  GestureIndicatorBuilder() {
    if (this.seekDragging || this.rewinding || this.boosting || this.slideDragging) {
      Column({ space: 8 }) {
        if (this.boosting) {
          Text($r('app.string.video_hosting_boost'))
            .fontColor(Color.White)
            .fontSize(16)
        } else if (this.slideDragging) {
          Text(this.slideLabelText())
            .fontColor(Color.White)
            .fontSize(16)
        } else {
          if (this.rewinding) {
            Text($r('app.string.video_hosting_rewind'))
              .fontColor(Color.White)
              .fontSize(16)
          } else {
            Text(this.seekDeltaText())
              .fontColor(Color.White)
              .fontSize(16)
          }
          Text(`${formatHostedTime(this.rewinding ? this.session.state.currentTime : this.seekPreviewPos)} / ` +
            `${formatHostedTime(this.session.state.duration)}`)
            .fontColor(Color.White)
            .fontSize(14)
        }
      }
      .padding({ left: 32, right: 32, top: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#80000000')
      .borderRadius(16)
    }
  }

  /** 暂停时中部暂停标识（半透明圆形，点击恢复播放） */
  @Builder
  CenterPauseMarkBuilder() {
    if (this.isPauseMarkVisible()) {
      Column() {
        SymbolGlyph($r('sys.symbol.play'))
          .fontSize(32)
          .fontColor([Color.White])
      }
      .width(72)
      .height(72)
      .borderRadius(36)
      .backgroundColor('#66000000')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.session.togglePlay()
      })
    }
  }

  /** 控制面板：RelativeContainer 上/下渐变控制栏 + 中部加载/错误提示 */
  @Builder
  ControlPanelBuilder() {
    RelativeContainer() {
      // 上控制栏：返回 + 页面标题
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontColor([Color.White])
          .margin({ left: 20 })
          .onClick(() => {
            this.session.close()
          })
        Text(this.title)
          .fontColor(Color.White)
          .fontSize(14)
          .fontWeight(500)
          .layoutWeight(1)
          .margin({ left: 16 })
          .align(Alignment.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(22)
          .fontColor([Color.White])
          .margin({ right: 20 })
          .onClick(() => {
            this.openSettings()
          })
      }
      .width('100%')
      .padding({ top: 16, bottom: 12 })
      .linearGradient({
        angle: 180,
        colors: [['#000000', 0.0], ['#80000000', 0.5], ['#00000000', 1.0]]
      })
      .id('hostedTopBar')
      .alignRules({
        top: { anchor: '__container__', align: VerticalAlign.Top }
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const h: Length = newArea.height
        if (typeof h === 'number') {
          this.topBarHeight = h
        }
      })

      // 中部缓冲指示
      if (!this.session.state.error && this.session.state.buffering) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(Color.White)
          Text($r('app.string.video_hosting_buffering'))
            .fontColor(Color.White)
            .fontSize(14)
        }
        .padding({ left: 32, right: 32, top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#80000000')
        .borderRadius(16)
        .alignRules({
          middle: { anchor: '__container__', align: HorizontalAlign.Center },
          center: { anchor: '__container__', align: VerticalAlign.Center }
        })
      }

      // 中部播放错误：点击重试
      if (this.session.state.error) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
            .fontSize(32)
            .fontColor([Color.White])
          Text($r('app.string.video_host_play_failed'))
            .fontColor(Color.White)
            .fontSize(14)
          Text($r('app.string.video_hosting_retry'))
            .fontColor('rgba(255,255,255,0.7)')
            .fontSize(12)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .alignRules({
          middle: { anchor: '__container__', align: HorizontalAlign.Center },
          center: { anchor: '__container__', align: VerticalAlign.Center }
        })
        .onClick(() => {
          this.session.retry()
        })
      }

      // 下控制栏：进度行（时间 + 进度条 + 总时长）+ 控件行（播放/暂停、倍速）
      Column() {
        Row() {
          Text(formatHostedTime(this.sliderDisplayValue()))
            .fontSize(12)
            .margin({ left: 12, right: 6 })
            .fontColor(Color.White)
          Slider({
            value: this.sliderDisplayValue(),
            min: 0,
            max: Math.max(this.session.state.duration, 1),
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .blockColor(Color.White)
            .trackColor('rgba(255,255,255,0.4)')
            .trackThickness(2)
            .selectedColor(Color.White)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                this.sliderDragging = true
                this.sliderValue = value
                this.cancelHideTimer()
              } else {
                this.sliderDragging = false
                this.sliderValue = value
                this.session.seekTo(value)
                this.scheduleAutoHide()
              }
            })
          Text(formatHostedTime(this.session.state.duration))
            .fontSize(12)
            .margin({ left: 6, right: 12 })
            .fontColor(Color.White)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          SymbolGlyph(this.session.state.playing ? $r('sys.symbol.pause') : $r('sys.symbol.play'))
            .fontSize(24)
            .fontColor([Color.White])
            .margin({ left: 16 })
            .onClick(() => {
              this.session.togglePlay()
              this.scheduleAutoHide()
            })
          Blank()
          if (this.pipSupported) {
            SymbolGlyph($r('sys.symbol.smal_window_playback'))
              .fontSize(22)
              .fontColor([Color.White])
              .margin({ right: 18 })
              .onClick(() => {
                this.togglePiP()
                this.scheduleAutoHide()
              })
          }
          SymbolGlyph($r('sys.symbol.airplayaudio'))
            .fontSize(22)
            .fontColor([Color.White])
            .margin({ right: 18 })
            .onClick(() => {
              this.startCast()
              this.scheduleAutoHide()
            })
          Text(`${this.session.state.speed}X`)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderWidth(1)
            .borderColor(Color.White)
            .borderRadius(4)
            .fontSize(12)
            .fontColor(Color.White)
            .margin({ right: 16 })
            .onClick(() => {
              this.session.cycleSpeed()
              this.scheduleAutoHide()
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 6 })
      }
      .padding({ top: 10, bottom: 10 })
      .width('100%')
      .linearGradient({
        angle: 180,
        colors: [['#00000000', 0.0], ['#80000000', 0.5], ['#ff000000', 1.0]]
      })
      .id('hostedBottomBar')
      .alignRules({
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom }
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const h: Length = newArea.height
        if (typeof h === 'number') {
          this.bottomBarHeight = h
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 设置面板：半透明遮罩（点击关闭）+ 右上角深色卡片（播放比例、循环播放） */
  @Builder
  SettingsPanelBuilder() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 遮罩：点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.35)')
        .onClick(() => {
          this.closeSettings()
        })
      // 设置卡片
      Column() {
        Text($r('app.string.video_hosting_scale_label'))
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.6)')
          .margin({ bottom: 2 })
        this.ScaleOptionBuilder(0, $r('app.string.video_hosting_scale_fit'))
        this.ScaleOptionBuilder(1, $r('app.string.video_hosting_scale_crop'))
        this.ScaleOptionBuilder(2, $r('app.string.video_hosting_scale_stretch'))
        Divider()
          .color('rgba(255,255,255,0.15)')
          .margin({ top: 6, bottom: 6 })
        Row() {
          Text($r('app.string.video_hosting_loop'))
            .fontSize(14)
            .fontColor(Color.White)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.session.state.looping })
            .selectedColor(QhState.currentThemeColor)
            .onChange((isOn: boolean) => {
              this.session.setLooping(isOn)
            })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width(224)
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor('#E61F1F1F')
      .borderRadius(14)
      .margin({ top: 60, right: 12 })
    }
    .width('100%')
    .height('100%')
  }

  /** 设置面板：播放比例选项行（选中项高亮 + 勾选标记） */
  @Builder
  ScaleOptionBuilder(mode: number, label: Resource) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.session.state.scaleMode === mode ? Color.White : 'rgba(255,255,255,0.7)')
        .layoutWeight(1)
      if (this.session.state.scaleMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([Color.White])
      }
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
    .onClick(() => {
      this.session.setScaleMode(mode)
    })
  }
}
