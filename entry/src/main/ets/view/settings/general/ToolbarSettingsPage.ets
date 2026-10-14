import { NaviContainer } from '../../../components/NaviContainer';
import { UISettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';

function toolbarLabel(v: string): ResourceStr {
  if (v === 'top') {
    return $r('app.string.toolbar_top');
  }
  return $r('app.string.toolbar_bottom');
}

@Builder
export function ToolbarSettingsBuilder() {
  ToolbarSettingsPage()
}

@ComponentV2
struct ToolbarSettingsPage {

  @Local items: CustomItemInfo[] = []
  @Local picker: PickerConfig = new PickerConfig()
  @Local showPicker: boolean = false
  @Local pickerHeight: number = pickerSheetHeight(2)

  aboutToAppear(): void {
    this.items = [
      new CustomItemInfo({
        id: 'toolbar_position',
        title: $r('app.string.toolbar_position'),
        type: ItemActionType.TEXT,
        value: ResourceUtils.getString(toolbarLabel(UISettings.toolbar_position)),
        onChange: (v: string | boolean | number): void => {
          this.openPositionPicker()
        }
      })
    ]
  }

  private openPositionPicker(): void {
    this.picker.title = $r('app.string.toolbar_position')
    this.picker.options = [
      new PickerOption('bottom', $r('app.string.toolbar_bottom')),
      new PickerOption('top', $r('app.string.toolbar_top'))
    ]
    this.picker.selected = UISettings.toolbar_position
    this.picker.onSelect = (v: string): void => {
      UISettings.toolbar_position = v
      this.items[0].value = ResourceUtils.getString(toolbarLabel(v))
    }
    this.pickerHeight = pickerSheetHeight(this.picker.options.length)
    this.showPicker = true
  }

  build() {
    NaviContainer({
      title: $r('app.string.toolbar_settings'),
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
