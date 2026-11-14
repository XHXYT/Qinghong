import { http } from '@kit.NetworkKit';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import bridge from 'libentry.so';
import { QhState, _QhState } from '../../entryability/AppState';
import { createLogger } from './app/Logger';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { toastUtil } from './ui/ToastUtils';
import { UISettings } from '../entity/SettingsModel';

/** /json/list 返回的调试目标（仅取所需字段） */
interface DevToolsTargetRaw {
  id: string
  title: string
  url: string
  type: string
}

/**
 * 应用内完整 DevTools：
 * rawfile 内置前端 dist（zip）→ 首次解压到沙箱 → native 桥（回环 HTTP + CDP 代理）
 * → /json 匹配当前页 target → 停靠分屏（上页面/下工具 或 左页面/右工具）或弹出独立标签。
 * 停靠时页面保持可见，调试通道（Elements/Console/Network）不受页面后台化影响。
 */
@ObservedV2
export class DevToolsViewModel {
  private static readonly PORT = 8322
  private static readonly ZIP_RAWFILE = 'devtools_frontend.zip'
  /** 前端 dist 版本（结构变更时 +1 触发重新解压） */
  private static readonly FRONTEND_VER = '17'
  /** 停靠分屏占比（DevTools 区域）调整范围 */
  private static readonly RATIO_MIN = 0.2
  private static readonly RATIO_MAX = 0.8

  /** 停靠面板是否打开（弹出独立标签时为 false） */
  @Trace docked: boolean = false
  /** inspector 页面地址（变化触发 Web 重载，实现切换标签重定向） */
  @Trace inspectorUrl: string = ''
  /** 当前调试目标 id（popout 重建无停靠参数的 URL 用） */
  @Trace targetId: string = ''
  /** 停靠分屏占比（DevTools 区域） */
  @Trace ratio: number = 0.5
  /** 前端 device mode（设备模拟器）开启：DevTools 铺满，真实网页悬浮于模拟器手机框内 */
  @Trace deviceModeOn: boolean = false
  /** 模拟器手机框内页面区域（悬浮 Web 定位）：前端经 __qhDevTools.setDeviceFrame 上报，dock CSS px = vp */
  @Trace deviceFrameX: number = 0
  @Trace deviceFrameY: number = 0
  @Trace deviceFrameW: number = 0
  @Trace deviceFrameH: number = 0
  /** 模拟的视口尺寸（device preset 的 CSS 尺寸；悬浮 Web 以此为布局尺寸再按 zoom 缩放对齐手机框） */
  @Trace deviceEmuW: number = 0
  @Trace deviceEmuH: number = 0
  /** 手机框显示缩放（screencast screenZoom；悬浮 Web 以 .scale() 对齐，触摸经逆变换映射） */
  @Trace deviceEmuZoom: number = 1

  controller: webview.WebviewController = new webview.WebviewController()
  private preparing: boolean = false
  /** 重定向序号：连续切换标签时只应用最新一次结果 */
  private retargetSeq: number = 0
  private readonly logger = createLogger('DevTools')

  /** 桥接根地址（识别弹出的 inspector 标签） */
  baseUrl(): string {
    return `http://127.0.0.1:${DevToolsViewModel.PORT}`
  }

  /** 实际停靠侧：用户显式设置优先，未设置时宽屏靠右、窄屏靠下 */
  effectiveSide(): 'bottom' | 'right' | 'left' {
    if (UISettings.devtools_layout === 'bottom') {
      return 'bottom'
    }
    if (UISettings.devtools_layout === 'right') {
      return 'right'
    }
    if (UISettings.devtools_layout === 'left') {
      return 'left'
    }
    return QhState.widthBp > 1 ? 'right' : 'bottom'
  }

  /** 前端停靠菜单（⋮ 菜单停靠侧四图标）经 __qhDevTools 调用：切停靠侧 / 弹出独立标签 */
  setLayout(side: string): boolean {
    if (side === 'undocked') {
      this.popout()
      return true
    }
    if (side === 'left' || side === 'bottom' || side === 'right') {
      UISettings.devtools_layout = side
      return true
    }
    return false
  }

  /** 前端模拟器开关经 __qhDevTools 调用：true 时 DevTools 铺满、真实网页悬浮到模拟器手机框 */
  setDeviceMode(on: boolean): boolean {
    this.deviceModeOn = on
    if (!on) {
      this.resetDeviceFrame()
    }
    return true
  }

  /** 前端上报模拟器手机框页面区域（canvas 矩形）+ 模拟视口尺寸 + 缩放；w/h 为 0 表示无有效区域 */
  setDeviceFrame(x: number, y: number, w: number, h: number,
    emuW: number, emuH: number, zoom: number): boolean {
    this.deviceFrameX = x
    this.deviceFrameY = y
    this.deviceFrameW = w
    this.deviceFrameH = h
    this.deviceEmuW = emuW
    this.deviceEmuH = emuH
    this.deviceEmuZoom = zoom > 0 ? zoom : 1
    return true
  }

