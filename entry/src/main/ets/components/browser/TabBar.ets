import { tabsVM, TabInfo } from '../../viewmodel/TabsViewModel';
import { HomeImmersive } from '../../common/utils/HomeImmersive';
import { homeBg } from '../../common/utils/HomeBg';
import { ActionBarColor } from '../../common/utils/ActionBarColor';

/**
 * 标签栏：横向标签条（工具栏在上时紧随操作栏下一行，工具栏在下时置顶）
 */
@ComponentV2
export struct TabBar {

  /** 芯片底色：主页沉浸暗背景用浅色半透明（白字可读），其余用通用底 */
  private chipBg(selected: boolean): ResourceColor {
    if (!selected) {
      return Color.Transparent
    }
    if (HomeImmersive.active() && homeBg.dark) {
      return 'rgba(255,255,255,0.18)'
    }
    return $r('sys.color.comp_background_tertiary')
  }

  @Builder
  tabChip(tab: TabInfo) {
    Row({ space: 5 }) {
      Text(tab.title)
        .fontSize(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 140 })
        .fontColor(ActionBarColor.fg($r('sys.color.font_primary')))
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(11)
        .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'))])
        .onClick(() => {
          tabsVM.closeTab(tab.id)
        })
    }
    .height(26)
    .padding({ left: 10, right: 7 })
    .borderRadius(13)
    .backgroundColor(this.chipBg(tabsVM.activeTabId === tab.id))
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
          .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'))])
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
