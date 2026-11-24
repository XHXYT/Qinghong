import { AbilityConstant, common, Configuration, EnvironmentCallback, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AvoidanceManager, SmartAvoidance } from '../common/utils/ui/AvoidManager';
import { QhState, _QhState } from './AppState';
import { toastUtil } from '../common/utils/ui/ToastUtils';
import { preferenceUtil } from '../common/utils/persistence/PreferenceUtil';
import { kvDbUtil } from '../common/utils/storage/KVdbUtil';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { syncVM } from '../viewmodel/SyncViewModel';
import { ColorUtils } from '../common/utils/ui/ColorUtils';
import { ResourceUtils } from '../common/utils/app/ResourceUtil';
import { SettingsUtils } from '../common/utils/app/SettingsUtils';
import { FontStore } from '../common/utils/ui/FontStore';
import { adBlockEngine } from '../common/utils/adblock/AdBlockEngine';
import { adBlockStore } from '../common/utils/adblock/AdBlockStore';
import { adBlockSubsStore } from '../common/utils/adblock/AdBlockSubs';
import { animation } from '../common/utils/ui/AnimationUtil';
import { AppConstants } from '../common/constants/AppConstants';
import { createLogger } from '../common/utils/app/Logger';
import { siteSettingsVM } from '../viewmodel/SiteSettingsViewModel';
import { hostsVM } from '../viewmodel/HostsViewModel';
import { DnsUtils } from '../common/utils/network/DnsUtils';
import { UaUtils } from '../common/utils/web/UaUtils';
import { tabsVM } from '../viewmodel/TabsViewModel';
import { scriptVM } from '../viewmodel/ScriptViewModel';
import { extensionVM } from '../viewmodel/ExtensionViewModel';
import { ShortcutViewModel } from '../viewmodel/ShortcutViewModel';
import { DataClearer } from '../common/utils/app/DataClearer';
import { StatusBarSync } from '../common/utils/ui/StatusBarSync';
import { EXT_SCHEME } from '../common/utils/extension/ExtensionResources';
import { webview } from '@kit.ArkWeb';
import { TextReader, WindowManager } from '@kit.SpeechKit';

const logger = createLogger('EntryAbility')

export default class EntryAbility extends UIAbility {
  private avoidManager: AvoidanceManager | undefined = undefined;
  /** 后台已暂停网页定时器标记（仅恢复本应用主动暂停的状态） */
  private webTimersPaused: boolean = false;
  /** 系统环境（内存压力）监听 ID，onDestroy 注销用 */
  private envCallbackId: number = -1;
  private envCallback: EnvironmentCallback = {
    onConfigurationUpdated: (_config: Configuration): void => {
    },
    onMemoryLevel: (level: AbilityConstant.MemoryLevel): void => {
      this.trimWebMemory(level)
    }
  }
  private avoidListener: (avoidance: SmartAvoidance) => void = (newAvoidance) => {
    QhState.bottomRectHeight = newAvoidance.bottom
    QhState.topRectHeight = newAvoidance.top
    QhState.leftAvoidWidth = newAvoidance.left
    QhState.rightAvoidWidth = newAvoidance.right
  }

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    // 冷启动：记录外部拉起的链接，Index 恢复会话后消费。
    // 必须在首个 await 之前执行：onCreate 为 async 且生命周期不等待其完成，
    // await 期间 onWindowStageCreate/loadContent 会先行触发 Index 注册处理器并
    // 进入 restoreSession；届时再捕获会把 URL 交给处理器在恢复中途建标签，
    // 随后 restoreSession 的 this.tabs = restored 会把该标签整体抹掉（外链丢失）
    this.captureExternalUrl(want)
    // 扩展自定义协议注册：必须在 Web 引擎初始化前（首个 Web 组件创建前）执行
    try {
      webview.WebviewController.customizeSchemes([{
        schemeName: EXT_SCHEME,
        isSupportCORS: true,
        isSupportFetch: true,
        isStandard: true,
        isSecure: true,
        isCspBypassing: true
      }]);
      logger.info('Init', `customizeSchemes ${EXT_SCHEME} registered`);
    } catch (error) {
      logger.error('Init', `customizeSchemes failed: ${error}`);
    }
    // 初始化与应用环境：暴露完成信号（Index 等待后再恢复会话，防安装后首启竞态）
    const initTask: Promise<void> = this.initAppEnvironment();
    QhState.appInitialized = initTask;
    try {
      await initTask;
      logger.info('Init', 'App environment initialized successfully.');
    } catch (error) {
      logger.error(`Init`, `Initialization failed, ${error}`);
    }
    // 旧版散放在 files 根目录的快捷方式图标迁入专门文件夹
    ShortcutViewModel.migrateLegacyIcons();
    ShortcutViewModel.cleanOrphanIcons();
    // 订阅系统内存压力（联动 ArkWeb trimMemory 按压释放缓存）
    try {
      this.envCallbackId = this.context.getApplicationContext().on('environment', this.envCallback)
    } catch (error) {
      logger.error('Init', `register environment callback failed: ${error}`)
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 热启动：直接交给已注册的处理器打开
    this.captureExternalUrl(want)
  }