  private resetDeviceFrame(): void {
    this.deviceFrameX = 0
    this.deviceFrameY = 0
    this.deviceFrameW = 0
    this.deviceFrameH = 0
    this.deviceEmuW = 0
    this.deviceEmuH = 0
    this.deviceEmuZoom = 1
  }

  /** 分屏占比（DevTools 区域）约束 */
  clampRatio(v: number): number {
    const r: number = Number.isNaN(v) ? 0.5 : v
    return Math.min(DevToolsViewModel.RATIO_MAX, Math.max(DevToolsViewModel.RATIO_MIN, r))
  }

  /** 拆除 dock 前让前端先退出设备模拟（经 willHide → model.emulate(None) 恢复页面 UA/视口 override） */
  private clearDeviceModeInFrontend(): void {
    if (!this.docked || !this.deviceModeOn) {
      return
    }
    try {
      this.controller.runJavaScript(
        'try{var o=globalThis.Emulation&&globalThis.Emulation.AdvancedApp'
        + '?globalThis.Emulation.AdvancedApp.instance():null;var v=o&&o.deviceModeView;'
        + 'if(v&&v.showDeviceModeSetting&&v.showDeviceModeSetting.get()){v.showDeviceModeSetting.set(false)}}catch(e){}""')
    } catch (e) {
      this.logger.warn(`clearDeviceModeInFrontend: ${JSON.stringify(e)}`)
    }
  }

  /** 弹出为独立标签页（关闭停靠面板；URL 不带停靠参数，前端保持独立窗口形态） */
  popout(): void {
    if (!this.docked) {
      return
    }
    this.clearDeviceModeInFrontend()
    this.deviceModeOn = false
    this.resetDeviceFrame()
    const url: string = this.inspectorUrlOf(this.targetId, false)
    this.docked = false
    tabsVM.newTab(url)
  }

  /** 关闭停靠面板 */
  close(): void {
    this.clearDeviceModeInFrontend()
    this.deviceModeOn = false
    this.resetDeviceFrame()
    this.docked = false
  }

  /** 菜单入口：已停靠则关闭；inspector 标签激活则关闭它恢复停靠；否则对当前页停靠打开 */
  async open(): Promise<void> {
    if (this.preparing) {
      return
    }
    if (this.docked) {
      this.close()
      return
    }
    let tab = tabsVM.activeTab
    if (tab === null) {
      return
    }
    // 弹出的 inspector 标签激活中：菜单点击视为收回停靠（关掉该标签，停靠到激活的相邻标签）
    if (tab.url.startsWith(this.baseUrl())) {
      tabsVM.closeTab(tab.id)
      tab = tabsVM.activeTab
    }
    if (tab === null || tab.isHome) {
      toastUtil.showToast({ message: $r('app.string.devtools_no_page') })
      return
    }
    this.preparing = true
    const currentUrl: string = tab.url
    try {
      toastUtil.showToast({ message: $r('app.string.devtools_preparing') })
      try {
        // 打开 DevTools 时确保内核调试通道可用（不改动持久设置）
        webview.WebviewController.setWebDebuggingAccess(true)
      } catch (e) {
        this.logger.warn(`setWebDebuggingAccess: ${JSON.stringify(e)}`)
      }
      const dir: string = await this.ensureFrontend()
      if (!bridge.startBridge(DevToolsViewModel.PORT, dir)) {
        toastUtil.showToast({ message: $r('app.string.devtools_start_failed') })
        return
      }
      // 打开时允许兜底到首个页面目标（用户打开意图明确）
      const target: DevToolsTargetRaw | null = await this.findTargetFor(currentUrl, true)
      if (target === null) {
        toastUtil.showToast({ message: $r('app.string.devtools_no_target') })
        return
      }
      this.controller = new webview.WebviewController()
      this.targetId = target.id
      this.inspectorUrl = this.inspectorUrlOf(target.id, true)
      this.docked = true
    } catch (e) {
      this.logger.error(`open failed: ${JSON.stringify(e)}`)
      toastUtil.showToast({ message: $r('app.string.devtools_start_failed') })
    } finally {
      this.preparing = false
    }
  }

