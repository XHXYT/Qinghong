import { QhState } from '../entryability/AppState';

/**
 * 底部半模态单选选择器的选项
 */
@ObservedV2
export class PickerOption {
  @Trace value: string = '';
  @Trace label: ResourceStr = '';

  constructor(value: string, label: ResourceStr) {
    this.value = value;
    this.label = label;
  }
}

/**
 * 选择器配置（标题/选项/当前选中值/选中回调）
 */
@ObservedV2
export class PickerConfig {
  @Trace title: ResourceStr = '';
  @Trace options: PickerOption[] = [];
  @Trace selected: string = '';
  onSelect?: (value: string) => void = undefined;
}

/**
 * 按选项数量计算 sheet 高度（拖拽条区 24 + 标题 48 + 选项 n*52 + 底部 12），
 * 选项超过 10 条时封顶（选项区内部滚动）
 */
export function pickerSheetHeight(optionCount: number): number {
  return 24 + 48 + Math.min(optionCount, 10) * 52 + 12;
}

/**
 * 底部半模态单选选择器（与菜单 sheet 同体系）
 */
@ComponentV2
export struct SheetPicker {
  @Require @Param config: PickerConfig;
  @Event close: () => void = () => {
  };

  build() {
    Column() {
      Text(this.config.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .height(48)
      // 选项超 10 条时内部滚动（高度与 pickerSheetHeight 封顶一致）
      Scroll() {
        Column() {
          Repeat<PickerOption>(this.config.options)
            .each((ri: RepeatItem<PickerOption>) => {
              Row() {
                Text(ri.item.label)
                  .fontSize(16)
                  .fontColor(this.config.selected === ri.item.value ? QhState.currentThemeColor : $r('sys.color.font_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.config.selected === ri.item.value) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor([QhState.currentThemeColor])
                }
              }
              .width('100%')
              .height(52)
              .padding({ left: 24, right: 24 })
              .onClick(() => {
                if (this.config.onSelect) {
                  this.config.onSelect(ri.item.value);
                }
                this.close();
              })
            })
            .key((opt: PickerOption) => opt.value)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 520 })
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
  }
}
