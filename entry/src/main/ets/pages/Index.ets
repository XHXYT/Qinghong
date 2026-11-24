import { QhState } from '../entryability/AppState';
import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI';
import { tabsVM, TabInfo } from '../viewmodel/TabsViewModel';
import { syncVM } from '../viewmodel/SyncViewModel';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { sniffVM } from '../viewmodel/SniffViewModel';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { webview } from '@kit.ArkWeb';
import { HomepageView, HomeBgLayer } from '../components/browser/HomepageView';
import { HomeImmersive } from '../common/utils/home/HomeImmersive';
import { homeBg } from '../common/utils/home/HomeBg';
import { StatusBarSync } from '../common/utils/ui/StatusBarSync';
import { HomeHtmlView } from '../components/browser/HomeHtmlView';
import { HomeBookmarksView } from '../components/browser/HomeBookmarksView';
import { AddressBar } from '../components/browser/AddressBar';
import { BrowserToolbar } from '../components/browser/Toolbar';
import { MergedActionBar } from '../components/browser/MergedActionBar';
import { MenuSheetHost } from '../components/browser/MenuSheetHost';
import { TabBar } from '../components/browser/TabBar';
import { BookmarkBar } from '../components/browser/BookmarkBar';
import { BookmarkFolderMenu } from '../components/browser/BookmarkFolderMenu';
import { ActionBarColor } from '../common/utils/ui/ActionBarColor';
import { volumeKeyPaging } from '../common/utils/ui/VolumeKeyPaging';
import { kbShortcutDispatch } from '../common/utils/ui/KbShortcutDispatch';
import { TabSwitcher } from '../components/browser/TabSwitcher';
import { FindInPageBar } from '../components/browser/FindInPageBar';
import { TabWeb } from '../components/browser/TabWeb';
import { NetworkLogTab } from '../view/NetworkLogPage';
import { ReaderView } from '../components/browser/ReaderView';
import { ElementInspectorPanel } from '../components/browser/ElementInspectorPanel';
import { TopMenuPanel } from '../components/browser/TopMenuPanel';
import { inspectorVM } from '../viewmodel/InspectorViewModel';
import { hitokoto } from '../common/utils/home/Hitokoto';
import { toastUtil } from '../common/utils/ui/ToastUtils';
import { VideoFullScreen } from '../common/utils/ui/VideoFullScreen';
import { downloadVM } from '../viewmodel/DownloadViewModel';
import { DownloadConfirmDialog } from '../components/browser/DownloadConfirmDialog';
import { assistantVM } from '../viewmodel/WebAssistantViewModel';
import { WebHostedPlayerView, WebHostedPlayerSession } from '../components/browser/WebHostedPlayer';
import { ExtBackgroundHosts } from '../components/extension/ExtBackgroundHosts';
import { ExtPopupView } from '../components/extension/ExtPopupView';
import { extensionVM } from '../viewmodel/ExtensionViewModel';
import { DevToolsDock } from '../components/browser/DevToolsDock';
import { devtoolsVM } from '../common/utils/DevTools';

@Entry
@ComponentV2
struct Index {

  /** 扩展 popup 半模态开关：bindSheet isShow 需本地 @Local 布尔驱动（VM 回调同步），表达式参数对已打开 sheet 的关闭不可靠 */
  @Local popupSheetVisible: boolean = false
  /** DevTools 分屏容器尺寸（拖拽换算占比用） */
  @Local splitW: number = 0
  @Local splitH: number = 0
  /** 拖拽起始占比（onActionStart 捕获） */
  @Local dragStartRatio: number = 0.5

  aboutToAppear(): void {
    // 扩展 popup 开关回调 → 驱动 bindSheet isShow
    extensionVM.onPopupVisibilityChanged = (open: boolean): void => {
      this.popupSheetVisible = open
    }
    this.registerExternalUrlHandler()
    this.setupKeyboardAvoid()
    this.bootstrapAfterInit()
  }

