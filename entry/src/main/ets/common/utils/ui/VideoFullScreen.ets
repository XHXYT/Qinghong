import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { _QhState } from '../../../entryability/AppState';
import { SettingsUtils } from '../app/SettingsUtils';
import { createLogger } from '../app/Logger';

const logger = createLogger('VideoFullScreen')

/**
 * 网页视频全屏窗口控制：
 * 进入时隐藏系统状态栏/导航栏，横屏视频自动转横屏（竖屏视频保持当前方向）；
 * 退出时恢复系统栏并回落到应用设置的屏幕方向。
 * 应用内地址栏/工具栏的隐藏由 TabInfo.videoFullScreen 驱动（Index 布局）。
 */
export class VideoFullScreen {

  /** 进入网页视频全屏（videoWidth/videoHeight 为触发全屏的元素尺寸，取不到为 0） */
  static enter(videoWidth: number, videoHeight: number): void {
    const win: window.Window | undefined = _QhState.window
    if (!win) {
      return
    }
    try {
      win.setWindowSystemBarEnable([])
        .catch((): void => {
        })
    } catch (error) {
      const err = error as BusinessError
      logger.error(`enter hide system bars failed: ${err.code} ${err.message}`)
    }
    // 横屏视频转横屏；竖屏视频不改变方向
    if (videoWidth > videoHeight) {
      try {
        win.setPreferredOrientation(window.Orientation.LANDSCAPE)
          .catch((err: BusinessError): void => {
            logger.error(`enter landscape failed: ${err.code} ${err.message}`)
          })
      } catch (error) {
        const err = error as BusinessError
        logger.error(`enter landscape failed: ${err.code} ${err.message}`)
      }
    }
  }

  /** 退出网页视频全屏：恢复系统栏与应用设置的屏幕方向 */
  static exit(): void {
    const win: window.Window | undefined = _QhState.window
    if (!win) {
      return
    }
    try {
      win.setWindowSystemBarEnable(['status', 'navigation'])
        .catch((): void => {
        })
    } catch (error) {
      const err = error as BusinessError
      logger.error(`exit restore system bars failed: ${err.code} ${err.message}`)
    }
    SettingsUtils.applyOrientation()
  }
}
