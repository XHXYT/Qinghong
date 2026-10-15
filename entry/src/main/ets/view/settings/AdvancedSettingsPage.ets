import { webview } from '@kit.ArkWeb';
import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer } from '../../components/NaviContainer';
import { appSettings } from '../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../common/entity/CusItemInfo';
import { CustomListItem } from '../../components/CusItemBuilder';
import { buildDialogButtons } from '../../components/dialog/AppContentDialog';
import { toastUtil } from '../../common/utils/ToastUtils';
import { tabsVM } from '../../viewmodel/TabsViewModel';

@Builder
export function AdvancedSettingsBuilder() {
  AdvancedSettingsPage()
}

@ComponentV2
struct AdvancedSettingsPage {

  @Local items: CustomItemInfo[] = []
  @Local sslAckChecked: boolean = false

  private sslConfirmDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.initDialogs()
    const items: CustomItemInfo[] = []
    items.push(new CustomItemInfo({
      id: 'no_image_mode',
      title: $r('app.string.no_image_mode'),
      subtitle: $r('app.string.no_image_mode_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.no_image_mode,
      onChange: (v: string | boolean | number): void => {
        appSettings.no_image_mode = v as boolean
      }
    }))
    // 保留长按选择振动：网页振动开启时被强制开启，置灰无意义
    const hapticItem: CustomItemInfo = new CustomItemInfo({
      id: 'web_haptic_enabled',
      title: $r('app.string.web_haptic'),
      subtitle: $r('app.string.web_haptic_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_haptic_enabled,
      enabled: !appSettings.web_vibration_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_haptic_enabled = v as boolean
      }
    })
    items.push(new CustomItemInfo({
      id: 'web_vibration_enabled',
      title: $r('app.string.web_vibration'),
      subtitle: $r('app.string.web_vibration_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_vibration_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_vibration_enabled = v as boolean
        hapticItem.enabled = v !== true
      }
    }))
    items.push(hapticItem)
    items.push(new CustomItemInfo({
      id: 'show_sniff_button',
      title: $r('app.string.show_sniff_button'),
      type: ItemActionType.TOGGLE,
      value: appSettings.show_sniff_button,
      enabled: false,
      disabledHint: $r('app.string.feature_not_available'),
      onChange: (v: string | boolean | number): void => {
        appSettings.show_sniff_button = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'allow_debug_web',
      title: $r('app.string.allow_debug_web'),
      type: ItemActionType.TOGGLE,
      value: appSettings.allow_debug_web,
      onChange: (v: string | boolean | number): void => {
        appSettings.allow_debug_web = v as boolean
        try {
          webview.WebviewController.setWebDebuggingAccess(appSettings.allow_debug_web)
        } catch (e) {
          console.error(`[AdvancedSettings] setWebDebuggingAccess 失败: ${e}`)
        }
      }
    }))
    items.push(new CustomItemInfo({
      id: 'disable_safe_browsing',
      title: $r('app.string.disable_safe_browsing'),
      subtitle: $r('app.string.disable_safe_browsing_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.disable_safe_browsing,
      onChange: (v: string | boolean | number): void => {
        appSettings.disable_safe_browsing = v as boolean
        // 对已挂载的标签立即生效（未挂载的由 onPageBegin 兜底应用）
        for (const tab of tabsVM.tabs) {
          const controller: webview.WebviewController | null = tab.controller
          if (controller) {
            try {
              controller.enableSafeBrowsing(!appSettings.disable_safe_browsing)
            } catch (e) {
              console.error(`[AdvancedSettings] enableSafeBrowsing 失败: ${e}`)
            }
          }
        }
      }
    }))
    items.push(new CustomItemInfo({
      id: 'ignore_ssl_warning',
      title: $r('app.string.ignore_ssl_warning'),
      subtitle: $r('app.string.ignore_ssl_warning_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.ignore_ssl_warning,
      onChange: (v: string | boolean | number): void => {
        if (v === true) {
          // 先回弹开关，弹窗确认后才真正开启
          this.setItemValue('ignore_ssl_warning', false)
          this.sslConfirmDialog?.open()
        } else {
          appSettings.ignore_ssl_warning = false
        }
      }
    }))
    this.items = items
  }

  private initDialogs(): void {
    this.sslConfirmDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.ignore_ssl_warning'),
        contentBuilder: (): void => {
          this.sslConfirmContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], true,
          (index: number): void => {
            if (index === 1) {
              if (!this.sslAckChecked) {
                toastUtil.showToast({ message: $r('app.string.ssl_warning_ack_required') })
                return
              }
              appSettings.ignore_ssl_warning = true
              this.setItemValue('ignore_ssl_warning', true)
            }
            this.sslConfirmDialog?.close()
          }),
        contentAreaPadding: { top: 16, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.sslAckChecked = false
      }
    })
  }

  private setItemValue(id: string, v: string | boolean | number): void {
    for (const item of this.items) {
      if (item.id === id) {
        item.value = v
        return
      }
    }
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_advanced'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      ListItem() {
        Column() {
          Repeat<CustomItemInfo>(this.items)
            .each((ri: RepeatItem<CustomItemInfo>) => {
              CustomListItem({
                item: ri.item,
                itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
              })
            })
            .key((item: CustomItemInfo) => item.id)
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.background_color'))
        .clip(true)
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(56)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  sslConfirmContent() {
    Column({ space: 16 }) {
      Text($r('app.string.ssl_warning_dialog_message'))
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeight(22)
      Row() {
        Checkbox()
          .size({ width: 22, height: 22 })
          .select(this.sslAckChecked)
          .hitTestBehavior(HitTestMode.None)
        Text($r('app.string.ssl_warning_ack'))
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .width('100%')
      .onClick(() => {
        this.sslAckChecked = !this.sslAckChecked
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
