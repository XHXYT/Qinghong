import { connection } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { tabsVM, TabInfo } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { downloadVM } from '../../viewmodel/DownloadViewModel';
import { appSettings } from '../../common/entity/SettingsModel';
import { toastUtil } from '../../common/utils/ToastUtils';
import { ResourceUtils } from '../../common/utils/ResourceUtil';
import { UaUtils } from '../../common/utils/UaUtils';
import { AdBlockEngine, adBlockEngine } from '../../common/utils/AdBlockEngine';
import { adBlockStore } from '../../common/utils/AdBlockStore';
import { WebScripts } from '../../common/utils/WebScripts';
import { SitePolicy, SiteSettingsViewModel, siteSettingsVM } from '../../viewmodel/SiteSettingsViewModel';

/**
 * 剪贴板 JS 代理对象（window.__qhNative）：
 * 网页 navigator.clipboard 文本读写转发原生按站点策略处理
 */
class ClipboardBridge {
  private readonly handler: (action: string, cbId: number, text: string) => void

  constructor(handler: (action: string, cbId: number, text: string) => void) {
    this.handler = handler
  }

  clipboardRequest(action: string, cbId: number, text: string): void {
    this.handler(action, cbId, text)
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

  /** BFCache 开关已应用状态（null=未应用；避免重复 setBackForwardCacheOptions） */
  private appliedBfcOn: boolean | null = null
  /** 重定向询问放行后的重导航地址（避免二次询问） */
  private pendingRedirectUrl: string = ''
  /** 网络状态监听（WIFI 切换时刷新图片开关） */
  private netConn: connection.NetConnection | null = null
  /** 剪贴板 JS 代理（window.__qhNative）：网页剪贴板文本读写转发原生策略处理 */
  private clipboardBridge: ClipboardBridge = new ClipboardBridge((action: string, cbId: number, text: string): void => {
    this.handleClipboardRequest(action, cbId, text)
  })

  aboutToAppear(): void {
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
    return this.policy.adBlock === 'app' ? appSettings.ad_block_enabled : this.policy.adBlock === 'on'
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

  /** 文档加载前注入脚本：隐私脚本 + 剪贴板接管 + 振动禁用（全局关闭时） */
  private documentStartScripts(): Array<ScriptItem> {
    const scripts: Array<ScriptItem> = WebScripts.privacyScripts(this.adBlockOn())
    scripts.push(WebScripts.clipboardScript())
    if (!appSettings.web_vibration_enabled) {
      scripts.push(WebScripts.vibrationBlockScript())
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
    const tab: TabInfo | null = tabsVM.newTab('', this.tab.isIncognito, false)
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
   * 广告拦截：命中规则返回空响应并累计统计，否则放行（null = 默认加载）
   */
  private interceptRequest(event: OnInterceptRequestEvent): WebResourceResponse | null {
    try {
      // 主框架请求放行（拦截会导致页面无法打开）
      if (event.request.isMainFrame()) {
        return null
      }
      const url: string = event.request.getRequestUrl()
      if (!adBlockEngine.shouldBlock(url, this.adBlockOn())) {
        return null
      }
      // 命中拦截规则：返回空响应并累计统计（按资源类型预估流量）
      adBlockStore.add(1, AdBlockEngine.estimateBytes(url))
      const response: WebResourceResponse = new WebResourceResponse()
      response.setResponseData('')
      response.setResponseEncoding('utf-8')
      response.setResponseMimeType('text/plain')
      response.setResponseCode(200)
      response.setReasonMessage('OK')
      return response
    } catch (e) {
      console.error(`[TabWeb] onInterceptRequest 失败: ${e}`)
      return null
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
            this.grantWebLocation(event)
          }
        },
        {
          value: $r('app.string.deny'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            event.geolocation.invoke(event.origin, false, false)
          }
        }
      ]
    }, 'geoPermission')
  }

  /**
   * 授权网页定位：先申请系统位置权限（精确+模糊任一通过即可），再响应网页请求
   */
  private grantWebLocation(event: OnGeolocationShowEvent): void {
    const atManager = abilityAccessCtrl.createAtManager()
    const perms: Array<Permissions> = ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION']
    atManager.requestPermissionsFromUser(getContext(this), perms)
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
    atManager.requestPermissionsFromUser(getContext(this), perms)
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
      const data: pasteboard.PasteData = pasteboard.createPlainTextData(text)
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
    atManager.requestPermissionsFromUser(getContext(this), perms)
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

  build() {
    Stack() {
      Web({ src: this.tab.url, controller: tabsVM.ensureController(this.tab), incognitoMode: this.tab.isIncognito })
        .onControllerAttached(() => {
          UaUtils.applyTo(tabsVM.ensureController(this.tab))
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
          methodList: ['clipboardRequest'],
          controller: tabsVM.ensureController(this.tab)
        })
        .copyOptions(this.policy.clipboardMode === 'block' ? CopyOptions.None : CopyOptions.LocalDevice)
        .enableHapticFeedback(appSettings.web_vibration_enabled || appSettings.web_haptic_enabled)
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
          // 导航发起前用缓存策略提前应用，保证 UA 对本次主框架请求生效
          const p: SitePolicy | null =
            siteSettingsVM.cachedPolicy(SiteSettingsViewModel.hostOf(event.data.getRequestUrl()))
          if (p !== null) {
            this.applyPolicy(p)
          }
          return this.interceptRedirect(event)
        })
        .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => {
          return this.interceptRequest(event)
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
          this.applySafeBrowsing()
          this.refreshPolicy(event.url)
          browserVM.updateNavState(this.tab)
        })
        .onPageEnd((event: OnPageEndEvent) => {
          this.tab.url = event.url
          this.tab.progress = 100
          this.applyBackForwardCache()
          browserVM.onPageEnded(this.tab, event.url)
          browserVM.updateNavState(this.tab)
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.tab.progress = event.newProgress
        })
        .onTitleReceive((event: OnTitleReceiveEvent) => {
          this.tab.title = event.title
        })
        .onSearchResultReceive((event: OnSearchResultReceiveEvent) => {
          browserVM.onFindResult(event.activeMatchOrdinal, event.numberOfMatches, event.isDoneCounting)
        })
        .onDownloadStart((event: OnDownloadStartEvent) => {
          downloadVM.download(event.url)
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
    }
    .width('100%')
    .height('100%')
    .visibility(this.tab.id === tabsVM.activeTabId ? Visibility.Visible : Visibility.None)
  }
}
