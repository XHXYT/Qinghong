import { QhState } from '../entryability/AppState';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { tabsVM, TabInfo } from '../viewmodel/TabsViewModel';
import { syncVM } from '../viewmodel/SyncViewModel';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { sniffVM } from '../viewmodel/SniffViewModel';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { webview } from '@kit.ArkWeb';
import { HomepageView, HomeBgLayer } from '../components/browser/HomepageView';
import { HomeImmersive } from '../common/utils/HomeImmersive';
import { HomeHtmlView } from '../components/browser/HomeHtmlView';
import { HomeBookmarksView } from '../components/browser/HomeBookmarksView';
import { AddressBar } from '../components/browser/AddressBar';
import { BrowserToolbar } from '../components/browser/Toolbar';
import { MergedActionBar } from '../components/browser/MergedActionBar';
import { TabBar } from '../components/browser/TabBar';
import { BookmarkBar } from '../components/browser/BookmarkBar';
import { BookmarkFolderMenu } from '../components/browser/BookmarkFolderMenu';
import { ActionBarColor } from '../common/utils/ActionBarColor';
import { volumeKeyPaging } from '../common/utils/VolumeKeyPaging';
import { kbShortcutDispatch } from '../common/utils/KbShortcutDispatch';
import { TabSwitcher } from '../components/browser/TabSwitcher';
import { FindInPageBar } from '../components/browser/FindInPageBar';
import { TabWeb } from '../components/browser/TabWeb';
import { NetworkLogTab } from '../view/NetworkLogPage';
import { ReaderView } from '../components/browser/ReaderView';
import { ElementInspectorPanel } from '../components/browser/ElementInspectorPanel';
import { TopMenuPanel } from '../components/browser/TopMenuPanel';
import { inspectorVM } from '../viewmodel/InspectorViewModel';
import { hitokoto } from '../common/utils/Hitokoto';
import { toastUtil } from '../common/utils/ToastUtils';

@Entry
@ComponentV2
struct Index {

