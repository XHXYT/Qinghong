import { QhState } from '../../entryability/AppState';
import { tabsVM, TabInfo } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { TabSwitcherColumns, gridColumnsTemplate } from '../../common/utils/breakpoint/BreakPoint';

/**
 * 标签管理全屏覆盖层
 */
@ComponentV2
export struct TabSwitcher {

  aboutToAppear(): void {
    // 覆盖层展示中暂停主页整窗截图（会把本覆盖层截进快照）
    tabsVM.homeSnapshotPaused = true
  }

  aboutToDisappear(): void {
    tabsVM.homeSnapshotPaused = false
  }

  private switchTo(tab: TabInfo): void {
    tabsVM.switchTab(tab.id)
    browserVM.showTabSwitcher = false
  }

  @Builder
  tabCard(tab: TabInfo) {
    GridItem() {
      Column({ space: 8 }) {
        // 卡片头：标题 + 关闭
        Row() {
          Text(tab.title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(tab.isIncognito ? Color.White : $r('sys.color.font_primary'))
            .layoutWeight(1)
          if (tab.isIncognito) {
            SymbolGlyph($r('sys.symbol.eye'))
              .fontSize(13)
              .fontColor([Color.White])
          }
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([tab.isIncognito ? Color.White : $r('sys.color.font_secondary')])
            .padding(6)
            .onClick(() => {
              tabsVM.closeTab(tab.id)
            })
        }
        .width('100%')

        // 卡片体：窗口快照 / 主页图标 / URL
        Column() {
          if (tab.snapshot !== null) {
            Image(tab.snapshot)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(10)
              .clip(true)
          } else if (tab.isHome) {
            SymbolGlyph($r('sys.symbol.house'))
              .fontSize(28)
              .fontColor([tab.isIncognito ? Color.White : $r('sys.color.font_secondary')])
          } else {
            Text(tab.url)
              .fontSize(12)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(tab.isIncognito ? Color.White : $r('sys.color.font_secondary'))
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(8)
      }
      .aspectRatio(0.92)
      .borderRadius(16)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(tab.isIncognito ? '#2A2A2A' : $r('sys.color.comp_background_tertiary'))
      .border({
        width: 2,
        color: tab.id === tabsVM.activeTabId ? QhState.currentThemeColor : Color.Transparent
      })
      .onClick(() => {
        this.switchTo(tab)
      })
    }
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text($r('app.string.new_tab'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })

      // 标签网格
      Scroll() {
        Grid() {
          ForEach(tabsVM.tabs, (tab: TabInfo) => {
            this.tabCard(tab)
          }, (tab: TabInfo) => tab.id.toString())
        }
        .columnsTemplate(gridColumnsTemplate(TabSwitcherColumns(QhState.widthBp)))
        .columnsGap(12)
        .rowsGap(12)
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)

      // 底部操作
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_primary')])
          Text($r('app.string.new_tab'))
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
        }
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          tabsVM.newTab()
          browserVM.showTabSwitcher = false
        })

        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_primary')])
          Text($r('app.string.incognito_tab'))
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
        }
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          tabsVM.newIncognitoTab()
          browserVM.showTabSwitcher = false
        })

        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_primary')])
          Text($r('app.string.close_all'))
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
        }
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          tabsVM.closeAll()
          browserVM.showTabSwitcher = false
        })
      }
      .width('100%')
      .height(64)
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    // 顶部避让内化为覆盖层自身内边距：背景仍全屏铺底，标题行避让状态栏
    .padding({ top: QhState.topRectHeight, bottom: QhState.bottomRectHeight })
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
