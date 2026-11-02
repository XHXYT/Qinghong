import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer } from '../../../components/NaviContainer';
import { appSettings } from '../../../common/entity/SettingsModel';
import SiteSettingInfo from '../../../common/entity/SiteSettingInfo';
import { SiteSettingsViewModel, siteSettingsVM } from '../../../viewmodel/SiteSettingsViewModel';
import { ProxyUtils, SITE_PROXY_KEY } from '../../../common/utils/ProxyUtils';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { QhState } from '../../../entryability/AppState';

@Builder
export function ProxySettingsBuilder() {
  ProxyPage()
}

@ComponentV2
struct ProxyPage {

  @Local enabledItem: CustomItemInfo = new CustomItemInfo({ id: 'proxy_enabled', type: ItemActionType.TOGGLE })
  @Local typeItem: CustomItemInfo = new CustomItemInfo({ id: 'proxy_type', type: ItemActionType.TEXT })
  @Local serverItem: CustomItemInfo = new CustomItemInfo({ id: 'proxy_server', type: ItemActionType.TEXT })
  @Local portItem: CustomItemInfo = new CustomItemInfo({ id: 'proxy_port', type: ItemActionType.TEXT })
  @Local scopeItem: CustomItemInfo = new CustomItemInfo({ id: 'proxy_scope', type: ItemActionType.ROUTER })

  @Local showTypePicker: boolean = false
  @Local picker: PickerConfig = new PickerConfig()
  @Local pickerHeight: number = pickerSheetHeight(2)

  @Local overrides: SiteSettingInfo[] = []
  @Local serverInput: string = ''
  @Local portInput: string = ''

  private serverDialog: CustomDialogController | undefined = undefined
  private portDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.enabledItem.title = $r('app.string.settings_proxy')
    this.enabledItem.subtitle = $r('app.string.proxy_desc')
    this.enabledItem.value = appSettings.proxy_enabled
    this.enabledItem.onChange = (v: string | boolean | number): void => {
      appSettings.proxy_enabled = v as boolean
      this.syncItemStates()
      ProxyUtils.apply()
    }
    this.typeItem.title = $r('app.string.proxy_type')
    this.typeItem.onChange = (v: string | boolean | number): void => {
      this.openTypePicker()
    }
    this.serverItem.title = $r('app.string.proxy_server')
    this.serverItem.onChange = (v: string | boolean | number): void => {
      this.serverDialog?.open()
    }
    this.portItem.title = $r('app.string.proxy_port')
    this.portItem.onChange = (v: string | boolean | number): void => {
      this.portDialog?.open()
    }
    this.scopeItem.title = $r('app.string.proxy_routed_sites')
    this.scopeItem.onChange = (v: string | boolean | number): void => {
      QhState.pushPage('settings_site_item', SITE_PROXY_KEY)
    }
    this.syncScope()
    this.loadOverrides()
    this.syncItemStates()
    this.serverDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.proxy_server'),
        contentBuilder: (): void => {
          this.serverInputContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doSaveServer()
            }
            this.serverDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.serverInput = appSettings.proxy_host
      }
    })
    this.portDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.proxy_port'),
        contentBuilder: (): void => {
          this.portInputContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doSavePort()
            }
            this.portDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.portInput = appSettings.proxy_port > 0 ? String(appSettings.proxy_port) : ''
      }
    })
  }

  /** 同步「走代理」默认档描述（默认开=全部走代理；默认关=仅例外走代理） */
  private syncScope(): void {
    this.scopeItem.subtitle = ProxyUtils.proxyDefault() === 'on' ?
      $r('app.string.proxy_default_on') : $r('app.string.proxy_default_off')
  }

  /** 加载单独配置了走代理的站点列表 */
  private loadOverrides(): void {
    siteSettingsVM.listByKey(SITE_PROXY_KEY).then((list: SiteSettingInfo[]): void => {
      this.overrides = list
    })
  }

  /** 同步类型/服务器/端口条目的展示值与可用态 */
  private syncItemStates(): void {
    this.typeItem.value = ResourceUtils.getString(appSettings.proxy_type === 'socks' ?
      $r('app.string.proxy_type_socks') : $r('app.string.proxy_type_http'))
    this.typeItem.enabled = appSettings.proxy_enabled
    this.serverItem.value = appSettings.proxy_host.trim() === '' ?
      ResourceUtils.getString($r('app.string.proxy_server_hint')) : appSettings.proxy_host
    this.serverItem.enabled = appSettings.proxy_enabled
    this.portItem.value = appSettings.proxy_port > 0 ? String(appSettings.proxy_port) : ''
    this.portItem.enabled = appSettings.proxy_enabled
  }

  private doSaveServer(): void {
    const h: string = this.serverInput.trim()
    if (h === '' || h.includes(' ')) {
      toastUtil.showToast({ message: $r('app.string.proxy_server_invalid') })
      return
    }
    appSettings.proxy_host = h
    this.syncItemStates()
    ProxyUtils.apply()
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  private doSavePort(): void {
    const p: number = parseInt(this.portInput.trim(), 10)
    if (Number.isNaN(p) || p < 1 || p > 65535) {
      toastUtil.showToast({ message: $r('app.string.proxy_port_invalid') })
      return
    }
    appSettings.proxy_port = p
    this.syncItemStates()
    ProxyUtils.apply()
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  private openTypePicker(): void {
    const options: PickerOption[] = [
      new PickerOption('http', $r('app.string.proxy_type_http')),
      new PickerOption('socks', $r('app.string.proxy_type_socks'))
    ]
    this.picker.title = $r('app.string.proxy_type')
    this.picker.options = options
    this.picker.selected = appSettings.proxy_type
    this.picker.onSelect = (v: string): void => {
      appSettings.proxy_type = v
      this.syncItemStates()
      ProxyUtils.apply()
    }
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showTypePicker = true
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_proxy'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onShown: (): void => {
        // 从「走代理」管理页返回时刷新默认档描述与单独配置列表
        this.syncScope()
        this.loadOverrides()
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      // 代理服务器卡片
      ListItem() {
        Column() {
          CustomListItem({
            item: this.enabledItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 16 })
          CustomListItem({
            item: this.typeItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 16 })
          CustomListItem({
            item: this.serverItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 16 })
          CustomListItem({
            item: this.portItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .margin({ top: 10 })

      // 走代理范围：网站设定 · 走代理（默认开关 + 单独配置站点）
      ListItem() {
        Column() {
          CustomListItem({
            item: this.scopeItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          if (this.overrides.length > 0) {
            Divider()
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16 })
            ForEach(this.overrides, (o: SiteSettingInfo) => {
              Row() {
                Text(o.site)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(o.value === 'on' ? $r('app.string.site_proxy') : $r('app.string.proxy_site_off'))
                  .fontSize(13)
                  .fontColor(o.value === 'on' ? '#66BB6A' : $r('sys.color.font_secondary'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }, (o: SiteSettingInfo) => `${o.site}|${o.value}`)
          }
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
    .bindSheet(this.showTypePicker!!, this.typePickerBuilder(), {
      preferType: SheetType.CENTER,
      height: this.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showTypePicker = false
      }
    })
  }

  @Builder
  serverInputContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: $r('app.string.proxy_server_hint'), text: this.serverInput })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.serverInput = v
        })
    }
    .width('100%')
  }

  @Builder
  portInputContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: '1080', text: this.portInput })
        .height(44)
        .fontSize(15)
        .type(InputType.Number)
        .onChange((v: string) => {
          this.portInput = v
        })
    }
    .width('100%')
  }

  @Builder
  typePickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showTypePicker = false
      }
    })
  }
}