  /** 等待应用基础环境（首选项/设置加载）完成后，再执行依赖配置的初始化。
   *  onCreate 的 async 初始化与 loadContent 并行，安装后首启尤其慢，
   *  若不等先用默认配置恢复会话/应用设置，会造成"配置丢失"假象
   *  （UI 渲染读 @Trace 配置会随加载完成自动刷新，不受此影响） */
  private async bootstrapAfterInit(): Promise<void> {
    try {
      await QhState.appInitialized
    } catch (e) {
      console.error(`[Index] 等待应用环境初始化失败: ${e}`)
    }
    // 主页背景明暗重估：背景图采样/背景主题 → 操作栏与搜索框黑/白字依据
    homeBg.refresh()
    this.applyWebDebuggingAccess()
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
      console.info(`[Index] 外部链接处理器开新标签: ${url}`)
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
    // 网页助手菜单：返回关闭
    if (assistantVM.showMenu) {
      assistantVM.closeMenu()
      return true
    }
    // 视频托管播放器：返回关闭全屏托管层（会话保留，页面再次播放可唤起）
    const hostTab = tabsVM.activeTab
    if (hostTab !== null && hostTab.hostedSession !== null && hostTab.hostedSession.state.show) {
      hostTab.hostedSession.close()
      return true
    }
    // 网页视频全屏：返回先退出全屏（触发 Web 退出全屏回调恢复界面）
    const fullTab = tabsVM.activeTab
    if (fullTab !== null && fullTab.videoFullScreen) {
      const handler = fullTab.videoExitHandler
      if (handler !== null) {
        handler.exitFullScreen()
      } else {
        fullTab.videoFullScreen = false
        VideoFullScreen.exit()
      }
      return true
    }
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
    // 下载确认弹窗：返回关闭
    if (downloadVM.pending !== null) {
      downloadVM.cancelDownload()
      return true
    }
    // DevTools 停靠面板：返回先收起
    if (devtoolsVM.docked) {
      devtoolsVM.close()
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

  /** 当前激活标签的视频托管会话（null = 无托管播放） */
  @Computed
  private get activeHostedSession(): WebHostedPlayerSession | null {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab !== null && tab.hostedSession !== null) {
      return tab.hostedSession
    }
    return null
  }

  private async initTabs(): Promise<void> {
    // 会话恢复失败不阻塞后续：外部链接消费与自动同步照常执行
    try {
      await tabsVM.restoreSession()
    } catch (e) {
      console.error(`[Index] 会话恢复失败: ${e}`)
    }
    // 冷启动：消费外部拉起（默认浏览器协议）的链接；
    // 恢复/全新启动后活动标签为空白主页时直接导航（keep 模式免留多余空标签），否则开新标签
    if (QhState.pendingOpenUrl) {
      const url = QhState.pendingOpenUrl
      QhState.pendingOpenUrl = ''
      console.info(`[Index] 冷启动消费待开链接: ${url}`)
      const active = tabsVM.activeTab
      if (active !== null && active.isHome && active.url === '') {
        tabsVM.navigate(active, url)
      } else {
        tabsVM.newTab(url)
      }
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

  /** 操作栏隐藏中（滑动/点击隐藏、网页视频全屏，各标签独立记忆） */
  private barsHidden(): boolean {
    const tab = tabsVM.activeTab
    return tab !== null && (tab.actionBarHidden || tab.videoFullScreen)
  }

  /** 地址栏左图标顶弹面板弹出边：底部栏布局（合并栏在下/双行在下）自底向上，其余自顶向下——跟随搜索框所在栏 */
  private pageMenuEdge(): string {
    return (this.mergedBottom() || this.doubleBottom()) ? 'bottom' : 'top'
  }

  /** 地址栏左图标顶弹面板距弹出边偏移：合并在上=顶栏实测总高、在下=底栏实测总高、
      传统顶部布局=地址栏高度（44+进度条2）+状态栏避让 */
  private topMenuEdgeOffset(): number {
    if (this.mergedBottom() || this.doubleBottom()) {
      return QhState.homeBottomBarHeight
    }
    if (this.mergedTop()) {
      return QhState.homeTopBarHeight
    }
    const tab = tabsVM.activeTab
    return QhState.topRectHeight + 44 + (tab !== null && tab.progress < 100 ? 2 : 0)
  }

  /** 标签栏行：启用标签栏且为合并单行布局 */
  private showTabBarRow(): boolean {
    return UISettings.show_tab_bar && (this.mergedTop() || this.mergedBottom())
  }

  /** 网页助手悬浮按钮显隐：设置开启 + 网页标签（非主页/无痕/弹窗）+ 无覆盖层 + 检测到视频/音频 */
  private showAssistantButton(): boolean {
    if (!appSettings.web_assistant || this.readerActive() || browserVM.showFindBar
      || browserVM.showTabSwitcher || browserVM.gameMode) {
      return false
    }
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.isIncognito || tab.isPopupWindow || tab.videoFullScreen) {
      return false
    }
    return sniffVM.hasMedia(tab.id)
  }

  /** 托管播放器标题（当前标签页面标题） */
  private hostedTitle(): string {
    const tab: TabInfo | null = tabsVM.activeTab
    return tab !== null ? tab.title : ''
  }

  /** 网页助手系统菜单（悬浮按钮 bindMenu 弹出）：资源嗅探/视频托管/投屏播放/下载视频 */
  @Builder
  private assistantMenu() {
    Menu() {
      if (appSettings.resource_sniff) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.waveform')),
          content: $r('app.string.resource_sniff')
        })
          .onClick(() => {
            assistantVM.closeMenu()
            sniffVM.open()
          })
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.play_square')),
        content: $r('app.string.video_hosting')
      })
        .onClick(() => {
          assistantVM.triggerVideoHosting()
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_up_left_and_arrow_down_right')),
        content: $r('app.string.video_fullscreen')
      })
        .onClick(() => {
          assistantVM.triggerNativeFullscreen()
        })
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.screen_share')),
        content: $r('app.string.cast_play')
      })
        .onClick(() => {
          assistantVM.closeMenu()
          toastUtil.showToast({ message: $r('app.string.feature_not_available') })
        })
      if (assistantVM.playingUrl !== '' && !assistantVM.playingUrl.startsWith('blob:')) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_circle')),
          content: $r('app.string.download_video')
        })
          .onClick(() => {
            const url: string = assistantVM.playingUrl
            assistantVM.closeMenu()
            const tab: TabInfo | null = tabsVM.activeTab
            downloadVM.download(url, tab !== null ? tab.url : '')
          })
      }
    }
  }

  /** 顶栏可见且吸收状态栏区域（合并栏在上或传统布局顶部地址栏时，栏背景沉浸到状态栏） */
  private topBarsImmersive(): boolean {
    if (this.readerActive() || this.barsHidden()) {
      return false
    }
    if (this.mergedTop()) {
      return true
    }
    // 传统布局：顶部地址栏在位，其背景延伸至状态栏（双底/底部布局顶部无栏；地址栏关闭后顶部无栏）
    return !this.mergedBottom() && !this.doubleBottom() && UISettings.show_address_bar
  }

  /** 状态栏沉浸色条颜色：与最顶行栏背景一致（含色彩模式；渐变时为透明，由顶栏组延续渐变覆盖状态栏区域） */
  private topBarsBg(): ResourceColor {
    return ActionBarColor.bg($r('sys.color.comp_background_primary'))
  }

  /** 内容区是否需要避让底部小白条（合并上布局网页全屏铺至底边不避让；仅栏隐藏且查找栏在底时避让） */
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
    // 合并上：底部无操作栏，小白条区域直接给网页；其余布局由底部操作栏自行避让
    return false
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
    // 进出主页：状态栏图标色按主页沉浸背景明暗重算
    StatusBarSync.sync()
  }

  /** 活动标签 id（供 @Monitor 驱动 DevTools 停靠目标切换） */
  @Computed
  get activeTabIdNum(): number {
    return tabsVM.activeTabId
  }

  @Monitor('activeTabIdNum')
  onActiveTabIdChange(): void {
    devtoolsVM.onActiveTabChanged()
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

  /** 标签挂载区：全部标签常驻挂载，活动标签置顶 */
  @Builder
  tabsStack() {
    ForEach(tabsVM.tabs, (tab: TabInfo) => {
      Stack() {
        this.tabContent(tab)
      }
      .width('100%')
      .height('100%')
      // 活动标签置顶：Web 为原生视图，常驻挂载下若后台标签（Visibility.None）
      // 叠在上层，其表面仍截获触摸/滚动手势，导致可见页无法滚动
      .zIndex(tab.id === tabsVM.activeTabId ? 1 : 0)
      // 组件快照目标：标签管理卡片窗口缩略图
      .id(`tabc_${tab.id}`)
    }, (tab: TabInfo) => tab.id.toString())
  }

  /** DevTools 分屏容器方向已废弃：主区/面板/分隔条均绝对定位（切换停靠侧仅属性变化，不重建子树） */

  /** 模拟器悬浮 Web 布局宽：优先用前端上报的模拟视口尺寸（页面 override 与之匹配，布局像素级一致），
   * 缺失时退回手机框 canvas 矩形宽 */
  private mainAreaWidth(): Length {
    if (devtoolsVM.docked && devtoolsVM.deviceModeOn) {
      if (devtoolsVM.deviceEmuW > 0) {
        return devtoolsVM.deviceEmuW
      }
      return devtoolsVM.deviceFrameW > 0 ? devtoolsVM.deviceFrameW : '100%'
    }
    const side = devtoolsVM.effectiveSide()
    return devtoolsVM.docked && (side === 'right' || side === 'left')
      ? `${(1 - devtoolsVM.ratio) * 100}%` : '100%'
  }

  /** 模拟器悬浮 Web 布局高：优先模拟视口高，缺失时退回 canvas 矩形高 */
  private mainAreaHeight(): Length {
    if (devtoolsVM.docked && devtoolsVM.deviceModeOn) {
      if (devtoolsVM.deviceEmuH > 0) {
        return devtoolsVM.deviceEmuH
      }
      return devtoolsVM.deviceFrameH > 0 ? devtoolsVM.deviceFrameH : '100%'
    }
    return devtoolsVM.docked && devtoolsVM.effectiveSide() === 'bottom'
      ? `${(1 - devtoolsVM.ratio) * 100}%` : '100%'
  }

  /** 主区定位：模拟器开启且 canvas 区域有效时悬浮到手机框（组件未缩放几何与 canvas 矩形同心对齐，
   * .scale 缩放后视觉即覆盖 canvas）；正常分屏靠左停靠时让出 dock 侧 */
  private mainAreaPos(): Position {
    if (devtoolsVM.docked && devtoolsVM.deviceModeOn
      && devtoolsVM.deviceFrameW > 0 && devtoolsVM.deviceFrameH > 0) {
      const w: number = devtoolsVM.deviceEmuW > 0 ? devtoolsVM.deviceEmuW : devtoolsVM.deviceFrameW
      const h: number = devtoolsVM.deviceEmuH > 0 ? devtoolsVM.deviceEmuH : devtoolsVM.deviceFrameH
      return {
        x: devtoolsVM.deviceFrameX + (devtoolsVM.deviceFrameW - w) / 2,
        y: devtoolsVM.deviceFrameY + (devtoolsVM.deviceFrameH - h) / 2
      }
    }
    if (devtoolsVM.docked && devtoolsVM.effectiveSide() === 'left') {
      return { x: `${devtoolsVM.ratio * 100}%`, y: 0 }
    }
    return { x: 0, y: 0 }
  }

  /** 主区缩放：模拟器开启且区域有效时按前端 screenZoom 缩放（缩放后视觉尺寸 = canvas 矩形，
   * 触摸经 ArkUI 逆变换映射回 Web 坐标），其余状态 1:1 */
  private mainAreaScale(): ScaleOptions {
    if (devtoolsVM.docked && devtoolsVM.deviceModeOn
      && devtoolsVM.deviceFrameW > 0 && devtoolsVM.deviceFrameH > 0) {
      const z: number = devtoolsVM.deviceEmuZoom > 0 ? devtoolsVM.deviceEmuZoom : 1
      return { x: z, y: z, centerX: '50%', centerY: '50%' }
    }
    return { x: 1, y: 1, centerX: '50%', centerY: '50%' }
  }

  /** 主区层级：模拟器开启且手机框区域有效时抬升到 dock 之上（悬浮真实网页原生触摸），
   * 其余状态沉底由 dock 遮盖或分屏错开 */
  private mainAreaZ(): number {
    return devtoolsVM.docked && devtoolsVM.deviceModeOn
      && devtoolsVM.deviceFrameW > 0 && devtoolsVM.deviceFrameH > 0 ? 2 : 0
  }

  /** DevTools 面板宽：左右分屏时按占比，靠下占满；模拟器开启时铺满 */
  private dockAreaWidth(): string {
    if (devtoolsVM.docked && devtoolsVM.deviceModeOn) {
      return '100%'
    }
    const side = devtoolsVM.effectiveSide()
    return side === 'right' || side === 'left' ? `${devtoolsVM.ratio * 100}%` : '100%'
  }

  /** DevTools 面板高：靠下时按占比，靠右占满；模拟器开启时铺满 */
  private dockAreaHeight(): string {
    if (devtoolsVM.docked && devtoolsVM.deviceModeOn) {
      return '100%'
    }
    return devtoolsVM.effectiveSide() === 'bottom' ? `${devtoolsVM.ratio * 100}%` : '100%'
  }

  /** DevTools 面板定位：绝对定位脱离 Flex 布局流（不占位），正常停靠贴分屏边界，模拟器开启时铺满全屏遮盖主区 */
  private dockPos(): Position {
    if (devtoolsVM.docked && devtoolsVM.deviceModeOn) {
      return { x: 0, y: 0 }
    }
    const side = devtoolsVM.effectiveSide()
    if (side === 'right') {
      return { x: `${(1 - devtoolsVM.ratio) * 100}%`, y: 0 }
    }
    if (side === 'bottom') {
      return { x: 0, y: `${(1 - devtoolsVM.ratio) * 100}%` }
    }
    return { x: 0, y: 0 }
  }

  /** 分屏拖拽分隔条：PanGesture 调整 DevTools 区域占比（0.2~0.8）；reverse 为靠左停靠时反向 */
  @Builder
  splitHandle(vertical: boolean, reverse: boolean) {
    Row() {
      Column()
        .width(vertical ? 4 : 36)
        .height(vertical ? 36 : 4)
        .borderRadius(2)
        .backgroundColor($r('sys.color.font_tertiary'))
    }
    .width(vertical ? 10 : '100%')
    .height(vertical ? '100%' : 10)
    // 绝对定位贴分屏边界（脱离 Flex 流，dock 已不占位，主区不再被分隔条挤压）
    .position(vertical
      ? { x: reverse ? this.splitW * devtoolsVM.ratio - 5 : this.splitW * (1 - devtoolsVM.ratio) - 5, y: 0 }
      : { x: 0, y: this.splitH * (1 - devtoolsVM.ratio) - 5 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .gesture(PanGesture()
      .onActionStart((e: GestureEvent) => {
        this.dragStartRatio = devtoolsVM.ratio
      })
      .onActionUpdate((e: GestureEvent) => {
        const base: number = vertical ? this.splitW : this.splitH
        if (base <= 0) {
          return
        }
        let delta: number = (vertical ? e.offsetX : e.offsetY) / base
        // 拖向 dock 一侧 = dock 收缩（right/bottom 分隔条跟手取反）；靠左停靠 dock 固定左缘不取反
        if (!reverse) {
          delta = -delta
        }
        devtoolsVM.ratio = devtoolsVM.clampRatio(this.dragStartRatio + delta)
      }))
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

  /** 扩展 popup 半模态内容（bindSheet 承载） */
  @Builder
  extPopupBuilder() {
    if (extensionVM.popupExt !== null) {
      ExtPopupView({ ext: extensionVM.popupExt })
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
        // 扩展 background 隐藏宿主：1x1 铺底渲染（不可见、不交互），声明 background/service_worker 的扩展各挂一个；
        // 扩展总开关关闭时整体卸载（后台停止），重新开启后随挂载重建
        if (appSettings.extension_enabled) {
          ExtBackgroundHosts()
        }
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
            if (!this.readerActive() && !browserVM.gameMode) {
              // 槽位包裹层：背景/渐变即时就位（不随栏滑入位移），过渡期间先填满栏位，避免露出外层容器底色
              Stack() {
                if (!this.barsHidden()) {
                  Column() {
                    if (this.mergedTop()) {
                      if (this.showTabBarRow()) {
                        TabBar()
                      }
                      MergedActionBar({ barPosition: 'top' })
                        // 抬升合并栏层级：搜索联想面板向下溢出渲染时不被后绘制的书签栏覆盖
                        .zIndex(1)
                      if (UISettings.show_bookmark_bar) {
                        BookmarkBar()
                      } else {
                        // 操作栏与 web 内容间距（书签栏开启时由书签栏承担过渡）
                        Column()
                          .width('100%')
                          .height(3)
                      }
                    } else if (!this.mergedBottom() && !this.doubleBottom() && UISettings.show_address_bar) {
                      AddressBar()
                    }
                  }
                  .width('100%')
                  // 顶部避让内化为栏容器内边距：背景层不再被整体推下，主页背景可铺至状态栏
                  .padding({ top: QhState.topRectHeight })
                  .transition(this.barTransition('top'))
                }
              }
              .width('100%')
              // 槽位即时底色（主页沉浸时透明，透出主页背景层）
              .backgroundColor(this.homeImmersive() ? Color.Transparent
                : ActionBarColor.bg($r('sys.color.comp_background_primary')))
              // 色彩模式：页面顶部渐变的延续模拟（含状态栏内边距区域，下端衔接页面顶色；纯色时为全透明不绘制）
              .linearGradient(ActionBarColor.gradient())
              // 抬升顶部栏层级：地址栏搜索联想面板可覆盖内容区渲染
              .zIndex(2)
              .transition(this.barTransition('top'))
              // 实测顶栏总高（含状态栏避让内边距）：定制页全屏预览按此还原真实主页栏占位
              .onAreaChange((_o: Area, n: Area): void => {
                QhState.homeTopBarHeight = (n.height as number)
              })
            }

            Stack({ alignContent: Alignment.Bottom }) {
              // 主区常驻：dock 开关不销毁/重建标签树（if/else 换容器会销毁页面 Web，
              // 导致被调试的内核 target 失效、DevTools ws 断连）。
              // 停靠侧切换 = Flex direction 属性变化（Row↔Column），同样不销毁子树。
              // 主区常驻：dock 开关不销毁/重建标签树（绝对定位仅改属性，不换容器）。
              // 模拟器开启时前端经 __qhDevTools.setDeviceFrame 上报手机框页面区域，
              // 主区 Web 悬浮其上（zIndex 2 > dock）：原生渲染 + 原生触摸/输入法。
              // 主区容器必须为 Stack：tabsStack 为 @Builder（无包装节点），ForEach 的各标签容器
              // 直接成为本容器子节点——Stack 下互相重叠铺满（仅活动标签可见）；
              // 若用 Column 会垂直堆叠，非首标签被排到屏幕外（白屏回归）
              Stack() {
                this.tabsStack()
              }
              .width(this.mainAreaWidth())
              .height(this.mainAreaHeight())
              .position(this.mainAreaPos())
              .scale(this.mainAreaScale())
              .zIndex(this.mainAreaZ())

              // DevTools 面板：绝对定位。正常停靠贴分屏边界，模拟器开启时铺满（悬浮 Web 覆盖手机框区域）。
              if (devtoolsVM.docked) {
                DevToolsDock()
                  .width(this.dockAreaWidth())
                  .height(this.dockAreaHeight())
                  .position(this.dockPos())
              }

              if (devtoolsVM.docked && !devtoolsVM.deviceModeOn) {
                this.splitHandle(devtoolsVM.effectiveSide() !== 'bottom',
                  devtoolsVM.effectiveSide() === 'left')
              }

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

              // 网页助手悬浮按钮：当前页检测到视频/音频时显示（高级设置「网页助手」可关）
              if (this.showAssistantButton()) {
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
                    assistantVM.openMenu()
                  })
                  // 系统菜单：点击悬浮按钮先采集正在播放的视频再弹出
                  .bindMenu(assistantVM.showMenu, this.assistantMenu, {
                    placement: Placement.TopRight,
                    offset: { x: 0, y: -6 },
                    onDisappear: () => {
                      assistantVM.closeMenu()
                    }
                  })
                }
                .width('100%')
              }
            }
            .layoutWeight(1)
            // 分屏区域实测尺寸：主区/面板/分隔条绝对定位的边界计算依据
            .onAreaChange((_o: Area, n: Area): void => {
              this.splitW = n.width as number
              this.splitH = n.height as number
            })
            // 仅栏隐藏且查找栏在底时避让小白条；合并上布局网页直接铺至屏幕底边
            .padding({ bottom: this.needsBottomPadding() ? QhState.bottomRectHeight : 0 })
            // 主页沉浸时背景由全屏主页背景层接管，内容区透明；
            // 色彩模式跟随底栏色（页面视口底部条带色）：栏滑动/网页尺寸变化过渡期露出的容器层不再泛白
            .backgroundColor(this.homeImmersive()
              ? Color.Transparent
              : ActionBarColor.bg($r('app.color.background_color_accent'), false))
            // HTML 主页沉浸时内容区穿透触摸给底层全屏 Web
            .hitTestBehavior(this.htmlHomeFull()
              ? HitTestMode.Transparent
              : HitTestMode.Default)

            if (browserVM.showFindBar) {
              FindInPageBar()
            }

            // 底部操作区：合并栏在下（标签栏常驻其正上方、书签栏贴其上方）/ 双行地址栏+工具栏 / 传统布局工具栏
            if (!this.readerActive() && !browserVM.gameMode) {
              // 槽位包裹层：底色即时就位（不随栏上滑位移），滑入过渡期间先填满栏位，避免露出外层容器底色
              Stack() {
                if (!this.barsHidden()) {
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
                      if (UISettings.show_address_bar) {
                        AddressBar({ suggestBelow: false })
                      }
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
              // 槽位即时底色：与底栏一致（色彩模式取页面视口底部条带色；主页沉浸时透明透出主页背景层）
              .backgroundColor(this.homeImmersive() ? Color.Transparent
                : ActionBarColor.bg($r('sys.color.comp_background_primary'), false))
              .transition(this.barTransition('bottom'))
              // 实测底栏总高：定制页全屏预览按此还原真实主页栏占位
              .onAreaChange((_o: Area, n: Area): void => {
                QhState.homeBottomBarHeight = (n.height as number)
              })
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
            TopMenuPanel({ edge: this.pageMenuEdge(), edgeOffset: this.topMenuEdgeOffset() })
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

        // 下载确认弹窗：接管下载事件后先确认（可改文件名）再开始下载
        if (downloadVM.pending !== null) {
          DownloadConfirmDialog()
        }

        // 视频托管播放器：全窗口沉浸层（托管会话播放时覆盖整个应用窗口）
        if (this.activeHostedSession !== null && this.activeHostedSession.state.show) {
          WebHostedPlayerView({ session: this.activeHostedSession, title: this.hostedTitle() })
        }

        // 菜单半模态根层宿主：浏览器标识/字号/保存网页等选择 sheet（宽屏 CENTER 居中）
        MenuSheetHost()
      }
      .width('100%')
      .height('100%')
      // 根层底色兜底：窗口默认白底之上再铺应用背景（栏过渡/网页 resize 的任何露底不再泛白）
      .backgroundColor($r('app.color.background_color_accent'))
      // 主页整窗快照目标（标签管理卡片：背景层与内容一次截全）
      .id('mainRoot')
      // 扩展 popup：居中半模态（SheetType.CENTER），内容为虚拟域 popup 文档
      .bindSheet(this.popupSheetVisible, this.extPopupBuilder(), {
        preferType: SheetType.CENTER,
        width: '100%',
        height: '62%',
        dragBar: false,
        showClose: true,
        // 背景自适应各扩展 popup 实际页色（ExtPopupView 探测；未探测用系统默认）
        backgroundColor: extensionVM.popupBg !== '' ? extensionVM.popupBg : $r('sys.color.comp_background_primary'),
        onDisappear: (): void => {
          extensionVM.closePopup()
        }
      })
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
