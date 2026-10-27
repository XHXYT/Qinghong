import { tabsVM, TabInfo } from '../../viewmodel/TabsViewModel';
import { HomeImmersive } from '../../common/utils/HomeImmersive';

/**
 * 标签栏：横向标签条（工具栏在上时紧随操作栏下一行，工具栏在下时置顶）
 */
@ComponentV2
export struct TabBar {

  @Builder
  tabChip(tab: TabInfo) {
    Row({ space: 5 }) {
      Text(tab.title)
        .fontSize(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 140 })
        .fontColor($r('sys.color.font_primary'))
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(11)
        .fontColor([$r('sys.color.font_secondary')])
        .onClick(() => {
          tabsVM.closeTab(tab.id)
        })
    }
    .height(26)
    .padding({ left: 10, right: 7 })
    .borderRadius(13)
    .backgroundColor(tabsVM.activeTabId === tab.id ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (tabsVM.hasTab(tab.id)) {
        tabsVM.switchTab(tab.id)
      }
    })
  }

  build() {
    Scroll() {
      Row({ space: 6 }) {
        Repeat<TabInfo>(tabsVM.tabs)
          .each((ri: RepeatItem<TabInfo>) => {
            this.tabChip(ri.item)
          })
          .key((tab: TabInfo) => tab.id.toString())

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(15)
          .fontColor([$r('sys.color.font_secondary')])
          .onClick(() => {
            tabsVM.newTab('')
          })
      }
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(27)
    .align(Alignment.Start)
    // 主页沉浸时背景透明，透出全屏主页背景层
    .backgroundColor(HomeImmersive.active() ? Color.Transparent
      : $r('sys.color.comp_background_primary'))
  }
}
