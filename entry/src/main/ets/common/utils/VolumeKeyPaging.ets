import { inputConsumer, KeyCode } from '@kit.InputKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { appSettings } from '../entity/SettingsModel';

/**
 * 音量键翻页（操作设定-使用音量键翻页）：
 * 开启时经 inputConsumer 优先消费音量增/减按键（系统音量调节让位于翻页），
 * 音量上键向上滚动、音量下键向下滚动当前网页（约一屏的 90%）
 */
class VolumeKeyPaging {

  private subscribed: boolean = false

  private readonly upConfig: inputConsumer.KeyPressedConfig = {
    key: KeyCode.KEYCODE_VOLUME_UP,
    action: 1,
    isRepeat: false
  }
  private readonly downConfig: inputConsumer.KeyPressedConfig = {
    key: KeyCode.KEYCODE_VOLUME_DOWN,
    action: 1,
    isRepeat: false
  }

  private readonly onUp = (): void => {
    this.scrollActivePage(true)
  }

  private readonly onDown = (): void => {
    this.scrollActivePage(false)
  }

  /** 按设置同步订阅状态（应用启动与开关切换时调用） */
  sync(): void {
    if (appSettings.volume_key_paging) {
      this.subscribe()
    } else {
      this.unsubscribe()
    }
  }

  private subscribe(): void {
    if (this.subscribed) {
      return
    }
    try {
      inputConsumer.on('keyPressed', this.upConfig, this.onUp)
      inputConsumer.on('keyPressed', this.downConfig, this.onDown)
      this.subscribed = true
      console.info('[VolumeKeyPaging] 音量键翻页已开启')
    } catch (error) {
      console.error(`[VolumeKeyPaging] 订阅音量键失败: ${error}`)
    }
  }

  private unsubscribe(): void {
    if (!this.subscribed) {
      return
    }
    try {
      inputConsumer.off('keyPressed', this.onUp)
      inputConsumer.off('keyPressed', this.onDown)
      this.subscribed = false
      console.info('[VolumeKeyPaging] 音量键翻页已关闭')
    } catch (error) {
      console.error(`[VolumeKeyPaging] 退订音量键失败: ${error}`)
    }
  }

  /** 滚动当前标签网页（up=true 向上一屏，false 向下一屏） */
  private scrollActivePage(up: boolean): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome || tab.controller === null || browserVM.isReaderActive(tab.id)) {
      return
    }
    try {
      const dir: number = up ? -1 : 1
      tab.controller.runJavaScript(`window.scrollBy(0, ${dir} * window.innerHeight * 0.9)`)
        .catch((error: BusinessError): void => {
          console.error(`[VolumeKeyPaging] 翻页失败: ${error.code} ${error.message}`)
        })
    } catch (error) {
      console.error(`[VolumeKeyPaging] 翻页异常: ${error}`)
    }
  }
}

export const volumeKeyPaging: VolumeKeyPaging = new VolumeKeyPaging()
