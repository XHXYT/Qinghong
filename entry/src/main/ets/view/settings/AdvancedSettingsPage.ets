import { webview } from '@kit.ArkWeb';
import { CustomContentDialog } from '@kit.ArkUI';
import { SettingsScaffold, SettingsSection } from '../../components/SettingsScaffold';
import { appSettings } from '../../common/entity/SettingsModel';
import { DnsUtils } from '../../common/utils/DnsUtils';
import { CustomItemInfo, ItemActionType } from '../../common/entity/CusItemInfo';
import { buildDialogButtons } from '../../components/dialog/AppContentDialog';
import { toastUtil } from '../../common/utils/ToastUtils';
import { tabsVM } from '../../viewmodel/TabsViewModel';

@Builder
export function AdvancedSettingsBuilder() {
  AdvancedSettingsPage()
}

@ComponentV2
struct AdvancedSettingsPage {

  @Local sections: SettingsSection[] = []
  @Local sslAckChecked: boolean = false

  private items: CustomItemInfo[] = []
  private sslConfirmDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.initDialogs()
    // 网页浏览
    const gBrowsing = new SettingsSection('browsing', $r('app.string.advanced_group_browsing'))
    gBrowsing.items.push(new CustomItemInfo({
      id: 'no_image_mode',
      title: $r('app.string.no_image_mode'),
      subtitle: $r('app.string.no_image_mode_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.no_image_mode,
      onChange: (v: string | boolean | number): void => {
        appSettings.no_image_mode = v as boolean
      }
    }))
    gBrowsing.items.push(new CustomItemInfo({
      id: 'pause_web_timers',
      title: $r('app.string.pause_web_timers'),
      subtitle: $r('app.string.pause_web_timers_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.pause_web_timers,
      onChange: (v: string | boolean | number): void => {
        appSettings.pause_web_timers = v as boolean
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
    gBrowsing.items.push(new CustomItemInfo({
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
    gBrowsing.items.push(hapticItem)
    gBrowsing.items.push(new CustomItemInfo({
      id: 'back_to_top',
      title: $r('app.string.back_to_top'),
      subtitle: $r('app.string.back_to_top_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.back_to_top,
      onChange: (v: string | boolean | number): void => {
        appSettings.back_to_top = v as boolean
      }
    }))
    gBrowsing.items.push(new CustomItemInfo({
      id: 'blank_screen_retry',
      title: $r('app.string.blank_screen_retry'),
      subtitle: $r('app.string.blank_screen_retry_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.blank_screen_retry,
      onChange: (v: string | boolean | number): void => {
        appSettings.blank_screen_retry = v as boolean
      }
    }))
    gBrowsing.items.push(new CustomItemInfo({
      id: 'web_overscroll_bounce',
      title: $r('app.string.web_overscroll_bounce'),
      subtitle: $r('app.string.web_overscroll_bounce_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_overscroll_bounce,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_overscroll_bounce = v as boolean
      }
    }))
    // 加载与性能
    const gPerf = new SettingsSection('performance', $r('app.string.advanced_group_performance'))
    gPerf.items.push(new CustomItemInfo({
      id: 'web_fast_destroy',
      title: $r('app.string.web_fast_destroy'),
      subtitle: $r('app.string.web_fast_destroy_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_fast_destroy,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_fast_destroy = v as boolean
      }
    }))
    gPerf.items.push(new CustomItemInfo({
      id: 'dns_preconnect_enabled',
      title: $r('app.string.dns_preconnect'),
      subtitle: $r('app.string.dns_preconnect_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.dns_preconnect_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.dns_preconnect_enabled = v as boolean
        DnsUtils.applyPreconnect()
      }
    }))
    gPerf.items.push(new CustomItemInfo({
      id: 'web_prefetch',
      title: $r('app.string.web_prefetch'),
      subtitle: $r('app.string.web_prefetch_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_prefetch,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_prefetch = v as boolean
      }
    }))
    // 网页助手（组标题复用功能名）
    const gAssistant = new SettingsSection('assistant', $r('app.string.web_assistant'))
    // 资源嗅探：依赖网页助手（总开关关闭时禁用并联动关闭）
    const sniffItem: CustomItemInfo = new CustomItemInfo({
      id: 'resource_sniff',
      title: $r('app.string.resource_sniff'),
      subtitle: $r('app.string.resource_sniff_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.resource_sniff,
      enabled: appSettings.web_assistant,
      onChange: (v: string | boolean | number): void => {
        appSettings.resource_sniff = v as boolean
      }
    })
    gAssistant.items.push(new CustomItemInfo({
      id: 'web_assistant',
      title: $r('app.string.web_assistant'),
      subtitle: $r('app.string.web_assistant_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_assistant,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_assistant = v as boolean
        if (!appSettings.web_assistant) {
          // 总开关关闭：联动关闭资源嗅探（反向不联动）
          appSettings.resource_sniff = false
          sniffItem.value = false
        }
        sniffItem.enabled = appSettings.web_assistant
      }
    }))
    gAssistant.items.push(sniffItem)
    // 安全
    const gSecurity = new SettingsSection('security', $r('app.string.advanced_group_security'))
    gSecurity.items.push(new CustomItemInfo({
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
    gSecurity.items.push(new CustomItemInfo({
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
    gSecurity.items.push(new CustomItemInfo({
      id: 'web_block_private_network',
      title: $r('app.string.web_block_private_network'),
      subtitle: $r('app.string.web_block_private_network_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_block_private_network,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_block_private_network = v as boolean
      }
    }))
    gSecurity.items.push(new CustomItemInfo({
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
    this.items = gBrowsing.items.concat(gPerf.items).concat(gAssistant.items).concat(gSecurity.items)
    this.sections = [gBrowsing, gPerf, gAssistant, gSecurity]
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
    SettingsScaffold({
      title: $r('app.string.settings_advanced'),
      sections: this.sections
    })
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
