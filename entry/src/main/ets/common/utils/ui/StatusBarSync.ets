import { display, window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UISettings } from '../../entity/SettingsModel';
import { tabsVM } from '../../../viewmodel/TabsViewModel';
import { browserVM } from '../../../viewmodel/BrowserViewModel';
import { ActionBarColor } from './ActionBarColor';
import { HomeImmersive } from '../home/HomeImmersive';
import { homeBg } from '../home/HomeBg';
import { QhState, _QhState } from '../../../entryability/AppState';
import { createLogger } from '../app/Logger';

const logger = createLogger('StatusBarSync')

/**
 * 系统状态栏图标颜色同步：
 * 1. 操作栏色彩模式：顶栏取页面色且窗口铺满整屏时，按页面色深浅反色（深底浅字/浅底深字）；
 * 2. 主页沉浸：主页背景铺至状态栏下时，按主页背景明暗反色（与色彩模式设置无关）；
 * 其余（PC 自由窗口、小窗、分屏、阅读模式、未提取到颜色的页面）还原跟随深浅色的默认值。
 */
export class StatusBarSync {

  /** 上次已应用的状态栏图标色，去重避免重复设置 */
  private static applied: string = ''

  /** 计算并应用状态栏图标颜色（幂等；页面色/主页背景变化/切标签/开关色彩模式/布局切换/窗口模式变化/深浅色切换时调用） */
  static sync(): void {
    const win: window.Window | undefined = _QhState.window
    if (win === undefined) {
      return
    }
    const tab = tabsVM.activeTab
    const base: boolean = !QhState.windowMode
      && !browserVM.showReader
      && StatusBarSync.isFullScreen(win)
    const webColored: boolean = base
      && UISettings.action_bar_color_mode
      && UISettings.app_layout !== 'bottom'
      && UISettings.app_layout !== 'bottom_double'
      && tab !== null && !tab.isHome && tab.themeColor !== ''
    // 主页沉浸：主页背景延伸至状态栏下，按背景明暗取图标色
    const homeColored: boolean = base && HomeImmersive.active()
    let color: string
    if (webColored && tab !== null) {
      color = ActionBarColor.isDarkColor(tab.themeColor) ? '#FFFFFFFF' : '#FF000000'
    } else if (homeColored) {
      color = homeBg.dark ? '#FFFFFFFF' : '#FF000000'
    } else {
      color = StatusBarSync.isDarkMode() ? '#FFFFFFFF' : '#FF000000'
    }
    if (color === StatusBarSync.applied) {
      return
    }
    StatusBarSync.applied = color
    win.setWindowSystemBarProperties({ statusBarContentColor: color })
      .then((): void => {
        logger.debug(`状态栏图标色已应用: ${color}`)
      })
      .catch((error: BusinessError): void => {
        logger.error(`状态栏图标色应用失败: ${error}`)
      })
  }

  /** 窗口是否铺满整屏（小窗/分屏/自由窗口不覆盖系统状态栏，无需同步） */
  private static isFullScreen(win: window.Window): boolean {
    try {
      const rect: window.Rect = win.getWindowProperties().windowRect
      const d: display.Display = display.getDefaultDisplaySync()
      return rect.width === d.width && rect.height === d.height
    } catch (error) {
      return false
    }
  }

  /** 当前是否深色模式（还原默认状态栏图标色用） */
  private static isDarkMode(): boolean {
    try {
      const conf: resourceManager.Configuration = _QhState.Context.resourceManager.getConfigurationSync()
      return conf.colorMode === resourceManager.ColorMode.DARK
    } catch (error) {
      return false
    }
  }
}
