import { ConfigurationConstant } from '@kit.AbilityKit';
import { SettingsScaffold, SettingsSection } from '../../../components/SettingsScaffold';
import { appSettings, UISettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { SettingsUtils } from '../../../common/utils/app/SettingsUtils';
import { ResourceUtils } from '../../../common/utils/app/ResourceUtil';

function themeModeKey(mode: ConfigurationConstant.ColorMode): string {
  if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
    return 'light'
  }
  if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
    return 'dark'
  }
  return 'system'
}

function themeModeLabel(mode: ConfigurationConstant.ColorMode): ResourceStr {
  if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
    return $r('app.string.night_theme_light')
  }
  if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
    return $r('app.string.night_theme_dark')
  }
  return $r('app.string.night_theme_follow_system')
}

function applyThemeMode(key: string): void {
  let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  if (key === 'light') {
    mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
  } else if (key === 'dark') {
    mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK
  }
  UISettings.color_mode = mode
  SettingsUtils.setColorMode()
}

@Builder
export function SettingsNightModeBuilder() {
  NightModePage()
}

@ComponentV2
struct NightModePage {

  @Local groups: SettingsSection[] = []
  @Local picker: PickerConfig = new PickerConfig()
  /** 半模态类型 'theme' 主题选择器 | 'mask' 蒙版滤镜配置 */
  @Local sheetType: string = ''
  @Local showSheet: boolean = false

  aboutToAppear(): void {
    this.buildItems()
  }

  private textItem(id: string, title: ResourceStr, subtitle: ResourceStr | undefined, value: string,
    onClick: () => void): CustomItemInfo {
    return new CustomItemInfo({
      id: id,
      title: title,
      subtitle: subtitle,
      type: ItemActionType.TEXT,
      value: value,
      onChange: (v: string | boolean | number): void => {
        onClick()
      }
    })
  }

  private setItemValue(id: string, v: string): void {
    for (const group of this.groups) {
      for (const item of group.items) {
        if (item.id === id) {
          item.value = v
          return
        }
      }
    }
  }

