import { window } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { _QhState } from "../../../entryability/AppState";
import { UISettings, appSettings } from "../../entity/SettingsModel";
import { createLogger } from "./Logger";

const logger = createLogger('SettingsUtils')


export class SettingsUtils {

  /**
   * 设置颜色模式
   */
  static setColorMode() {
    try {
      logger.info('ColorMode', `保存的颜色模式：${UISettings.color_mode}`);
      _QhState.Context.getApplicationContext().setColorMode(UISettings.color_mode);
    } catch (err) {
      logger.error(`ColorMode`, `Failed to set colorMode, ${err}`)
    }
  }

  /**
   * 应用语言偏好：'system' 跟随系统，'zh' 中文，'en' English
   * 跟随系统时检测当前系统语言并直接设置为该语言（而非 'default'），保证切换后页面立即刷新
   */
  static applyLanguage() {
    let lang: string
    if (appSettings.language === 'en') {
      lang = 'en-US'
    } else if (appSettings.language === 'zh') {
      lang = 'zh-Hans'
    } else {
      const sysLang: string = i18n.System.getSystemLanguage()
      lang = sysLang.startsWith('en') ? 'en-US' : sysLang
    }
    try {
      i18n.System.setAppPreferredLanguage(lang)
      logger.info('Language', `应用语言已设置为: ${lang}`)
    } catch (err) {
      logger.error('Language', `设置应用语言失败: ${err}`)
    }
  }

  /**
   * 应用屏幕方向：'auto' 跟随系统旋转，'portrait' 竖屏，'landscape' 横屏
   */
  static applyOrientation() {
    const win: window.Window | undefined = _QhState.window
    if (!win) {
      return
    }
    const orientation: window.Orientation = appSettings.screen_orientation === 'portrait'
      ? window.Orientation.PORTRAIT
      : (appSettings.screen_orientation === 'landscape'
        ? window.Orientation.LANDSCAPE
        : window.Orientation.AUTO_ROTATION)
    win.setPreferredOrientation(orientation).then((): void => {
      logger.info('Orientation', `屏幕方向已设置为: ${appSettings.screen_orientation}`)
    }).catch((err: BusinessError): void => {
      logger.error('Orientation', `设置屏幕方向失败: ${err.code} ${err.message}`)
    })
  }

}
