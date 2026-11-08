import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer } from '../../../components/NaviContainer';
import { appSettings } from '../../../common/entity/SettingsModel';
import { QhState } from '../../../entryability/AppState';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ui/ToastUtils';
import { ResourceUtils } from '../../../common/utils/app/ResourceUtil';
import { ReadModeCssStore } from '../../../common/utils/storage/ReadModeCssStore';

/**
 * 阅读模式背景色预设
 */
class BgPreset {
  readonly key: string
  label: ResourceStr
  readonly hex: string

  constructor(key: string, label: ResourceStr, hex: string) {
    this.key = key
    this.label = label
    this.hex = hex
  }
}

const BG_PRESETS: BgPreset[] = [
  new BgPreset('paper', $r('app.string.read_mode_bg_paper'), '#F6F1E7'),
  new BgPreset('green', $r('app.string.read_mode_bg_green'), '#C7EDCC'),
  new BgPreset('white', $r('app.string.read_mode_bg_white'), '#FFFFFF'),
  new BgPreset('black', $r('app.string.read_mode_bg_black'), '#1C1C1C')
]

function isDarkColor(hex: string): boolean {
  const r: number = parseInt(hex.substring(1, 3), 16)
  const g: number = parseInt(hex.substring(3, 5), 16)
  const b: number = parseInt(hex.substring(5, 7), 16)
  return (r * 0.299 + g * 0.587 + b * 0.114) < 140
}

function readModeTextHex(): string {
  return isDarkColor(appSettings.readModeBgHex()) ? '#EAEAEA' : '#3A3A3A'
}

function isValidHexColor(s: string): boolean {
  if (s.length !== 7 || s.charAt(0) !== '#') {
    return false
  }
  for (let i = 1; i < 7; i++) {
    const c: string = s.charAt(i)
    const ok: boolean = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    if (!ok) {
      return false
    }
  }
  return true
}

function cssSummary(): string {
  return ReadModeCssStore.load().trim() !== ''
    ? ResourceUtils.getString($r('app.string.read_mode_css_set'))
    : ResourceUtils.getString($r('app.string.read_mode_css_empty'))
}

@Builder
export function SettingsReadModeBuilder() {
  ReadModePage()
}

@ComponentV2
struct ReadModePage {

  @Local buttonItem: CustomItemInfo = new CustomItemInfo({
    id: 'read_mode_address_button',
    title: $r('app.string.read_mode_address_button'),
    subtitle: $r('app.string.read_mode_address_button_desc'),
    type: ItemActionType.TOGGLE,
    value: true
  })
  @Local confirmItem: CustomItemInfo = new CustomItemInfo({
    id: 'read_mode_confirm',
    title: $r('app.string.read_mode_confirm'),
    subtitle: $r('app.string.read_mode_confirm_desc'),
    type: ItemActionType.TOGGLE,
    value: true
  })
  @Local cssItem: CustomItemInfo = new CustomItemInfo({
    id: 'read_mode_css',
    title: $r('app.string.read_mode_css'),
    type: ItemActionType.TEXT,
    value: ''
  })

  @Local showCssSheet: boolean = false
  @Local cssDraft: string = ''
  @Local customColorDraft: string = ''

