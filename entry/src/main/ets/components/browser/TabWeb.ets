import { connection } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { abilityAccessCtrl, Permissions, PermissionRequestResult, Want } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { CustomContentDialog, display } from '@kit.ArkUI';
import { tabsVM, TabInfo } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { downloadVM } from '../../viewmodel/DownloadViewModel';
import { appSettings, UISettings } from '../../common/entity/SettingsModel';
import { toastUtil } from '../../common/utils/ui/ToastUtils';
import { ResourceUtils } from '../../common/utils/app/ResourceUtil';
import { UaUtils } from '../../common/utils/web/UaUtils';
import { DnsUtils } from '../../common/utils/network/DnsUtils';
import { ProxyUtils } from '../../common/utils/network/ProxyUtils';
import { AdvancedSecurityUtils } from '../../common/utils/security/AdvancedSecurityUtils';
import { ItpBypassUtils } from '../../common/utils/security/ItpBypassUtils';
import { AdBlockEngine } from '../../common/utils/adblock/AdBlockEngine';
import { adBlockStore } from '../../common/utils/adblock/AdBlockStore';
import { WebScripts } from '../../common/utils/scripts/WebScripts';
import { VideoScripts } from '../../common/utils/scripts/VideoScripts';
import { VideoFullScreen } from '../../common/utils/ui/VideoFullScreen';
import { WebHostedPlayerSession } from './WebHostedPlayer';
import { ReaderScripts } from '../../common/utils/scripts/ReaderScripts';
import { ViewSourceScripts } from '../../common/utils/scripts/ViewSourceScripts';
import { SitePolicy, SiteSettingsViewModel, siteSettingsVM } from '../../viewmodel/SiteSettingsViewModel';
import { hostsVM } from '../../viewmodel/HostsViewModel';
import { passwordVM, PasswordDecision } from '../../viewmodel/PasswordViewModel';
import PasswordInfo from '../../common/entity/PasswordInfo';
import { buildDialogButtons } from '../dialog/AppContentDialog';
import { _QhState } from '../../entryability/AppState';
import { LongPressMenuItem, LongPressMenuItems, LongPressTarget } from '../../common/constants/LongPressMenuItems';
import { longPressVM, LongPressContext } from '../../viewmodel/LongPressMenuViewModel';
import { netLogVM } from '../../viewmodel/NetworkLogViewModel';
import { trackerVM } from '../../viewmodel/TrackerViewModel';
import { inspectorVM } from '../../viewmodel/InspectorViewModel';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';
import { scriptVM } from '../../viewmodel/ScriptViewModel';
import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import { ExtensionResources, EXT_SCHEME_PREFIX } from '../../common/utils/extension/ExtensionResources';
import { translateVM } from '../../viewmodel/TranslateViewModel';
import { GmValueRaw, GmDeleteValueRaw, GmOpenTabRaw, GmClipboardRaw, GmNotifyRaw, GmDownloadRaw, GmMenuRaw, GmMenuIdRaw } from '../../common/utils/userscript/GmRuntime';
import { ExtNotifyRaw } from '../../common/utils/extension/ChromeShim';
import { kbShortcutDispatch } from '../../common/utils/ui/KbShortcutDispatch';
import { NetDiagnose, DiagnoseResult, SegmentState } from '../../common/utils/network/NetDiagnose';

/** 网页选区矩形（CSS px，相对视口；由注入脚本返回的 JSON 解析而来） */
interface SelectionRect {
  x: number
  y: number
  w: number
  h: number
  iw: number
}

