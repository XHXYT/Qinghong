import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { appSettings, UISettings } from '../../common/entity/SettingsModel';
import { UrlUtils, SearchToolbarEngines, ToolbarEngineEntry } from '../../common/constants/SearchEngines';
import { ActionBarColor } from '../../common/utils/ActionBarColor';
import { HomeImmersive } from '../../common/utils/HomeImmersive';
import { homeHtmlRefresh } from '../../common/utils/HomeHtmlRefresh';
import { hitokoto } from '../../common/utils/Hitokoto';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { searchVM } from '../../viewmodel/SearchViewModel';
import { SearchSuggestPanel } from './SearchSuggestPanel';

/**
 * 地址栏显示文本（按地址栏内容设置：标题/地址/域名，标题为空回退域名）
 */
export function addressDisplayText(url: string, title: string): string {
  if (UISettings.address_bar_content === 'title' && title !== '') {
    return title
  }
  if (UISettings.address_bar_content === 'url') {
    return url
  }
  return UrlUtils.hostOf(url)
}

/**
 * 顶部地址栏：内联输入，回车直达 URL 或搜索引擎（无独立搜索页）
 * 最左图标：主页态=搜索图标，网页态=盾牌；点按=全宽顶弹面板（路由入口/页面信息），
 * 长按=切换搜索引擎菜单
 */
@ComponentV2
export struct AddressBar {
  /** 编辑中（聚焦时展示完整地址，失焦回退显示文本） */
  @Local editing: boolean = false
  @Local editText: string = ''
  /** 联想面板展开方向：顶部地址栏向下、底部双行布局向上 */
  @Param suggestBelow: boolean = true

  /** 主页态监测：回到主页时重置编辑状态，地址栏恢复默认展示 */
  @Computed
  get inHomeMode(): boolean {
    const tab = tabsVM.activeTab
    return tab === null || tab.isHome
  }

  @Monitor('inHomeMode')
  onHomeModeChange(): void {
    this.editing = false
    this.editText = ''
  }

  /** 长按菜单：切换搜索引擎 */
  @Builder
  engineMenuBuilder() {
    Menu() {
      ForEach(SearchToolbarEngines.enabledEngines(), (e: ToolbarEngineEntry) => {
        MenuItem({ content: e.name })
          .contentFontColor(appSettings.search_engine_id === e.id
            ? QhState.currentThemeColor
            : $r('sys.color.font_primary'))
          .onClick(() => {
            appSettings.search_engine_id = e.id
            // 同步刷新 HTML 主页的引擎下拉显示
            homeHtmlRefresh.request()
          })
      }, (e: ToolbarEngineEntry) => e.id)
    }
    .backgroundColor($r('app.color.start_window_background'))
    .borderRadius(16)
  }

  /** 最左图标：主页态搜索图标 / 网页态按连接安全状态切换（勾盾/警示盾/锁盾） */
  private entryIcon(): Resource {
    const tab = tabsVM.activeTab
    if (tab !== null && !tab.isHome) {
      const state: string = UrlUtils.secureStateOf(tab.url)
      if (state === 'insecure') {
        return $r('sys.symbol.exclamationmark_shield_fill')
      }
      if (state === 'secure') {
        return $r('sys.symbol.checkmark_shield')
      }
      return $r('sys.symbol.lock_shield')
    }
    return $r('sys.symbol.magnifyingglass')
  }

  /** 最左图标颜色：HTTP 不安全=警示红，其余跟随次级前景 */
  private entryIconColor(): ResourceColor {
    const tab = tabsVM.activeTab
    if (tab !== null && !tab.isHome && UrlUtils.secureStateOf(tab.url) === 'insecure') {
      return '#E84026'
    }
    return ActionBarColor.fg($r('sys.color.font_secondary'))
  }