  private customColorDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.buttonItem = new CustomItemInfo({
      id: 'read_mode_address_button',
      title: $r('app.string.read_mode_address_button'),
      subtitle: $r('app.string.read_mode_address_button_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.read_mode_address_button,
      onChange: (v: string | boolean | number): void => {
        appSettings.read_mode_address_button = v as boolean
      }
    })
    this.confirmItem = new CustomItemInfo({
      id: 'read_mode_confirm',
      title: $r('app.string.read_mode_confirm'),
      subtitle: $r('app.string.read_mode_confirm_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.read_mode_confirm,
      onChange: (v: string | boolean | number): void => {
        appSettings.read_mode_confirm = v as boolean
      }
    })
    this.cssItem = new CustomItemInfo({
      id: 'read_mode_css',
      title: $r('app.string.read_mode_css'),
      subtitle: $r('app.string.read_mode_css_desc'),
      type: ItemActionType.TEXT,
      value: cssSummary(),
      onChange: (v: string | boolean | number): void => {
        this.cssDraft = ReadModeCssStore.load()
        this.showCssSheet = true
      }
    })
    this.initDialogs()
  }

  private initDialogs(): void {
    this.customColorDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.read_mode_custom_color_title'),
        contentBuilder: (): void => {
          this.customColorContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], false,
          (index: number): void => {
            if (index === 1) {
              const color: string = this.customColorDraft.trim()
              if (!isValidHexColor(color)) {
                toastUtil.showToast({ message: $r('app.string.read_mode_invalid_color') })
                return
              }
              appSettings.read_mode_custom_bg = color
              appSettings.read_mode_bg_color = 'custom'
            }
            this.customColorDialog?.close()
          }),
        contentAreaPadding: { top: 16, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.customColorDraft = appSettings.read_mode_bg_color === 'custom'
          ? appSettings.read_mode_custom_bg : ''
      }
    })
  }

  build() {
    NaviContainer({
      title: $r('app.string.read_mode'),
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
      // 交互
      ListItem() {
        Column() {
          Text($r('app.string.read_group_interaction'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ left: 4, bottom: 6, top: 10 })
          Column() {
            CustomListItem({
              item: this.buttonItem,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
            CustomListItem({
              item: this.confirmItem,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor($r('app.color.background_color'))
          .clip(true)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 外观
      ListItem() {
        Column() {
          Text($r('app.string.read_group_appearance'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ left: 4, bottom: 6, top: 18 })
          Column() {
            this.appearanceContent()
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor($r('app.color.background_color'))
          .clip(true)
          .padding(16)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      // 高级
      ListItem() {
        Column() {
          Text($r('app.string.read_group_advanced'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ left: 4, bottom: 6, top: 18 })
          Column() {
            CustomListItem({
              item: this.cssItem,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor($r('app.color.background_color'))
          .clip(true)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(56)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
    .bindSheet(this.showCssSheet!!, this.cssSheetContent(), {
      preferType: SheetType.CENTER,
      height: 430,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showCssSheet = false
        this.cssItem.value = cssSummary()
      }
    })
  }

  @Builder
  appearanceContent() {
    Column({ space: 20 }) {
      // 背景色
      Column({ space: 12 }) {
        Text($r('app.string.read_mode_bg_color'))
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
        Row({ space: 16 }) {
          ForEach(BG_PRESETS, (preset: BgPreset) => {
            this.bgSwatch(preset)
          }, (preset: BgPreset) => preset.key)
          this.customSwatch()
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 字体大小
      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.read_mode_font_size'))
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Text(`${appSettings.read_mode_font_size}`)
            .fontSize(15)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        Slider({
          value: appSettings.read_mode_font_size,
          min: 12,
          max: 28,
          step: 1,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .selectedColor(QhState.currentThemeColor)
          .blockColor(QhState.currentThemeColor)
          .onChange((v: number): void => {
            appSettings.read_mode_font_size = Math.round(v)
          })
      }
      .width('100%')

      // 衬线字体（整行点击切换）
      Row() {
        Text($r('app.string.read_mode_serif'))
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: appSettings.read_mode_serif })
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .onClick(() => {
        appSettings.read_mode_serif = !appSettings.read_mode_serif
      })

      // 预览
      Column({ space: 8 }) {
        Text($r('app.string.read_mode_preview'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
        Column({ space: 10 }) {
          Text($r('app.string.read_mode_preview_title'))
            .fontSize(appSettings.read_mode_font_size + 4)
            .fontWeight(FontWeight.Bold)
            .fontColor(readModeTextHex())
          Text($r('app.string.read_mode_preview_text'))
            .fontSize(appSettings.read_mode_font_size)
            .fontColor(readModeTextHex())
            .lineHeight(appSettings.read_mode_font_size * 1.8)
        }
        .width('100%')
        .padding(16)
        .borderRadius(12)
        .backgroundColor(appSettings.readModeBgHex())
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  bgSwatch(preset: BgPreset) {
    Column({ space: 6 }) {
      Column()
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(preset.hex)
        .border({
          width: appSettings.read_mode_bg_color === preset.key ? 2 : 1,
          color: appSettings.read_mode_bg_color === preset.key
            ? QhState.currentThemeColor : $r('sys.color.comp_divider')
        })
      Text(preset.label)
        .fontSize(11)
        .fontColor(appSettings.read_mode_bg_color === preset.key
          ? QhState.currentThemeColor : $r('sys.color.font_secondary'))
    }
    .onClick(() => {
      appSettings.read_mode_bg_color = preset.key
    })
  }

  @Builder
  customSwatch() {
    Column({ space: 6 }) {
      Column()
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(appSettings.read_mode_custom_bg)
        .border({
          width: appSettings.read_mode_bg_color === 'custom' ? 2 : 1,
          color: appSettings.read_mode_bg_color === 'custom'
            ? QhState.currentThemeColor : $r('sys.color.comp_divider')
        })
      Text($r('app.string.read_mode_bg_custom'))
        .fontSize(11)
        .fontColor(appSettings.read_mode_bg_color === 'custom'
          ? QhState.currentThemeColor : $r('sys.color.font_secondary'))
    }
    .onClick(() => {
      this.customColorDraft = appSettings.read_mode_bg_color === 'custom'
        ? appSettings.read_mode_custom_bg : ''
      this.customColorDialog?.open()
    })
  }

  @Builder
  customColorContent() {
    Row({ space: 12 }) {
      Column()
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(isValidHexColor(this.customColorDraft.trim())
          ? this.customColorDraft.trim() : $r('sys.color.comp_background_secondary'))
        .border({ width: 1, color: $r('sys.color.comp_divider') })
      TextInput({ text: this.customColorDraft, placeholder: '#F2E8D5' })
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .onChange((v: string): void => {
          this.customColorDraft = v
        })
    }
    .width('100%')
  }

  @Builder
  cssSheetContent() {
    Column() {
      Text($r('app.string.read_mode_css'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 8, bottom: 12 })

      Column({ space: 14 }) {
        TextArea({ text: this.cssDraft, placeholder: $r('app.string.read_mode_css_hint') })
          .width('100%')
          .height(220)
          .fontSize(13)
          .fontFamily('monospace')
          .textAlign(TextAlign.Start)
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .borderRadius(12)
          .onChange((v: string): void => {
            this.cssDraft = v
          })

        Text($r('app.string.read_mode_css_apply_hint'))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))

        Button($r('app.string.save'))
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .width('100%')
          .onClick(() => {
            ReadModeCssStore.save(this.cssDraft)
            this.cssItem.value = cssSummary()
            this.showCssSheet = false
            toastUtil.showToast({ message: $r('app.string.saved') })
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }
}
