import { common } from "@kit.AbilityKit"
import { window } from "@kit.ArkUI"
import { createLogger } from "../common/utils/Logger"

const logger = createLogger('QhState')


@ObservedV2
export class _QhState {

  public static appVersion: string = '1.0.0'

  // 窗口对象
  public static UIContext: UIContext
  public static Context: common.UIAbilityContext
  public static window: window.Window;
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

  // 全局路由
  @Trace pageStack: NavPathStack = new NavPathStack()

  /** @description 当前主题色(Resource) */
  @Trace currentThemeColor: Resource = $r('sys.color.icon_emphasize')

  /**
   * 推送路由
   */
  pushPage(name: string, param: Object | null | undefined, animated: boolean = true): void {
    this.pageStack.pushPathByName(name, param ?? null, animated)
    logger.debug('Router', `pushPage: ${name}, stack size: ${this.pageStack.size()}`)
  }

  /**
   * 弹出路由
   */
  popPage(animated: boolean = false): void {
    this.pageStack.pop(animated)
  }

}

export const QhState: _QhState = new _QhState()
