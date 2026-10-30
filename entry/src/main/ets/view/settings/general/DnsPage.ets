import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer } from '../../../components/NaviContainer';
import { appSettings } from '../../../common/entity/SettingsModel';
import { DnsUtils } from '../../../common/utils/DnsUtils';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { QhState } from '../../../entryability/AppState';

@Builder
export function DnsSettingsBuilder() {
  DnsPage()
}

@ComponentV2
struct DnsPage {

  @Local dohItem: CustomItemInfo = new CustomItemInfo({ id: 'doh_enabled', type: ItemActionType.TOGGLE })
  @Local providerItem: CustomItemInfo = new CustomItemInfo({ id: 'doh_provider', type: ItemActionType.TEXT })
  @Local customItem: CustomItemInfo = new CustomItemInfo({ id: 'doh_custom', type: ItemActionType.TEXT })
  @Local hostsItem: CustomItemInfo = new CustomItemInfo({ id: 'hosts_entry', type: ItemActionType.TEXT })

  @Local showProviderPicker: boolean = false
  @Local picker: PickerConfig = new PickerConfig()
  @Local pickerHeight: number = pickerSheetHeight(6)
  @Local customUrl: string = ''

  private customDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.dohItem.title = $r('app.string.dns_doh')
    this.dohItem.subtitle = $r('app.string.dns_doh_desc')
    this.dohItem.value = appSettings.dns_doh_enabled
    this.dohItem.onChange = (v: string | boolean | number): void => {
      appSettings.dns_doh_enabled = v as boolean
      DnsUtils.applyDoh()
    }
    this.providerItem.title = $r('app.string.dns_provider')
    this.providerItem.value = ResourceUtils.getString(DnsUtils.providerName(appSettings.dns_doh_provider))
    this.providerItem.onChange = (v: string | boolean | number): void => {
      this.openProviderPicker()
    }
    this.customItem.title = $r('app.string.dns_custom_url')
    this.customItem.value = appSettings.dns_doh_custom === '' ?
      ResourceUtils.getString($r('app.string.dns_custom_url_hint')) : appSettings.dns_doh_custom
    this.customItem.enabled = appSettings.dns_doh_provider === 'custom'
    this.customItem.onChange = (v: string | boolean | number): void => {
      this.customDialog?.open()
    }
    this.hostsItem.title = $r('app.string.settings_hosts')
    this.hostsItem.subtitle = $r('app.string.hosts_desc')
    this.hostsItem.onChange = (v: string | boolean | number): void => {
      QhState.pushPage('settings_hosts', null)
    }
    this.customDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.dns_custom_url'),
        contentBuilder: (): void => {
          this.customUrlContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doSaveCustom()
            }
            this.customDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.customUrl = appSettings.dns_doh_custom
      }
    })
  }

  private doSaveCustom(): void {
    const u: string = this.customUrl.trim()
    if (!u.startsWith('https://')) {
      toastUtil.showToast({ message: $r('app.string.dns_custom_url_invalid') })
      return
    }
    appSettings.dns_doh_custom = u
    this.customItem.value = u
    DnsUtils.applyDoh()
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  private openProviderPicker(): void {
    const options: PickerOption[] = []
    for (const p of DnsUtils.DOH_PROVIDERS) {
      options.push(new PickerOption(p.id, p.nameRes))
    }
    options.push(new PickerOption('custom', $r('app.string.dns_provider_custom')))
    this.picker.title = $r('app.string.dns_provider')
    this.picker.options = options
    this.picker.selected = appSettings.dns_doh_provider
    this.picker.onSelect = (v: string): void => {
      appSettings.dns_doh_provider = v
      this.providerItem.value = ResourceUtils.getString(DnsUtils.providerName(v))
      this.customItem.enabled = v === 'custom'
      DnsUtils.applyDoh()
    }
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showProviderPicker = true
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_dns'),
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
      // DNS 优化卡片
      ListItem() {
        Column() {
          CustomListItem({
            item: this.dohItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 16 })
          CustomListItem({
            item: this.providerItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          if (appSettings.dns_doh_provider === 'custom') {
            Divider()
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16 })
            CustomListItem({
              item: this.customItem,
              itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
            })
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .margin({ top: 10 })

      // 域名 IP 指定（Hosts）
      ListItem() {
        Column() {
          CustomListItem({
            item: this.hostsItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .margin({ top: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(QhState.bottomRectHeight)
    .padding({ left: 16, right: 16 })
    .bindSheet(this.showProviderPicker!!, this.providerPickerBuilder(), {
      height: this.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showProviderPicker = false
      }
    })
  }

  @Builder
  customUrlContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: $r('app.string.dns_custom_url_hint'), text: this.customUrl })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.customUrl = v
        })
    }
    .width('100%')
  }

  @Builder
  providerPickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showProviderPicker = false
      }
    })
  }
}
