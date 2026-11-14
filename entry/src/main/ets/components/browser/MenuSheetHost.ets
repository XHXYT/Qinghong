import { QhState } from '../../entryability/AppState';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { SheetPicker } from '../SheetPicker';

/**
 * 菜单半模态根层宿主：浏览器标识/图片显示模式/字号缩放/保存网页等选择 sheet 统一挂载。
 * 原先挂在 Toolbar / MergedActionBar 上——栏组件随布局模式或隐藏状态卸载后 sheet 无宿主弹不出；
 * 挂 Index 根层后不依赖任何栏组件常驻。宽屏（widthBp > 1）以 CENTER 居中弹窗形态展示。
 */
@ComponentV2
export struct MenuSheetHost {

  build() {
    Column()
      .width(0)
      .height(0)
      .bindSheet(menuVM.showSheet!!, this.sheetBuilder(), {
        height: menuVM.sheetKind === 'font' ? 172 : (menuVM.sheetKind === 'save' ? 252 : menuVM.pickerHeight),
        preferType: SheetType.CENTER,
        dragBar: true,
        showClose: false,
        backgroundColor: $r('sys.color.comp_background_primary'),
        onDisappear: (): void => {
          menuVM.showSheet = false
        }
      })
  }

  /** 半模态内容：选择器、字号滑杆或保存网页（menuVM.sheetKind 决定） */
  @Builder
  sheetBuilder() {
    if (menuVM.sheetKind === 'font') {
      Column() {
        Row() {
          Text($r('app.string.font_size'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Text(`${menuVM.fontZoomValue}%`)
            .fontSize(16)
            .fontColor(QhState.currentThemeColor)
        }
        .width('100%')
        .height(48)
        Slider({ value: menuVM.fontZoomValue, min: 50, max: 200, step: 5, style: SliderStyle.InSet })
          .selectedColor(QhState.currentThemeColor)
          .width('100%')
          .margin({ top: 8, bottom: 12 })
          .onChange((value: number, mode: SliderChangeMode) => {
            menuVM.applyFontZoom(value)
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              menuVM.persistFontZoom()
            }
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 8 })
    } else if (menuVM.sheetKind === 'save') {
      this.saveSheetContent()
    } else {
      SheetPicker({
        config: menuVM.picker,
        close: (): void => {
          menuVM.showSheet = false
        }
      })
    }
  }

  /** 保存网页弹窗：名称输入 + 保存为PDF 勾选 + 操作按钮（标题与 SheetPicker 同款居中样式） */
  @Builder
  saveSheetContent() {
    Column() {
      Text($r('app.string.save_dialog_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .height(48)
      Column({ space: 12 }) {
        TextInput({ text: menuVM.saveName })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onChange((v: string) => {
            menuVM.saveName = v
          })
        Row({ space: 8 }) {
          Checkbox()
            .select(menuVM.saveAsPdf)
            .selectedColor(QhState.currentThemeColor)
            .onChange((v: boolean) => {
              menuVM.saveAsPdf = v
            })
          Text($r('app.string.save_as_pdf'))
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
        }
        .width('100%')
        Row({ space: 12 }) {
          Button($r('app.string.cancel'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              menuVM.showSheet = false
            })
          Button($r('app.string.save'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(QhState.currentThemeColor)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              menuVM.confirmSave()
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 20 })
    }
    .width('100%')
  }
}
