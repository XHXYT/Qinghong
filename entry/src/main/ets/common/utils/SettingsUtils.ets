import { _QhState } from "../../entryability/AppState";
import { UISettings } from "../entity/SettingsModel";
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

}
