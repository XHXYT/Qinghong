import { SymbolGlyphModifier } from '@kit.ArkUI';
import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { toastUtil } from '../../common/utils/ToastUtils';

/**
 * 底部工具栏：返回/前进/主页/标签管理/菜单
 */
@ComponentV2
export struct BrowserToolbar {

  private addBookmark(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) return
    bookmarkVM.addBookmark(tab.title, tab.url)
    toastUtil.showToast({ message: $r('app.string.bookmark_added') })
  }

  private async copyLink(): Promise<void> {
    const ok = await browserVM.copyLink()
    if (ok) {
      toastUtil.showToast({ message: $r('app.string.link_copied') })
    }
  }

  @Builder
  toolbarMenu() {
    Menu() {
      MenuItem({
        content: $r('app.string.refresh'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_counterclockwise_clock'))
      })
        .onClick(() => {
          browserVM.refresh()
        })
      MenuItem({
        content: $r('app.string.incognito_tab'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.eye'))
      })
        .onClick(() => {
          tabsVM.newIncognitoTab()
          toastUtil.showToast({ message: $r('app.string.incognito_hint') })
        })
      MenuItem({
        content: $r('app.string.add_bookmark'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bookmark'))
      })
        .onClick(() => {
          this.addBookmark()
        })
      MenuItem({
        content: $r('app.string.find_in_page'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass'))
      })
        .onClick(() => {
          browserVM.showFindBar = true
        })
      MenuItem({
        content: $r('app.string.copy_link'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_text'))
      })
        .onClick(() => {
          this.copyLink()
        })
      MenuItem({
        content: $r('app.string.bookmarks'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.list_book'))
      })
        .onClick(() => {
          QhState.pushPage('bookmarks', null)
        })
      MenuItem({
        content: $r('app.string.history'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.clock'))
      })
        .onClick(() => {
          QhState.pushPage('history', null)
        })
      MenuItem({
        content: $r('app.string.downloads'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.circle_and_arrow_down'))
      })
        .onClick(() => {
          QhState.pushPage('downloads', null)
        })
      MenuItem({
        content: $r('app.string.settings'),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape_fill'))
      })
        .onClick(() => {
          QhState.pushPage('settings', null)
        })
    }
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(16)
  }

  build() {
    Row() {
      // 返回
      Row() {
        Stack({ alignContent: Alignment.TopStart }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(26)
            .fontColor([navColor(tabsVM.activeTab ? tabsVM.activeTab.canBack : false)])
        }
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        browserVM.goBack()
      })

      // 前进
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(26)
          .fontColor([navColor(tabsVM.activeTab ? tabsVM.activeTab.canForward : false)])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        browserVM.goForward()
      })

      // 主页
      Row() {
        SymbolGlyph($r('sys.symbol.house'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        const tab = tabsVM.activeTab
        if (tab) {
          tabsVM.goHome(tab)
        }
      })

      // 标签管理
      Row() {
        Stack({ alignContent: Alignment.TopEnd }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
          Text(`${tabsVM.tabCount}`)
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(QhState.currentThemeColor)
            .borderRadius(8)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .constraintSize({ minWidth: 16 })
            .offset({ x: 8, y: -6 })
        }
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        browserVM.showTabSwitcher = true
      })

      // 菜单
      Row() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .bindMenu(this.toolbarMenu)
    }
    .width('100%')
    .height(52)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}

function navColor(enabled: boolean): ResourceColor {
  return enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')
}
