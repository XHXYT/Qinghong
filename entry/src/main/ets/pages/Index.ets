import { QhState } from '../entryability/AppState';
import { tabsVM, TabInfo } from '../viewmodel/TabsViewModel';
import { syncVM } from '../viewmodel/SyncViewModel';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { searchVM } from '../viewmodel/SearchViewModel';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { webview } from '@kit.ArkWeb';
import { HomepageView } from '../components/browser/HomepageView';
import { HomeBookmarksView } from '../components/browser/HomeBookmarksView';
import { AddressBar, AddressEditOverlay } from '../components/browser/AddressBar';
import { BrowserToolbar } from '../components/browser/Toolbar';
import { MergedActionBar } from '../components/browser/MergedActionBar';
import { TabBar } from '../components/browser/TabBar';
import { BookmarkBar } from '../components/browser/BookmarkBar';
import { BookmarkFolderMenu } from '../components/browser/BookmarkFolderMenu';
import { ActionBarColor } from '../common/utils/ActionBarColor';
import { TabSwitcher } from '../components/browser/TabSwitcher';
import { FindInPageBar } from '../components/browser/FindInPageBar';
import { TabWeb } from '../components/browser/TabWeb';
import { NetworkLogTab } from '../view/NetworkLogPage';
import { ReaderView } from '../components/browser/ReaderView';
import { ElementInspectorPanel } from '../components/browser/ElementInspectorPanel';
import { inspectorVM } from '../viewmodel/InspectorViewModel';

@Entry
@ComponentV2
struct Index {

  aboutToAppear(): void {
    this.applyWebDebuggingAccess()
    this.registerExternalUrlHandler()
    this.initTabs()
  }

  aboutToDisappear(): void {
    QhState.externalUrlHandler = null
  }

  /**
   * 注册外部链接处理器：应用运行中（热启动 onNewWant）被系统以浏览器身份拉起时打开新标签
   */
  private registerExternalUrlHandler(): void {
    QhState.externalUrlHandler = (url: string): void => {
      tabsVM.newTab(url)
    }
  }

  private applyWebDebuggingAccess(): void {
    try {
      webview.WebviewController.setWebDebuggingAccess(appSettings.allow_debug_web)
    } catch (e) {
      console.error(`[Index] setWebDebuggingAccess 失败: ${e}`)
    }
  }

  /**
   * 系统返回：覆盖层 > 网页回退(到底回主页) > 默认退出
   */
  onBackPress(): boolean {
    if (browserVM.showReader) {
      browserVM.closeReader()
      return true
    }
    if (browserVM.showTabSwitcher) {
      browserVM.showTabSwitcher = false
      return true
    }
    if (browserVM.isEditingAddress) {
      browserVM.isEditingAddress = false
      searchVM.clear()
      return true
    }
    if (browserVM.showFindBar) {
      browserVM.closeFind()
      return true
    }
    if (this.inspectorVisible()) {
      inspectorVM.handleBack()
      return true
    }
    return browserVM.goBack()
  }

  /** 元素审查面板是否实际可见（打开中 + 绑定当前标签 + 无覆盖层遮挡） */
  private inspectorVisible(): boolean {
    return inspectorVM.showInspector && !this.readerActive()
      && !browserVM.showTabSwitcher && !browserVM.isEditingAddress
      && tabsVM.activeTabId === inspectorVM.boundTabId
  }

  private async initTabs(): Promise<void> {
    await tabsVM.restoreSession()
    // 冷启动：消费外部拉起（默认浏览器协议）的链接
    if (QhState.pendingOpenUrl) {
      const url = QhState.pendingOpenUrl
      QhState.pendingOpenUrl = ''
      tabsVM.newTab(url)
    }
    // 开启了自动同步则启动时合并本地与云端数据（不阻塞界面）
    syncVM.autoSyncIfNeeded()
  }

  /** 当前标签是否处于阅读模式（阅读时隐藏地址栏与工具栏，沉浸阅读） */
  private readerActive(): boolean {
    return browserVM.showReader && tabsVM.activeTabId === browserVM.readerArticle.tabId
  }

  /** 合并单行布局：工具栏在上 */
  private mergedTop(): boolean {
    return UISettings.app_layout === 'top'
  }

  /** 合并单行布局：工具栏在下 */
  private mergedBottom(): boolean {
    return UISettings.app_layout === 'bottom'
  }

  /** 双行工具栏布局：地址栏 + 工具栏都在底部 */
  private doubleBottom(): boolean {
    return UISettings.app_layout === 'bottom_double'
  }

  /** 操作栏自动隐藏中（滑动/点击隐藏触发，各标签独立记忆） */
  private barsHidden(): boolean {
    const tab = tabsVM.activeTab
    return tab !== null && tab.actionBarHidden
  }

  /** 标签栏行：启用标签栏且为合并单行布局 */
  private showTabBarRow(): boolean {
    return UISettings.show_tab_bar && (this.mergedTop() || this.mergedBottom())
  }

  /** 顶栏可见且吸收状态栏区域（合并栏在上时背景沉浸到状态栏，否则内容避让） */
  private topBarsImmersive(): boolean {
    return this.mergedTop() && !this.readerActive() && !this.barsHidden()
  }

  /** 状态栏沉浸色条颜色：与最顶行栏背景一致（标签栏在最上用其底色，否则操作栏底色含色彩模式） */
  private topBarsBg(): ResourceColor {
    if (this.showTabBarRow()) {
      return $r('sys.color.comp_background_primary')
    }
    return ActionBarColor.bg($r('sys.color.comp_background_primary'))
  }

