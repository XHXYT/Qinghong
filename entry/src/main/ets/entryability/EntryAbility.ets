import { AbilityConstant, common, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AvoidanceManager, SmartAvoidance } from '../common/utils/AvoidManager';
import { QhState, _QhState } from './AppState';
import { toastUtil } from '../common/utils/ToastUtils';
import { preferenceUtil } from '../common/utils/persistence/PreferenceUtil';
import { kvDbUtil } from '../common/utils/KVdbUtil';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { syncVM } from '../viewmodel/SyncViewModel';
import { ColorUtils } from '../common/utils/ColorUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { SettingsUtils } from '../common/utils/SettingsUtils';
import { FontStore } from '../common/utils/FontStore';
import { adBlockEngine } from '../common/utils/AdBlockEngine';
import { adBlockStore } from '../common/utils/AdBlockStore';
import { adBlockSubsStore } from '../common/utils/AdBlockSubs';
import { animation } from '../common/utils/AnimationUtil';
import { AppConstants } from '../common/constants/AppConstants';
import { createLogger } from '../common/utils/Logger';
import { siteSettingsVM } from '../viewmodel/SiteSettingsViewModel';
import { webview } from '@kit.ArkWeb';

const logger = createLogger('EntryAbility')

export default class EntryAbility extends UIAbility {
  private avoidManager: AvoidanceManager | undefined = undefined;
  private avoidListener: (avoidance: SmartAvoidance) => void = (newAvoidance) => {
    QhState.bottomRectHeight = newAvoidance.bottom
    QhState.topRectHeight = newAvoidance.top
    QhState.leftAvoidWidth = newAvoidance.left
    QhState.rightAvoidWidth = newAvoidance.right
  }

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      await this.initAppEnvironment();
      logger.info('Init', 'App environment initialized successfully.');
    } catch (error) {
      logger.error(`Init`, `Initialization failed, ${error}`);
    }
    // 冷启动：记录外部拉起的链接，Index 恢复会话后消费
    this.captureExternalUrl(want)
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 热启动：直接交给已注册的处理器打开
    this.captureExternalUrl(want)
  }

  /**
   * 捕获外部以浏览器身份拉起本应用时传入的 http/https 链接
   */
  private captureExternalUrl(want: Want): void {
    const uri = want.uri ?? ''
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
    syncVM.destroy()
    logger.info('Lifecycle', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.info('Lifecycle', 'EntryAbility onWindowStageCreate');
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
      // 初始化广告拦截引擎与统计（规则装载到 ArkWeb 原生 AdsBlock 引擎）
      adBlockEngine.init()
      adBlockStore.load()
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
  }

  onBackground(): void {
    logger.info('Lifecycle', 'EntryAbility onBackground');
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
    // 启用前进后退缓存框架（默认关闭；生效范围由各标签按站点策略配置 size=0/10）
    try {
      webview.WebviewController.enableBackForwardCache(new webview.BackForwardCacheSupportedFeatures())
    } catch (e) {
      logger.error('Lifecycle', `enableBackForwardCache 失败: ${e}`)
    }
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
      logger.info('WindowRect', `窗口高度：${rect.height} px 宽度：${rect.width} px`)
    } catch (error) {
      logger.error(`WindowDimensions`, `Failed to getWindowProperties., ${error}`)
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
    });

    // 窗口模式状态监听
    try {
      windowClass.on('freeWindowModeChange', (data) => {
        QhState.windowMode = data
        logger.debug(`WindowMode 当前窗口状态：${QhState.windowMode}`)
      });
    } catch (exception) {
      logger.error(`Failed to enable the listener for free window mode changes. Cause: ${JSON.stringify(exception)}`);
    }
  }

  private onWidthBpChange(UIContext: UIContext): void {
    QhState.widthBp = UIContext.getWindowWidthBreakpoint();
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
