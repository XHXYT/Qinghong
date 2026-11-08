import { common } from "@kit.AbilityKit"
import { window } from "@kit.ArkUI"
import { createLogger } from "../common/utils/app/Logger"

const logger = createLogger('QhState')


@ObservedV2
export class _QhState {

  public static appVersion: string = '1.0.0'

  // 窗口对象
  public static UIContext: UIContext
  public static Context: common.UIAbilityContext
  public static window: window.Window;

  /** 外部（http/https 链接）拉起待打开的 URL，冷启动时由 Index 消费 */
  public pendingOpenUrl: string = ''
  /** 外部链接处理器（Index 注册，热启动 onNewWant 时消费） */
  public externalUrlHandler: ((url: string) => void) | null = null
  /** @description 窗口宽度 -px */
  public static windowWidth_px: number;
  /** @description 窗口高度 -px */
  public static windowHeight_px: number;
  /** @description 导航栏避让高度 */
  @Trace bottomRectHeight: number = 0
  /** @description 状态栏避让高度 */
  @Trace topRectHeight: number = 0
  /** @description 左侧避让宽度 */
  @Trace leftAvoidWidth: number = 0
  /** @description 右侧避让宽度 */
  @Trace rightAvoidWidth: number = 0
  /** @description 主页顶部栏实测总高（含状态栏避让，供定制页全屏预览还原真实主页栏占位） */
  @Trace homeTopBarHeight: number = 0
  /** @description 主页底部栏实测总高（供定制页全屏预览还原真实主页栏占位） */
  @Trace homeBottomBarHeight: number = 0
  /** @description 窗口高度 -vp */
  @Trace windowHeight: number = 0
  /** @description 窗口宽度 -vp */
  @Trace windowWidth: number = 0
  /** @description 当前宽度断点 */
  @Trace widthBp: number = 0
  /** @description 当前高度断点 */
  @Trace heightBp: number = 0
  /** @description 窗口模式 true为PC窗口模式 false为普通窗口模式 */
  @Trace windowMode: boolean = false

  /** 是否初始化中 */
  @Trace isInitializing: boolean = true

  /** 应用基础环境（首选项/设置加载）初始化完成信号：Index 恢复会话前等待，
   *  避免安装后首启 onCreate 的 async 初始化与 loadContent 竞态先用默认配置执行；
   *  默认已完成的 Promise 兜底（EntryAbility 异常路径不让等待方永久挂起） */
  public appInitialized: Promise<void> = Promise.resolve()

  // 全局路由
  @Trace pageStack: NavPathStack = new NavPathStack()

  /** 大屏设置分栏激活时，右侧子导航栈；null 表示未激活（普通单栏路由） */
  public settingsSplitStack: NavPathStack | null = null

  /** @description 当前主题色(Resource) */
  @Trace currentThemeColor: Resource = $r('sys.color.icon_emphasize')

  /** 判断是否为设置相关路由（大屏分栏时推入右侧子栈） */
  isSettingsRoute(name: string): boolean {
    if (name.startsWith('settings_')) {
      return true
    }
    return name === 'about' || name === 'search_engine' || name === 'search_settings'
      || name === 'search_toolbar' || name === 'downloads'
  }

  /** 设置分栏是否生效：子栈已激活且设置页处于路由栈顶 */
  isSplitActive(): boolean {
    if (this.settingsSplitStack === null) {
      return false
    }
    const names: string[] = this.pageStack.getAllPathName()
    return names.length > 0 && names[names.length - 1] === 'settings'
  }

  /**
   * 推送路由
   */
  pushPage(name: string, param: Object | null | undefined, animated: boolean = true): void {
    const split: NavPathStack | null = this.settingsSplitStack
    if (split !== null && this.isSplitActive() && this.isSettingsRoute(name)) {
      split.pushPathByName(name, param ?? null, animated)
      logger.debug('Router', `pushPage(split): ${name}, stack size: ${split.size()}`)
      return
    }
    this.pageStack.pushPathByName(name, param ?? null, animated)
    logger.debug('Router', `pushPage: ${name}, stack size: ${this.pageStack.size()}`)
  }

  /**
   * 弹出路由
   */
  popPage(animated: boolean = false): void {
    const split: NavPathStack | null = this.settingsSplitStack
    if (split !== null && this.isSplitActive() && split.size() > 0) {
      split.pop(animated)
      return
    }
    this.pageStack.pop(animated)
  }

  /**
   * 返回路由根（浏览器主页）：逐层弹出全部路由
   */
  popToRoot(animated: boolean = false): void {
    const split: NavPathStack | null = this.settingsSplitStack
    if (split !== null) {
      split.clear()
    }
    while (this.pageStack.size() > 0) {
      this.pageStack.pop(animated)
    }
    logger.debug('Router', `popToRoot: stack size: ${this.pageStack.size()}`)
  }

  /**
   * 清空全部路由（含大屏设置分栏子栈），回到浏览器主界面
   */
  clearAllPages(): void {
    const split: NavPathStack | null = this.settingsSplitStack
    if (split !== null) {
      split.clear()
    }
    this.pageStack.clear()
  }

}

export const QhState: _QhState = new _QhState()
