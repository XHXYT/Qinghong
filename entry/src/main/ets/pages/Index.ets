import { QhState } from '../entryability/AppState';
import { tabsVM, TabInfo } from '../viewmodel/TabsViewModel';
import { syncVM } from '../viewmodel/SyncViewModel';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { searchVM } from '../viewmodel/SearchViewModel';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { webview } from '@kit.ArkWeb';
import { HomepageView } from '../components/browser/HomepageView';
import { AddressBar, AddressEditOverlay } from '../components/browser/AddressBar';
import { BrowserToolbar } from '../components/browser/Toolbar';
import { TabSwitcher } from '../components/browser/TabSwitcher';
import { FindInPageBar } from '../components/browser/FindInPageBar';
import { TabWeb } from '../components/browser/TabWeb';

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
  onBackPressed(): boolean {
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
    return browserVM.goBack()
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

  @Builder
  tabContent(tab: TabInfo) {
    if (tab.isHome) {
      HomepageView({ tab: tab })
    } else {
      TabWeb({ tab: tab })
    }
  }

  build() {
    Navigation(QhState.pageStack) {
      Stack({ alignContent: Alignment.Top }) {
        // 主内容：地址栏 + 标签内容 + 工具栏（地址栏流式布局，网页内容自然下推）
        Column() {
          AddressBar()

          if (UISettings.toolbar_position === 'top') {
            BrowserToolbar()
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
          // 工具栏在顶部时，由内容区避让底部小白条区域
          .padding({ bottom: UISettings.toolbar_position === 'top' ? QhState.bottomRectHeight : 0 })

          if (browserVM.showFindBar) {
            FindInPageBar()
          }

          if (UISettings.toolbar_position !== 'top') {
            BrowserToolbar()
          }
        }
        .width('100%')
        .height('100%')

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
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
