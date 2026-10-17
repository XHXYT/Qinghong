import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { searchVM, SuggestItem, SuggestType } from '../../viewmodel/SearchViewModel';
import { UrlUtils, SearchToolbarEngines, ToolbarEngineEntry } from '../../common/constants/SearchEngines';
import { appSettings } from '../../common/entity/SettingsModel';

/**
 * 顶部地址栏（网页态显示，点击进入编辑）
 */
@ComponentV2
export struct AddressBar {

  build() {
    Column() {
      if (tabsVM.activeTab && !tabsVM.activeTab.isHome) {
        Row() {
          // 可点击进入编辑的域名区
          Row({ space: 8 }) {
            SymbolGlyph(tabSecureIcon(tabsVM.activeTab.url))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
            Text(UrlUtils.hostOf(tabsVM.activeTab.url))
              .fontSize(15)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
          }
          .layoutWeight(1)
          .height(44)
          .padding({ left: 16 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            browserVM.isEditingAddress = true
          })

          // 阅读模式按钮：页面检测为适合阅读时自动出现，点击二次确认后进入
          if (appSettings.read_mode_address_button && tabsVM.activeTab.readerable
            && !browserVM.isReaderActive(tabsVM.activeTab.id)) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(20)
              .fontColor([$r('sys.color.font_secondary')])
              .margin({ right: 14 })
              .onClick(() => {
                browserVM.enterReaderWithConfirm()
              })
          }
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)

        // 进度条
        if (tabsVM.activeTab.progress < 100) {
          Progress({ value: tabsVM.activeTab.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color(QhState.currentThemeColor)
            .backgroundColor(Color.Transparent)
        }
      }
    }
    .width('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}

function tabSecureIcon(url: string): Resource {
  if (url.startsWith('https://')) {
    return $r('sys.symbol.lock')
  }
  return $r('sys.symbol.website')
}

function suggestIcon(type: SuggestType): Resource {
  if (type === SuggestType.SEARCH_HISTORY) {
    return $r('sys.symbol.clock')
  }
  if (type === SuggestType.NETWORK_SUGGEST) {
    return $r('sys.symbol.magnifyingglass')
  }
  if (type === SuggestType.BOOKMARK) {
    return $r('sys.symbol.bookmark')
  }
  if (type === SuggestType.FAVORITES) {
    return $r('sys.symbol.star')
  }
  if (type === SuggestType.TAB) {
    return $r('sys.symbol.square_grid_2x2')
  }
  return $r('sys.symbol.website')
}

/**
 * 地址编辑态全屏覆盖层（输入 + 联想列表）
 */
@ComponentV2
export struct AddressEditOverlay {
  @Local inputText: string = ''

  aboutToAppear(): void {
    // 初始内容：主页态留空，网页态带当前域名便于继续输入
    const tab = tabsVM.activeTab
    this.inputText = tab && !tab.isHome ? UrlUtils.hostOf(tab.url) : ''
    this.refresh()
  }

  private refresh(): void {
    const tab = tabsVM.activeTab
    searchVM.updateSuggestions(this.inputText, tab ? tab.isIncognito : false)
  }

  private close(): void {
    browserVM.isEditingAddress = false
    searchVM.clear()
  }

  @Builder
  engineMenuBuilder() {
    Menu() {
      ForEach(SearchToolbarEngines.enabledEngines(), (e: ToolbarEngineEntry) => {
        MenuItem({ content: e.name })
          .contentFontColor($r('sys.color.font_primary'))
          .onClick(() => {
            const text = this.inputText.trim()
            if (text) {
              browserVM.submitAddressWithEngine(text, e.id)
            } else {
              // 未输入时仅切换当前搜索引擎
              appSettings.search_engine_id = e.id
            }
          })
      }, (e: ToolbarEngineEntry) => e.id)
    }
    .backgroundColor($r('app.color.start_window_background'))
    .borderRadius(16)
  }

  build() {
    Column() {
      // 输入行
      Row({ space: 10 }) {
        if (appSettings.search_toolbar_enabled && SearchToolbarEngines.enabledEngines().length > 0) {
          // 搜索工具菜单入口（最左侧图标）
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_secondary')])
            .bindMenu(this.engineMenuBuilder())
        } else {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_secondary')])
        }
        TextInput({ text: this.inputText, placeholder: $r('app.string.search_hint') })
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0 })
          .borderRadius(0)
          .enterKeyType(EnterKeyType.Search)
          .defaultFocus(true)
          .onChange((v: string) => {
            this.inputText = v
            this.refresh()
          })
          .onSubmit(() => {
            browserVM.submitAddress(this.inputText)
          })
        Text($r('app.string.cancel'))
          .fontSize(15)
          .fontColor(QhState.currentThemeColor)
          .onClick(() => {
            this.close()
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      // 联想列表
      List() {
        ForEach(searchVM.suggestions, (s: SuggestItem, idx: number) => {
          ListItem() {
            Row({ space: 12 }) {
              SymbolGlyph(suggestIcon(s.type))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
              Text(s.text)
                .fontSize(15)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
              if (s.url) {
                Text(UrlUtils.hostOf(s.url))
                  .fontSize(12)
                  .maxLines(1)
                  .fontColor($r('sys.color.font_secondary'))
              }
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              if (s.tabId >= 0) {
                tabsVM.switchTab(s.tabId)
                this.close()
                return
              }
              if (s.url) {
                browserVM.openUrl(s.url)
              } else {
                browserVM.submitAddress(s.text)
              }
            })
          }
        }, (s: SuggestItem, idx: number) => `${s.type}_${s.text}_${idx}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0.5, color: $r('sys.color.comp_divider'), startMargin: 16, endMargin: 16 })
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: QhState.bottomRectHeight })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onClick(() => {
      this.close()
    })
  }
}
