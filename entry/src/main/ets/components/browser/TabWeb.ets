import { connection } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { CustomContentDialog, display } from '@kit.ArkUI';
import { tabsVM, TabInfo } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { downloadVM } from '../../viewmodel/DownloadViewModel';
import { appSettings, UISettings } from '../../common/entity/SettingsModel';
import { toastUtil } from '../../common/utils/ToastUtils';
import { ResourceUtils } from '../../common/utils/ResourceUtil';
import { UaUtils } from '../../common/utils/UaUtils';
import { AdBlockEngine } from '../../common/utils/AdBlockEngine';
import { adBlockStore } from '../../common/utils/AdBlockStore';
import { WebScripts } from '../../common/utils/WebScripts';
import { ReaderScripts } from '../../common/utils/ReaderScripts';
import { ViewSourceScripts } from '../../common/utils/ViewSourceScripts';
import { SitePolicy, SiteSettingsViewModel, siteSettingsVM } from '../../viewmodel/SiteSettingsViewModel';
import { passwordVM, PasswordDecision } from '../../viewmodel/PasswordViewModel';
import PasswordInfo from '../../common/entity/PasswordInfo';
import { buildDialogButtons } from '../dialog/AppContentDialog';
import { _QhState } from '../../entryability/AppState';
import { LongPressMenuItem, LongPressMenuItems, LongPressTarget } from '../../common/constants/LongPressMenuItems';
import { longPressVM, LongPressContext } from '../../viewmodel/LongPressMenuViewModel';
import { netLogVM } from '../../viewmodel/NetworkLogViewModel';
import { inspectorVM } from '../../viewmodel/InspectorViewModel';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';
import { scriptVM } from '../../viewmodel/ScriptViewModel';
import { GmValueRaw, GmDeleteValueRaw, GmOpenTabRaw, GmClipboardRaw, GmNotifyRaw, GmDownloadRaw, GmMenuRaw, GmMenuIdRaw } from '../../common/utils/GmRuntime';

/** 网页选区矩形（CSS px，相对视口；由注入脚本返回的 JSON 解析而来） */
interface SelectionRect {
  x: number
  y: number
  w: number
  h: number
  iw: number
}

/**
 * 剪贴板 + 密码 + 审查 + 媒体嗅探 JS 代理对象（window.__qhNative）：
 * 网页 navigator.clipboard 文本读写转发原生按站点策略处理；
 * 登录表单凭据捕获上报原生弹保存提示；
 * 元素审查页内选点回传（__qhNative.inspectEvent）；
 * 媒体嗅探钩子上报（__qhNative.sniffMedia）记入网络日志
 */
class ClipboardBridge {
  private readonly handler: (action: string, cbId: number, text: string) => void
  private readonly passwordHandler: (username: string, password: string) => void
  private readonly inspectHandler: (payload: string) => void
  private readonly scrollHandler: (hidden: boolean) => void
  private readonly tapToggleHandler: () => void
  private readonly gmHandler: (api: string, json: string) => void
  private readonly sniffHandler: (url: string, kind: string) => void

  constructor(handler: (action: string, cbId: number, text: string) => void,
    passwordHandler: (username: string, password: string) => void,
    inspectHandler: (payload: string) => void,
    scrollHandler: (hidden: boolean) => void,
    tapToggleHandler: () => void,
    gmHandler: (api: string, json: string) => void,
    sniffHandler: (url: string, kind: string) => void) {
    this.handler = handler
    this.passwordHandler = passwordHandler
    this.inspectHandler = inspectHandler
    this.scrollHandler = scrollHandler
    this.tapToggleHandler = tapToggleHandler
    this.gmHandler = gmHandler
    this.sniffHandler = sniffHandler
  }

  clipboardRequest(action: string, cbId: number, text: string): void {
    this.handler(action, cbId, text)
  }

  passwordSubmit(username: string, password: string): void {
    this.passwordHandler(username, password)
  }

  inspectEvent(payload: string): void {
    this.inspectHandler(payload)
  }

  /** 滑动显隐操作栏（仅 slide 模式生效） */
  actionBarScroll(hidden: boolean): void {
    this.scrollHandler(hidden)
  }

  /** 点击切换操作栏（仅 tap 模式生效） */
  actionBarTapToggle(): void {
    this.tapToggleHandler()
  }

  /** GM_* API 桥（__qhNative.gmRequest）：脚本沙箱转发原生执行 */
  gmRequest(api: string, json: string): void {
    this.gmHandler(api, json)
  }

  /** 媒体嗅探钩子上报（__qhNative.sniffMedia）：记录网络日志驱动悬浮按钮/嗅探面板 */
  sniffMedia(url: string, kind: string): void {
    this.sniffHandler(url, kind)
  }
}

/**
 * 单个标签的网页内容：Web 组件 + 全部 Web 事件处理 + 夜间蒙版
 */
@ComponentV2
export struct TabWeb {
  @Require @Param tab: TabInfo

  /** 当前站点运行时策略（站点设定 > 全局默认 > 应用设置） */
  @Local policy: SitePolicy = new SitePolicy()
  /** 当前是否处于 WIFI 网络（仅WIFI有图模式用） */
  @Local wifiConnected: boolean = false
  /** 已应用的 UA 覆盖（'' = 跟随应用） */
  private appliedUa: string | null = null

  /** 广告拦截开关已应用状态（null=未应用；避免重复 enableAdsBlock） */
  private appliedAdsBlockOn: boolean | null = null

  /** BFCache 开关已应用状态（null=未应用；避免重复 setBackForwardCacheOptions） */
  private appliedBfcOn: boolean | null = null
  /** 重定向询问放行后的重导航地址（避免二次询问） */
  private pendingRedirectUrl: string = ''
  /** 阅读可用性检测序号（页面开始导航时 +1，使旧延迟检测作废） */
  private detectSeq: number = 0
  /** 网络状态监听（WIFI 切换时刷新图片开关） */
  private netConn: connection.NetConnection | null = null
  /** 剪贴板 JS 代理（window.__qhNative）：网页剪贴板文本读写转发原生策略处理 */
  private clipboardBridge: ClipboardBridge = new ClipboardBridge((action: string, cbId: number, text: string): void => {
    this.handleClipboardRequest(action, cbId, text)
  }, (username: string, password: string): void => {
    this.handlePasswordSubmit(username, password)
  }, (payload: string): void => {
    inspectorVM.onInspectEvent(this.tab.id, payload)
  }, (hidden: boolean): void => {
    // 滑动显隐：仅 slide 模式生效
    if (UISettings.auto_hide_action_bar === 'slide') {
      this.setBarHiddenAnimated(hidden)
    }
  }, (): void => {
    // 点击切换：仅 tap 模式生效
    if (UISettings.auto_hide_action_bar === 'tap') {
      this.setBarHiddenAnimated(!this.tab.actionBarHidden)
    }
  }, (api: string, json: string): void => {
    this.handleGmRequest(api, json)
  }, (url: string, kind: string): void => {
    this.handleSniffMedia(url, kind)
  })

  /** 保存密码提示弹窗 */
  private savePromptDialog: CustomDialogController | undefined = undefined
  /** 更新密码提示弹窗 */
  private updatePromptDialog: CustomDialogController | undefined = undefined
  /** 待提示的凭据（弹窗内容） */
  @Local promptHost: string = ''
  @Local promptUsername: string = ''
  private promptPassword: string = ''
  /** 已提示过的凭据 key（防重复弹窗） */
  private passwordPromptKey: string = ''

  /** 长按/右键菜单：是否显示 */
  @Local ctxMenuVisible: boolean = false
  /** 长按/右键菜单：条目列表 */
  @Local ctxMenuItems: LongPressMenuItem[] = []
  /** 长按/右键菜单：面板位置与高度（vp，相对 Web 组件） */
  @Local ctxMenuX: number = 0
  @Local ctxMenuY: number = 0
  @Local ctxMenuHeight: number = 0
  /** 当前菜单是否为文字选中菜单（自绘面板，动作走文本分支） */
  private ctxIsTextMenu: boolean = false
  /** Web 区域实际尺寸（vp，菜单位置/高度计算用） */
  private webWidthVp: number = 0
  private webHeightVp: number = 0
  /** 看图模式：全屏查看的图片地址（'' = 关闭） */
  @Local imageViewerUrl: string = ''

