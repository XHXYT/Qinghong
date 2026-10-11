import { QhState } from '../entryability/AppState';
import { tabsVM, TabInfo } from '../viewmodel/TabsViewModel';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { downloadVM } from '../viewmodel/DownloadViewModel';
import { UISettings } from '../common/entity/SettingsModel';
import { HomepageView } from '../components/browser/HomepageView';
import { AddressBar, AddressEditOverlay } from '../components/browser/AddressBar';
import { BrowserToolbar } from '../components/browser/Toolbar';
import { TabSwitcher } from '../components/browser/TabSwitcher';
import { FindInPageBar } from '../components/browser/FindInPageBar';

@Entry
@ComponentV2
struct Index {

  aboutToAppear(): void {
    this.initTabs()
  }

  private async initTabs(): Promise<void> {
    await tabsVM.restoreSession()
  }

  @Builder
  tabContent(tab: TabInfo) {
    Stack() {
      if (tab.isHome) {
        HomepageView({ tab: tab })
      } else {
        Web({ src: tab.url, controller: tabsVM.ensureController(tab), incognitoMode: tab.isIncognito })
          .domStorageAccess(true)
          .databaseAccess(true)
          .onPageBegin((event: OnPageBeginEvent) => {
            browserVM.updateNavState(tab)
          })
          .onPageEnd((event: OnPageEndEvent) => {
            tab.url = event.url
            tab.progress = 100
            browserVM.onPageEnded(tab, event.url)
            browserVM.updateNavState(tab)
          })
          .onProgressChange((event: OnProgressChangeEvent) => {
            tab.progress = event.newProgress
          })
          .onTitleReceive((event: OnTitleReceiveEvent) => {
            tab.title = event.title
          })
          .onSearchResultReceive((event: OnSearchResultReceiveEvent) => {
            browserVM.onFindResult(event.activeMatchOrdinal, event.numberOfMatches, event.isDoneCounting)
          })
          .onDownloadStart((event: OnDownloadStartEvent) => {
            downloadVM.download(event.url)
          })
      }
    }
    .width('100%')
    .height('100%')
    .visibility(tab.id === tabsVM.activeTabId ? Visibility.Visible : Visibility.None)
  }

  build() {
    Navigation(QhState.pageStack) {
      Stack({ alignContent: Alignment.Top }) {
        // 主内容：标签内容 + 工具栏
        Column() {
          if (UISettings.toolbar_position === 'top') {
            BrowserToolbar()
          }

          Stack() {
            ForEach(tabsVM.tabs, (tab: TabInfo) => {
              this.tabContent(tab)
            }, (tab: TabInfo) => tab.id.toString())
          }
          .layoutWeight(1)

          if (browserVM.showFindBar) {
            FindInPageBar()
          }

          if (UISettings.toolbar_position !== 'top') {
            BrowserToolbar()
          }
        }
        .width('100%')
        .height('100%')

        // 顶部地址栏（网页态）
        AddressBar()

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
        top: tabsVM.activeTab && !tabsVM.activeTab.isHome ? QhState.topRectHeight : 0,
        bottom: QhState.bottomRectHeight
      })
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