  /**
   * 捕获外部以浏览器身份拉起本应用时传入的 http/https 链接
   * （含桌面快捷方式以 Want 参数 url 拉起的场景）
   */
  private captureExternalUrl(want: Want): void {
    let uri = want.uri ?? ''
    if (uri === '') {
      const params: Record<string, Object> | undefined = want.parameters
      const v: Object | undefined = params === undefined ? undefined : params['url']
      if (v !== undefined && typeof v === 'string') {
        uri = v
      }
    }
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      logger.info('WantUri', `外部拉起链接: ${uri}`)
      if (QhState.externalUrlHandler) {
        QhState.externalUrlHandler(uri)
      } else {
        QhState.pendingOpenUrl = uri
      }
    }
  }

  onDestroy(): void {
    if (this.envCallbackId !== -1) {
      this.context.getApplicationContext().off('environment', this.envCallbackId)
    }
    syncVM.destroy()
    // 退出时清除数据（按「退出时清除数据」设置项执行）
    try {
      DataClearer.clearExitData()
    } catch (error) {
      logger.error('Lifecycle', `退出清理失败, ${error}`)
    }
    logger.info('Lifecycle', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.info('Lifecycle', 'EntryAbility onWindowStageCreate');
    // 朗读控件（TextReader）前置：必须在 init 前设置窗口管理器，否则朗读控件初始化失败
    try {
      WindowManager.setWindowStage(windowStage);
    } catch (error) {
      logger.error('Lifecycle', `WindowManager.setWindowStage failed: ${error}`);
    }
    // loadContent 内部（Index 构建/恢复标签的首个 Web attach）早于 loadContent 回调，
    // 断点不预置时 UA 会按 widthBp=0 的手机形态错误下发；先按窗口物理宽预置先导值
    this.preinitWindowWidthBp(windowStage)
    windowStage.loadContent('pages/Index', async (err) => {
      if (err.code) {
        logger.error(`WindowStage`, `Failed to load the content., ${err}`)
        return;
      }
      try {
        const data = await windowStage.getMainWindow()
        // 初始化UI上下文
        _QhState.UIContext = data.getUIContext()
        // 初始化通知工具
        toastUtil.initContext(_QhState.UIContext, this.context)
        // 注册沙箱内自定义字体（依赖 UIContext）
        FontStore.registerAll()
        // 应用第三方 Cookie 开关（内核不持久化，每次启动需重设）
        try {
          webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(appSettings.third_party_cookie)
        } catch (error) {
          logger.error('Init', `putAcceptThirdPartyCookieEnabled failed: ${error}`)
        }
      // 初始化广告拦截引擎与统计（规则装载到 ArkWeb 原生 AdsBlock 引擎）
      adBlockEngine.init()
      adBlockStore.load()
      // 用户脚本列表预载（Web 组件创建时需要生成 document-start 注入项）
      scriptVM.loadAll().then((): void => {
      })
      // 扩展列表预载（content_scripts 的 document-start 注入项依赖）
      extensionVM.loadAll().then((): void => {
      })
      // 订阅规则文件较大，延迟到主页首帧渲染后再合并装载；
      // 规则内容哈希未变化时跳过，利用内核持久化避免重复编译解析
      setTimeout((): void => {
        adBlockSubsStore.load().then((): void => {
          adBlockEngine.syncToWebEngine()
          if (adBlockSubsStore.isAutoUpdateDue()) {
            // 更新成功后引擎经 onRulesChanged 回调自动重新装载
            adBlockSubsStore.updateAll(true)
          }
        })
      }, 100)
        // 初始化动画工具
        animation.init(_QhState.UIContext)
        // 初始化窗口相关
        this.intRectWindow(windowStage, _QhState.UIContext)
      } catch (error) {
        logger.error(`WindowStage`, `Failed to get the Main Window, ${error}`)
      }
      logger.info('WindowStage', 'Succeeded in loading the content.');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 深浅色切换：还原态状态栏图标色需跟随刷新（色彩模式覆盖态不受影响）
    StatusBarSync.sync()
  }

  onWindowStageWillDestroy(windowStage: window.WindowStage): void {
    if (this.avoidManager) {
      this.avoidManager.offChangeListener(this.avoidListener);
      this.avoidManager.destroy();
      this.avoidManager = undefined;
    }
    logger.info('Lifecycle', 'EntryAbility onWindowStageWillDestroy');
  }

  onWindowStageDestroy(): void {
    logger.info('Lifecycle', 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    logger.info('Lifecycle', 'EntryAbility onForeground');
    // 恢复被后台暂停的网页 JS 定时器
    if (this.webTimersPaused) {
      this.webTimersPaused = false
      try {
        webview.WebviewController.resumeAllTimers()
      } catch (error) {
        logger.error('Lifecycle', `resumeAllTimers failed: ${error}`)
      }
    }
  }

  onBackground(): void {
    logger.info('Lifecycle', 'EntryAbility onBackground');
    // 退后台立即冲刷会话（含浏览历史栈）：进程被杀/崩溃后恢复最新状态
    tabsVM.flushSession();
    // 后台暂停全部网页 JS 定时器（省电，回前台恢复）
    if (appSettings.pause_web_timers && !this.webTimersPaused) {
      this.webTimersPaused = true
      try {
        webview.WebviewController.pauseAllTimers()
      } catch (error) {
        logger.error('Lifecycle', `pauseAllTimers failed, ${error}`)
      }
    }
  }

  /**
   * 系统内存压力联动：按压力等级让 ArkWeb 内核释放缓存（static，作用于全部 Web 实例）
   * LOW → MODERATE 裁剪（释放低代价缓存）；CRITICAL → CRITICAL 裁剪（释放全部可释放内存）
   */
  private trimWebMemory(level: AbilityConstant.MemoryLevel): void {
    try {
      if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
        webview.WebviewController.trimMemoryByPressureLevel(webview.PressureLevel.MEMORY_PRESSURE_LEVEL_MODERATE)
        logger.info('Memory', '系统内存 LOW，ArkWeb 执行 MODERATE 裁剪')
      } else if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
        webview.WebviewController.trimMemoryByPressureLevel(webview.PressureLevel.MEMORY_PRESSURE_LEVEL_CRITICAL)
        logger.info('Memory', '系统内存 CRITICAL，ArkWeb 执行 CRITICAL 裁剪')
      }
    } catch (error) {
      logger.error('Memory', `trimMemoryByPressureLevel failed, ${error}`)
    }
  }

  // --- 核心初始化 ---

  /**
   * 初始化应用基础环境（首选项、KV、设置加载、颜色模式）
   */
  private async initAppEnvironment(): Promise<void> {
    // 初始化上下文
    _QhState.Context = this.context
    // 初始化首选项
    await preferenceUtil.init(this.context, AppConstants.PREFERENCE_FILE);
    // 初始化KV数据库
    await kvDbUtil.initKVManager(this.context, AppConstants.KV_STORE_ID)
    // 加载设置数据
    await appSettings.load()
    await UISettings.load()
    // 预加载站点无痕覆盖缓存（Web 创建期过滤用，失败不阻塞启动）
    siteSettingsVM.preloadIncognitoCache()
    // 预热域名级 UA 映射（站点 UA 覆盖冷启动即注册，首次导航即生效）
    siteSettingsVM.syncHostUaMap()
    // 启用前进后退缓存框架（默认关闭；生效范围由各标签按站点策略配置 size=0/10）
    try {
      webview.WebviewController.enableBackForwardCache(new webview.BackForwardCacheSupportedFeatures())
    } catch (e) {
      logger.error('Lifecycle', `enableBackForwardCache 失败: ${e}`)
    }
    // DNS 优化（DoH）与预解析加速内核配置
    DnsUtils.applyAll()
    // Hosts 域名 IP 指定同步内核（冷启动即生效）
    hostsVM.syncToWeb()
    // 加载 WebDAV 同步配置
    await syncVM.loadConfig()
    // 初始化颜色工具
    ColorUtils.init(this.context)
    // 初始化资源工具
    ResourceUtils.init(this.context)
    // 设置深浅色模式
    SettingsUtils.setColorMode()
    // 应用语言偏好
    SettingsUtils.applyLanguage()
  }

  // --- 窗口与UI管理 ---

  /**
   * 初始化窗口（全屏、避让、断点、监听）
   */
  private async intRectWindow(windowStage: window.WindowStage, UIContext: UIContext): Promise<void> {
    try {
      const windowClass: window.Window = windowStage.getMainWindowSync();

      // 设置窗口全屏
      windowClass.setWindowLayoutFullScreen(true).then(() => {
        logger.info('WindowRect', 'Succeeded in setting the window layout to full-screen mode.');
      }).catch((err: BusinessError) => {
        logger.error(`WindowRect`, `Failed to set the window layout to full-screen mode., ${err}`)
      });

      // 获取布局避让遮挡的区域
      this.avoidManager = new AvoidanceManager(windowClass, UIContext);
      await this.avoidManager.init();
      // 注册监听器，当避让值变化时，更新UI状态
      this.avoidManager.onChangeListener(this.avoidListener);
      logger.info('WindowRect', 'Avoid manager initialized and listener registered.');

      // 初始化窗口尺寸与断点
      this.initWindowDimensions(windowClass, UIContext)
      // 应用屏幕方向设置
      SettingsUtils.applyOrientation();

      // 注册窗口状态监听器
      this.registerWindowListeners(windowClass, UIContext);

    } catch (error) {
      logger.error(`WindowChange`, `#intRectWindow Failed to getMainWindowSync., ${error}`)
    }
  }

  /**
   * 初始化窗口尺寸与断点
   */
  private initWindowDimensions(windowClass: window.Window, UIContext: UIContext): void {
    try {
      const properties = windowClass.getWindowProperties()
      const rect = properties.windowRect
      const WindowHeight = UIContext.px2vp(rect.height)
      const WindowWidth = UIContext.px2vp(rect.width)

      _QhState.window = windowClass;
      _QhState.windowWidth_px = rect.width;
      _QhState.windowHeight_px = rect.height;
      QhState.widthBp = UIContext.getWindowWidthBreakpoint()
      QhState.windowHeight = WindowHeight
      QhState.windowWidth = WindowWidth
      // 断点初始化后检测形态变化：首次 Web attach 可能早于本函数（loadContent 先于回调），
      // 此时 UA 已按 widthBp=0 的手机形态设置，需在此重应用为宽屏形态
      this.reapplyUaIfFormChanged()
      // 窗口就绪后再同步一次状态栏图标色：主页背景明暗重估可能早于此处（_QhState.window 未就绪时 sync 空转）
      StatusBarSync.sync()
      logger.info('WindowRect', `窗口高度：${rect.height} px 宽度：${rect.width} px`)
    } catch (error) {
      logger.error(`WindowDimensions`, `Failed to getWindowProperties., ${error}`)
    }
  }

  /**
   * loadContent 前预置窗口宽度断点（窗口物理宽 / 屏幕密度 → vp，按 WidthBreakpoint 阈值折算）：
   * 恢复标签的首个 Web attach 发生在 loadContent 内部、早于 initWindowDimensions，
   * 断点不预置时 syncAppUa 会按 widthBp=0 的手机形态把移动 UA 设为应用级 UA（竞态）；
   * 本函数提供先导值，initWindowDimensions 随后以 getWindowWidthBreakpoint() 权威值覆盖
   */
  private preinitWindowWidthBp(windowStage: window.WindowStage): void {
    try {
      const win: window.Window = windowStage.getMainWindowSync()
      const rect: window.Rect = win.getWindowProperties().windowRect
      const d: display.Display = display.getDefaultDisplaySync()
      if (d.densityPixels <= 0) {
        return
      }
      const widthVp: number = rect.width / d.densityPixels
      let bp: number = 1
      if (widthVp >= 1440) {
        bp = 4
      } else if (widthVp >= 840) {
        bp = 3
      } else if (widthVp >= 600) {
        bp = 2
      } else if (widthVp < 320) {
        bp = 0
      }
      QhState.widthBp = bp
      _QhState.windowWidth_px = rect.width
      _QhState.windowHeight_px = rect.height
      logger.info('WindowRect', `预置宽度断点: ${bp}（${Math.round(widthVp)}vp）`)
    } catch (error) {
      logger.error(`WindowDimensions`, `预置宽度断点失败., ${error}`)
    }
  }

  /**
   * 注册窗口大小与模式变化监听
   */
  private registerWindowListeners(windowClass: window.Window, UIContext: UIContext): void {
    // 监听窗口大小变化
    windowClass.on('windowSizeChange', (data) => {
      const WindowWidth = UIContext.px2vp(data.width)!
      const WindowHeight = UIContext.px2vp(data.height)!

      QhState.windowHeight = WindowHeight
      QhState.windowWidth = WindowWidth
      _QhState.windowWidth_px = data.width;
      _QhState.windowHeight_px = data.height;

      this.onWidthBpChange(UIContext)
      this.onHeightBpChange(WindowHeight, WindowWidth)
      // 小窗/分屏进出全屏形态：状态栏图标色重新计算
      StatusBarSync.sync()
    });

    // 窗口模式状态监听
    try {
      windowClass.on('freeWindowModeChange', (data) => {
        QhState.windowMode = data
        this.reapplyUaIfFormChanged()
        // 自由窗口模式不覆盖状态栏：图标色还原默认
        StatusBarSync.sync()
        logger.debug(`WindowMode 当前窗口状态：${QhState.windowMode}`)
      });
    } catch (exception) {
      logger.error(`Failed to enable the listener for free window mode changes. Cause: ${JSON.stringify(exception)}`);
    }
  }

  /** 上一次是否处于宽屏形态（跨档变化时重应用 UA） */
  private lastWideForm: boolean = false

  /** 宽屏形态跨档变化时重应用 UA（Web 未附加前跳过，由 onWebAttach 首次同步兜底） */
  private reapplyUaIfFormChanged(): void {
    const wide: boolean = UaUtils.wideForm()
    if (wide !== this.lastWideForm) {
      this.lastWideForm = wide
      logger.info('WindowRect', `设备形态变化：wideForm=${wide}，重应用 UA`)
      if (UaUtils.defaultUa !== '') {
        UaUtils.applyToAll()
      }
    }
  }

  private onWidthBpChange(UIContext: UIContext): void {
    QhState.widthBp = UIContext.getWindowWidthBreakpoint();
    this.reapplyUaIfFormChanged()
  }

  private onHeightBpChange(WindowHeight: number, WindowWidth: number): void {
    let heightBp = 0
    const ratio = WindowHeight / WindowWidth
    if (ratio < 0.79) {
      heightBp = 0
    } else if (ratio < 1.2) {
      heightBp = 1
    } else {
      heightBp = 2
    }
    QhState.heightBp = heightBp
  }
}
