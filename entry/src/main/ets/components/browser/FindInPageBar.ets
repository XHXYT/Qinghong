import { QhState } from '../../entryability/AppState';
import { browserVM } from '../../viewmodel/BrowserViewModel';

/**
 * 页内查找栏（悬浮于工具栏上方）
 */
@ComponentV2
export struct FindInPageBar {
  @Local keyword: string = ''

  build() {
    Row({ space: 10 }) {
      TextInput({ text: this.keyword, placeholder: $r('app.string.find_hint') })
        .layoutWeight(1)
        .height(40)
        .fontSize(15)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .defaultFocus(true)
        .onChange((v: string) => {
          this.keyword = v
          browserVM.findInPage(v)
        })

      Text(browserVM.findTotal > 0 ?
        `${browserVM.findOrdinal + 1}/${browserVM.findTotal}` : $r('app.string.no_match'))
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))

      SymbolGlyph($r('sys.symbol.arrow_up_circle'))
        .fontSize(22)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => {
          browserVM.findJump(false)
        })

      SymbolGlyph($r('sys.symbol.arrow_down_circle'))
        .fontSize(22)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => {
          browserVM.findJump(true)
        })

      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(22)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => {
          browserVM.closeFind()
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 12, color: '#22000000' })
  }
}