  /** 操作栏显隐切换：布局与栏滑入滑出统一走 250ms 动画（同值不重复触发） */
  private setBarHiddenAnimated(hidden: boolean): void {
    if (this.tab.actionBarHidden === hidden) {
      return
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
      this.tab.actionBarHidden = hidden
    })
  }
  /** 看图模式：捏合缩放倍数 */
  @Local viewerScale: number = 1
  private viewerBaseScale: number = 1
  /** 长按上下文（命中元素快照） */
  private ctxLinkUrl: string = ''
  private ctxImageUrl: string = ''
  private ctxLinkText: string = ''
  private ctxResult: WebContextMenuResult | null = null

  aboutToAppear(): void {
    this.initPasswordDialogs()
    this.netConn = connection.createNetConnection()
    this.netConn.on('netAvailable', () => {
      this.updateWifiState()
    })
    this.netConn.on('netLost', () => {
      this.updateWifiState()
    })
    this.netConn.register(() => {
    })
    this.updateWifiState()
  }

  aboutToDisappear(): void {
    this.netConn?.unregister(() => {
    })
    inspectorVM.removeLogs(this.tab.id)
  }

  /** 查询当前默认网络是否为 WIFI */
  private updateWifiState(): void {
    connection.getDefaultNet().then((net: connection.NetHandle) => {
      connection.getNetCapabilities(net).then((caps: connection.NetCapabilities) => {
        this.wifiConnected = caps.bearerTypes.indexOf(connection.NetBearType.BEARER_WIFI) >= 0
      }).catch(() => {
        this.wifiConnected = false
      })
    }).catch(() => {
      this.wifiConnected = false
    })
  }

  /** 当前是否允许加载在线图片（高级-无图模式优先级最高；其余按站点策略） */
  private imageAllowedOnline(): boolean {
    if (appSettings.no_image_mode) {
      return false
    }
    if (this.policy.imageMode === 'app') {
      return true
    }
    if (this.policy.imageMode === 'wifi') {
      return this.wifiConnected
    }
    return this.policy.imageMode === 'allow'
  }

  /** 当前站点广告拦截是否生效 */
  private adBlockOn(): boolean {
    return AdBlockEngine.policyOn(this.policy)
  }

  /**
   * 广告拦截开关应用到当前 Web 实例（ArkWeb 原生 AdsBlock，站点级开关）
   */
  private applyAdsBlockEnable(): void {
    const on: boolean = this.adBlockOn()
    if (this.appliedAdsBlockOn === on) {
      return
    }
    try {
      tabsVM.ensureController(this.tab).enableAdsBlock(on)
      this.appliedAdsBlockOn = on
    } catch (e) {
      console.error(`[TabWeb] enableAdsBlock 失败: ${e}`)
    }
  }

  /**
   * 应用返回不刷新（BFCache）配置：
   * 在 onPageEnd 应用——页面离开进入缓存的决策取决于该页自己的站点策略；
   * 开启 size=10/ttl=600s，关闭 size=0（框架启用后默认 size=1，必须显式关）
   */
  private applyBackForwardCache(): void {
    const c = this.tab.controller
    if (c === null) {
      return
    }
    const on: boolean = this.policy.backNoReload
    if (this.appliedBfcOn === on) {
      return
    }
    try {
      const opts: webview.BackForwardCacheOptions = new webview.BackForwardCacheOptions()
      if (on) {
        opts.size = 10
        opts.timeToLive = 600
      } else {
        opts.size = 0
        opts.timeToLive = 0
      }
      c.setBackForwardCacheOptions(opts)
      this.appliedBfcOn = on
    } catch (e) {
      console.error(`[TabWeb] 设置前进后退缓存失败: ${e}`)
    }
  }

  /** 文档加载前注入脚本：隐私脚本 + 剪贴板接管 + 长按菜单辅助 + 振动禁用（全局关闭时）+ 密码管理器 */
  /** 用户脚本：@run-at document-end/idle，按 URL 匹配后注入 */
  private injectUserScripts(url: string): void {
    const code: string = scriptVM.onPageEndCode(url)
    if (code !== '') {
      tabsVM.ensureController(this.tab).runJavaScript(code)
        .catch((): void => {
        })
    }
  }

  /**
   * GM_* API 原生执行（__qhNative.gmRequest）：
   * 值读写持久化+跨标签广播、跨域请求（@connect 校验）、菜单命令注册、
   * 打开标签/剪贴板/通知/下载转发对应模块
   */
  private handleGmRequest(api: string, json: string): void {
    try {
      switch (api) {
        case 'setValue': {
          const raw: GmValueRaw = JSON.parse(json) as GmValueRaw
          scriptVM.gmSetValue(raw.scriptId, raw.key, raw.valueRaw, this.tab.id)
          break
        }
        case 'deleteValue': {
          const raw: GmDeleteValueRaw = JSON.parse(json) as GmDeleteValueRaw
          scriptVM.gmDeleteValue(raw.scriptId, raw.key, this.tab.id)
          break
        }
        case 'xhr':
          scriptVM.gmXhr(json, this.tab)
          break
        case 'xhrAbort':
          scriptVM.gmXhrAbort(json)
          break
        case 'openTab': {
          const raw: GmOpenTabRaw = JSON.parse(json) as GmOpenTabRaw
          if (raw.url !== '') {
            tabsVM.newTab(raw.url, this.tab.isIncognito)
          }
          break
        }
        case 'clipboard': {
          const raw: GmClipboardRaw = JSON.parse(json) as GmClipboardRaw
          const data: pasteboard.PasteData =
            pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, raw.text)
          pasteboard.getSystemPasteboard().setData(data)
            .catch((): void => {
            })
          break
        }
        case 'notify': {
          const raw: GmNotifyRaw = JSON.parse(json) as GmNotifyRaw
          if (raw.text !== '') {
            toastUtil.showToast({ message: raw.text })
          }
          break
        }
        case 'download': {
          const raw: GmDownloadRaw = JSON.parse(json) as GmDownloadRaw
          if (raw.url !== '') {
            downloadVM.download(raw.url, this.tab.url)
          }
          break
        }
        case 'registerMenu': {
          const raw: GmMenuRaw = JSON.parse(json) as GmMenuRaw
          scriptVM.gmRegisterMenu(this.tab.id, raw.scriptId, raw.menuId, raw.name)
          break
        }
        case 'unregisterMenu': {
          const raw: GmMenuIdRaw = JSON.parse(json) as GmMenuIdRaw
          scriptVM.gmUnregisterMenu(raw.menuId)
          break
        }
        default:
          break
      }
    } catch (e) {
      console.warn(`[TabWeb] gmRequest ${api} 失败: ${e}`)
    }
  }

  /** 媒体嗅探上报（__qhNative.sniffMedia 钩子脚本）：记入网络日志；无痕模式不记录 */
  private handleSniffMedia(url: string, kind: string): void {
    if (this.tab.isIncognito) {
      return
    }
    console.info(`[QhSniff] hook ${kind} ${url}`)
    netLogVM.recordSniffed(this.tab.id, url, kind)
  }

  private documentStartScripts(): Array<ScriptItem> {
    const scripts: Array<ScriptItem> = WebScripts.privacyScripts()
    scripts.push(WebScripts.clipboardScript())
    scripts.push(WebScripts.contextMenuScript())
    scripts.push(WebScripts.actionBarScript())
    scripts.push(WebScripts.sniffMediaScript())
    if (!appSettings.web_vibration_enabled) {
      scripts.push(WebScripts.vibrationBlockScript())
    }
    if (!appSettings.system_password_manager) {
      scripts.push(WebScripts.passwordScript())
    }
    // 用户脚本：@run-at document-start（@match 规则做 URL 预过滤）
    for (const item of scriptVM.docStartScriptItems()) {
      scripts.push(item)
    }
    return scripts
  }

  /** 解析并应用站点策略 */
  private refreshPolicy(url: string): void {
    const host: string = SiteSettingsViewModel.hostOf(url)
    if (host === '') {
      return
    }
    siteSettingsVM.resolvePolicy(host).then((p: SitePolicy): void => {
      this.applyPolicy(p)
    })
  }

  private applyPolicy(p: SitePolicy): void {
    this.policy = p
    this.applyUa(p)
    this.applyAdsBlockEnable()
    siteSettingsVM.registerLive(p.host, p)
  }

  /** 应用 UA（'' 跟随应用走 UaUtils，覆盖值直接 setCustomUserAgent） */
  private applyUa(p: SitePolicy): void {
    const c = this.tab.controller
    if (c === null) {
      return
    }
    if (this.appliedUa === p.uaOverride) {
      return
    }
    try {
      if (p.uaOverride === '') {
        UaUtils.applyTo(c)
      } else {
        c.setCustomUserAgent(p.uaOverride)
      }
      this.appliedUa = p.uaOverride
    } catch (e) {
      console.error(`[TabWeb] 应用站点 UA 失败: ${e}`)
    }
  }

  /**
   * 站点重定向拦截（onLoadIntercept）：
   * 拦主框架、非用户手势、非 HTTP 30x 链的跨域自动跳转（脚本 location / meta refresh）；
   * ask 询问后经 pendingRedirectUrl 放行一次，block 直接拦并提示；
   * 同域自动跳转、用户点击、30x 链、返回/前进不受影响
   */
  private interceptRedirect(event: OnLoadInterceptEvent): boolean {
    const mode: string = this.policy.redirectMode
    if (mode === 'allow') {
      return false
    }
    // 返回/前进等应用主动导航：消费标记放行
    if (this.tab.programmaticNav) {
      this.tab.programmaticNav = false
      return false
    }
    let mainFrame: boolean = false
    let gesture: boolean = false
    let redirect: boolean = false
    try {
      mainFrame = event.data.isMainFrame()
      gesture = event.data.isRequestGesture()
      redirect = event.data.isRedirect()
    } catch (e) {
      return false
    }
    if (!mainFrame || gesture || redirect || this.tab.isHome) {
      return false
    }
    const target: string = event.data.getRequestUrl()
    // 询问后放行的重导航
    if (target === this.pendingRedirectUrl) {
      this.pendingRedirectUrl = ''
      return false
    }
    const currentHost: string = SiteSettingsViewModel.hostOf(this.tab.url)
    const targetHost: string = SiteSettingsViewModel.hostOf(target)
    // 无已提交页面参照或同域自动跳转：放行
    if (currentHost === '' || targetHost === '' || currentHost === targetHost) {
      return false
    }
    if (mode === 'block') {
      toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.site_redirect_blocked')), duration: 2500 })
      return true
    }
    // ask：先拦，确认后重导航
    toastUtil.showAlertDialog({
      title: $r('app.string.redirect_permission_title'),
      message: `${currentHost} ${ResourceUtils.getString($r('app.string.redirect_ask_message'))}\n${target}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.allow'),
          action: (): void => {
            this.pendingRedirectUrl = target
            try {
              tabsVM.ensureController(this.tab).loadUrl(target)
            } catch (e) {
              console.error(`[TabWeb] 重定向放行失败: ${e}`)
            }
          }
        },
        {
          value: $r('app.string.deny'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'redirectPermission')
    return true
  }

  /**
   * 网页请求新窗口（window.open / target=_blank）：
   * 弹出式窗口开关开启 → 直接以新标签打开；
   * 未开启 → 询问许可（内核在此期间阻塞渲染，须在允许/拒绝/取消时均回执解除）
   */
  private handleWindowNew(event: OnWindowNewEvent): void {
    if (appSettings.popup_allowed) {
      this.openPopupAsTab(event)
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(this.tab.url)
    // autoCancel false：强制二选一，避免点外部关闭弹窗导致内核渲染持续阻塞
    toastUtil.showAlertDialog({
      title: $r('app.string.popup_permission_title'),
      message: `${host} ${ResourceUtils.getString($r('app.string.popup_ask_message'))}`,
      autoCancel: false,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.allow'),
          action: (): void => {
            this.openPopupAsTab(event)
          }
        },
        {
          value: $r('app.string.deny'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            this.rejectPopup(event)
          }
        }
      ]
    }, 'popupPermission')
  }

  /** 以新标签打开弹出式窗口：Web 空 src 绑定新控制器，导航由内核驱动（支持 about:blank + document.write） */
  private openPopupAsTab(event: OnWindowNewEvent): void {
    const before: number = tabsVM.tabs.length
    const tab: TabInfo | null = tabsVM.newTab('', this.tab.isIncognito, false, true)
    if (tab === null || tabsVM.tabs.length === before) {
      // 标签数已达上限（newTab 返回当前活动标签），不创建新窗口
      this.rejectPopup(event)
      return
    }
    tab.isHome = false
    tab.isPopupWindow = true
    try {
      event.handler.setWebController(tabsVM.ensureController(tab))
    } catch (e) {
      console.error(`[TabWeb] 绑定弹窗控制器失败: ${e}`)
    }
  }

  /** 告知内核未创建新窗口（解除源页面渲染阻塞，window.open 返回被拦截） */
  private rejectPopup(event: OnWindowNewEvent): void {
    try {
      event.handler.setWebController(null)
    } catch (e) {
      console.error(`[TabWeb] 拒绝弹窗失败: ${e}`)
    }
  }

  /**
   * 智能防跟踪应用到当前 Web 实例（ArkWeb 内核拦截跨站跟踪请求携带 Cookie）
   */
  private applyIntelligentTrackingPrevention(): void {
    try {
      tabsVM.ensureController(this.tab)
        .enableIntelligentTrackingPrevention(appSettings.intelligent_tracking_prevention)
    } catch (e) {
      console.error(`[TabWeb] enableIntelligentTrackingPrevention 失败: ${e}`)
    }
  }

  /**
   * 对当前标签应用安全浏览开关（controller 已挂载后调用才生效）
   */
  private applySafeBrowsing(): void {
    try {
      tabsVM.ensureController(this.tab).enableSafeBrowsing(!appSettings.disable_safe_browsing)
    } catch (e) {
      console.error(`[TabWeb] enableSafeBrowsing 失败: ${e}`)
    }
  }

  private showGeolocationDialog(event: OnGeolocationShowEvent): void {
    // 站点策略：允许/阻止直接生效，询问与跟随应用走应用流程
    if (this.policy.locationMode === 'allow') {
      this.grantWebLocation(event)
      return
    }
    if (this.policy.locationMode === 'block') {
      event.geolocation.invoke(event.origin, false, false)
      return
    }
    if (!appSettings.geolocation_access) {
      event.geolocation.invoke(event.origin, false, false)
      return
    }
    toastUtil.showAlertDialog({
      title: $r('app.string.geolocation_permission_title'),
      message: `${event.origin} ${ResourceUtils.getString($r('app.string.geolocation_permission_message'))}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.allow'),
          action: (): void => {
            // 记录决策到站点设置，后续访问不再重复询问
            this.policy.locationMode = 'allow'
            this.rememberPermission(event.origin, 'site_location', 'allow')
            this.grantWebLocation(event)
          }
        },
        {
          value: $r('app.string.deny'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            this.policy.locationMode = 'block'
            this.rememberPermission(event.origin, 'site_location', 'block')
            event.geolocation.invoke(event.origin, false, false)
          }
        }
      ]
    }, 'geoPermission')
  }

  /** 持久化网页权限弹窗决策（允许/阻止）到站点设置 */
  private rememberPermission(origin: string, key: string, mode: string): void {
    const host: string = SiteSettingsViewModel.hostOf(origin)
    if (host === '') {
      return
    }
    siteSettingsVM.setOverride(host, key, mode).catch((): void => {
    })
  }

  /**
   * 授权网页定位：先申请系统位置权限（精确+模糊任一通过即可），再响应网页请求
   */
  private grantWebLocation(event: OnGeolocationShowEvent): void {
    const atManager = abilityAccessCtrl.createAtManager()
    const perms: Array<Permissions> = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION']
    atManager.requestPermissionsFromUser(_QhState.Context, perms)
      .then((result: PermissionRequestResult): void => {
        let granted: boolean = false
        for (const r of result.authResults) {
          if (r === 0) {
            granted = true
          }
        }
        event.geolocation.invoke(event.origin, granted, false)
      })
      .catch((error: BusinessError): void => {
        console.error(`[TabWeb] 申请位置权限失败: ${error.code} ${error.message}`)
        event.geolocation.invoke(event.origin, false, false)
      })
  }

  /**
   * 网页摄像头/麦克风权限请求：站点策略 allow 直接授权、block 直接拒绝、其余弹窗询问
   */
  private handlePermissionRequest(event: OnPermissionRequestEvent): void {
    const req = event.request
    const resources: Array<string> = req.getAccessibleResource()
    const allowed: Array<string> = []
    const askList: Array<string> = []
    for (const r of resources) {
      if (r !== 'TYPE_VIDEO_CAPTURE' && r !== 'TYPE_AUDIO_CAPTURE') {
        continue
      }
      const mode: string = r === 'TYPE_VIDEO_CAPTURE' ? this.policy.cameraMode : this.policy.micMode
      if (mode === 'allow') {
        allowed.push(r)
      } else if (mode === 'ask' || mode === 'app') {
        askList.push(r)
      }
      // 'block' 不授权
    }
    if (askList.length === 0) {
      if (allowed.length > 0) {
        this.grantWebResources(req, allowed)
      } else {
        req.deny()
      }
      return
    }
    const hasCam: boolean = askList.indexOf('TYPE_VIDEO_CAPTURE') >= 0
    const hasMic: boolean = askList.indexOf('TYPE_AUDIO_CAPTURE') >= 0
    const msgRes: Resource = hasCam && hasMic ? $r('app.string.web_permission_use_both')
      : (hasCam ? $r('app.string.web_permission_use_camera') : $r('app.string.web_permission_use_mic'))
    toastUtil.showAlertDialog({
      title: $r('app.string.web_permission_title'),
      message: `${req.getOrigin()} ${ResourceUtils.getString(msgRes)}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.allow'),
          action: (): void => {
            this.rememberResourceDecision(req.getOrigin(), askList, 'allow')
            for (const r of askList) {
              allowed.push(r)
            }
            this.grantWebResources(req, allowed)
          }
        },
        {
          value: $r('app.string.deny'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            this.rememberResourceDecision(req.getOrigin(), askList, 'block')
            if (allowed.length > 0) {
              this.grantWebResources(req, allowed)
            } else {
              req.deny()
            }
          }
        }
      ]
    }, 'webPermission')
  }

  /** 记录摄像头/麦克风弹窗决策，并同步 live 策略避免同页重复弹窗 */
  private rememberResourceDecision(origin: string, resources: Array<string>, mode: string): void {
    for (const r of resources) {
      if (r === 'TYPE_VIDEO_CAPTURE') {
        this.policy.cameraMode = mode
        this.rememberPermission(origin, 'site_camera', mode)
      } else if (r === 'TYPE_AUDIO_CAPTURE') {
        this.policy.micMode = mode
        this.rememberPermission(origin, 'site_microphone', mode)
      }
    }
  }

  /** 授权网页资源前先确保系统级摄像头/麦克风权限 */
  private grantWebResources(req: PermissionRequest, resources: Array<string>): void {
    const perms: Array<Permissions> = []
    for (const r of resources) {
      if (r === 'TYPE_VIDEO_CAPTURE' && perms.indexOf('ohos.permission.CAMERA') < 0) {
        perms.push('ohos.permission.CAMERA')
      } else if (r === 'TYPE_AUDIO_CAPTURE' && perms.indexOf('ohos.permission.MICROPHONE') < 0) {
        perms.push('ohos.permission.MICROPHONE')
      }
    }
    if (perms.length === 0) {
      req.grant(resources)
      return
    }
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    atManager.requestPermissionsFromUser(_QhState.Context, perms)
      .then((result: PermissionRequestResult): void => {
        let allGranted: boolean = true
        for (const r of result.authResults) {
          if (r !== 0) {
            allGranted = false
          }
        }
        if (allGranted) {
          req.grant(resources)
        } else {
          req.deny()
        }
      })
      .catch((error: BusinessError): void => {
        console.error(`[TabWeb] 申请系统权限失败: ${error.message}`)
        req.deny()
      })
  }

  /**
   * 网页剪贴板文本读写请求（window.__qhNative 代理）：
   * 站点策略 allow 放行 / ask 弹窗询问 / block 拒绝
   */
  private handleClipboardRequest(action: string, cbId: number, text: string): void {
    const mode: string = this.policy.clipboardMode
    if (mode === 'block') {
      this.resolveClipboard(cbId, false)
      return
    }
    const isWrite: boolean = action === 'writeText'
    if (mode === 'ask') {
      const msgRes: Resource = isWrite ? $r('app.string.clipboard_write_message')
        : $r('app.string.clipboard_read_message')
      toastUtil.showAlertDialog({
        title: $r('app.string.clipboard_permission_title'),
        message: `${this.policy.host} ${ResourceUtils.getString(msgRes)}`,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        buttons: [
          {
            value: $r('app.string.allow'),
            action: (): void => {
              if (isWrite) {
                this.doClipboardWrite(cbId, text)
              } else {
                this.doClipboardRead(cbId)
              }
            }
          },
          {
            value: $r('app.string.deny'),
            style: DialogButtonStyle.DEFAULT,
            action: (): void => {
              this.resolveClipboard(cbId, false)
            }
          }
        ]
      }, 'clipboardPermission')
      return
    }
    if (isWrite) {
      this.doClipboardWrite(cbId, text)
    } else {
      this.doClipboardRead(cbId)
    }
  }

  /** 原生写入系统剪贴板（无需权限） */
  private doClipboardWrite(cbId: number, text: string): void {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      pasteboard.getSystemPasteboard().setData(data)
        .then((): void => {
          this.resolveClipboard(cbId, true)
        })
        .catch((error: BusinessError): void => {
          console.error(`[TabWeb] 剪贴板写入失败: ${error.code} ${error.message}`)
          this.resolveClipboard(cbId, false)
        })
    } catch (error) {
      console.error(`[TabWeb] 剪贴板写入异常: ${error}`)
      this.resolveClipboard(cbId, false)
    }
  }

  /** 原生读取系统剪贴板（需 READ_PASTEBOARD 权限，先申请） */
  private doClipboardRead(cbId: number): void {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    const perms: Array<Permissions> = ['ohos.permission.READ_PASTEBOARD']
    atManager.requestPermissionsFromUser(_QhState.Context, perms)
      .then((result: PermissionRequestResult): void => {
        if (result.authResults.length === 0 || result.authResults[0] !== 0) {
          this.resolveClipboard(cbId, false)
          return
        }
        pasteboard.getSystemPasteboard().getData()
          .then((data: pasteboard.PasteData): void => {
            let text: string = ''
            try {
              text = data.getPrimaryText()
            } catch (e) {
              text = ''
            }
            this.resolveClipboard(cbId, true, text)
          })
          .catch((error: BusinessError): void => {
            console.error(`[TabWeb] 剪贴板读取失败: ${error.code} ${error.message}`)
            this.resolveClipboard(cbId, false)
          })
      })
      .catch((error: BusinessError): void => {
        console.error(`[TabWeb] 申请剪贴板权限失败: ${error.code} ${error.message}`)
        this.resolveClipboard(cbId, false)
      })
  }

  /** 剪贴板请求结果回传网页（window.__qhClipboardDone） */
  private resolveClipboard(cbId: number, ok: boolean, text: string = ''): void {
    try {
      const controller: webview.WebviewController = tabsVM.ensureController(this.tab)
      controller.runJavaScript(`window.__qhClipboardDone && window.__qhClipboardDone(${cbId}, ${ok}, ${JSON.stringify(text)})`)
        .catch((error: BusinessError): void => {
          console.error(`[TabWeb] 剪贴板回调失败: ${error.code} ${error.message}`)
        })
    } catch (error) {
      console.error(`[TabWeb] 剪贴板回调异常: ${error}`)
    }
  }

  /** 初始化保存/更新密码提示弹窗 */
  private initPasswordDialogs(): void {
    this.savePromptDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.password_save_title'),
        contentBuilder: (): void => {
          this.promptMessageContent()
        },
        buttons: buildDialogButtons([$r('app.string.password_later_action'), $r('app.string.password_never_action'),
          $r('app.string.password_save_action')], false,
          (index: number): void => {
            if (index === 1) {
              passwordVM.addNever(this.promptHost)
            } else if (index === 2) {
              passwordVM.upsert(this.promptHost, this.promptUsername, this.promptPassword)
            }
            this.savePromptDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
    this.updatePromptDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.password_update_title'),
        contentBuilder: (): void => {
          this.promptMessageContent()
        },
        buttons: buildDialogButtons([$r('app.string.password_later_action'), $r('app.string.password_update_action')],
          false,
          (index: number): void => {
            if (index === 1) {
              passwordVM.upsert(this.promptHost, this.promptUsername, this.promptPassword)
            }
            this.updatePromptDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  /** 提示弹窗正文：网站 + 用户名 */
  @Builder
  promptMessageContent() {
    Column({ space: 4 }) {
      Text(this.promptHost)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.promptUsername !== '') {
        Text(ResourceUtils.getStringWithArgs($r('app.string.password_save_user_line'), [this.promptUsername]))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Text(ResourceUtils.getString($r('app.string.password_save_pass_line')))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 注入脚本捕获登录凭据上报（__qhNative.passwordSubmit）：
   * 按设置与去重规则弹「保存/更新密码」提示
   */
  private handlePasswordSubmit(username: string, password: string): void {
    if (!appSettings.password_save_prompt || appSettings.system_password_manager) {
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(this.tab.url)
    if (host === '' || password === '') {
      return
    }
    const key: string = `${host}\n${username}\n${password}`
    if (key === this.passwordPromptKey) {
      return
    }
    this.passwordPromptKey = key
    passwordVM.decideSave(host, username, password)
      .then((decision: PasswordDecision): void => {
        if (decision === PasswordDecision.SKIP) {
          return
        }
        this.promptHost = host
        this.promptUsername = username
        this.promptPassword = password
        if (decision === PasswordDecision.SAVE) {
          this.savePromptDialog?.open()
        } else {
          this.updatePromptDialog?.open()
        }
      })
      .catch((error: BusinessError): void => {
        console.error(`[TabWeb] 密码保存决策失败: ${error.code} ${error.message}`)
      })
  }

  /** 页面加载完成后自动填充已保存的密码（托管给系统时由系统接管） */
  private autofillPassword(): void {
    if (appSettings.system_password_manager) {
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(this.tab.url)
    if (host === '') {
      return
    }
    passwordVM.credentialFor(host)
      .then((info: PasswordInfo | null): void => {
        if (info === null) {
          return
        }
        try {
          const controller: webview.WebviewController = tabsVM.ensureController(this.tab)
          controller.runJavaScript(`window.__qhFillPassword && window.__qhFillPassword(${JSON.stringify(info.username)}, ${JSON.stringify(info.password)})`)
            .catch((error: BusinessError): void => {
              console.error(`[TabWeb] 密码自动填充失败: ${error.code} ${error.message}`)
            })
        } catch (error) {
          console.error(`[TabWeb] 密码自动填充异常: ${error}`)
        }
      })
      .catch((error: BusinessError): void => {
        console.error(`[TabWeb] 查询已保存密码失败: ${error.code} ${error.message}`)
      })
  }

  /**
   * 色彩模式：提取页面 meta theme-color 供操作栏自适应（提取失败保持默认色）
   */
  private detectThemeColor(): void {
    if (!UISettings.action_bar_color_mode || this.tab.isHome) {
      return
    }
    const c = this.tab.controller
    if (c === null) {
      return
    }
    const script: string =
      '(function(){var m=document.querySelector(\'meta[name="theme-color"]\');' +
      'return m&&m.content?m.content:""})()'
    c.runJavaScript(script)
      .then((raw: string) => {
        let v: string = raw
        if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
          try {
            v = JSON.parse(raw) as string
          } catch (e) {
            // 保持原值
          }
        }
        if (v !== '' && v.startsWith('#')) {
          this.tab.themeColor = v
        }
      })
      .catch((): void => {
      })
  }

  /**
   * 页面加载完成后检测是否适合阅读模式（isProbablyReaderable 启发式），
   * 结果驱动地址栏阅读按钮显隐；设置关闭时不检测。
   * 延迟 500ms 执行且导航后旧检测作废，不与页面收尾阶段的资源加载抢占
   */
  private detectReadability(): void {
    if (!appSettings.read_mode_address_button || this.tab.isHome) {
      this.tab.readerable = false
      return
    }    const seq: number = this.detectSeq
    setTimeout(() => {
      if (seq !== this.detectSeq || this.tab.isHome || this.tab.controller === null
        || !appSettings.read_mode_address_button) {
        return
      }
      const c = this.tab.controller
      c.runJavaScript(`${ReaderScripts.readerableProbeJs()};JSON.stringify(window.__qhIsReadable())`)
        .then((raw: string) => {
          let v: string = raw
          if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
            try {
              v = JSON.parse(raw) as string
            } catch (e) {
              // 保持原值
            }
          }
          this.tab.readerable = v === 'true'
          console.info(`[TabWeb] 阅读可用性检测 readable=${this.tab.readerable} url=${this.tab.url}`)
        })
        .catch((error: BusinessError): void => {
          this.tab.readerable = false
          console.error(`[TabWeb] 阅读可用性检测失败: ${error.code} ${error.message}`)
        })
    }, 500)
  }

  /** 长按/右键菜单：是否需要接管（true=显示自定义菜单，false=系统默认） */
  private handleContextMenu(event: OnContextMenuShowEvent): boolean {
    const p = event.param
    // 输入框/可编辑元素交给系统默认编辑菜单
    if (p.isEditable() || p.getInputFieldType() !== ContextMenuInputFieldType.None) {
      return false
    }
    // 已选中文本交给系统默认选择菜单
    const selection = p.getSelectionText()
    if (typeof selection === 'string' && selection !== '') {
      return false
    }
    const linkUrl = p.getLinkUrl() ?? ''
    const imageUrl = p.getSourceUrl() ?? ''
    if (linkUrl === '' && imageUrl === '') {
      return false
    }
    const items = this.buildCtxMenuItems(linkUrl !== '', imageUrl !== '')
    if (items.length === 0) {
      return false
    }
    this.ctxLinkUrl = linkUrl
    this.ctxImageUrl = imageUrl
    this.ctxLinkText = ''
    this.ctxResult = event.result
    this.ctxIsTextMenu = false
    this.ctxMenuItems = items
    this.placeCtxMenu(p.x(), p.y(), items.length)
    this.ctxMenuVisible = true
    if (linkUrl !== '') {
      this.fetchCtxLinkText()
    }
    return true
  }

  /** 按开关配置与命中元素类型构建菜单条目 */
  private buildCtxMenuItems(isLink: boolean, isImage: boolean): LongPressMenuItem[] {
    const enabled = LongPressMenuItems.enabledIds()
    const items: LongPressMenuItem[] = []
    for (const item of LongPressMenuItems.ALL) {
      if (!enabled.includes(item.id)) {
        continue
      }
      if (item.target === LongPressTarget.LINK && !isLink) {
        continue
      }
      if (item.target === LongPressTarget.IMAGE && !isImage) {
        continue
      }
      items.push(item)
    }
    return items
  }

  /**
   * 按内容高度与 Web 区域钳制面板位置与高度（入参 vp，相对 Web 组件）
   * 纵向：锚点下方优先；下方放不下翻到锚点上方（不遮挡选中内容）；均放不下贴底
   */
  private clampMenuPosition(x: number, anchorTop: number, anchorBottom: number, rowCount: number): void {
    const panelW = 160
    const ui = this.getUIContext()
    let vw = this.webWidthVp > 0 ? this.webWidthVp :
      ui.px2vp(display.getDefaultDisplaySync().width)
    let vh = this.webHeightVp > 0 ? this.webHeightVp :
      ui.px2vp(display.getDefaultDisplaySync().height)
    if (!(vw > 0)) {
      vw = 360
    }
    if (!(vh > 0)) {
      vh = 780
    }
    // 高度：贴合内容，超出 Web 可用高度时封顶（内部滚动）
    const h = Math.min(rowCount * 48, Math.max(vh - 16, 96))
    if (!(x > 0)) {
      x = 8
    }
    x = Math.min(Math.max(x, 8), Math.max(vw - panelW - 8, 8))
    // 间距：菜单与选区/触点保持 14vp 间距
    const gap = 14
    let y = anchorBottom + gap
    if (y + h > vh - 8) {
      const yAbove = anchorTop - gap - h
      y = yAbove >= 8 ? yAbove : Math.max(8, vh - h - 8)
    }
    this.ctxMenuX = x
    this.ctxMenuY = y
    this.ctxMenuHeight = h
  }

  /** 计算菜单面板位置与高度（px→vp 后钳制） */
  private placeCtxMenu(xPx: number, yPx: number, rowCount: number): void {
    const ui = this.getUIContext()
    const ay = ui.px2vp(yPx)
    this.clampMenuPosition(ui.px2vp(xPx), ay, ay, rowCount)
  }

  /** 读取注入脚本记录的命中链接文本（复制链接文本用） */
  private fetchCtxLinkText(): void {
    try {
      const c = tabsVM.ensureController(this.tab)
      c.runJavaScript('window.__qhCtxText||""')
        .then((raw: string): void => {
          let v: string = raw
          if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
            try {
              v = JSON.parse(raw) as string
            } catch (e) {
              v = raw
            }
          }
          this.ctxLinkText = v
        })
        .catch((error: BusinessError): void => {
          console.error(`[TabWeb] 读取长按链接文本失败: ${error.code} ${error.message}`)
        })
    } catch (e) {
      console.error(`[TabWeb] 读取长按链接文本异常: ${e}`)
    }
  }

  /** 关闭自定义长按菜单并释放内核菜单状态 */
  private closeCtxMenu(): void {
    this.ctxMenuVisible = false
    this.ctxIsTextMenu = false
    const result = this.ctxResult
    this.ctxResult = null
    if (result !== null) {
      try {
        result.closeContextMenu()
      } catch (e) {
        console.error(`[TabWeb] closeContextMenu 失败: ${e}`)
      }
    }
  }

  /** 内核隐藏菜单（如返回键）时同步清理自定义面板状态 */
  private onCtxMenuHidden(): void {
    this.ctxMenuVisible = false
    this.ctxResult = null
    this.ctxIsTextMenu = false
  }

  /** 执行菜单动作后关闭菜单 */
  private runCtxAction(item: LongPressMenuItem): void {
    // 文字选中菜单：动作走文本分支（复制/全选/搜索/分享）
    if (this.ctxIsTextMenu) {
      const id = item.id
      this.closeCtxMenu()
      if (id === 'text_copy') {
        this.onTextMenuCopy()
      } else if (id === 'text_select_all') {
        this.onTextMenuSelectAll()
      } else if (id === 'text_search') {
        this.onTextMenuSearch()
      } else if (id === 'text_share') {
        this.onTextMenuShare()
      }
      return
    }
    const ctx = new LongPressContext()
    ctx.linkUrl = this.ctxLinkUrl
    ctx.imageUrl = this.ctxImageUrl
    ctx.linkText = this.ctxLinkText
    ctx.pageUrl = this.tab.url
    ctx.pageTitle = this.tab.title
    const tab = this.tab
    this.closeCtxMenu()
    longPressVM.runAction(item.id, ctx, tab, (url: string): void => {
      this.imageViewerUrl = url
    })
  }

  /** 取网页当前选中文本（含输入框/文本域选区） */
  private async fetchSelectionText(): Promise<string> {
    try {
      const c = tabsVM.ensureController(this.tab)
      const raw: string = await c.runJavaScript(
        '(function(){var s=window.getSelection().toString();if(!s){var el=document.activeElement;' +
        'if(el&&(el.tagName===\'INPUT\'||el.tagName===\'TEXTAREA\')&&typeof el.selectionStart===\'number\'){' +
        's=el.value.substring(el.selectionStart,el.selectionEnd);}}return s||\'\';})()')
      let v: string = raw
      if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
        try {
          v = JSON.parse(raw) as string
        } catch (e) {
          v = raw
        }
      }
      return v
    } catch (e) {
      console.error(`[TabWeb] 读取选中文本异常: ${e}`)
      return ''
    }
  }

  /** 文本菜单：复制选中文本 */
  private onTextMenuCopy(): void {
    this.fetchSelectionText()
      .then((text: string): void => {
        longPressVM.copySelectedText(text)
      })
      .catch((): void => {
      })
  }

  /** 文本菜单：全选（编辑框内全选其内容，普通页面全选正文） */
  private onTextMenuSelectAll(): void {
    try {
      tabsVM.ensureController(this.tab).runJavaScript('document.execCommand("selectAll")')
    } catch (e) {
      console.error(`[TabWeb] 全选执行异常: ${e}`)
    }
  }

  /** 文本菜单：按地址栏提交逻辑搜索选中文本 */
  private onTextMenuSearch(): void {
    this.fetchSelectionText()
      .then((text: string): void => {
        longPressVM.searchText(text)
      })
      .catch((): void => {
      })
  }

  /** 文本菜单：分享选中文本 */
  private onTextMenuShare(): void {
    this.fetchSelectionText()
      .then((text: string): void => {
        longPressVM.shareText(text)
      })
      .catch((): void => {
      })
  }

  /**
   * 文字选中：取选区矩形并显示自绘文本菜单（复用长按菜单面板）
   * 作为 editMenuOptions.onCreateMenu 的触发点调用
   */
  private async showTextMenuAtSelection(): Promise<void> {
    const items = LongPressMenuItems.TEXT_MENU
    if (items.length === 0) {
      return
    }
    let xVp = -1
    let selTopVp = -1
    let selBottomVp = -1
    try {
      const c = tabsVM.ensureController(this.tab)
      const raw: string = await c.runJavaScript(
        '(function(){try{var s=window.getSelection();' +
        'if(s&&s.rangeCount>0&&!s.isCollapsed){var r=s.getRangeAt(0).getBoundingClientRect();' +
        'if(r.width>0||r.height>0){return JSON.stringify({x:r.left,y:r.top,w:r.width,h:r.height,iw:window.innerWidth});}}}catch(e){}' +
        'try{var el=document.activeElement;' +
        'if(el&&(el.tagName===\'INPUT\'||el.tagName===\'TEXTAREA\')&&typeof el.selectionStart===\'number\'' +
        '&&el.selectionStart!==el.selectionEnd){var r2=el.getBoundingClientRect();' +
        'return JSON.stringify({x:r2.left,y:r2.top,w:r2.width,h:r2.height,iw:window.innerWidth});}}catch(e){}' +
        'return \'\';})()')
      let selJson: string = raw
      if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
        try {
          selJson = JSON.parse(raw) as string
        } catch (e) {
          selJson = ''
        }
      }
      if (selJson !== '' && selJson.startsWith('{')) {
        try {
          const rect = JSON.parse(selJson) as SelectionRect
          // CSS px → vp：按 Web 宽与视口宽比例换算（无捏合缩放时准确）
          const scale = rect.iw > 0 && this.webWidthVp > 0 ? this.webWidthVp / rect.iw : 1
          // 面板中心对齐选区中心，纵向锚点取选区顶/底
          xVp = (rect.x + rect.w / 2) * scale - 80
          selTopVp = rect.y * scale
          selBottomVp = (rect.y + rect.h) * scale
        } catch (e) {
          xVp = -1
        }
      }
    } catch (e) {
      console.error(`[TabWeb] 读取选区矩形异常: ${e}`)
      xVp = -1
    }
    if (xVp < 0 || selBottomVp < 0) {
      // 选区矩形获取失败：居中偏上兜底
      const vh = this.webHeightVp > 0 ? this.webHeightVp : 600
      xVp = (this.webWidthVp > 0 ? this.webWidthVp : 360) / 2 - 80
      selTopVp = vh * 0.4
      selBottomVp = vh * 0.4
    }
    this.ctxLinkUrl = ''
    this.ctxImageUrl = ''
    this.ctxLinkText = ''
    this.ctxResult = null
    this.ctxIsTextMenu = true
    this.ctxMenuItems = items
    this.clampMenuPosition(xVp, selTopVp, selBottomVp, items.length)
    this.ctxMenuVisible = true
  }

  /** 源码视图自愈重载标志（防死循环） */
  private viewSourceRetried: boolean = false

  /** 源码视图标签：捕获的 HTML 经转义模板 loadData 渲染（CSP 禁脚本） */
  private loadViewSourceDoc(): void {
    try {
      const prefix: string = ViewSourceScripts.URL_PREFIX
      const srcUrl: string = this.tab.url.startsWith(prefix)
        ? this.tab.url.substring(prefix.length) : this.tab.url
      const doc: string = ViewSourceScripts.buildDoc(srcUrl, this.tab.viewSourceHtml,
        ResourceUtils.getString($r('app.string.view_source')),
        ResourceUtils.getString($r('app.string.dom_tree')))
      tabsVM.ensureController(this.tab).loadData(doc, 'text/html', 'UTF-8', ' ', ' ')
      console.info(`[TabWeb] 源码视图已提交 docLen=${doc.length}`)
    } catch (e) {
      console.error(`[TabWeb] 源码视图加载失败: ${e}`)
    }
  }

  /**
   * 源码视图内容校验：loadData 与初始 about:blank 存在竞态（同 ReaderView），
   * 若文档被空白页覆盖则自愈重载一次（viewSourceRetried 防死循环）
   */
  private verifyViewSourceLoaded(): void {
    tabsVM.ensureController(this.tab)
      .runJavaScript('JSON.stringify(document.body ? document.body.innerText.length : -1)')
      .then((raw: string) => {
        let text: string = raw
        try {
          const parsed = JSON.parse(raw) as string
          if (typeof parsed === 'string') {
            text = parsed
          }
        } catch (e) {
          // 保留原始返回
        }
        const len: number = Number(text)
        if (len <= 0 && !this.viewSourceRetried) {
          this.viewSourceRetried = true
          console.error('[TabWeb] 源码视图内容为空，自愈重载')
          this.loadViewSourceDoc()
        }
      })
      .catch((error: BusinessError): void => {
        console.error(`[TabWeb] 源码视图校验失败: ${error.code} ${error.message}`)
        if (!this.viewSourceRetried) {
          this.viewSourceRetried = true
          this.loadViewSourceDoc()
        }
      })
  }

  build() {
    Stack() {
      Web({
        src: this.tab.viewSourceHtml !== '' ? 'about:blank' : this.tab.url,
        controller: tabsVM.ensureController(this.tab),
        incognitoMode: this.tab.isIncognito
      })
        .onControllerAttached(() => {
          if (this.tab.viewSourceHtml !== '') {
            this.loadViewSourceDoc()
            return
          }
          UaUtils.applyTo(tabsVM.ensureController(this.tab))
          this.applyAdsBlockEnable()
          this.applyIntelligentTrackingPrevention()
          // 安全浏览需在页面加载前设置（onPageBegin 时首屏加载已开始）
          this.applySafeBrowsing()
          this.refreshPolicy(this.tab.url)
        })
        .domStorageAccess(true)
        .databaseAccess(true)
        .onlineImageAccess(this.imageAllowedOnline())
        .javaScriptAccess(this.policy.jsEnabled)
        .textZoomRatio(this.policy.fontZoom)
        .forceEnableZoom(appSettings.force_enable_zoom)
        .darkMode(appSettings.force_dark_web ? WebDarkMode.On : WebDarkMode.Auto)
        .forceDarkAccess(appSettings.force_dark_web)
        .javaScriptOnDocumentStart(this.documentStartScripts())
        .javaScriptProxy({
          object: this.clipboardBridge,
          name: '__qhNative',
          methodList: ['clipboardRequest', 'passwordSubmit', 'inspectEvent', 'actionBarScroll',
            'actionBarTapToggle', 'gmRequest', 'sniffMedia'],
          controller: tabsVM.ensureController(this.tab)
        })
        .copyOptions(this.policy.clipboardMode === 'block' ? CopyOptions.None : CopyOptions.LocalDevice)
        .enableHapticFeedback(appSettings.web_vibration_enabled || appSettings.web_haptic_enabled)
        .enableAutoFill(appSettings.system_password_manager)
        .multiWindowAccess(true)
        .allowWindowOpenMethod(true)
        .onWindowNew((event: OnWindowNewEvent) => {
          this.handleWindowNew(event)
        })
        .onActivateContent(() => {
          // window.open 复用已绑定窗口名时，将对应标签切换到前台
          tabsVM.activeTabId = this.tab.id
        })
        .onWindowExit(() => {
          // 弹出式窗口页面调用 window.close() 时关闭对应标签
          if (this.tab.isPopupWindow) {
            tabsVM.closeTab(this.tab.id)
          }
        })
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          // 源码视图：不应用站点策略——loadData 导航栈内同步 setCustomUserAgent
          // 会触发内核 NavigationController 重入断言（SIGTRAP 崩溃），直接放行
          if (this.tab.viewSourceHtml !== '') {
            return false
          }
          // 导航发起前用缓存策略提前应用，保证 UA 对本次主框架请求生效
          const p: SitePolicy | null =
            siteSettingsVM.cachedPolicy(SiteSettingsViewModel.hostOf(event.data.getRequestUrl()))
          if (p !== null) {
            this.applyPolicy(p)
          }
          return this.interceptRedirect(event)
        })
        // 网络日志数据源：轻量记录每个请求（仅字符串处理，无痕标签不记录），
        // 返回 null 按原方式加载（真机已验证该用法无副作用）
        .onInterceptRequest((event: OnInterceptRequestEvent) => {
          if (!this.tab.isIncognito) {
            netLogVM.recordRequest(this.tab.id, event.request, event.request.isMainFrame())
          }
          return null
        })
        // 广告拦截：ArkWeb 原生 AdsBlock 引擎（规则经 AdsBlockManager 全局装载，
        // 实例级开关 enableAdsBlock 随站点策略应用；此回调周期性批量上报拦截结果）
        .onAdsBlocked((details: AdsBlockedDetails) => {
          const urls: Array<string> = details.adsBlocked
          if (urls.length === 0) {
            return
          }
          let bytes: number = 0
          for (const u of urls) {
            bytes += AdBlockEngine.estimateBytes(u)
          }
          adBlockStore.add(urls.length, bytes)
          netLogVM.markBlocked(this.tab.id, urls)
          console.info(`[TabWeb] 广告拦截命中 ${urls.length} 条: ${urls[0]}`)
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          // 资源加载失败诊断日志（主框架/子资源均会回调）
          netLogVM.markError(this.tab.id, event.request.getRequestUrl())
          console.error(`[TabWeb] 资源加载失败 ${event.error.getErrorCode()}: ` +
            `${event.request.getRequestUrl()} ${event.error.getErrorInfo()}`)
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          // HTTP 层错误诊断日志（4xx/5xx 不触发 onErrorReceive）
          netLogVM.markHttpError(this.tab.id, event.request.getRequestUrl())
          console.error(`[TabWeb] HTTP错误 ${event.response.getResponseCode()}: ` +
            `${event.request.getRequestUrl()}`)
        })
        // 网页图标由内核浏览器进程获取（不经过 onInterceptRequest），按惯例补记 /favicon.ico
        .onFaviconReceived((event: OnFaviconReceivedEvent) => {
          netLogVM.recordFavicon(this.tab.id, this.tab.url)
        })
        .geolocationAccess(this.policy.locationMode === 'allow' ? true : appSettings.geolocation_access)
        .onGeolocationShow((event: OnGeolocationShowEvent) => {
          this.showGeolocationDialog(event)
        })
        .onPermissionRequest((event: OnPermissionRequestEvent) => {
          this.handlePermissionRequest(event)
        })
        .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => {
          if (appSettings.ignore_ssl_warning) {
            event.handler.handleConfirm()
          } else {
            event.handler.handleCancel()
          }
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          // 导航离开时关闭可能残留的自定义菜单
          this.closeCtxMenu()
          // 元素审查：绑定标签导航时清选点与选中态（面板保留）
          inspectorVM.resetForNavigation(this.tab.id)
          // 用户脚本：清空本标签已注册的 GM 菜单命令（新页面由脚本重新注册）
          scriptVM.clearMenuCommands(this.tab.id)
          // 源码视图：无站点策略应用（about:blank），跳过
          if (this.tab.viewSourceHtml !== '') {
            return
          }
          this.applySafeBrowsing()
          this.refreshPolicy(event.url)
          this.detectSeq++
          this.tab.readerable = false
          // 色彩模式：新页面 theme-color 重新提取
          this.tab.themeColor = ''
          browserVM.updateNavState(this.tab)
        })
        .onPageEnd((event: OnPageEndEvent) => {
          // 源码视图：仅做内容校验（初始 about:blank 竞态自愈），不写地址/历史/导航状态
          if (this.tab.viewSourceHtml !== '') {
            this.verifyViewSourceLoaded()
            return
          }
          this.tab.url = event.url
          this.tab.progress = 100
          this.applyBackForwardCache()
          this.autofillPassword()
          this.injectUserScripts(event.url)
          this.detectReadability()
          this.detectThemeColor()
          browserVM.onPageEnded(this.tab, event.url)
          browserVM.updateNavState(this.tab)
        })
        // 页面 favicon 回调：按 host 缓存（书签列表/桌面快捷方式展示用）
        .onFaviconReceived((event: OnFaviconReceivedEvent) => {
          console.info(`[TabWeb] onFaviconReceived url=${this.tab.url}`)
          faviconCache.saveFromPixelMap(FaviconCache.hostOf(this.tab.url), event.favicon)
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.tab.progress = event.newProgress
        })
        .onTitleReceive((event: OnTitleReceiveEvent) => {
          // 源码文档无 <title>，保持标签标题"源码"不被空标题覆盖
          if (this.tab.viewSourceHtml !== '') {
            return
          }
          this.tab.title = event.title
        })
        // 控制台消息捕获（元素审查-调试页数据源），返回 false 保持默认输出行为
        .onConsole((event: OnConsoleEvent): boolean => {
          const m = event.message
          const lv = m.getMessageLevel()
          const level: string = lv === MessageLevel.Error ? 'error'
            : lv === MessageLevel.Warn ? 'warn'
              : lv === MessageLevel.Debug ? 'debug' : 'log'
          inspectorVM.pushLog(this.tab.id, level, m.getMessage(), m.getSourceId(), `${m.getLineNumber()}`)
          return false
        })
        .onSearchResultReceive((event: OnSearchResultReceiveEvent) => {
          browserVM.onFindResult(event.activeMatchOrdinal, event.numberOfMatches, event.isDoneCounting)
        })
        // 网页元素长按菜单（PC 窗口模式鼠标右键同触发）：返回 true 接管为自定义菜单
        .onContextMenuShow((event: OnContextMenuShowEvent): boolean => {
          return this.handleContextMenu(event)
        })
        .onContextMenuHide(() => {
          this.onCtxMenuHidden()
        })
        // 文字长按/选中：屏蔽系统文本菜单（onCreateMenu 返回空），改弹自绘面板
        .editMenuOptions({
          onCreateMenu: (menuItems: Array<TextMenuItem>): Array<TextMenuItem> => {
            this.showTextMenuAtSelection()
            return []
          },
          onMenuItemClick: (menuItem: TextMenuItem, textRange: TextRange): boolean => {
            return false
          }
        } as EditMenuOptions)
        .onDownloadStart((event: OnDownloadStartEvent) => {
          downloadVM.download(event.url, this.tab.url)
        })

      // 夜间模式：网页蒙版滤镜
      if (appSettings.night_mask_enabled) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(appSettings.maskColorHex())
          .opacity(appSettings.night_mask_opacity / 100)
          .hitTestBehavior(HitTestMode.None)
      }

      // 网页元素长按/右键菜单（自定义接管）
      if (this.ctxMenuVisible) {
        this.ctxMenuOverlay()
      }

      // 看图模式：图片全屏查看
      if (this.imageViewerUrl !== '') {
        this.imageViewerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .visibility(this.tab.id === tabsVM.activeTabId ? Visibility.Visible : Visibility.None)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const w = newValue.width
      const h = newValue.height
      if (typeof w === 'number' && w > 0) {
        this.webWidthVp = w
      }
      if (typeof h === 'number' && h > 0) {
        this.webHeightVp = h
      }
    })
    // 滑动导航：并行横滑手势（不阻断网页触摸），大幅横向滑动触发前进/后退
    .parallelGesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
      .onActionEnd((event: GestureEvent) => {
        this.handleSwipeNav(event.offsetX, event.offsetY)
      }))
  }

  /**
   * 滑动导航判定（操作设定-滑动屏幕前进后退开启时）：
   * 位移超阈值且横向主导——右滑后退、左滑前进；
   * 看图/长按菜单覆盖层展示中不触发
   */
  private handleSwipeNav(dx: number, dy: number): void {
    if (!appSettings.swipe_nav_enabled || this.tab.isHome
      || this.imageViewerUrl !== '' || this.ctxMenuVisible) {
      return
    }
    if (Math.abs(dx) < 90 || Math.abs(dx) < Math.abs(dy) * 1.2) {
      return
    }
    if (dx > 0) {
      browserVM.goBack()
    } else {
      browserVM.goForward()
    }
  }

  /** 长按/右键自定义菜单覆盖层：透明捕获层 + 浮动文字面板 */
  @Builder
  ctxMenuOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.closeCtxMenu()
        })
      Scroll() {
        Column() {
          ForEach(this.ctxMenuItems, (item: LongPressMenuItem) => {
            Text(item.title)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .textAlign(TextAlign.Start)
              .onClick(() => {
                this.runCtxAction(item)
            })
          }, (item: LongPressMenuItem) => item.id)
        }
        .width('100%')
      }
      .width(160)
      .height(this.ctxMenuHeight)
      .align(Alignment.Top)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
        .combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: 150, curve: Curve.EaseOut }))
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(16)
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.2)', offsetX: 0, offsetY: 8 })
      .position({ x: this.ctxMenuX, y: this.ctxMenuY })
    }
    .width('100%')
    .height('100%')
  }

  /** 看图模式：黑底全屏查看，单击关闭，捏合缩放 */
  @Builder
  imageViewerOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(this.imageViewerUrl)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
        .scale({ x: this.viewerScale, y: this.viewerScale })
        .gesture(PinchGesture()
          .onActionStart(() => {
            this.viewerBaseScale = this.viewerScale
          })
          .onActionUpdate((event: GestureEvent) => {
            this.viewerScale = Math.min(5, Math.max(1, this.viewerBaseScale * event.scale))
          }))
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(28)
        .fontColor([Color.White])
        .margin(16)
        .onClick(() => {
          this.closeImageViewer()
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.92)')
    .onClick(() => {
      this.closeImageViewer()
    })
  }

  /** 关闭看图模式并复位缩放 */
  private closeImageViewer(): void {
    this.viewerScale = 1
    this.viewerBaseScale = 1
    this.imageViewerUrl = ''
  }
}