  aboutToAppear(): void {
    this.applyWebDebuggingAccess()
    this.registerExternalUrlHandler()
    this.setupKeyboardAvoid()
    this.initTabs()
    hitokoto.ensure()
    // 音量键翻页开关开启时订阅音量键优先消费
    volumeKeyPaging.sync()
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
    // 游戏模式：2 秒内连按两次返回退出，首次提示「再按一次退出」
    if (browserVM.gameMode) {
      if (!browserVM.handleGameModeBack()) {
        toastUtil.showToast({ message: $r('app.string.game_mode_exit_hint') })
      }
      return true
    }
    if (browserVM.showReader) {
      browserVM.closeReader()
      return true
    }
    if (browserVM.showTabSwitcher) {
      browserVM.showTabSwitcher = false
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
      && !browserVM.showTabSwitcher
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

  /** 地址栏左图标顶弹面板距顶端偏移：传统布局=顶部地址栏高度（44+进度条2），双底布局=0；均含状态栏避让 */
  private topMenuEdgeOffset(): number {
    if (this.doubleBottom()) {
      return QhState.topRectHeight
    }
    const tab = tabsVM.activeTab
    return QhState.topRectHeight + 44 + (tab !== null && tab.progress < 100 ? 2 : 0)
  }

  /** 标签栏行：启用标签栏且为合并单行布局 */
  private showTabBarRow(): boolean {
    return UISettings.show_tab_bar && (this.mergedTop() || this.mergedBottom())
  }

  /** 资源嗅探悬浮按钮显隐：设置开启 + 网页标签（非主页/无痕/弹窗）+ 无覆盖层 + 检测到视频/音频 */
  private showSniffButton(): boolean {
    if (!appSettings.show_sniff_button || this.readerActive() || browserVM.showFindBar
      || browserVM.showTabSwitcher || browserVM.gameMode) {
      return false
    }
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.isIncognito || tab.isPopupWindow) {
      return false
    }
    return sniffVM.hasMedia(tab.id)
  }

  /** 顶栏可见且吸收状态栏区域（合并栏在上或传统布局顶部地址栏时，栏背景沉浸到状态栏） */
  private topBarsImmersive(): boolean {
    if (this.readerActive() || this.barsHidden()) {
      return false
    }
    if (this.mergedTop()) {
      return true
    }
    // 传统布局：顶部地址栏在位，其背景延伸至状态栏（双底/底部布局顶部无栏）
    return !this.mergedBottom() && !this.doubleBottom()
  }

  /** 状态栏沉浸色条颜色：与最顶行栏背景一致（标签栏在最上用其底色，否则地址栏/操作栏底色含色彩模式） */
  private topBarsBg(): ResourceColor {
    if (this.mergedTop() && this.showTabBarRow()) {
      return $r('sys.color.comp_background_primary')
    }
    return ActionBarColor.bg($r('sys.color.comp_background_primary'))
  }

  /** 内容区是否需要避让底部小白条（底部无操作栏避让时） */
  private needsBottomPadding(): boolean {
    if (this.readerActive()) {
      return false
    }
    if (browserVM.gameMode) {
      return false
    }
    if (this.barsHidden()) {
      // 隐藏沉浸态网页延伸至小白条下；查找栏在底时仍需避让
      return browserVM.showFindBar
    }
    return this.mergedTop()
  }

  /** 操作栏出入场动画：整组贴边滑出/滑入（时长曲线与显隐 animateTo 一致） */
  private barTransition(edge: 'top' | 'bottom'): TransitionEffect {
    return TransitionEffect.translate({ y: edge === 'top' ? '-100%' : '100%' })
      .animation({ duration: 250, curve: Curve.Friction })
  }

  /** 主页沉浸态：原生主页背景延伸至状态栏与底部操作栏/小白条区域 */
  private homeImmersive(): boolean {
    return HomeImmersive.active()
  }

  /** 活动标签为主页（供 @Monitor 监听切换键盘避让模式） */
  @Computed
  get homeTabActive(): boolean {
    const tab = tabsVM.activeTab
    return tab !== null && tab.isHome
  }

  @Monitor('homeTabActive')
  onHomeTabActiveChange(): void {
    this.applyKeyboardAvoid()
  }

  /**
   * 键盘避让模式：主页（未压入设置页）时不避让键盘——主页背景/布局不被输入法顶起，
   * 键盘悬浮覆盖底部；离开主页或进入设置等路由页时恢复进入时捕获的默认模式
   */
  private savedAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET

  private setupKeyboardAvoid(): void {
    try {
      this.savedAvoidMode = this.getUIContext().getKeyboardAvoidMode()
    } catch (e) {
      console.error(`[Index] getKeyboardAvoidMode 失败: ${e}`)
    }
    // 导航栈切换（进/出设置页）时重估避让模式
    QhState.pageStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        operation: NavigationOperation, isAnimated: boolean): void => {
        this.applyKeyboardAvoid()
      }
    })
    this.applyKeyboardAvoid()
  }

  private applyKeyboardAvoid(): void {
    const onHome = this.homeTabActive && QhState.pageStack.size() === 0
    this.getUIContext().setKeyboardAvoidMode(
      onHome ? KeyboardAvoidMode.NONE : this.savedAvoidMode)
  }

  /** HTML 主页沉浸：活动标签为 HTML 主页时网页全屏铺底渲染 */
  private htmlHomeFull(): boolean {
    return this.homeImmersive() && appSettings.isHomeHtmlMode()
  }

  @Builder
  tabContent(tab: TabInfo) {
    if (tab.nativeView === 'network-log') {
      // 原生视图标签：网络日志（非 Web 组件）
      NetworkLogTab({ tab: tab })
    } else if (tab.isHome) {
      // 主页内容：与 TabWeb 相同的并行横滑手势（滑动导航在主页同样生效）
      Stack() {
        if (appSettings.home_page_mode === 'blank') {
          // 空白模式：无内容
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.background_color_accent'))
        } else if (appSettings.home_page_mode === 'bookmarks') {
          HomeBookmarksView()
        } else if (appSettings.isHomeHtmlMode()) {
          // HTML 主页：沉浸时由 Index 全屏层渲染，此处透明占位
          if (!this.htmlHomeFull()) {
            HomeHtmlView({ tab: tab })
          } else {
            Column()
              .width('100%')
              .height('100%')
              // 全屏层已渲染，占位不拦截触摸（穿透给底层 Web）
              .hitTestBehavior(HitTestMode.None)
          }
        } else {
          HomepageView({ tab: tab, immersive: this.homeImmersive() })
        }
      }
      .width('100%')
      .height('100%')
      .parallelGesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent) => {
          this.handleSwipeNav(event.offsetX, event.offsetY)
        }))
    } else {
      TabWeb({ tab: tab })
    }
  }

  /** 主页滑动导航判定：右滑后退（标签栈回退）、左滑前进（返回离开主页前的页面） */
  private handleSwipeNav(dx: number, dy: number): void {
    if (!appSettings.swipe_nav_enabled) {
      return
    }
    if (Math.abs(dx) < 90 || Math.abs(dx) < Math.abs(dy) * 1.2) {
      return
    }
    if (dx > 0) {
      browserVM.goBack()
    } else {
      browserVM.goForward()
    }
  }

  build() {
    Navigation(QhState.pageStack) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 主页沉浸背景层：原生主页背景延伸至状态栏与底部操作栏/小白条区域
        if (this.homeImmersive() && !appSettings.isHomeHtmlMode()) {
          HomeBgLayer()
        }
        // HTML 主页沉浸层：网页全屏铺底渲染，延伸至状态栏与底部操作栏/小白条区域
        if (this.htmlHomeFull()) {
          HomeHtmlImmersiveLayer()
        }
        // 状态栏沉浸色条：合并栏在上/传统布局顶部地址栏时，栏背景延伸至状态栏区域消除色带断层（主页沉浸时由主页背景接管）
        if (this.topBarsImmersive() && !this.homeImmersive() && !browserVM.gameMode) {
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
            if (!this.readerActive() && !this.barsHidden() && !browserVM.gameMode) {
              Column() {
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
              .width('100%')
              // 顶部避让内化为栏容器内边距：背景层不再被整体推下，主页背景可铺至状态栏
              .padding({ top: QhState.topRectHeight })
              .transition(this.barTransition('top'))
            }

            Stack({ alignContent: Alignment.Bottom }) {
              ForEach(tabsVM.tabs, (tab: TabInfo) => {
                Stack() {
                  this.tabContent(tab)
                }
                .width('100%')
                .height('100%')
                // 组件快照目标：标签管理卡片窗口缩略图
                .id(`tabc_${tab.id}`)
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

              // 资源嗅探悬浮按钮：当前页检测到视频/音频时显示（高级设置可关）
              if (this.showSniffButton()) {
                Row() {
                  Blank()
                  Row() {
                    SymbolGlyph($r('sys.symbol.music_note_circle'))
                      .fontSize(20)
                      .fontColor([Color.White])
                  }
                  .width(44)
                  .height(44)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(QhState.currentThemeColor)
                  .borderRadius(22)
                  .shadow({ radius: 12, color: 'rgba(0,0,0,0.2)', offsetY: 2 })
                  .margin({ right: 16, bottom: 14 })
                  .onClick(() => {
                    sniffVM.open()
                  })
                }
                .width('100%')
              }
            }
            .layoutWeight(1)
            // 操作栏不在底部（工具栏在上）或已自动隐藏时，由内容区避让底部小白条区域
            .padding({ bottom: this.needsBottomPadding() ? QhState.bottomRectHeight : 0 })
            // 主页沉浸时背景由全屏主页背景层接管，内容区透明
            .backgroundColor(this.homeImmersive()
              ? Color.Transparent
              : $r('app.color.background_color_accent'))
            // HTML 主页沉浸时内容区穿透触摸给底层全屏 Web
            .hitTestBehavior(this.htmlHomeFull()
              ? HitTestMode.Transparent
              : HitTestMode.Default)

            if (browserVM.showFindBar) {
              FindInPageBar()
            }

            // 底部操作区：合并栏在下（标签栏常驻其正上方、书签栏贴其上方）/ 双行地址栏+工具栏 / 传统布局工具栏
            if (!this.readerActive() && !this.barsHidden() && !browserVM.gameMode) {
              Column() {
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
              .width('100%')
              .transition(this.barTransition('bottom'))
            }
          }
          .width('100%')
          .height('100%')
          // HTML 主页沉浸时整列穿透触摸给底层全屏 Web（子组件命中仍优先）
          .hitTestBehavior(this.htmlHomeFull()
            ? HitTestMode.Transparent
            : HitTestMode.Default)

          // 书签文件夹树覆盖层（合并栏在上：贴顶边向下展开；在下：贴底边向上展开）
          if (browserVM.showBookmarkMenu && UISettings.show_bookmark_bar
            && !this.barsHidden() && !this.readerActive() && !browserVM.gameMode) {
            BookmarkFolderMenu({
              rootFolder: browserVM.bookmarkMenuFolder,
              edgeAnchor: this.mergedBottom() ? 'bottom' : 'top',
              edgeOffset: this.mergedBottom()
                ? QhState.bottomRectHeight + 34 + (this.showTabBarRow() ? 27 : 0) + 33 + 6
                : QhState.topRectHeight + (this.showTabBarRow() ? 27 : 0) + 34 + 33 + 6
            })
          }

          // 标签管理
          if (browserVM.showTabSwitcher) {
            TabSwitcher()
          }

          // 地址栏左图标全宽顶弹面板（主页态路由入口 / 网页态页面信息）
          if (browserVM.showPageMenu && !this.readerActive() && !this.barsHidden()
            && !browserVM.showTabSwitcher && !browserVM.gameMode) {
            TopMenuPanel({ edgeOffset: this.topMenuEdgeOffset() })
          }
        }
        .width('100%')
        .height('100%')
        // 非沉浸主页：容器直接以通用背景色铺满（含状态栏区域），顶部避让内化到顶栏内边距，背景不再断层
        .backgroundColor(this.homeTabActive && !this.homeImmersive()
          ? $r('app.color.background_color_accent')
          : Color.Transparent)
        // HTML 主页沉浸时内层容器穿透触摸给底层全屏 Web
        .hitTestBehavior(this.htmlHomeFull()
          ? HitTestMode.Transparent
          : HitTestMode.Default)

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
      // 主页整窗快照目标（标签管理卡片：背景层与内容一次截全）
      .id('mainRoot')
      // 键盘快捷键：根节点按键分发（匹配设置页自定义组合）
      .onKeyEvent((e: KeyEvent) => {
        kbShortcutDispatch.handle(e)
      })
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}

/**
 * HTML 主页沉浸全屏层：活动标签为 HTML 主页时，网页铺满整屏（含状态栏与底部栏区域）
 */
@ComponentV2
struct HomeHtmlImmersiveLayer {
  build() {
    if (tabsVM.activeTab !== null) {
      HomeHtmlView({ tab: tabsVM.activeTab })
    }
  }
}
