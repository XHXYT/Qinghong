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
import { ExtToolbarButton } from '../extension/ExtToolbarButton';
import { EXT_SCHEME_PREFIX } from '../../common/utils/ExtensionResources';

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
 * 地址最左图标入口（地址栏/合并栏地址胶囊共用）：
 * 主页态=搜索图标，网页态=按连接安全状态切换（勾盾/警示盾/锁盾）；
 * 点按=全宽顶弹面板（路由入口/页面信息），长按=切换搜索引擎菜单
 */
@ComponentV2
export struct AddressEntryIcon {
  /** 图标字号（地址栏 19，合并栏胶囊按容器高度缩小） */
  @Param iconSize: number = 19

  /** 是否处于顶部操作栏（底部栏不做页面色前景适配，传 ActionBarColor.fg 的 atTop） */
  @Param suggestBelow: boolean = true
  /** 是否位于顶部位（false=底部位不跟随页面色自适应） */
  @Param atTop: boolean = true

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

  /** 最左图标：主页态搜索图标 / 扩展页 root / 网页态按连接安全状态切换（勾盾/警示盾/锁盾） */
  private entryIcon(): Resource {
    const tab = tabsVM.activeTab
    if (tab !== null && !tab.isHome) {
      if (tab.url.startsWith(EXT_SCHEME_PREFIX)) {
        return $r('sys.symbol.root')
      }
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
    return ActionBarColor.fg($r('sys.color.font_secondary'), this.atTop)
  }

  build() {
    SymbolGlyph(this.entryIcon())
      .fontSize(this.iconSize)
      .fontColor([this.entryIconColor()])
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, (): void => {
          browserVM.showPageMenu = true
        })
      })
      .bindContextMenu(this.engineMenuBuilder(), ResponseType.LongPress)
  }
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

  build() {
    Column() {
      if (tabsVM.activeTab && !tabsVM.activeTab.isHome) {
        Row({ space: 12 }) {
          AddressEntryIcon({ atTop: this.suggestBelow })
          TextInput({
            text: this.editing ? this.editText
              : addressDisplayText(tabsVM.activeTab.url, tabsVM.activeTab.title),
            placeholder: $r('app.string.search_hint')
          })
            .fontSize(15)
            // 占位符显式对齐正文字号（默认 16fp 会显大）
            .placeholderFont({ size: 15 })
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), this.suggestBelow))
            .placeholderColor(ActionBarColor.fg($r('sys.color.font_secondary'), this.suggestBelow))
            .caretColor(ActionBarColor.fg($r('sys.color.font_primary'), this.suggestBelow))
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
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
              .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), this.suggestBelow)])
              .onClick(() => {
                browserVM.enterReaderWithConfirm()
              })
          }

          // 刷新按钮
          SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
            .fontSize(20)
            .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), this.suggestBelow)])
            .onClick(() => {
              browserVM.refresh()
            })

          // 扩展入口（拼图按钮：刷新按钮右侧，菜单向下/向上随布局；操作栏设置开关 + 扩展总开关控制）
          if (UISettings.show_extension_button && appSettings.extension_enabled) {
            ExtToolbarButton({ anchor: this.suggestBelow ? 'top' : 'bottom' })
          }
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12 })

        // 进度条
        if (tabsVM.activeTab.progress < 100) {
          Progress({ value: tabsVM.activeTab.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color(ActionBarColor.fg(QhState.currentThemeColor, this.suggestBelow))
            .backgroundColor(Color.Transparent)
        }
      } else if (tabsVM.activeTab && tabsVM.activeTab.isHome) {
        // 主页态：地址栏直接输入搜索或直达
        Row({ space: 8 }) {
          AddressEntryIcon({ atTop: this.suggestBelow })
          TextInput({ text: this.editText, placeholder: hitokoto.quote !== '' ? hitokoto.quote : $r('app.string.search_hint') })
            .fontSize(15)
            // 占位符显式对齐正文字号（默认 16fp 会显大）
            .placeholderFont({ size: 15 })
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), this.suggestBelow))
            .placeholderColor(ActionBarColor.fg($r('sys.color.font_secondary'), this.suggestBelow))
            .caretColor(ActionBarColor.fg($r('sys.color.font_primary'), this.suggestBelow))
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
            .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), this.suggestBelow)])
            .onClick(() => {
              menuVM.startScan()
            })

          // 扩展入口（主页态常驻右上角，与网页态地址栏一致，便于随时打开扩展 popup；操作栏设置开关 + 扩展总开关控制）
          if (UISettings.show_extension_button && appSettings.extension_enabled) {
            ExtToolbarButton({ anchor: this.suggestBelow ? 'top' : 'bottom', bar: 'addr' })
          }
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
      }

      // 搜索联想面板：输入时浮于内容区（顶部布局向下展开、底部双行布局向上展开）；
      // 仅地址输入框编辑中显示（共享 suggestions，避免主页搜索框输入联动弹出本面板）
      if (searchVM.suggestions.length > 0 && this.editing) {
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
      : ActionBarColor.bg($r('sys.color.comp_background_primary'), this.suggestBelow))
  }
}