  /** 活动标签变化（Index @Monitor 驱动）：停靠中切换调试目标，主页/无目标时收起 */
  async onActiveTabChanged(): Promise<void> {
    if (!this.docked) {
      return
    }
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      this.close()
      return
    }
    const seq: number = ++this.retargetSeq
    // 重定向须精确匹配，不兜底其他页面目标
    const target: DevToolsTargetRaw | null = await this.findTargetFor(tab.url, false)
    if (seq !== this.retargetSeq) {
      return
    }
    if (target === null) {
      this.close()
      toastUtil.showToast({ message: $r('app.string.devtools_no_target') })
      return
    }
    this.targetId = target.id
    this.inspectorUrl = this.inspectorUrlOf(target.id, true)
  }

  /**
   * inspector 地址：dock 模式追加 can_dock + dockside（前端据此启用 ⋮ 菜单停靠行、
   * ✕ 关闭按钮并同步初始停靠侧）；popout 模式不追加，保持「焦点页面」等独立窗口行为
   */
  private inspectorUrlOf(targetId: string, docked: boolean): string {
    let url: string = `${this.baseUrl()}/frontend/inspector.html`
      + `?ws=127.0.0.1:${DevToolsViewModel.PORT}/devtools/page/${targetId}`
    if (docked) {
      url += `&can_dock=true&dockside=${this.effectiveSide()}`
    }
    return url
  }

  /** 确保前端 dist 已解压到沙箱（版本变化时全量重建）；返回 dist 目录 */
  private async ensureFrontend(): Promise<string> {
    const root: string = `${_QhState.Context.filesDir}/devtools`
    const dir: string = `${root}/frontend`
    let upToDate = false
    try {
      if (fileIo.accessSync(`${dir}/frontend.ver`) && fileIo.accessSync(`${dir}/inspector.html`)) {
        upToDate = fileIo.readTextSync(`${dir}/frontend.ver`).trim() === DevToolsViewModel.FRONTEND_VER
      }
    } catch (e) {
      upToDate = false
    }
    if (upToDate) {
      return dir
    }
    const start = Date.now()
    try {
      if (fileIo.accessSync(root)) {
        fileIo.rmdirSync(root)
      }
    } catch (e) {
      // 目录不存在等场景可忽略
    }
    fileIo.mkdirSync(root, true)
    fileIo.mkdirSync(dir, true)
    const data: Uint8Array =
      _QhState.Context.resourceManager.getRawFileContentSync(DevToolsViewModel.ZIP_RAWFILE)
    const buf: ArrayBuffer = new ArrayBuffer(data.byteLength)
    new Uint8Array(buf).set(data)
    const zipPath: string = `${root}/frontend.zip`
    const f: fileIo.File = fileIo.openSync(zipPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(f.fd, buf)
    fileIo.closeSync(f)
    try {
      await zlib.decompressFile(zipPath, dir)
    } finally {
      try {
        fileIo.unlinkSync(zipPath)
      } catch (e) {
        // 临时文件清理失败可忽略
      }
    }
    // 写版本标记（下次启动按此判断是否需重建）
    const vf: fileIo.File = fileIo.openSync(`${dir}/frontend.ver`,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(vf.fd, DevToolsViewModel.FRONTEND_VER)
    fileIo.closeSync(vf)
    this.logger.info(`frontend v${DevToolsViewModel.FRONTEND_VER} unpacked in ${Date.now() - start}ms`)
    return dir
  }

  /** 从内核调试后端拉 /json/list，匹配页面调试目标；strict=false 时不兜底首个页面 */
  private async findTargetFor(url: string, allowFallback: boolean): Promise<DevToolsTargetRaw | null> {
    const client = http.createHttp()
    try {
      const resp = await client.request(`${this.baseUrl()}/json/list`, {
        connectTimeout: 3000,
        readTimeout: 5000,
        expectDataType: http.HttpDataType.STRING
      })
      if (resp.responseCode !== 200 || typeof resp.result !== 'string') {
        return null
      }
      const raw = JSON.parse(resp.result) as DevToolsTargetRaw[]
      if (!Array.isArray(raw)) {
        this.logger.error(`/json/list not array: ${resp.result.substring(0, 200)}`)
        return null
      }
      // 排除 inspector 页面自身（作为 Web 也是 page target，fallback 命中会自连套娃）
      const pages: DevToolsTargetRaw[] = raw.filter((t: DevToolsTargetRaw) =>
        t.type === 'page' && !t.url.startsWith(this.baseUrl()))
      const summary: string[] = pages.map((t: DevToolsTargetRaw): string =>
        `${t.type}|${t.id.substring(0, 16)}|${t.url.substring(0, 60)}`)
      this.logger.info(`/json/list ${raw.length} targets, pages: ${summary.join(' ; ')}`)
      const want: string = DevToolsViewModel.normalize(url)
      for (const t of pages) {
        if (DevToolsViewModel.normalize(t.url) === want) {
          return t
        }
      }
      const host: string = DevToolsViewModel.hostOf(url)
      for (const t of pages) {
        if (DevToolsViewModel.hostOf(t.url) === host) {
          return t
        }
      }
      return allowFallback && pages.length > 0 ? pages[0] : null
    } catch (e) {
      this.logger.error(`findTargetFor: ${JSON.stringify(e)}`)
      return null
    } finally {
      client.destroy()
    }
  }

  private static normalize(u: string): string {
    let s: string = u.indexOf('#') >= 0 ? u.substring(0, u.indexOf('#')) : u
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1)
    }
    return s
  }

  private static hostOf(u: string): string {
    const m: number = u.indexOf('://')
    const rest: string = m >= 0 ? u.substring(m + 3) : u
    const slash: number = rest.indexOf('/')
    return slash >= 0 ? rest.substring(0, slash) : rest
  }
}

export const devtoolsVM = new DevToolsViewModel()