/** HTML 文本/属性转义（错误页 URL 注入防 XSS） */
function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
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
  private readonly videoHandler: (api: string, arg: string) => void

  constructor(handler: (action: string, cbId: number, text: string) => void,
    passwordHandler: (username: string, password: string) => void,
    inspectHandler: (payload: string) => void,
    scrollHandler: (hidden: boolean) => void,
    tapToggleHandler: () => void,
    gmHandler: (api: string, json: string) => void,
    sniffHandler: (url: string, kind: string) => void,
    videoHandler: (api: string, arg: string) => void) {
    this.handler = handler
    this.passwordHandler = passwordHandler
    this.inspectHandler = inspectHandler
    this.scrollHandler = scrollHandler
    this.tapToggleHandler = tapToggleHandler
    this.gmHandler = gmHandler
    this.sniffHandler = sniffHandler
    this.videoHandler = videoHandler
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

  /** 视频手势桥（__qhNative.videoRequest）：全屏左半屏上下滑调节窗口亮度 */
  videoRequest(api: string, arg: string): void {
    this.videoHandler(api, arg)
  }

  /** 已安装扩展商店 ID 集合（__qhNative.getInstalledExtIds，同步返回 JSON 数组字符串；
   * 商店页注入 JS 据此把已安装扩展的"获取"按钮显示为"已安装"） */
  getInstalledExtIds(): string {
    return extensionVM.installedExtIdsJson()
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
  /** 加载卡住分段诊断覆盖层可见性 */
  @Local diagVisible: boolean = false
  /** 诊断三段状态（浏览器/网络/网站） */
  @Local diagDevice: SegmentState = SegmentState.CHECKING
  @Local diagNetwork: SegmentState = SegmentState.CHECKING
  @Local diagSite: SegmentState = SegmentState.CHECKING
  /** 诊断完成（三段出结果或短路，控制文案与按钮） */
  @Local diagDone: boolean = false
  /** 诊断目标 host（覆盖层文案展示） */
  @Local diagHost: string = ''
  /** 已应用的 UA 覆盖（'' = 跟随应用） */
  private appliedUa: string | null = null

  /** 广告拦截开关已应用状态（null=未应用；避免重复 enableAdsBlock） */
  private appliedAdsBlockOn: boolean | null = null

  /** 智能防跟踪已应用状态（null=未应用；避免重复 enableIntelligentTrackingPrevention） */
  private appliedItpOn: boolean | null = null

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
  }, (api: string, arg: string): void => {
    this.handleVideoRequest(api, arg)
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

  /** HTTP 认证：本次导航已自动尝试过的 host|realm（防错误凭证 401 死循环，onPageBegin 清空） */
  private authGuard: Map<string, boolean> = new Map()
  /** HTTP 认证：待处理的核心 handler（弹窗登录/取消时消费） */
  private pendingAuthHandler: HttpAuthHandler | null = null
  /** HTTP 认证弹窗状态 */
  @Local authHost: string = ''
  @Local authRealm: string = ''
  @Local authUsername: string = ''
  @Local authPassword: string = ''
  @Local authShowPwd: boolean = false
  @Local authRemember: boolean = true
  /** 上次自动尝试的凭证被拒（弹窗顶部提示） */
  @Local authFailed: boolean = false
  private httpAuthDialog: CustomDialogController | undefined = undefined

  /** JS 弹窗（alert/confirm/prompt）：类型 'alert' | 'confirm' | 'prompt' */
  @Local jsKind: string = ''
  /** JS 弹窗：来源站点 / 消息 / prompt 输入 */
  @Local jsDlgHost: string = ''
  @Local jsDlgMessage: string = ''
  @Local jsDlgInput: string = ''
  /** JS 弹窗：勾选「阻止此页更多弹窗」 */
  @Local jsBlockMore: boolean = false
  /** JS 弹窗：待回执的内核 result（按钮点击时消费） */
  private pendingJsResult: JsResult | null = null
  private jsAlertDialog: CustomDialogController | undefined = undefined
  private jsConfirmDialog: CustomDialogController | undefined = undefined

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
    this.initHttpAuthDialog()
    this.initJsDialogs()
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
    this.cancelLoadStallWatchdog()
    this.netConn?.unregister(() => {
    })
    inspectorVM.removeLogs(this.tab.id)
    // 视频托管：释放托管会话（AVPlayer 等底层资源）
    if (this.tab.hostedSession !== null) {
      this.tab.hostedSession.release()
    }
    // 全屏中组件销毁（Web 随之销毁不会再回调退出）：恢复系统栏与方向
    if (this.tab.videoFullScreen) {
      this.tab.videoFullScreen = false
      this.tab.videoExitHandler = null
      VideoFullScreen.exit()
    }
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

  /** 网页字体族：开启"应用到网页"且已选自定义字体时返回 family，否则空串（回落默认） */
  private webFontFamily(): string {
    return appSettings.web_font_enabled ? appSettings.font_family : ''
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
    let code: string = scriptVM.onPageEndCode(url)
    // 扩展 content_scripts：document-end/document_idle
    code += extensionVM.onPageEndCode(url)
    // 商店直装浮层（Chrome Web Store / Edge Add-ons 站点）
    code += extensionVM.storePageCode(url)
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
        // ==== 扩展兼容层（__qhExtCore → __qhNative.gmRequest） ====
        case 'extStorageGet':
          extensionVM.extStorageGet(json, this.tab.controller)
          break
        case 'extStorageSet':
          extensionVM.extStorageSet(json, this.tab.controller)
          break
        case 'extStorageRemove':
          extensionVM.extStorageRemove(json, this.tab.controller)
          break
        case 'extStorageClear':
          extensionVM.extStorageClear(json, this.tab.controller)
          break
        case 'extSendMsg':
          extensionVM.extSendMessage(json, this.tab)
          break
        case 'extRespond':
          extensionVM.extRespond(json)
          break
        case 'extStoreInstall':
          extensionVM.extStoreInstall(json)
          break
        // ==== 扩展页面标签页（虚拟域 post-install/options）宿主沙箱路由 ====
        case 'extSendMsgPopup':
          extensionVM.extSendMsgFromPopup(json, tabsVM.ensureController(this.tab))
          break
        case 'extPortConnect':
          // 内容脚本/标签内扩展页 runtime.connect → bg 宿主 onConnect
          extensionVM.extPortConnect(json, tabsVM.ensureController(this.tab), 'tab', this.tab)
          break
        case 'extPortMsg':
          extensionVM.extPortMsg(json, tabsVM.ensureController(this.tab))
          break
        case 'extPortDisconnect':
          extensionVM.extPortDisconnect(json, tabsVM.ensureController(this.tab))
          break
        case 'extTabQuery':
          extensionVM.extTabQuery(json, tabsVM.ensureController(this.tab))
          break
        case 'extTabSendMsg':
          extensionVM.extTabSendMsg(json, tabsVM.ensureController(this.tab))
          break
        case 'extTabCreate':
          extensionVM.extTabCreate(json, tabsVM.ensureController(this.tab))
          break
        case 'extExecuteScript':
          extensionVM.extExecuteScript(json, tabsVM.ensureController(this.tab))
          break
        case 'extNotify': {
          const notifyRaw: ExtNotifyRaw = JSON.parse(json) as ExtNotifyRaw
          if (notifyRaw.text !== '') {
            toastUtil.showToast({ message: notifyRaw.text })
          }
          break
        }
        case 'extWindowClose':
          /* 扩展页 window.close()（Chrome 语义）→ 关当前标签；
             延迟销毁避免在 javaScriptProxy 回调内卸载 Web */
          setTimeout((): void => {
            tabsVM.closeTab(this.tab.id)
          }, 0)
          break
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

  /**
   * 视频手势原生请求（__qhNative.videoRequest）：
   * brightness 设窗口亮度（0-1）、brightnessReset 恢复跟随系统（-1）
   */
  private handleVideoRequest(api: string, arg: string): void {
    const win = _QhState.window
    if (!win) {
      return
    }
    try {
      if (api === 'brightness') {
        const v: number = Number(arg)
        if (!Number.isNaN(v)) {
          win.setWindowBrightness(Math.min(1, Math.max(0.02, v)))
            .catch((): void => {
            })
        }
      } else if (api === 'brightnessReset') {
        win.setWindowBrightness(-1)
          .catch((): void => {
          })
      }
    } catch (e) {
      console.error(`[TabWeb] 视频手势亮度请求失败: ${e}`)
    }
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
    // 视频控制：手势 + 键盘快捷键（任一开启时注入）
    const videoScript: ScriptItem | null = VideoScripts.controlScript()
    if (videoScript !== null) {
      scripts.push(videoScript)
    }
    // 用户脚本：@run-at document-start（@match 规则做 URL 预过滤）
    for (const item of scriptVM.docStartScriptItems()) {
      scripts.push(item)
    }
    // 扩展 content_scripts：manifest run_at = document_start（matches 预过滤）
    for (const item of extensionVM.docStartScriptItems()) {
      scripts.push(item)
    }
    // 商店站原生安装按钮接管（crxsoso）：文档开始注入，保证监听先于页面按钮可点击
    for (const item of extensionVM.storePageStartItems()) {
      scripts.push(item)
    }
    // 扩展页面标签页（虚拟域 post-install/options 等）：注入宿主沙箱（含 core）
    for (const item of extensionVM.extPageScriptItems()) {
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
    this.applyIntelligentTrackingPrevention()
    siteSettingsVM.registerLive(p.host, p)
  }

  /** 应用 UA（域名级模式下由内核按 host 映射处理，实例级仅能力回退时使用） */
  private applyUa(p: SitePolicy): void {
    if (UaUtils.hostUaMode()) {
      this.appliedUa = p.uaOverride
      return
    }
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
   * 网页请求新窗口（window.open / target=_blank），按站点策略三态处理：
   * 允许 → 直接以新标签打开；拒绝 → 回执拦截并提示；
   * 询问 → 弹窗许可（内核在此期间阻塞渲染，须在允许/拒绝/取消时均回执解除）
   */
  private handleWindowNew(event: OnWindowNewEvent): void {
    if (this.policy.popupMode === 'allow') {
      this.openPopupAsTab(event)
      return
    }
    if (this.policy.popupMode === 'block') {
      this.rejectPopup(event)
      toastUtil.showToast({ message: $r('app.string.popup_blocked_toast') })
      return
    }
    // 询问：与当前页同域名的窗口直接放行（about:blank/空目标继承来源页源，视为同域）
    if (appSettings.popup_allow_same_host && this.isSameHostPopup(event.targetUrl)) {
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

  /** 弹出目标与当前页是否同域名（空目标/about:blank 由来源页 document.write 写入，视为同域） */
  private isSameHostPopup(targetUrl: string): boolean {
    if (targetUrl === '' || targetUrl === 'about:blank') {
      return true
    }
    const targetHost: string = SiteSettingsViewModel.hostOf(targetUrl)
    return targetHost !== '' && targetHost === SiteSettingsViewModel.hostOf(this.tab.url)
  }

  /**
   * 智能防跟踪应用到当前 Web 实例（ArkWeb 内核拦截跨站跟踪请求携带 Cookie）：
   * 全局开关 && 站点未开「允许跨站跟踪」豁免
   */
  private applyIntelligentTrackingPrevention(): void {
    const on: boolean = appSettings.intelligent_tracking_prevention && !this.policy.allowCrossSiteTracking
    if (this.appliedItpOn === on) {
      return
    }
    try {
      tabsVM.ensureController(this.tab)
        .enableIntelligentTrackingPrevention(on)
      this.appliedItpOn = on
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

  /**
   * 网页屏幕录制授权（getDisplayMedia）：站点策略 allow/block 直接生效，其余弹窗询问；
   * 弹窗决策写入单站点例外（rememberPermission → setOverride(host)，不碰全局默认）
   */
  private handleScreenCaptureRequest(event: OnScreenCaptureRequestEvent): void {
    const handler: ScreenCaptureHandler = event.handler
    const origin: string = handler.getOrigin()
    if (this.policy.screenCaptureMode === 'allow') {
      handler.grant({ captureMode: WebCaptureMode.HOME_SCREEN })
      return
    }
    if (this.policy.screenCaptureMode === 'block') {
      handler.deny()
      return
    }
    toastUtil.showAlertDialog({
      title: $r('app.string.web_permission_title'),
      message: `${origin} ${ResourceUtils.getString($r('app.string.web_permission_use_screen'))}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.allow'),
          action: (): void => {
            this.policy.screenCaptureMode = 'allow'
            this.rememberPermission(origin, 'site_screen_capture', 'allow')
            handler.grant({ captureMode: WebCaptureMode.HOME_SCREEN })
          }
        },
        {
          value: $r('app.string.deny'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            this.policy.screenCaptureMode = 'block'
            this.rememberPermission(origin, 'site_screen_capture', 'block')
            handler.deny()
          }
        }
      ]
    }, 'webScreenCapture')
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

  /** 初始化 HTTP 认证登录弹窗 */
  private initHttpAuthDialog(): void {
    this.httpAuthDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.http_auth_title'),
        contentBuilder: (): void => {
          this.httpAuthContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.http_auth_login')], false,
          (index: number): void => {
            if (index === 1) {
              this.doHttpAuthLogin()
              return
            }
            this.cancelHttpAuth()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  /** HTTP 认证弹窗正文：站点 / realm / 失败提示 / 用户名密码输入 / 记住开关 */
  @Builder
  httpAuthContent() {
    Column({ space: 12 }) {
      if (this.authFailed) {
        Text($r('app.string.http_auth_failed'))
          .fontSize(14)
          .fontColor(Color.Red)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Text(this.authHost)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.authRealm !== '') {
        Text(this.authRealm)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      TextInput({ placeholder: ResourceUtils.getString($r('app.string.label_username')), text: this.authUsername })
        .height(48)
        .fontSize(16)
        .onChange((value: string): void => {
          this.authUsername = value
        })
      Row({ space: 8 }) {
        TextInput({
          placeholder: ResourceUtils.getString($r('app.string.label_password')),
          text: this.authPassword
        })
          .height(48)
          .fontSize(16)
          .type(this.authShowPwd ? InputType.Normal : InputType.Password)
          .onChange((value: string): void => {
            this.authPassword = value
          })
        SymbolGlyph(this.authShowPwd ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
          .fontSize(22)
          .fontColor([$r('sys.color.font_secondary')])
          .onClick((): void => {
            this.authShowPwd = !this.authShowPwd
          })
      }
      .alignItems(VerticalAlign.Center)
      if (!this.tab.isIncognito) {
        Row() {
          Text($r('app.string.http_auth_remember'))
            .fontSize(14)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.authRemember })
            .onChange((isOn: boolean): void => {
              this.authRemember = isOn
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * HTTP 认证请求分流：非无痕且未自动尝试过 → 查密码管理器自动登录（一次）；
   * 否则弹登录框。guard 防止错误凭证 401 死循环，onPageBegin 清空
   */
  private handleHttpAuth(event: OnHttpAuthRequestEvent): void {
    const host: string = event.host
    const realm: string = event.realm
    const key: string = `${host}|${realm}`
    const tried: boolean = this.authGuard.get(key) === true
    if (!this.tab.isIncognito && !tried) {
      passwordVM.basicCredentialFor(host, realm)
        .then((cred: PasswordInfo | null): void => {
          if (cred !== null && !this.authGuard.get(key)) {
            this.authGuard.set(key, true)
            event.handler.confirm(cred.username, cred.password)
            return
          }
          this.openHttpAuthDialog(event.handler, host, realm, tried)
        })
        .catch((): void => {
          this.openHttpAuthDialog(event.handler, host, realm, tried)
        })
      return
    }
    this.openHttpAuthDialog(event.handler, host, realm, tried)
  }

  /** 打开 HTTP 认证登录弹窗 */
  private openHttpAuthDialog(handler: HttpAuthHandler, host: string, realm: string, failed: boolean): void {
    this.pendingAuthHandler = handler
    this.authHost = host
    this.authRealm = realm
    this.authUsername = ''
    this.authPassword = ''
    this.authShowPwd = false
    this.authRemember = true
    this.authFailed = failed
    this.httpAuthDialog?.open()
  }

  /** 弹窗「登录」：确认认证，勾选记住则写入密码管理器（无痕不落库） */
  private doHttpAuthLogin(): void {
    const host: string = this.authHost
    const realm: string = this.authRealm
    const username: string = this.authUsername
    const password: string = this.authPassword
    this.authGuard.set(`${host}|${realm}`, true)
    if (this.authRemember && !this.tab.isIncognito) {
      passwordVM.upsertBasic(host, realm, username, password)
    }
    this.pendingAuthHandler?.confirm(username, password)
    this.pendingAuthHandler = null
    this.httpAuthDialog?.close()
  }

  /** 弹窗「取消」：取消本次认证 */
  private cancelHttpAuth(): void {
    this.pendingAuthHandler?.cancel()
    this.pendingAuthHandler = null
    this.httpAuthDialog?.close()
  }

  /** 初始化 JS 三大弹窗（alert 单按钮 / confirm+prompt 双按钮） */
  private initJsDialogs(): void {
    this.jsAlertDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.js_dialog_title'),
        contentBuilder: (): void => {
          this.jsDialogContent(false)
        },
        buttons: buildDialogButtons([$r('app.string.confirm')], false,
          (index: number): void => {
            this.finishJsDialog(true)
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
    this.jsConfirmDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.js_dialog_title'),
        contentBuilder: (): void => {
          this.jsDialogContent(true)
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], false,
          (index: number): void => {
            this.finishJsDialog(index === 1)
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  /** JS 弹窗正文：站点 / 消息 / prompt 输入框 / 阻止此页更多弹窗开关 */
  @Builder
  jsDialogContent(withCancel: boolean) {
    Column({ space: 12 }) {
      Text(this.jsDlgHost)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.jsDlgMessage)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
      if (this.jsKind === 'prompt') {
        TextInput({ text: this.jsDlgInput })
          .height(48)
          .fontSize(16)
          .onChange((value: string): void => {
            this.jsDlgInput = value
          })
      }
      Row() {
        Text($r('app.string.js_dialog_block'))
          .fontSize(14)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.jsBlockMore })
          .onChange((isOn: boolean): void => {
            this.jsBlockMore = isOn
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** JS alert()：本页已阻止时直接回执确定，否则弹应用风格对话框 */
  private handleJsAlert(event: OnAlertEvent): boolean {
    if (this.tab.jsDialogBlocked) {
      event.result.handleConfirm()
      return true
    }
    this.jsKind = 'alert'
    this.jsDlgHost = SiteSettingsViewModel.hostOf(event.url)
    this.jsDlgMessage = event.message
    this.jsDlgInput = ''
    this.jsBlockMore = false
    this.pendingJsResult = event.result
    this.jsAlertDialog?.open()
    return true
  }

  /** JS confirm()：本页已阻止时直接回执取消，否则弹应用风格对话框 */
  private handleJsConfirm(event: OnConfirmEvent): boolean {
    if (this.tab.jsDialogBlocked) {
      event.result.handleCancel()
      return true
    }
    this.jsKind = 'confirm'
    this.jsDlgHost = SiteSettingsViewModel.hostOf(event.url)
    this.jsDlgMessage = event.message
    this.jsDlgInput = ''
    this.jsBlockMore = false
    this.pendingJsResult = event.result
    this.jsConfirmDialog?.open()
    return true
  }

  /** JS prompt()：本页已阻止时直接回执取消，否则弹应用风格对话框（带输入框） */
  private handleJsPrompt(event: OnPromptEvent): boolean {
    if (this.tab.jsDialogBlocked) {
      event.result.handleCancel()
      return true
    }
    this.jsKind = 'prompt'
    this.jsDlgHost = SiteSettingsViewModel.hostOf(event.url)
    this.jsDlgMessage = event.message
    this.jsDlgInput = event.value
    this.jsBlockMore = false
    this.pendingJsResult = event.result
    this.jsConfirmDialog?.open()
    return true
  }

  /** JS 弹窗按钮回执：按类型回执内核；勾选阻止则本页后续弹窗自动关闭（onPageBegin 复位） */
  private finishJsDialog(confirmed: boolean): void {
    const result: JsResult | null = this.pendingJsResult
    this.pendingJsResult = null
    if (this.jsBlockMore) {
      this.tab.jsDialogBlocked = true
    }
    if (result === null) {
      return
    }
    try {
      if (this.jsKind === 'prompt') {
        if (confirmed) {
          result.handlePromptConfirm(this.jsDlgInput)
        } else {
          result.handleCancel()
        }
      } else if (this.jsKind === 'alert') {
        result.handleConfirm()
      } else {
        if (confirmed) {
          result.handleConfirm()
        } else {
          result.handleCancel()
        }
      }
    } catch (e) {
      console.error(`[TabWeb] JS 弹窗回执失败: ${e}`)
    }
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
   * 色彩模式：提取页面顶部条带颜色供操作栏自适应（提取失败保持默认色）。
   * 优先采样网页顶部（elementFromPoint 逐点取元素/祖先不透明背景色，检测 linear-gradient 渐变），
   * 无采样结果回退 meta theme-color，再回退 body/html 背景；返回 ["#hex", "#hex"]，第二色为渐变端色（纯色为 ""）
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
      '(function(){' +
      'function hx(c){var s="";for(var i=0;i<c.length;i++){var h=Math.round(c[i]).toString(16);s+=h.length<2?"0"+h:h}return "#"+s}' +
      'function pc(t){var m=t.match(/rgba?\\([^)]+\\)/);if(!m)return null;' +
      'var p=m[0].substring(m[0].indexOf("(")+1,m[0].indexOf(")")).split(",");' +
      'if(p.length<3)return null;if(p.length>3&&parseFloat(p[3])<0.9)return null;' +
      'return[parseFloat(p[0]),parseFloat(p[1]),parseFloat(p[2])]}' +
      'function eb(el){var g=0;while(el&&g<24){var st=getComputedStyle(el);' +
      'var bi=st.backgroundImage||"";' +
      'if(bi.indexOf("linear-gradient")>=0){var cs=bi.match(/rgba?\\([^)]+\\)/g);' +
      'if(cs&&cs.length>0){var a=pc(cs[0]);if(a){var b=pc(cs[cs.length-1]);' +
      'return{c:a,g:b&&b[0]===a[0]&&b[1]===a[1]&&b[2]===a[2]?null:b}}}}' +
      'var k=pc(st.backgroundColor);if(k)return{c:k,g:null};el=el.parentElement;g++}return null}' +
      'function at(x,y){var el=document.elementFromPoint(x,y);return el?eb(el):null}' +
      'var w=innerWidth,r=[0,0,0],n=0,ga=null,gb=null;' +
      'for(var y=2;y<=44;y+=7){for(var i=1;i<=3;i++){var q=at(w*i/4,y);' +
      'if(q){r[0]+=q.c[0];r[1]+=q.c[1];r[2]+=q.c[2];n++;if(q.g&&!ga){ga=q.c;gb=q.g}}}}' +
      'if(n>0){if(ga&&gb)return JSON.stringify([hx(ga),hx(gb)]);' +
      'return JSON.stringify([hx([r[0]/n,r[1]/n,r[2]/n]),""])}' +
      'var m=document.querySelector(\'meta[name="theme-color"]\');' +
      'if(m&&m.content)return JSON.stringify([m.content,""]);' +
      'var b=eb(document.body)||eb(document.documentElement);' +
      'return b?JSON.stringify([hx(b.c),""]):""' +
      '})()'
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
        if (v === '') {
          return
        }
        try {
          const pair: string[] = JSON.parse(v) as string[]
          if (pair.length === 2 && pair[0].startsWith('#')) {
            this.tab.themeColor = pair[0]
            this.tab.themeColor2 = pair[1].startsWith('#') ? pair[1] : ''
          }
        } catch (e) {
          // 解析失败保持默认色
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
      } else if (id === 'text_translate') {
        this.onTextMenuTranslate()
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

  /** 内核上报的当前选中文本（onTextSelectionChange 缓存；含 iframe 内跨帧选区，导航时重置） */
  private selTextCache: string = ''

  /** 白屏检测：已自动重试过的 URL（同 URL 仅重试一次防慢页面循环刷新；离开该 URL 后重置） */
  private blankRetryUrl: string = ''

  /** 加载停滞看门狗定时器句柄（onLoadIntercept 放行主框架导航时武装，仅守「响应未到达」阶段；onPageBegin 响应到达/页面绘制出内容/用户点继续等待/onPageEnd/错误页/销毁取消；-1 = 未启动） */
  private loadStallTimer: number = -1

  /** 诊断覆盖层已针对的 URL（同 URL 去重，防看门狗与白屏检测重复弹诊断） */
  private diagUrl: string = ''

  /** 当前主框架为已接管的应用错误页（onOverrideErrorPage 已返回）：白屏检测跳过——错误页大留白设计易被采样误判白屏，且自带重试入口无需刷新/诊断；新导航发起（onLoadIntercept 放行主框架）或 onPageBegin 到不同 URL 时复位 */
  private errorPageShown: boolean = false

  /** 已接管错误页对应的原始 URL：错误页自身的 onPageBegin/onPageEnd 报原始 URL（非 arkweb-error://），用它区分错误页内部回调与真实新导航 */
  private errorPageShownUrl: string = ''

  /** 本导航周期内页面已有绘制证据（首屏/主要内容/最大内容绘制任一触发）：白屏检测结果不信任直接跳过——内核检测器在大留白浅色页面误报（真机实测 hap.atomgit.com 已 OnPageEnd 仍报 contentful_point_count=0）；新导航发起/提交时复位 */
  private paintedSinceNav: boolean = false

  /**
   * 构建应用风格错误页 HTML（onOverrideErrorPage 返回值，主框架加载失败时替代内核默认错误页）：
   * 深浅色自适应 + 常见错误码文案映射 + 重试链接（点击重载原 URL）
   */
  private buildErrorPageHtml(event: OnErrorReceiveEvent): string {
    const url: string = event.request.getRequestUrl()
    const code: number = event.error.getErrorCode()
    let host: string = SiteSettingsViewModel.hostOf(url)
    if (host === '') {
      host = url
    }
    const tipRes: Resource = code === -2 ? $r('app.string.error_page_dns')
      : code === -106 ? $r('app.string.error_page_offline')
        : code === -109 ? $r('app.string.error_page_unreachable')
          : code === -118 ? $r('app.string.error_page_timeout')
            : $r('app.string.error_page_generic')
    const title: string = ResourceUtils.getString($r('app.string.error_page_title'))
    const tip: string = ResourceUtils.getString(tipRes)
    const retry: string = ResourceUtils.getString($r('app.string.error_page_retry'))
    return `<!DOCTYPE html><html><head><meta charset="utf-8">` +
      `<meta name="viewport" content="width=device-width,initial-scale=1">` +
      `<style>body{margin:0;display:flex;align-items:center;justify-content:center;` +
      `min-height:100vh;background:#f1f3f5;color:#182431;text-align:center;` +
      `font-family:system-ui,-apple-system,sans-serif}` +
      `.card{padding:0 32px;max-width:420px}` +
      `.icon{color:#a8a8a8}` +
      `h1{font-size:20px;font-weight:600;margin:24px 0 8px}` +
      `p.tip{font-size:15px;color:#6b7280;margin:0;line-height:1.6}` +
      `p.host{font-size:13px;color:#9aa0a6;margin:10px 0 0;word-break:break-all}` +
      `a.btn{display:inline-block;margin-top:28px;padding:10px 44px;border-radius:24px;` +
      `background:#0a59f7;color:#ffffff;text-decoration:none;font-size:15px}` +
      `p.code{margin-top:22px;font-size:12px;color:#b0b6bd}` +
      `@media(prefers-color-scheme:dark){body{background:#121212;color:#e6e6e6}` +
      `p.tip{color:#a6a6a6}p.host{color:#7d7d7d}p.code{color:#5c5c5c}.icon{color:#5f5f5f}}` +
      `</style></head><body><div class="card">` +
      `<svg class="icon" width="72" height="72" viewBox="0 0 24 24" fill="none" ` +
      `stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">` +
      `<path d="m3 3 18 18"/><path d="M5.6 5.7A7 7 0 0 0 9 19h8.5a4.5 4.5 0 0 0 2.5-.8"/>` +
      `<path d="M21.5 15.2a4.5 4.5 0 0 0-2.9-4.2A7 7 0 0 0 10 5.2"/>` +
      `</svg>` +
      `<h1>${title}</h1><p class="tip">${tip}</p><p class="host">${escapeHtml(host)}</p>` +
      `<a class="btn" href="${escapeHtml(url)}">${retry}</a>` +
      `<p class="code">ERROR ${code}</p>` +
      `</div></body></html>`
  }

  /** 白屏检测回调：重试开关只控制自动刷新；诊断覆盖层独立于开关；已接管错误页跳过（防误判+无需诊断） */
  private handleDetectedBlankScreen(event: BlankScreenDetectionEventInfo): void {
    console.info(`[TabWeb] 白屏检测触发: url=${event.url} blankRetryUrl=${this.blankRetryUrl} ` +
      `开关=${appSettings.blank_screen_retry}`)
    if (this.errorPageShown) {
      console.info('[TabWeb] 白屏检测忽略: 当前为已接管错误页（自带重试入口）')
      return
    }
    if (this.paintedSinceNav) {
      console.info('[TabWeb] 白屏检测忽略: 页面已有绘制内容（检测器误报）')
      return
    }
    if (appSettings.blank_screen_retry && event.url !== this.blankRetryUrl) {
      this.blankRetryUrl = event.url
      console.info('[TabWeb] 白屏首次检测: 自动刷新重试')
      toastUtil.showToast({ message: $r('app.string.blank_screen_retrying'), duration: 2000 })
      try {
        tabsVM.ensureController(this.tab).refresh()
      } catch (e) {
        console.error(`[TabWeb] 白屏自动重试失败: ${e}`)
      }
      return
    }
    // 重试后仍白屏（或已关闭自动重试）：弹分段连通性诊断覆盖层（浏览器→网络→网站）
    console.info('[TabWeb] 白屏重试仍无效或重试已关闭: 启动分段连通性诊断')
    this.startLoadDiagnosis()
  }

  /** 启动加载停滞看门狗：导航请求发起（onLoadIntercept 放行主框架）时武装，10s 内响应未到达（onPageBegin 未触发）判定导航悬挂，弹诊断覆盖层；响应到达（onPageBegin）、页面绘制出内容（首屏/主要内容/最大内容绘制）、用户点继续等待时取消——慢但在出内容的页面不弹诊断（已提交页面的白屏由内置白屏检测判定） */
  private startLoadStallWatchdog(): void {
    this.cancelLoadStallWatchdog()
    this.loadStallTimer = setTimeout((): void => {
      this.loadStallTimer = -1
      console.info(`[TabWeb] 加载停滞看门狗触发: url=${this.tab.url}`)
      this.startLoadDiagnosis()
    }, 10000)
  }

  private cancelLoadStallWatchdog(): void {
    if (this.loadStallTimer !== -1) {
      clearTimeout(this.loadStallTimer)
      this.loadStallTimer = -1
    }
  }

  /** 启动加载卡住分段诊断：弹覆盖层，段结果经回调渐进填充 */
  private startLoadDiagnosis(): void {
    if (this.diagVisible && this.diagUrl === this.tab.url) {
      return
    }
    this.diagUrl = this.tab.url
    console.info(`[TabWeb] 诊断覆盖层启动: url=${this.tab.url}`)
    this.diagHost = SiteSettingsViewModel.hostOf(this.tab.url)
    if (this.diagHost === '') {
      this.diagHost = this.tab.url
    }
    this.diagDevice = SegmentState.CHECKING
    this.diagNetwork = SegmentState.CHECKING
    this.diagSite = SegmentState.CHECKING
    this.diagDone = false
    this.diagVisible = true
    NetDiagnose.run(this.tab.url, (r: DiagnoseResult): void => {
      this.diagDevice = r.device
      this.diagNetwork = r.network
      this.diagSite = r.site
      this.diagDone = r.done
    }).catch((): void => {
      // 诊断异常兜底：标记完成，仅保留刷新入口
      this.diagDone = true
    })
  }

  /** 诊断覆盖层-刷新重试：关闭覆盖层并重载当前页 */
  private diagRetry(): void {
    this.diagVisible = false
    try {
      tabsVM.ensureController(this.tab).refresh()
    } catch (e) {
      console.error(`[TabWeb] 诊断覆盖层刷新失败: ${e}`)
    }
  }

  /** 诊断覆盖层-继续等待：仅关闭覆盖层回到页面（可能在慢加载），取消看门狗防覆盖层循环弹出 */
  private diagWait(): void {
    console.info(`[TabWeb] 诊断覆盖层继续等待: url=${this.tab.url}`)
    this.diagVisible = false
    this.cancelLoadStallWatchdog()
  }

  /** 页面绘制出内容（首屏/主要内容/最大内容绘制任一度量回调）：记录绘制证据（白屏检测结果此后不信任）；覆盖层展示中立即退场不再遮挡 */
  private handlePagePaint(metric: string): void {
    this.paintedSinceNav = true
    if (this.diagVisible) {
      console.info(`[TabWeb] 页面已绘制内容(${metric}): 诊断覆盖层退场 url=${this.tab.url}`)
      this.diagVisible = false
      this.cancelLoadStallWatchdog()
    }
  }

  /** 诊断覆盖层-设置网络：跳系统设置，失败 toast 兜底 */
  private diagOpenSettings(): void {
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility'
    }
    try {
      _QhState.Context.startAbility(want).catch((): void => {
        toastUtil.showToast({ message: $r('app.string.diag_settings_fail') })
      })
    } catch (e) {
      toastUtil.showToast({ message: $r('app.string.diag_settings_fail') })
    }
  }

  /** 诊断段/连线颜色：正常绿、失败红、检测中灰 */
  private diagStateColor(state: SegmentState): ResourceColor {
    if (state === SegmentState.OK) {
      return '#34C759'
    }
    if (state === SegmentState.FAIL) {
      return '#E84026'
    }
    return $r('sys.color.comp_background_tertiary')
  }

  /** 诊断结果文案：按断点/未完成分流 */
  private diagTip(): Resource {
    if (!this.diagDone) {
      return $r('app.string.diag_checking')
    }
    if (this.diagDevice === SegmentState.FAIL) {
      return $r('app.string.diag_device_fail')
    }
    if (this.diagNetwork === SegmentState.FAIL) {
      return $r('app.string.diag_net_fail')
    }
    if (this.diagSite === SegmentState.FAIL) {
      return $r('app.string.diag_site_fail')
    }
    return $r('app.string.diag_slow')
  }

  /** 取网页当前选中文本：优先内核缓存（跨帧准确、零往返），空则兜底 runJavaScript 读主帧+输入框选区 */
  private async fetchSelectionText(): Promise<string> {
    if (this.selTextCache !== '') {
      return this.selTextCache
    }
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

  /** 文本菜单：划词翻译（选中文本 → 引擎翻译 → 弹窗展示译文） */
  private onTextMenuTranslate(): void {
    this.fetchSelectionText()
      .then((text: string): void => {
        translateVM.translateSelection(text)
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
          UaUtils.onWebAttach(tabsVM.ensureController(this.tab))
          DnsUtils.onWebAttach()
          ProxyUtils.onWebAttach()
          AdvancedSecurityUtils.onWebAttach()
          ItpBypassUtils.onWebAttach()
          hostsVM.onWebAttach()
          // 会话崩溃恢复：一次性消费持久化历史栈（恢复前进/后退；普通重挂载无缓冲不干扰现历史）
          const savedState: Uint8Array | null = tabsVM.consumePendingWebState(this.tab.id)
          if (savedState !== null) {
            try {
              tabsVM.ensureController(this.tab).restoreWebState(savedState)
            } catch (e) {
              console.error(`[TabWeb] restoreWebState 失败: ${e}`)
            }
          }
          // 自定义错误页：先启用默认错误页功能，主框架加载失败才会触发 onOverrideErrorPage（API 20+，不启用回调不生效）
          tabsVM.ensureController(this.tab).setErrorPageEnabled(true)
          // 音频静音：Web 重挂时恢复该标签静音态（后台销毁重建后 setAudioMuted 状态丢失）
          if (this.tab.audioMuted) {
            try {
              tabsVM.ensureController(this.tab).setAudioMuted(true)
            } catch (e) {
              console.error(`[TabWeb] 恢复静音态失败: ${e}`)
            }
          }
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
        // 网页编码 fallback：老站 GBK/Big5 无 charset 声明时按站点策略解码（默认 UTF-8 内核行为）
        .defaultTextEncodingFormat(this.policy.textEncoding)
        .forceEnableZoom(appSettings.force_enable_zoom)
        .darkMode(appSettings.force_dark_web ? WebDarkMode.On : WebDarkMode.Auto)
        .forceDarkAccess(appSettings.force_dark_web)
        .webStandardFont(this.webFontFamily())
        .webSansSerifFont(this.webFontFamily())
        .webSerifFont(this.webFontFamily())
        .javaScriptOnDocumentStart(this.documentStartScripts())
        .javaScriptProxy({
          object: this.clipboardBridge,
          name: '__qhNative',
          methodList: ['clipboardRequest', 'passwordSubmit', 'inspectEvent', 'actionBarScroll',
            'actionBarTapToggle', 'gmRequest', 'sniffMedia', 'videoRequest', 'getInstalledExtIds'],
          controller: tabsVM.ensureController(this.tab)
        })
        .copyOptions(this.policy.clipboardMode === 'block' ? CopyOptions.None : CopyOptions.LocalDevice)
        .enableHapticFeedback(appSettings.web_vibration_enabled || appSettings.web_haptic_enabled)
        // 点击状态栏回到网页顶部（ArkWeb backToTop，系统特性，默认开启）
        .backToTop(appSettings.back_to_top)
        .enableAutoFill(appSettings.system_password_manager)
        .multiWindowAccess(true)
        .allowWindowOpenMethod(true)
        // B6：捏合缩放过程连续平滑缩放（默认关，内核松手才应用缩放会跳变）
        .pinchSmooth(true)
        // B6：边缘回弹（默认关=内核 NEVER；开=ALWAYS 橡皮筋回弹，新开标签生效）
        .overScrollMode(appSettings.web_overscroll_bounce ? OverScrollMode.ALWAYS : OverScrollMode.NEVER)
        // A3 无障碍：最小字号（网页 CSS 小字强制提升到该下限渲染，内核默认 8）
        .minFontSize(appSettings.web_min_font_size)
        // A3 无障碍：文本自动适配（窄屏密集小字自动放大 16-32px，内核默认开；关闭可修复被撑乱的排版）
        .textAutosizing(appSettings.web_text_autosizing)
        // 视频托管：内核级接管网页媒体（官方 enableNativeMediaPlayer 机制，全屏托管播放器播放）；
        // 待触发标志或已有托管会话时开启，其余时间交给内核自播
        .enableNativeMediaPlayer({
          enable: this.tab.pendingHostVideo || this.tab.hostedSession !== null,
          shouldOverlay: true
        })
        .onWindowNew((event: OnWindowNewEvent) => {
          this.handleWindowNew(event)
        })
        // JS 三大对话框（alert/confirm/prompt）：返回 true 应用接管，统一应用风格 + 可阻止本页更多弹窗
        .onAlert((event: OnAlertEvent): boolean => {
          return this.handleJsAlert(event)
        })
        .onConfirm((event: OnConfirmEvent): boolean => {
          return this.handleJsConfirm(event)
        })
        .onPrompt((event: OnPromptEvent): boolean => {
          return this.handleJsPrompt(event)
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
        // HTML5 视频全屏：网页请求全屏时隐藏应用栏+系统栏，横屏视频转横屏（退出回调恢复）
        .onFullScreenEnter((event: FullScreenEnterEvent) => {
          this.tab.videoFullScreen = true
          this.tab.videoExitHandler = event.handler
          VideoFullScreen.enter(event.videoWidth ?? 0, event.videoHeight ?? 0)
        })
        .onFullScreenExit(() => {
          this.tab.videoFullScreen = false
          this.tab.videoExitHandler = null
          VideoFullScreen.exit()
          // 手势调亮度过兜底恢复：退出网页全屏时恢复跟随系统亮度
          const win = _QhState.window
          if (win) {
            try {
              win.setWindowBrightness(-1)
                .catch((): void => {
                })
            } catch (e) {
              // 窗口异常时忽略
            }
          }
        })
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          // 源码视图：不应用站点策略——loadData 导航栈内同步 setCustomUserAgent
          // 会触发内核 NavigationController 重入断言（SIGTRAP 崩溃），直接放行
          if (this.tab.viewSourceHtml !== '') {
            return false
          }
          const reqUrl: string = event.data.getRequestUrl()
          // 商店桌面 UA 走域名级 setUserAgentForHosts（UaUtils.onWebAttach 注册）：
          // 导航栈内同步 setCustomUserAgent 同样触发内核重入断言（真机实测 SIGTRAP），
          // onLoadIntercept 内禁止任何实例级 UA 设置
          // 导航发起前用缓存策略提前应用，保证 UA 对本次主框架请求生效
          const p: SitePolicy | null =
            siteSettingsVM.cachedPolicy(SiteSettingsViewModel.hostOf(reqUrl))
          if (p !== null) {
            this.applyPolicy(p)
          }
          const blocked: boolean = this.interceptRedirect(event)
          // 加载停滞看门狗武装点：onPageBegin 对失败/悬挂导航不触发（ArkWeb 生命周期），
          // 改在导航请求发起点武装；仅主框架且放行的导航武装（被拦截的导航不会产生
          // onPageEnd，武装会误报；iframe 导航无独立 onPageBegin/End 同理不武装）
          if (!blocked) {
            try {
              if (event.data.isMainFrame()) {
                // 新主框架导航发起：复位已接管错误页标记与绘制证据（错误页内部 commit 不走本回调）
                this.errorPageShown = false
                this.errorPageShownUrl = ''
                this.paintedSinceNav = false
                this.startLoadStallWatchdog()
              }
            } catch (e) {
              // 主框架判定异常时跳过武装（内置白屏检测仍兜底）
            }
          }
          return blocked
        })
        // 网络日志数据源：轻量记录每个请求（仅字符串处理，无痕标签不记录），
        // 返回 null 按原方式加载（真机已验证该用法无副作用）；
        // 扩展资源请求（虚拟域/chrome-extension://）由 ExtensionResources 从沙箱目录服务
        .onInterceptRequest((event: OnInterceptRequestEvent) => {
          const reqUrl: string = event.request.getRequestUrl()
          if (ExtensionResources.isExtRequest(reqUrl)) {
            return ExtensionResources.respond(reqUrl, `${_QhState.Context.filesDir}/extensions`)
          }
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
          // 隐私报告（跟踪者视角）：无痕不记录（网站列表会暴露浏览历史）
          if (!this.tab.isIncognito) {
            trackerVM.recordBlocked(this.tab.url, urls)
              .catch((): void => {
              })
          }
          console.info(`[TabWeb] 广告拦截命中 ${urls.length} 条: ${urls[0]}`)
        })
        // 智能防跟踪拦截上报（仅 ITP 开启时触发）：隐私报告 ITP 段数据源，
        // 无痕不记录（网站列表会暴露浏览历史）；缓冲防抖落库，回调保持轻量
        .onIntelligentTrackingPreventionResult((details: IntelligentTrackingPreventionDetails) => {
          if (this.tab.isIncognito) {
            return
          }
          trackerVM.recordItpBlocked(details.host, details.trackerHost)
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          // 资源加载失败诊断日志（主框架/子资源均会回调）
          netLogVM.markError(this.tab.id, event.request.getRequestUrl())
          console.error(`[TabWeb] 资源加载失败 ${event.error.getErrorCode()}: ` +
            `${event.request.getRequestUrl()} ${event.error.getErrorInfo()}`)
        })
        // 主框架加载失败：返回应用风格错误页替代内核默认页（深浅色自适应 + 错误码文案 + 重试链接）；
        // 前提：onControllerAttached 已调 setErrorPageEnabled(true) 启用错误页功能，否则本回调不触发；
        // 返回值按官方示例传裸 HTML 字符串
        .onOverrideErrorPage((event: OnErrorReceiveEvent): string => {
          // 内核错误页接管，诊断覆盖层退场，取消加载停滞看门狗；
          // 标记已接管错误页：白屏检测跳过（错误页大留白易被采样误判）
          this.diagVisible = false
          this.cancelLoadStallWatchdog()
          this.errorPageShown = true
          this.errorPageShownUrl = event.request.getRequestUrl()
          const html: string = this.buildErrorPageHtml(event)
          console.info(`[TabWeb] onOverrideErrorPage 回调执行: code=${event.error.getErrorCode()} ` +
            `rawHtmlLen=${html.length}`)
          return html
        })
        // 白屏检测：导航后 5s 一次 17 点采样（用户交互后不检测，无误报路径）；
        // 检测常开：重试开关只控制自动刷新，诊断覆盖层独立
        .blankScreenDetectionConfig({
          enable: true,
          detectionTiming: [5]
        } as BlankScreenDetectionConfig)
        .onDetectedBlankScreen((event: BlankScreenDetectionEventInfo) => {
          this.handleDetectedBlankScreen(event)
        })
        // 页面绘制内容度量（首屏渲染完成 API23+ / 主要内容绘制 API12+ / 最大内容绘制 API12+）：
        // 内容画出来后诊断覆盖层立即退场不再遮挡——「内容出来了就别挡着」，
        // 修复慢加载页面元素已可见仍被诊断覆盖（本末倒置）
        .onFirstScreenPaint(() => {
          this.handlePagePaint('FirstScreenPaint')
        })
        .onFirstMeaningfulPaint(() => {
          this.handlePagePaint('FirstMeaningfulPaint')
        })
        .onLargestContentfulPaint(() => {
          this.handlePagePaint('LargestContentfulPaint')
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
        .onScreenCaptureRequest((event: OnScreenCaptureRequestEvent) => {
          this.handleScreenCaptureRequest(event)
        })
        .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent) => {
          if (appSettings.ignore_ssl_warning) {
            event.handler.handleConfirm()
          } else {
            event.handler.handleCancel()
          }
        })
        // HTTP Basic 认证：返回 true 由应用接管（自动登录或弹登录框），禁止内核默认弹窗
        .onHttpAuthRequest((event: OnHttpAuthRequestEvent): boolean => {
          this.handleHttpAuth(event)
          return true
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          // 导航离开时关闭可能残留的自定义菜单
          this.closeCtxMenu()
          // 视频托管：导航销毁旧页面媒体，释放旧托管会话（AVPlayer 等底层资源）
          if (this.tab.hostedSession !== null) {
            this.tab.hostedSession.release()
          }
          // 视频托管：每页注册内核媒体接管回调（内核创建网页媒体时回调，决定是否由应用接管）
          try {
            tabsVM.ensureController(this.tab).onCreateNativeMediaPlayer(
              (handler: webview.NativeMediaPlayerHandler,
                mediaInfo: webview.MediaInfo): webview.NativeMediaPlayerBridge | null => {
                return this.createHostedPlayer(handler, mediaInfo)
              })
          } catch (e) {
            // 页面异常态注册失败忽略
          }
          // HTTP 认证：进入新页面说明已通过认证，清空防死循环 guard
          this.authGuard.clear()
          // JS 弹窗：新页面解除「阻止此页更多弹窗」
          this.tab.jsDialogBlocked = false
          // 文本选区：新页面清空选中文本缓存
          this.selTextCache = ''
          // 白屏检测：导航到不同 URL 后重置自动重试 guard（同 URL 刷新流程内保持，防循环）
          if (event.url !== this.blankRetryUrl) {
            this.blankRetryUrl = ''
          }
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
          // 翻译：导航清翻译态（新页面需重新翻译）
          translateVM.clearTab(this.tab.id)
          this.detectSeq++
          this.tab.readerable = false
          // 色彩模式：新页面 theme-color 重新提取
          this.tab.themeColor = ''
          this.tab.themeColor2 = ''
          // 新导航开始，诊断覆盖层退场；响应已到达（onPageBegin 触发）取消看门狗——
          // 看门狗只守「响应未到达」的真悬挂，慢但在出内容的页面不再被 10s 误盖
          // （真机实测 hap.atomgit.com 慢加载误报）；已提交页面的白屏由内置白屏检测判定；
          // 已接管错误页自身的 onPageBegin 报原 URL，跳过复位（否则 +5s 白屏检测又盖错误页）
          this.diagVisible = false
          this.cancelLoadStallWatchdog()
          if (event.url !== this.errorPageShownUrl) {
            this.errorPageShown = false
          }
          // 新文档提交：绘制证据复位（本页绘制事件随后重新记录）
          this.paintedSinceNav = false
          browserVM.updateNavState(this.tab)
        })
        .onPageEnd((event: OnPageEndEvent) => {
          // 源码视图：仅做内容校验（初始 about:blank 竞态自愈），不写地址/历史/导航状态
          if (this.tab.viewSourceHtml !== '') {
            this.verifyViewSourceLoaded()
            return
          }
          // 会话恢复占位退场：真实页面已可见，撤下旧快照
          this.tab.showSnapshotPlaceholder = false
          // 页面加载完成，诊断覆盖层退场（覆盖慢页最终加载成功场景）；取消加载停滞看门狗
          this.diagVisible = false
          this.cancelLoadStallWatchdog()
          this.tab.url = event.url
          tabsVM.notifyTabInfoChanged(this.tab)
          // 页内导航 URL 已变：会话补保存（崩溃/重启恢复落在当前页而非旧地址）
          tabsVM.saveSessionDebounced()
          this.tab.progress = 100
          this.applyBackForwardCache()
          this.autofillPassword()
          this.injectUserScripts(event.url)
          this.detectReadability()
          this.detectThemeColor()
          // 翻译：页面语言命中「总是翻译」列表时自动翻译
          translateVM.autoTranslate(this.tab)
          browserVM.onPageEnded(this.tab, event.url)
          browserVM.updateNavState(this.tab)
          // 页面加载完成即补截快照：停留中的标签不切走也有最新快照可落盘（仅活动标签生效）
          tabsVM.captureTabSnapshot(this.tab)
        })
        // 导航提交精确事件（API 11）：同文档导航（hash 变化/pushState/replaceState/同页历史跳转）
        // 不触发 onPageBegin/End，此处同步 tab.url + 补会话保存——SPA 站点地址栏停留旧地址的修复
        .onNavigationEntryCommitted((event: LoadCommittedDetails) => {
          if (this.tab.viewSourceHtml !== '' || !event.isMainFrame) {
            return
          }
          if (event.isSameDocument && event.url !== '' && event.url !== this.tab.url) {
            this.tab.url = event.url
            tabsVM.notifyTabInfoChanged(this.tab)
            tabsVM.saveSessionDebounced()
            browserVM.updateNavState(this.tab)
          }
        })
        // 页面 favicon 回调：按 host 缓存（书签列表/桌面快捷方式展示用）
        .onFaviconReceived((event: OnFaviconReceivedEvent) => {
          console.info(`[TabWeb] onFaviconReceived url=${this.tab.url}`)
          faviconCache.saveFromPixelMap(FaviconCache.hostOf(this.tab.url), event.favicon)
        })
        // 页面 apple-touch-icon：内核直接报出高清图标 URL，下载入缓存（低清 favicon 被取代）
        .onTouchIconUrlReceived((event: OnTouchIconUrlReceivedEvent) => {
          faviconCache.saveTouchIconUrl(FaviconCache.hostOf(this.tab.url), event.url)
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.tab.progress = event.newProgress
          if (event.newProgress >= 100) {
            this.tab.showSnapshotPlaceholder = false
          }
        })
        .onTitleReceive((event: OnTitleReceiveEvent) => {
          // 源码文档无 <title>，保持标签标题"源码"不被空标题覆盖
          if (this.tab.viewSourceHtml !== '') {
            return
          }
          this.tab.title = event.title
          tabsVM.notifyTabInfoChanged(this.tab)
        })
        // 网页音频状态：播放/停止回写 TabInfo（标签角标展示）
        .onAudioStateChanged((event: OnAudioStateChangedEvent) => {
          this.tab.audioPlaying = event.playing
        })
        // 双指缩放百分比浮层：手势中实时显示，停 800ms 自动隐藏（newScale 即百分数）
        .onScaleChange((event: OnScaleChangeEvent) => {
          console.info(`[TabWeb] onScaleChange old=${event.oldScale} new=${event.newScale}`)
          this.handleScaleChange(event.newScale)
        })
        // 文档切换（旧文档不再显示、新文档即将显示）：复位页面级浮层（查找栏收起清高亮、缩放浮层隐藏）
        .onPageVisible((event: OnPageVisibleEvent) => {
          if (browserVM.showFindBar) {
            browserVM.closeFind()
          }
          if (browserVM.zoomPercent !== -1) {
            browserVM.hideZoomOverlay()
          }
        })
        // 键盘快捷键：Web 聚焦时先于内核拦截（命中组合返回 true 消费，其余透传网页）
        .onInterceptKeyEvent((e: KeyEvent): boolean => {
          return kbShortcutDispatch.handle(e)
        })
        // 控制台消息捕获（元素审查-调试页数据源），返回 false 保持默认输出行为
        .onConsole((event: OnConsoleEvent): boolean => {
          const m = event.message
          const lv = m.getMessageLevel()
          /* 临时诊断：扩展页（scheme 标签页）console Error/Warn 转发 hilog，
             定位 post-install 页卡加载（TabWeb 常规 console 只进 inspectorVM 不进 hilog） */
          if ((lv === MessageLevel.Error || lv === MessageLevel.Warn)
            && (this.tab.url.startsWith(EXT_SCHEME_PREFIX)
              || m.getSourceId().startsWith(EXT_SCHEME_PREFIX))) {
            console.warn(`[TabWeb ext console] ${m.getMessage().substring(0, 300)} @ ${m.getSourceId()}:${m.getLineNumber()}`)
          }
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
        // 文本选区变化：内核原生上报选中文本（含 iframe 内跨帧选区），缓存供菜单动作直取
        .onTextSelectionChange((selectionText: string) => {
          this.selTextCache = selectionText
        })
        .onDownloadStart((event: OnDownloadStartEvent) => {
          downloadVM.download(event.url, this.tab.url)
        })

      // 会话恢复占位：磁盘旧快照顶替加载中的网页（onPageEnd/进度 100 撤下；夜间蒙版等叠其上）
      if (this.tab.showSnapshotPlaceholder && this.tab.snapshot !== null) {
        Image(this.tab.snapshot)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.High)
          .draggable(false)
      }

      // 夜间模式：网页蒙版滤镜
      if (appSettings.night_mask_enabled) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(appSettings.maskColorHex())
          .opacity(appSettings.night_mask_opacity / 100)
          .hitTestBehavior(HitTestMode.None)
      }

      // 双指缩放百分比浮层
      if (browserVM.zoomPercent >= 0) {
        this.scaleOverlay()
      }

      // 网页元素长按/右键菜单（自定义接管）
      if (this.ctxMenuVisible) {
        this.ctxMenuOverlay()
      }

      // 看图模式：图片全屏查看
      if (this.imageViewerUrl !== '') {
        this.imageViewerOverlay()
      }

      // 加载卡住：分段连通性诊断覆盖层（浏览器→网络→网站）
      if (this.diagVisible) {
        this.diagOverlay()
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

  /**
   * 视频托管：内核媒体创建回调（onCreateNativeMediaPlayer）。
   * 仅接管「待触发」标签的 URL 直链视频（一次性消费触发标志）；MSE/blob 动态流与音频返回 null 交回内核自播。
   * 新视频创建时释放旧会话（托管跟随最新视频）；同 embedId 重复回调不重复接管。
   */
  private createHostedPlayer(handler: webview.NativeMediaPlayerHandler,
    mediaInfo: webview.MediaInfo): webview.NativeMediaPlayerBridge | null {
    if (mediaInfo.mediaType !== webview.MediaType.VIDEO || !this.tab.pendingHostVideo) {
      return null
    }
    if (this.tab.hostedSession !== null) {
      if (this.tab.hostedSession.embedId === mediaInfo.embedID) {
        return null
      }
      this.tab.hostedSession.release()
    }
    let src: string = ''
    for (const item of mediaInfo.mediaSrcList) {
      if (item.type === webview.SourceType.URL && item.source !== '') {
        src = item.source
        break
      }
    }
    if (src === '') {
      return null
    }
    const session: WebHostedPlayerSession = new WebHostedPlayerSession(src,
      (): void => {
        this.tab.hostedSession = null
      },
      (): void => {
        this.exitHostedPlayback()
      },
      handler, mediaInfo.embedID, mediaInfo.headers, mediaInfo.muted)
    this.tab.pendingHostVideo = false
    this.tab.hostedSession = session
    return session
  }

  /** 结束托管播放：刷新页面恢复网页内播放（托管媒体已释放，页面重建视频元素后内核自播） */
  private exitHostedPlayback(): void {
    this.tab.pendingHostVideo = false
    try {
      tabsVM.ensureController(this.tab).refresh()
    } catch (e) {
      // 刷新失败时保持现状，下次导航自然恢复
    }
  }

  /**
   * 双指缩放/快捷键缩放百分比浮层：缩放变化即显示，停 800ms 自动隐藏；
   * 加载中（重加载恢复缩放等）视为自动触发：纯数字、短时隐藏；否则手动触发：带步进按钮
   */
  private handleScaleChange(scale: number): void {
    if (scale <= 0) {
      return
    }
    const loading: boolean = this.tab.progress > 0 && this.tab.progress < 100
    this.tab.zoomPercent = scale
    browserVM.showZoomOverlay(Math.round(scale), !loading)
  }

  /**
   * 双指缩放百分比浮层（样式对齐视频手势提示：半透明黑底白字圆角）；
   * 手动触发带 −/+ 步进按钮（透明命中，空白区域透传网页触摸），自动触发纯数字
   */
  @Builder
  scaleOverlay() {
    Column() {
      if (browserVM.zoomManual) {
        Row({ space: 2 }) {
          Text('−')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              browserVM.zoomStep(-1)
            })
          Text(`${browserVM.zoomPercent}%`)
            .fontColor(Color.White)
            .fontSize(16)
            .constraintSize({ minWidth: 64 })
            .textAlign(TextAlign.Center)
          Text('+')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              browserVM.zoomStep(1)
            })
        }
        .padding({ left: 4, right: 4, top: 6, bottom: 6 })
        .backgroundColor('#80000000')
        .borderRadius(18)
      } else {
        Text(`${browserVM.zoomPercent}%`)
          .fontColor(Color.White)
          .fontSize(16)
          .padding({ left: 28, right: 28, top: 12, bottom: 12 })
          .backgroundColor('#80000000')
          .borderRadius(16)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(browserVM.zoomManual ? HitTestMode.Transparent : HitTestMode.None)
    .padding({ top: 36 })
  }

  /**
   * 加载卡住分段诊断覆盖层：浏览器→网络→网站三段链路（断点红/正常绿/检测中灰），
   * 结果文案 + 按钮（按断点显示 设置网络；继续等待 仅关覆盖层；刷新重试 关覆盖层并重载）
   */
  @Builder
  diagOverlay() {
    Column() {
      Row() {
        this.diagNode($r('sys.symbol.phone'), $r('app.string.diag_seg_device'), this.diagDevice)
        this.diagLink(this.diagDevice)
        this.diagNode($r('sys.symbol.wifi'), $r('app.string.diag_seg_network'), this.diagNetwork)
        this.diagLink(this.diagNetwork)
        this.diagNode($r('sys.symbol.website'), $r('app.string.diag_seg_site'), this.diagSite)
      }
      .alignItems(VerticalAlign.Bottom)

      Text($r('app.string.diag_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .margin({ top: 26 })

      Text(this.diagHost)
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '80%' })
        .margin({ top: 6 })

      Text(this.diagTip())
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .padding({ left: 32, right: 32 })
        .margin({ top: 14 })

      Row({ space: 12 }) {
        if (this.diagDone && (this.diagDevice === SegmentState.FAIL || this.diagNetwork === SegmentState.FAIL)) {
          Button($r('app.string.diag_btn_settings'))
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .borderRadius(22)
            .height(44)
            .padding({ left: 24, right: 24 })
            .onClick(() => {
              this.diagOpenSettings()
            })
        }
        Button($r('app.string.diag_btn_wait'))
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(22)
          .height(44)
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            this.diagWait()
          })
        Button($r('app.string.diag_btn_retry'))
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor('#0A59F7')
          .borderRadius(22)
          .height(44)
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            this.diagRetry()
          })
      }
      .margin({ top: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 诊断链路节点：状态色圆底 + 图标（检测中转圈）+ 标签 */
  @Builder
  diagNode(icon: Resource, label: Resource, state: SegmentState) {
    Column({ space: 6 }) {
      Stack() {
        Circle({ width: 52, height: 52 })
          .fill(this.diagStateColor(state))
        if (state === SegmentState.CHECKING) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color($r('sys.color.font_secondary'))
        } else {
          SymbolGlyph(icon)
            .fontSize(26)
            .fontColor([Color.White])
        }
      }
      Text(label)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
    }
  }

  /** 诊断链路连线：颜色跟随上游段状态，底边距对齐节点圆心 */
  @Builder
  diagLink(state: SegmentState) {
    Row()
      .width(30)
      .height(3)
      .borderRadius(1.5)
      .backgroundColor(this.diagStateColor(state))
      .margin({ left: 6, right: 6, bottom: 48 })
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
