import { SettingsScaffold, SettingsSection } from '../../../components/SettingsScaffold';
import { UISettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';


@Builder
export function ToolbarSettingsBuilder() {
  ToolbarSettingsPage()
}

function layoutLabel(v: string): ResourceStr {
  if (v === 'top') {
    return $r('app.string.layout_toolbar_top')
  }
  if (v === 'bottom') {
    return $r('app.string.layout_toolbar_bottom')
  }
  if (v === 'bottom_double') {
    return $r('app.string.layout_bottom_double')
  }
  return $r('app.string.layout_traditional')
}

function hideLabel(v: string): ResourceStr {
  if (v === 'slide') {
    return $r('app.string.auto_hide_slide')
  }
  if (v === 'tap') {
    return $r('app.string.auto_hide_tap')
  }
  return $r('app.string.auto_hide_always')
}

function contentLabel(v: string): ResourceStr {
  if (v === 'title') {
    return $r('app.string.address_content_title')
  }
  if (v === 'url') {
    return $r('app.string.address_content_url')
  }
  return $r('app.string.address_content_domain')
}

@ComponentV2
struct ToolbarSettingsPage {

  @Local items: CustomItemInfo[] = []
  @Local sections: SettingsSection[] = []
  @Local picker: PickerConfig = new PickerConfig()
  @Local showPicker: boolean = false
  @Local pickerHeight: number = pickerSheetHeight(2)

  aboutToAppear(): void {
    this.buildItems()
  }

  /** 按当前布局构建设置行：同类相邻——布局/隐藏/地址栏在前，合并布局的栏与按钮开关次之，外观在后 */
  private buildItems(): void {
    const items: CustomItemInfo[] = [
      new CustomItemInfo({
        id: 'app_layout',
        title: $r('app.string.app_layout'),
        type: ItemActionType.TEXT,
        value: ResourceUtils.getString(layoutLabel(UISettings.app_layout)),
        onChange: (v: string | boolean | number): void => {
          this.openLayoutPicker()
        }
      }),
      new CustomItemInfo({
        id: 'auto_hide_action_bar',
        title: $r('app.string.auto_hide_action_bar'),
        type: ItemActionType.TEXT,
        value: ResourceUtils.getString(hideLabel(UISettings.auto_hide_action_bar)),
        onChange: (v: string | boolean | number): void => {
          this.openHidePicker()
        }
      }),
      new CustomItemInfo({
        id: 'address_bar_content',
        title: $r('app.string.address_bar_content'),
        type: ItemActionType.TEXT,
        value: ResourceUtils.getString(contentLabel(UISettings.address_bar_content)),
        onChange: (v: string | boolean | number): void => {
          this.openContentPicker()
        }
      })
    ]
    if (UISettings.app_layout === 'top' || UISettings.app_layout === 'bottom') {
      items.push(new CustomItemInfo({
        id: 'show_tab_bar',
        title: $r('app.string.tab_bar'),
        type: ItemActionType.TOGGLE,
        value: UISettings.show_tab_bar,
        onChange: (v: string | boolean | number): void => {
          UISettings.show_tab_bar = v === true
        }
      }))
      items.push(new CustomItemInfo({
        id: 'show_bookmark_bar',
        title: $r('app.string.bookmark_bar'),
        type: ItemActionType.TOGGLE,
        value: UISettings.show_bookmark_bar,
        onChange: (v: string | boolean | number): void => {
          UISettings.show_bookmark_bar = v === true
        }
      }))
      items.push(new CustomItemInfo({
        id: 'show_home_button',
        title: $r('app.string.home_button'),
        type: ItemActionType.TOGGLE,
        value: UISettings.show_home_button,
        onChange: (v: string | boolean | number): void => {
          UISettings.show_home_button = v === true
        }
      }))
      items.push(new CustomItemInfo({
        id: 'show_download_button',
        title: $r('app.string.download_button'),
        type: ItemActionType.TOGGLE,
        value: UISettings.show_download_button,
        onChange: (v: string | boolean | number): void => {
          UISettings.show_download_button = v === true
        }
      }))
    }
    items.push(new CustomItemInfo({
      id: 'action_bar_color_mode',
      title: $r('app.string.action_bar_color_mode'),
      subtitle: $r('app.string.action_bar_color_mode_desc'),
      type: ItemActionType.TOGGLE,
      value: UISettings.action_bar_color_mode,
      onChange: (v: string | boolean | number): void => {
        UISettings.action_bar_color_mode = v === true
      }
    }))
    this.items = items
    const section: SettingsSection = new SettingsSection('toolbar_items')
    section.items = items
    section.topMargin = 12
    this.sections = [section]
  }

  private setItemValue(id: string, value: string | boolean | number): void {
    for (const it of this.items) {
      if (it.id === id) {
        it.value = value
        return
      }
    }
  }

  /** 应用布局并联动刷新设置行（追加/移除合并布局专属开关） */
  private applyLayout(layout: string): void {
    UISettings.app_layout = layout
    this.buildItems()
  }

  private openLayoutPicker(): void {
    this.picker.title = $r('app.string.app_layout')
    this.picker.options = [
      new PickerOption('traditional', $r('app.string.layout_traditional')),
      new PickerOption('top', $r('app.string.layout_toolbar_top')),
      new PickerOption('bottom', $r('app.string.layout_toolbar_bottom')),
      new PickerOption('bottom_double', $r('app.string.layout_bottom_double'))
    ]
    this.picker.selected = UISettings.app_layout
    this.picker.onSelect = (v: string): void => {
      this.applyLayout(v)
    }
    this.pickerHeight = pickerSheetHeight(this.picker.options.length)
    this.showPicker = true
  }

  private openHidePicker(): void {
    this.picker.title = $r('app.string.auto_hide_action_bar')
    this.picker.options = [
      new PickerOption('always', $r('app.string.auto_hide_always')),
      new PickerOption('slide', $r('app.string.auto_hide_slide')),
      new PickerOption('tap', $r('app.string.auto_hide_tap'))
    ]
    this.picker.selected = UISettings.auto_hide_action_bar
    this.picker.onSelect = (v: string): void => {
      UISettings.auto_hide_action_bar = v
      this.setItemValue('auto_hide_action_bar', ResourceUtils.getString(hideLabel(v)))
    }
    this.pickerHeight = pickerSheetHeight(this.picker.options.length)
    this.showPicker = true
  }

  private openContentPicker(): void {
    this.picker.title = $r('app.string.address_bar_content')
    this.picker.options = [
      new PickerOption('domain', $r('app.string.address_content_domain')),
      new PickerOption('url', $r('app.string.address_content_url')),
      new PickerOption('title', $r('app.string.address_content_title'))
    ]
    this.picker.selected = UISettings.address_bar_content
    this.picker.onSelect = (v: string): void => {
      UISettings.address_bar_content = v
      this.setItemValue('address_bar_content', ResourceUtils.getString(contentLabel(v)))
    }
    this.pickerHeight = pickerSheetHeight(this.picker.options.length)
    this.showPicker = true
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.toolbar_settings'),
      sections: this.sections,
      header: (): void => {
        this.previewBox()
      }
    })
  }

  /** 布局预览迷你元素（真实图标渲染） */
  @Builder
  miniTextLine(widthV: Length) {
    Row()
      .width(widthV)
      .height(6)
      .borderRadius(3)
      .backgroundColor($r('sys.color.comp_divider'))
  }

  @Builder
  miniTabCountBox() {
    Text('2')
      .fontSize(7)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .textAlign(TextAlign.Center)
      .width(10)
      .height(10)
      .border({ width: 1, color: $r('sys.color.font_primary'), radius: 2 })
  }

  @Builder
  miniAddressBar() {
    Row({ space: 5 }) {
      SymbolGlyph($r('sys.symbol.lock'))
        .fontSize(10)
        .fontColor([$r('sys.color.font_secondary')])
      this.miniTextLine(60)
    }
    .width('100%')
    .height(18)
    .padding({ left: 8 })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  miniToolbar() {
    Row({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_tertiary')])
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_tertiary')])
      SymbolGlyph($r('sys.symbol.house'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_primary')])
      this.miniTabCountBox()
      SymbolGlyph($r('sys.symbol.square_grid_2x2'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_primary')])
    }
    .width('100%')
    .height(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  miniMergedBar() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_tertiary')])
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_tertiary')])
      if (UISettings.show_home_button) {
        SymbolGlyph($r('sys.symbol.house'))
          .fontSize(12)
          .fontColor([$r('sys.color.font_primary')])
      }
      // 地址胶囊
      Row({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(8)
          .fontColor([$r('sys.color.font_secondary')])
        Row()
          .layoutWeight(1)
          .height(5)
          .borderRadius(2.5)
          .backgroundColor($r('sys.color.comp_divider'))
      }
      .layoutWeight(1)
      .height(14)
      .padding({ left: 6, right: 6 })
      .borderRadius(7)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .alignItems(VerticalAlign.Center)
      if (UISettings.show_download_button) {
        SymbolGlyph($r('sys.symbol.arrow_down_circle'))
          .fontSize(12)
          .fontColor([$r('sys.color.font_primary')])
      }
      if (!UISettings.show_tab_bar) {
        this.miniTabCountBox()
      }
      SymbolGlyph($r('sys.symbol.square_grid_2x2'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_primary')])
    }
    .width('100%')
    .height(20)
    .padding({ left: 6, right: 6 })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  miniTabChip(active: boolean) {
    Row({ space: 3 }) {
      this.miniTextLine(16)
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(8)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .height(12)
    .padding({ left: 5, right: 4 })
    .borderRadius(6)
    .backgroundColor(active ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  miniTabBar() {
    Row({ space: 4 }) {
      this.miniTabChip(true)
      this.miniTabChip(false)
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(10)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width('100%')
    .height(16)
    .padding({ left: 5 })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  miniFolderChip() {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(8)
        .fontColor([$r('sys.color.font_secondary')])
      this.miniTextLine(12)
    }
    .height(12)
    .padding({ left: 5, right: 5 })
    .borderRadius(6)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  miniBookmarkChip() {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.star'))
        .fontSize(8)
        .fontColor([$r('sys.color.font_secondary')])
      this.miniTextLine(14)
    }
    .height(12)
    .padding({ left: 5, right: 5 })
    .borderRadius(6)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  miniBookmarkBar() {
    Row({ space: 4 }) {
      this.miniFolderChip()
      this.miniBookmarkChip()
      this.miniBookmarkChip()
    }
    .width('100%')
    .height(14)
    .padding({ left: 5 })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .alignItems(VerticalAlign.Center)
  }

  /** 页面内容占位示意（文字行） */
  @Builder
  miniContent() {
    Column({ space: 6 }) {
      Row()
        .width('65%')
        .height(7)
        .borderRadius(3.5)
        .backgroundColor($r('sys.color.comp_background_primary'))
      Row()
        .width('45%')
        .height(7)
        .borderRadius(3.5)
        .backgroundColor($r('sys.color.comp_background_primary'))
      Row()
        .width('55%')
        .height(7)
        .borderRadius(3.5)
        .backgroundColor($r('sys.color.comp_background_primary'))
    }
    .layoutWeight(1)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, top: 12 })
  }

  /** 预览方框：按当前布局/标签栏/书签栏/按钮开关实时渲染迷你操作栏示意 */
  @Builder
  previewBox() {
    Column() {
      Column() {
        if (UISettings.app_layout === 'traditional') {
          this.miniAddressBar()
          this.miniContent()
          this.miniToolbar()
        } else if (UISettings.app_layout === 'top') {
          if (UISettings.show_tab_bar) {
            this.miniTabBar()
          }
          this.miniMergedBar()
          if (UISettings.show_bookmark_bar) {
            this.miniBookmarkBar()
          }
          this.miniContent()
        } else if (UISettings.app_layout === 'bottom') {
          this.miniContent()
          if (UISettings.show_bookmark_bar) {
            this.miniBookmarkBar()
          }
          if (UISettings.show_tab_bar) {
            this.miniTabBar()
          }
          this.miniMergedBar()
        } else {
          this.miniContent()
          this.miniAddressBar()
          this.miniToolbar()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(12)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .clip(true)
    }
    .width('100%')
    .height(180)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.background_color'))
    .margin({ top: 10 })
    .bindSheet(this.showPicker!!, this.pickerBuilder(), {
      height: this.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showPicker = false
      }
    })
  }

  @Builder
  pickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showPicker = false
      }
    })
  }
}