  private buildItems(): void {
    const groups: SettingsSection[] = []

    const gAppearance = new SettingsSection('appearance', $r('app.string.night_group_appearance'))
    gAppearance.items.push(this.textItem('theme_mode', $r('app.string.night_theme_mode'), undefined,
      ResourceUtils.getString(themeModeLabel(UISettings.color_mode)), (): void => {
        this.openThemePicker()
      }))
    groups.push(gAppearance)

    const gWeb = new SettingsSection('web', $r('app.string.night_group_web'))
    gWeb.items.push(this.textItem('night_mask', $r('app.string.night_mask_filter'),
      $r('app.string.night_mask_filter_desc'), this.maskSummary(), (): void => {
        this.sheetType = 'mask'
        this.showSheet = true
      }))
    gWeb.items.push(new CustomItemInfo({
      id: 'force_dark_web',
      title: $r('app.string.force_dark_web'),
      subtitle: $r('app.string.force_dark_web_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.force_dark_web,
      onChange: (v: string | boolean | number): void => {
        appSettings.force_dark_web = v as boolean
      }
    }))
    groups.push(gWeb)

    this.groups = groups
  }

  private openThemePicker(): void {
    this.picker.title = $r('app.string.night_theme_mode')
    this.picker.options = [
      new PickerOption('system', $r('app.string.night_theme_follow_system')),
      new PickerOption('light', $r('app.string.night_theme_light')),
      new PickerOption('dark', $r('app.string.night_theme_dark'))
    ]
    this.picker.selected = themeModeKey(UISettings.color_mode)
    this.picker.onSelect = (v: string): void => {
      applyThemeMode(v)
      this.setItemValue('theme_mode', ResourceUtils.getString(themeModeLabel(UISettings.color_mode)))
    }
    this.sheetType = 'theme'
    this.showSheet = true
  }

  private maskSummary(): string {
    if (!appSettings.night_mask_enabled) {
      return ResourceUtils.getString($r('app.string.night_mask_off'))
    }
    const color: ResourceStr = appSettings.night_mask_color === 'amber'
      ? $r('app.string.night_mask_color_amber')
      : $r('app.string.night_mask_color_black')
    return `${ResourceUtils.getString(color)} · ${appSettings.night_mask_opacity}%`
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.night_mode'),
      sections: this.groups,
      footer: (): void => {
        this.pageFooter()
      }
    })
  }

  /** 列表末尾锚点：挂载半模态 bindSheet */
  @Builder
  pageFooter() {
    Row()
      .height(1)
      .width('100%')
      .bindSheet(this.showSheet!!, this.sheetContent(), {
        preferType: SheetType.CENTER,
        height: this.sheetType === 'mask' ? 500 : pickerSheetHeight(3),
        dragBar: true,
        showClose: false,
        backgroundColor: $r('sys.color.comp_background_primary'),
        onDisappear: (): void => {
          this.showSheet = false
          if (this.sheetType === 'mask') {
            this.setItemValue('night_mask', this.maskSummary())
          }
        }
      })
  }

  @Builder
  sheetContent() {
    if (this.sheetType === 'theme') {
      SheetPicker({
        config: this.picker,
        close: (): void => {
          this.showSheet = false
        }
      })
    } else if (this.sheetType === 'mask') {
      this.maskSheetBody()
    }
  }

  @Builder
  maskSheetBody() {
    Column() {
      Text($r('app.string.night_mask_filter'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 8, bottom: 12 })

      Column({ space: 16 }) {
        // 开启滤镜（整行可点击）
        Row() {
          Text($r('app.string.night_mask_enable'))
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: appSettings.night_mask_enabled })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(48)
        .onClick(() => {
          appSettings.night_mask_enabled = !appSettings.night_mask_enabled
        })

        // 效果预览
        Column({ space: 8 }) {
          Text($r('app.string.night_mask_preview'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
          Stack() {
            // 模拟网页内容
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                Column()
                  .width(28)
                  .height(28)
                  .borderRadius(14)
                  .backgroundColor($r('app.color.night_preview_accent'))
                Column()
                  .width(120)
                  .height(14)
                  .borderRadius(7)
                  .backgroundColor($r('app.color.night_preview_title'))
              }
              .width('100%')

              Column()
                .width('70%')
                .height(10)
                .borderRadius(5)
                .backgroundColor($r('app.color.night_preview_text'))
              Column()
                .width('88%')
                .height(10)
                .borderRadius(5)
                .backgroundColor($r('app.color.night_preview_text'))
              Column()
                .width('45%')
                .height(10)
                .borderRadius(5)
                .backgroundColor($r('app.color.night_preview_text'))

              Row({ space: 10 }) {
                Column()
                  .layoutWeight(1)
                  .height(34)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.night_preview_block'))
                Column()
                  .layoutWeight(1)
                  .height(34)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.night_preview_block'))
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .padding(14)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor($r('app.color.night_preview_bg'))

            // 蒙版层
            if (appSettings.night_mask_enabled) {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(appSettings.maskColorHex())
                .opacity(appSettings.night_mask_opacity / 100)
                .hitTestBehavior(HitTestMode.None)
            }
          }
          .width('100%')
          .height(150)
          .borderRadius(12)
          .clip(true)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 不透明度滑动条
        Column({ space: 4 }) {
          Row() {
            Text($r('app.string.night_mask_opacity'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .layoutWeight(1)
            Text(`${appSettings.night_mask_opacity}%`)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
          }
          .width('100%')
          Slider({
            value: appSettings.night_mask_opacity,
            min: 5,
            max: 90,
            step: 5,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .enabled(appSettings.night_mask_enabled)
            .selectedColor(appSettings.maskColorHex())
            .blockColor(appSettings.maskColorHex())
            .onChange((v: number): void => {
              appSettings.night_mask_opacity = Math.round(v)
            })
        }
        .width('100%')
        .enabled(appSettings.night_mask_enabled)
        .opacity(appSettings.night_mask_enabled ? 1 : 0.4)

        // 滤镜颜色
        Column({ space: 8 }) {
          Text($r('app.string.night_mask_color'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
          Row({ space: 12 }) {
            Row({ space: 8 }) {
              Column()
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor('#000000')
              Text($r('app.string.night_mask_color_black'))
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
            }
            .padding({ left: 14, right: 16, top: 10, bottom: 10 })
            .borderRadius(22)
            .backgroundColor(appSettings.night_mask_color === 'black'
              ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
            .onClick(() => {
              appSettings.night_mask_color = 'black'
            })

            Row({ space: 8 }) {
              Column()
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(appSettings.maskColorHex())
              Text($r('app.string.night_mask_color_amber'))
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
            }
            .padding({ left: 14, right: 16, top: 10, bottom: 10 })
            .borderRadius(22)
            .backgroundColor(appSettings.night_mask_color === 'amber'
              ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
            .onClick(() => {
              appSettings.night_mask_color = 'amber'
            })
          }
          .width('100%')
        }
        .width('100%')
        .enabled(appSettings.night_mask_enabled)
        .opacity(appSettings.night_mask_enabled ? 1 : 0.4)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }
}
