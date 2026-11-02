import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { _QhState } from '../../entryability/AppState';
import { appSettings } from '../entity/SettingsModel';
import { createLogger } from './Logger';

const logger = createLogger('HomeBg');

/**
 * 主页背景明暗：背景图优先采样均值亮度，无图按背景主题（跟随系统时按当前生效深浅色）。
 * 供操作栏/地址栏/工具栏/搜索框按背景取黑/白前景色（暗背景白字、亮背景黑字）
 */
@ObservedV2
export class HomeBg {
  /** @description 当前主页背景是否偏暗（决定前景用白字还是黑字） */
  @Trace dark: boolean = false

  /** 背景图采样进行中（避免并发重入） */
  private sampling: boolean = false

  /**
   * 重估背景明暗：有背景图采样均值亮度，无图按背景主题
   */
  refresh(): void {
    const img: string = appSettings.home_bg_image
    if (img !== '' && fileIo.accessSync(img)) {
      this.sampleImage(img)
      return
    }
    this.dark = HomeBg.themeDark()
  }

  /** 背景主题判定：dark→true / light→false / system→当前生效深浅色 */
  private static themeDark(): boolean {
    if (appSettings.home_bg_theme === 'dark') {
      return true
    }
    if (appSettings.home_bg_theme === 'light') {
      return false
    }
    try {
      return _QhState.Context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    } catch (error) {
      return false
    }
  }

  /** 背景图均值亮度采样（降采样 32×32 后按感知亮度加权平均，低于阈值视为暗背景） */
  private async sampleImage(path: string): Promise<void> {
    if (this.sampling) {
      return
    }
    this.sampling = true
    let source: image.ImageSource | null = null
    let pm: image.PixelMap | null = null
    try {
      source = image.createImageSource(`file://${path}`)
      pm = await source.createPixelMap({
        desiredSize: { width: 32, height: 32 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      })
      const info: image.ImageInfo = await pm.getImageInfo()
      const w: number = info.size.width
      const h: number = info.size.height
      const buffer: ArrayBuffer = new ArrayBuffer(w * h * 4)
      await pm.readPixelsToBuffer(buffer)
      const px: Uint8Array = new Uint8Array(buffer)
      let total: number = 0
      for (let i: number = 0; i < w * h; i++) {
        total += 0.299 * px[i * 4] + 0.587 * px[i * 4 + 1] + 0.114 * px[i * 4 + 2]
      }
      this.dark = total / (w * h) < 140
    } catch (error) {
      logger.error(`sample bg failed: ${error}`)
      this.dark = HomeBg.themeDark()
    } finally {
      this.sampling = false
      if (pm !== null) {
        pm.release()
      }
      if (source !== null) {
        source.release()
      }
    }
  }
}

export const homeBg: HomeBg = new HomeBg()
