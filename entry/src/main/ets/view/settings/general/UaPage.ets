import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { appSettings, CustomUa } from '../../../common/entity/SettingsModel';
import { UaUtils, UserAgentPreset } from '../../../common/utils/UaUtils';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { QhState } from '../../../entryability/AppState';

@Builder
export function SettingsUaBuilder() {
  UaPage()
}

@ComponentV2
struct UaPage {

  @Local inputName: string = ''
  @Local inputUa: string = ''
  @Local showDesktopPicker: boolean = false
  @Local picker: PickerConfig = new PickerConfig()
  @Local pickerHeight: number = pickerSheetHeight(5)

  @Local desktopItem: CustomItemInfo = new CustomItemInfo({ id: 'ua_desktop', type: ItemActionType.TEXT })
  @Local simplifyItem: CustomItemInfo = new CustomItemInfo({ id: 'ua_simplify', type: ItemActionType.TOGGLE })

  private editingId: string = ''
  private addDialog: CustomDialogController | undefined = undefined
  private editDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    // 清理无效的电脑模式标识（历史「custom」取值或已删除的自定义 UA）
    if (['windows_chrome', 'windows_ie', 'macos'].indexOf(appSettings.ua_desktop) < 0
      && !appSettings.custom_uas.some((c: CustomUa): boolean => c.id === appSettings.ua_desktop)) {
      appSettings.ua_desktop = 'windows_chrome'
    }
    this.desktopItem.title = $r('app.string.ua_desktop_mode')
    this.desktopItem.value = ResourceUtils.getString(UaUtils.presetName(appSettings.ua_desktop))
    this.desktopItem.onChange = (v: string | boolean | number): void => {
      this.openDesktopPicker()
    }
    this.simplifyItem.title = $r('app.string.ua_simplify')
    this.simplifyItem.subtitle = $r('app.string.ua_simplify_desc')
    this.simplifyItem.value = appSettings.ua_simplify
    this.simplifyItem.onChange = (v: string | boolean | number): void => {
      appSettings.ua_simplify = v as boolean
      appSettings.save()
      UaUtils.applyToAll()
    }
    this.addDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.ua_add_title'),
        contentBuilder: (): void => {
          this.uaInputDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doAddUa()
            }
            this.addDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.inputName = ''
        this.inputUa = ''
      }
    })
    this.editDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.ua_edit_title'),
        contentBuilder: (): void => {
          this.uaInputDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doEditUa()
            }
            this.editDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.prefillEdit()
      }
    })
  }

  private prefillEdit(): void {
    for (const c of appSettings.custom_uas) {
      if (c.id === this.editingId) {
        this.inputName = c.name
        this.inputUa = c.ua
        return
      }
    }
    this.inputName = ''
    this.inputUa = ''
  }

  private doAddUa(): void {
    const name = this.inputName.trim()
    const ua = this.inputUa.trim()
    if (name === '' || ua === '') {
      return
    }
    const id = `custom_${new Date().getTime()}`
    appSettings.custom_uas.push(new CustomUa(id, name, ua))
    appSettings.ua_mode = id
    appSettings.save()
    UaUtils.applyToAll()
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  private doEditUa(): void {
    const name = this.inputName.trim()
    const ua = this.inputUa.trim()
    if (name === '' || ua === '') {
      return
    }
    for (const c of appSettings.custom_uas) {
      if (c.id === this.editingId) {
        c.name = name
        c.ua = ua
        // 若该 UA 同时是电脑模式标识，刷新显示名
        if (appSettings.ua_desktop === c.id) {
          this.desktopItem.value = c.name
        }
        break
      }
    }
    appSettings.save()
    if (appSettings.ua_mode === this.editingId) {
      UaUtils.applyToAll()
    }
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  private openEdit(c: CustomUa): void {
    this.editingId = c.id
    this.editDialog?.open()
  }

  private confirmDeleteUa(c: CustomUa): void {
    toastUtil.showAlertDialog({
      title: c.name,
      message: $r('app.string.ua_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            this.doDeleteUa(c)
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteUa')
  }

  private doDeleteUa(c: CustomUa): void {
    appSettings.custom_uas = appSettings.custom_uas.filter((x: CustomUa): boolean => x.id !== c.id)
    if (appSettings.ua_mode === c.id) {
      appSettings.ua_mode = 'default'
    }
    if (appSettings.ua_desktop === c.id) {
      appSettings.ua_desktop = 'windows_chrome'
      this.desktopItem.value = ResourceUtils.getString(UaUtils.presetName('windows_chrome'))
    }
    appSettings.save()
    UaUtils.applyToAll()
  }

  private selectUa(id: string): void {
    appSettings.ua_mode = id
    appSettings.save()
    UaUtils.applyToAll()
  }

  private openDesktopPicker(): void {
    const options: PickerOption[] = [
      new PickerOption('windows_chrome', $r('app.string.ua_windows_chrome')),
      new PickerOption('windows_ie', $r('app.string.ua_windows_ie')),
      new PickerOption('macos', $r('app.string.ua_macos'))
    ]
    // 自定义 UA 逐项列出，可直接选为电脑模式标识
    for (const c of appSettings.custom_uas) {
      options.push(new PickerOption(c.id, c.name))
    }
    this.picker.title = $r('app.string.ua_desktop_mode')
    this.picker.options = options
    this.picker.selected = appSettings.ua_desktop
    this.picker.onSelect = (v: string): void => {
      appSettings.ua_desktop = v
      appSettings.save()
      UaUtils.applyToAll()
      this.desktopItem.value = ResourceUtils.getString(UaUtils.presetName(v))
    }
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showDesktopPicker = true
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_ua'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.plus'),
          action: (): void => {
            this.addDialog?.open()
          }
        })
      ],
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
      // 预置标识
      ForEach(UaUtils.PRESETS, (p: UserAgentPreset, idx: number) => {
        ListItem() {
          Column() {
            Divider()
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16 })
              .visibility(idx === 0 ? Visibility.None : Visibility.Visible)
            Row() {
              Text(p.nameRes)
                .fontSize(16)
                .fontColor($r('sys.color.font_primary'))
                .fontFamily(appSettings.font_family)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (appSettings.ua_mode === p.id) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(20)
                  .fontColor([QhState.currentThemeColor])
              }
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.selectUa(p.id)
            })
          }
          .width('100%')
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius({ topLeft: idx === 0 ? 16 : 0, topRight: idx === 0 ? 16 : 0 })
        .margin({ top: idx === 0 ? 10 : 0 })
      }, (p: UserAgentPreset) => p.id)

      // 自定义标识
      if (appSettings.custom_uas.length > 0) {
        ForEach(appSettings.custom_uas, (c: CustomUa, idx: number) => {
          ListItem() {
            Column() {
              Divider()
                .color($r('sys.color.comp_divider'))
                .margin({ left: 16 })
              Row() {
                Column({ space: 2 }) {
                  Text(c.name)
                    .fontSize(16)
                    .fontColor($r('sys.color.font_primary'))
                    .fontFamily(appSettings.font_family)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(c.ua)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .fontFamily(appSettings.font_family)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (appSettings.ua_mode === c.id) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(20)
                    .fontColor([QhState.currentThemeColor])
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => {
                this.selectUa(c.id)
              })
              .bindContextMenu(this.customUaMenu(c), ResponseType.LongPress)
            }
            .width('100%')
          }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
          .borderRadius({
            bottomLeft: idx === appSettings.custom_uas.length - 1 ? 16 : 0,
            bottomRight: idx === appSettings.custom_uas.length - 1 ? 16 : 0
          })
          .swipeAction({
            end: {
              builder: (): void => {
                this.swipeEndBuilder(c)
              }
            }
          })
        }, (c: CustomUa) => c.id)
      } else {
        // 空提示
        ListItem() {
          Column() {
            Divider()
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16 })
            Text($r('app.string.ua_custom_empty_hint'))
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .fontFamily(appSettings.font_family)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 14 })
          }
          .width('100%')
        }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
          .borderRadius({ bottomLeft: 16, bottomRight: 16 })
        }

      // 分组头：高级
      ListItem() {
        Text($r('app.string.settings_advanced'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4, top: 18, bottom: 6 })
      }
      .width('100%')

      // 高级选项卡片
      ListItem() {
        Column() {
          CustomListItem({
            item: this.desktopItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 16 })
          CustomListItem({
            item: this.simplifyItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .margin({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(QhState.bottomRectHeight)
    .padding({ left: 16, right: 16 })
    .bindSheet(this.showDesktopPicker!!, this.desktopPickerBuilder(), {
      height: this.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showDesktopPicker = false
      }
    })
  }

  @Builder
  customUaMenu(c: CustomUa) {
    Menu() {
      MenuItem({ content: ResourceUtils.getString($r('app.string.edit')) })
        .onClick(() => {
          this.openEdit(c)
        })
      MenuItem({ content: ResourceUtils.getString($r('app.string.delete')) })
        .onClick(() => {
          this.confirmDeleteUa(c)
        })
    }
  }

  @Builder
  swipeEndBuilder(c: CustomUa) {
    Row({ space: 8 }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(16)
          .fontColor([Color.White])
        Text($r('app.string.edit'))
          .fontSize(13)
          .fontColor(Color.White)
      }
      .width(68)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor(QhState.currentThemeColor)
      .onClick(() => {
        this.openEdit(c)
      })

      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(16)
          .fontColor([Color.White])
        Text($r('app.string.delete'))
          .fontSize(13)
          .fontColor(Color.White)
      }
      .width(68)
      .height(52)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor('#E84026')
      .onClick(() => {
        this.confirmDeleteUa(c)
      })
    }
    .height(72)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  uaInputDialogContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: $r('app.string.ua_name_hint'), text: this.inputName })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.inputName = v
        })
      TextInput({ placeholder: $r('app.string.ua_value_hint'), text: this.inputUa })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.inputUa = v
        })
    }
    .width('100%')
  }

  @Builder
  desktopPickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showDesktopPicker = false
      }
    })
  }
}