  /** 内容区是否需要避让底部小白条（底部无操作栏避让时） */
  private needsBottomPadding(): boolean {
    return !this.readerActive() && (this.mergedTop() || this.barsHidden())
  }

  @Builder
  tabContent(tab: TabInfo) {
    if (tab.nativeView === 'network-log') {
      // 原生视图标签：网络日志（非 Web 组件）
      NetworkLogTab({ tab: tab })
    } else if (tab.isHome) {
      if (appSettings.home_page_mode === 'blank') {
        // 空白模式：无内容
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_color_accent'))
      } else if (appSettings.home_page_mode === 'bookmarks') {
        HomeBookmarksView()
      } else {
        HomepageView({ tab: tab })
      }
    } else {
      TabWeb({ tab: tab })
    }
  }

  build() {
    Navigation(QhState.pageStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 状态栏沉浸色条：合并栏在上时顶栏背景延伸至状态栏区域，消除色带断层
        if (this.topBarsImmersive()) {
          Column()
            .width('100%')
            .height(QhState.topRectHeight)
            .backgroundColor(this.topBarsBg())
            .position({ x: 0, y: 0 })
        }
        // 原主内容（避让状态栏）：地址栏 + 标签内容 + 工具栏
        Stack({ alignContent: Alignment.Top }) {
          Column() {
            // 顶部操作区：合并栏在上（标签栏常驻其正上方、书签栏贴其下方）/ 传统布局地址栏；底部布局组此处留空
            if (!this.readerActive() && !this.barsHidden()) {
              if (this.mergedTop()) {
                if (this.showTabBarRow()) {
                  TabBar()
                }
                MergedActionBar({ barPosition: 'top' })
                if (UISettings.show_bookmark_bar) {
                  BookmarkBar()
                }
              } else if (!this.mergedBottom() && !this.doubleBottom()) {
                AddressBar()
              }
            }

            Stack({ alignContent: Alignment.Bottom }) {
              ForEach(tabsVM.tabs, (tab: TabInfo) => {
                this.tabContent(tab)
              }, (tab: TabInfo) => tab.id.toString())

              // 撤销关闭提示条
              if (tabsVM.showUndoTip) {
                Row({ space: 16 }) {
                  Text($r('app.string.tab_closed'))
                    .fontSize(14)
                    .fontColor($r('sys.color.font_primary'))
                    .layoutWeight(1)
                  Text($r('app.string.undo'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(QhState.currentThemeColor)
                    .onClick(() => {
                      tabsVM.undoClose()
                    })
                }
                .width('100%')
                .constraintSize({ maxWidth: 480 })
                .padding({ left: 20, right: 20, top: 12, bottom: 12 })
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(24)
                .shadow({ radius: 16, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
                .margin({ left: 16, right: 16, bottom: 12 })
              }
            }
            .layoutWeight(1)
            // 操作栏不在底部（工具栏在上）或已自动隐藏时，由内容区避让底部小白条区域
            .padding({ bottom: this.needsBottomPadding() ? QhState.bottomRectHeight : 0 })
            .backgroundColor($r('app.color.background_color_accent'))

            if (browserVM.showFindBar) {
              FindInPageBar()
            }

            // 底部操作区：合并栏在下（标签栏常驻其正上方、书签栏贴其上方）/ 双行地址栏+工具栏 / 传统布局工具栏
            if (!this.readerActive() && !this.barsHidden()) {
              if (this.mergedBottom()) {
                if (UISettings.show_bookmark_bar) {
                  BookmarkBar()
                }
                if (this.showTabBarRow()) {
                  TabBar()
                }
                MergedActionBar({ barPosition: 'bottom' })
              } else if (this.doubleBottom()) {
                AddressBar()
                BrowserToolbar()
              } else if (!this.mergedTop()) {
                BrowserToolbar()
              }
            }
          }
          .width('100%')
          .height('100%')

          // 书签文件夹树覆盖层（合并栏在上：贴顶边向下展开；在下：贴底边向上展开）
          if (browserVM.showBookmarkMenu && UISettings.show_bookmark_bar
            && !this.barsHidden() && !this.readerActive()) {
            BookmarkFolderMenu({
              rootFolder: browserVM.bookmarkMenuFolder,
              edgeAnchor: this.mergedBottom() ? 'bottom' : 'top',
              edgeOffset: this.mergedBottom()
                ? QhState.bottomRectHeight + 34 + (this.showTabBarRow() ? 27 : 0) + 33 + 6
                : (this.showTabBarRow() ? 27 : 0) + 34 + 33 + 6
            })
          }

          // 标签管理
          if (browserVM.showTabSwitcher) {
            TabSwitcher()
          }

          // 地址编辑覆盖层
          if (browserVM.isEditingAddress) {
            AddressEditOverlay()
          }
        }
        .width('100%')
        .height('100%')
        .padding({
          top: QhState.topRectHeight
        })

        // 元素审查面板（标签切换/阅读/标签管理/地址编辑时由条件隐藏并清理页内蒙版）
        if (this.inspectorVisible()) {
          ElementInspectorPanel()
        }

        // 阅读模式覆盖层：全屏沉浸，不避让状态栏（正文滚动延伸至状态栏下）
        if (this.readerActive()) {
          ReaderView({
            article: browserVM.readerArticle,
            onClose: (): void => {
              browserVM.closeReader()
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