  /** 地址栏最左图标：点按=全宽顶弹面板，长按=搜索引擎菜单 */
  @Builder
  searchIconEntry() {
    SymbolGlyph(this.entryIcon())
      .fontSize(19)
      .fontColor([this.entryIconColor()])
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, (): void => {
          browserVM.showPageMenu = true
        })
      })
      .bindContextMenu(this.engineMenuBuilder(), ResponseType.LongPress)
  }

  build() {
    Column() {
      if (tabsVM.activeTab && !tabsVM.activeTab.isHome) {
        Row({ space: 8 }) {
          this.searchIconEntry()
          TextInput({
            text: this.editing ? this.editText
              : addressDisplayText(tabsVM.activeTab.url, tabsVM.activeTab.title),
            placeholder: $r('app.string.search_hint')
          })
            .fontSize(15)
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .placeholderColor(ActionBarColor.fg($r('sys.color.font_secondary')))
            .caretColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 0 })
            .borderRadius(0)
            .enterKeyType(EnterKeyType.Search)
            .onFocus(() => {
              this.editing = true
              this.editText = tabsVM.activeTab !== null ? tabsVM.activeTab.url : ''
            })
            .onChange((v: string) => {
              this.editText = v
              const t = tabsVM.activeTab
              searchVM.updateSuggestions(v, t !== null && t.isIncognito)
            })
            .onBlur(() => {
              this.editing = false
              searchVM.clearSoon()
            })
            .onSubmit(() => {
              browserVM.submitAddress(this.editText)
              searchVM.clear()
              this.editing = false
              this.editText = ''
              this.getUIContext().getFocusController().clearFocus()
            })

          // 阅读模式按钮：页面检测为适合阅读时自动出现，点击二次确认后进入
          if (appSettings.read_mode_address_button && tabsVM.activeTab.readerable
            && !browserVM.isReaderActive(tabsVM.activeTab.id)) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(20)
              .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'))])
              .onClick(() => {
                browserVM.enterReaderWithConfirm()
              })
          }

          // 刷新按钮（阅读模式入口右侧）
          SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
            .fontSize(19)
            .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'))])
            .margin({ right: 14 })
            .onClick(() => {
              browserVM.refresh()
            })
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16 })

        // 进度条
        if (tabsVM.activeTab.progress < 100) {
          Progress({ value: tabsVM.activeTab.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color(ActionBarColor.fg(QhState.currentThemeColor))
            .backgroundColor(Color.Transparent)
        }
      } else if (tabsVM.activeTab && tabsVM.activeTab.isHome) {
        // 主页态：地址栏直接输入搜索或直达
        Row({ space: 8 }) {
          this.searchIconEntry()
          TextInput({ text: this.editText, placeholder: hitokoto.quote !== '' ? hitokoto.quote : $r('app.string.search_hint') })
            .fontSize(15)
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .placeholderColor(ActionBarColor.fg($r('sys.color.font_secondary')))
            .caretColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 0 })
            .borderRadius(0)
            .enterKeyType(EnterKeyType.Search)
            .onChange((v: string) => {
              this.editText = v
              const t = tabsVM.activeTab
              searchVM.updateSuggestions(v, t !== null && t.isIncognito)
            })
            .onBlur(() => {
              searchVM.clearSoon()
            })
            .onSubmit(() => {
              browserVM.submitAddress(this.editText)
              searchVM.clear()
              this.editText = ''
              this.getUIContext().getFocusController().clearFocus()
            })

          // 扫码入口（菜单项同款）
          SymbolGlyph($r('sys.symbol.line_viewfinder'))
            .fontSize(19)
            .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'))])
            .onClick(() => {
              menuVM.startScan()
            })
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
      }

      // 搜索联想面板：输入时浮于内容区（顶部布局向下展开、底部双行布局向上展开）
      if (searchVM.suggestions.length > 0) {
        if (this.suggestBelow) {
          SearchSuggestPanel({
            panelBg: $r('sys.color.comp_background_primary'),
            onPick: (): void => {
              this.editing = false
              this.editText = ''
              this.getUIContext().getFocusController().clearFocus()
            }
          })
            .position({ x: 0, y: 48 })
        } else {
          SearchSuggestPanel({
            panelBg: $r('sys.color.comp_background_primary'),
            onPick: (): void => {
              this.editing = false
              this.editText = ''
              this.getUIContext().getFocusController().clearFocus()
            }
          })
            .position({ x: 0, y: 0 })
            .markAnchor({ x: 0, y: '100%' })
        }
      }
    }
    .width('100%')
    // 主页沉浸时背景透明，透出全屏主页背景层
    .backgroundColor(HomeImmersive.active() ? Color.Transparent
      : ActionBarColor.bg($r('sys.color.comp_background_primary')))
  }
}
