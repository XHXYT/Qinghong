import { webview } from '@kit.ArkWeb';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { TabInfo, tabsVM } from './TabsViewModel';
import { historyVM } from './HistoryViewModel';
import { searchVM } from './SearchViewModel';
import { SearchEngines, UrlUtils } from '../common/constants/SearchEngines';
import { createLogger } from '../common/utils/Logger';
import { ReaderScripts } from '../common/utils/ReaderScripts';
import { appSettings } from '../common/entity/SettingsModel';
import { toastUtil } from '../common/utils/ToastUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { _QhState } from '../entryability/AppState';

const logger = createLogger('BrowserViewModel')

/** runJavaScript 回参解包：string 结果经 JSON 编码（带引号），按需反序列化一次 */
function unwrapJsString(raw: string): string {
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    try {
      return JSON.parse(raw) as string
    } catch (e) {
      return raw
    }
  }
  return raw
}

/** 开关播报：「阅读模式：已开启/已关闭」 */
function announceToggle(item: ResourceStr, on: boolean): void {
  const label: string = typeof item === 'string' ? item : ResourceUtils.getString(item as Resource)
  const state: string =
    ResourceUtils.getString(on ? $r('app.string.toast_state_on') : $r('app.string.toast_state_off'))
  toastUtil.showToast({
    message: ResourceUtils.getStringWithArgs($r('app.string.menu_change_toast'), [label, state])
  })
}

/**
 * 阅读模式文章数据（Readability 提取结果）
 */
export class ReaderArticle {
  title: string = ''
  byline: string = ''
  dir: string = 'ltr'
  lang: string = ''
  siteName: string = ''
  publishedTime: string = ''
  content: string = ''
  excerpt: string = ''
  url: string = ''
  tabId: number = -1
  isIncognito: boolean = false
}

/**
 * 浏览器外壳交互状态与动作
 */
@ObservedV2
export class BrowserViewModel {
  /** 地址栏编辑态 */
  @Trace isEditingAddress: boolean = false
  /** 标签管理覆盖层 */
  @Trace showTabSwitcher: boolean = false
  /** 书签文件夹树覆盖层 */
  @Trace showBookmarkMenu: boolean = false
  /** 地址栏左图标全宽顶弹面板（主页态=路由入口，网页态=页面信息） */
  @Trace showPageMenu: boolean = false
  /** 覆盖层打开的文件夹路径（'' 为根） */
  @Trace bookmarkMenuFolder: string = ''
  /** 页内查找栏 */
  @Trace showFindBar: boolean = false
  /** 查找：当前命中序号（1 起） */
  @Trace findOrdinal: number = 0
  /** 查找：命中总数 */
  @Trace findTotal: number = 0
  /** 查找关键词 */
  @Trace findKeyword: string = ''
  /** 阅读模式覆盖层是否展示 */
  @Trace showReader: boolean = false
  /** 阅读模式文章（关闭时为空对象） */
  @Trace readerArticle: ReaderArticle = new ReaderArticle()
  /** 游戏模式：完全沉浸全屏（系统栏与应用栏全隐藏），返回两次退出 */
  @Trace gameMode: boolean = false
  /** 游戏模式：上次按返回键时间戳（2 秒内再按退出） */
  private lastGameBackAt: number = 0
  /** 缩放百分比浮层当前值（-1 隐藏；双指捏合与键盘缩放共用） */
  @Trace zoomPercent: number = -1
  /** 缩放浮层是否手动触发（显示 −/+ 步进按钮，消失更慢） */
  @Trace zoomManual: boolean = false
  private zoomOverlayTimer: number = -1

  constructor() {
  }

  get activeTab(): TabInfo | null {
    return tabsVM.activeTab
  }

  /** 打开阅读模式覆盖层 */
  openReader(article: ReaderArticle): void {
    this.readerArticle = article
    this.showReader = true
  }

  /** 关闭阅读模式覆盖层 */
  closeReader(): void {
    this.showReader = false
    this.readerArticle = new ReaderArticle()
  }

  /** 指定标签当前是否处于阅读模式 */
  isReaderActive(tabId: number): boolean {
    return this.showReader && this.readerArticle.tabId === tabId
  }

  /** 显示缩放百分比浮层：手动触发带步进按钮、3s 隐藏；自动触发（重加载等）纯数字、800ms 隐藏 */
  showZoomOverlay(percent: number, manual: boolean): void {
    this.zoomPercent = percent
    this.zoomManual = manual
    if (this.zoomOverlayTimer !== -1) {
      clearTimeout(this.zoomOverlayTimer)
    }
    this.zoomOverlayTimer = setTimeout((): void => {
      this.zoomOverlayTimer = -1
      this.zoomPercent = -1
      this.zoomManual = false
    }, manual ? 3000 : 800)
  }

  /** 立即隐藏缩放百分比浮层 */
  hideZoomOverlay(): void {
    if (this.zoomOverlayTimer !== -1) {
      clearTimeout(this.zoomOverlayTimer)
      this.zoomOverlayTimer = -1
    }
    this.zoomPercent = -1
    this.zoomManual = false
  }

  /** 活动标签网页缩放步进：1=放大(+25%) -1=缩小(-20%) 0=重置(100%)；手动触发浮层 */
  zoomStep(dir: number): void {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      return
    }
    let next: number = tab.zoomPercent > 0 ? tab.zoomPercent : 100
    try {
      const controller: webview.WebviewController = tabsVM.ensureController(tab)
      if (dir > 0) {
        controller.zoomIn()
        next = next * 1.25
      } else if (dir < 0) {
        controller.zoomOut()
        next = next * 0.8
      } else {
        controller.zoom(1)
        next = 100
      }
    } catch (error) {
      const err = error as BusinessError
      logger.error(`zoomStep dir=${dir} failed: ${err.code} ${err.message}`)
      return
    }
    next = Math.max(25, Math.min(500, Math.round(next)))
    tab.zoomPercent = next
    this.showZoomOverlay(next, true)
  }

  /** 进入游戏模式：隐藏系统状态栏/导航栏，应用内所有栏随 gameMode 一并隐藏 */
  enterGameMode(): void {
    this.gameMode = true
    try {
      _QhState.window.setWindowSystemBarEnable([])
        .catch((): void => {
        })
    } catch (error) {
      const err = error as BusinessError
      logger.error(`enterGameMode failed: ${err.code} ${err.message}`)
    }
  }

  /** 退出游戏模式：恢复系统状态栏/导航栏 */
  exitGameMode(): void {
    this.gameMode = false
    this.lastGameBackAt = 0
    try {
      _QhState.window.setWindowSystemBarEnable(['status', 'navigation'])
        .catch((): void => {
        })
    } catch (error) {
      const err = error as BusinessError
      logger.error(`exitGameMode failed: ${err.code} ${err.message}`)
    }
  }

  /** 游戏模式返回键分发：2 秒内连按两次退出；首次返回 false（由调用方提示「再按一次」） */
  handleGameModeBack(): boolean {
    const now: number = Date.now()
    if (now - this.lastGameBackAt < 2000) {
      this.exitGameMode()
      return true
    }
    this.lastGameBackAt = now
    return false
  }

  /**
   * 进入阅读模式：Readability 提取正文并打开覆盖层。
   * 地址栏阅读按钮与菜单「阅读模式」共用入口，提取成功直接进入（无确认弹窗）
   */
  enterReader(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return
    }
    const c = tab.controller
    if (c === null || this.isReaderActive(tab.id)) {
      return
    }
    c.runJavaScript(`${ReaderScripts.readabilityProbeJs()};JSON.stringify(window.__qhParseArticle())`)
      .then((raw: string) => {
        logger.info(`阅读提取返回 rawLen=${raw.length} url=${tab.url}`)
        const article = ReaderScripts.parseArticle(unwrapJsString(raw), tab)
        if (article === null) {
          logger.error(`Readability 解析失败 rawLen=${raw.length} url=${tab.url}`)
          toastUtil.showToast({ message: $r('app.string.reader_not_supported') })
          return
        }
        logger.info(`Readability 解析成功 title=${article.title} contentLen=${article.content.length}`)
        this.openReader(article)
        announceToggle($r('app.string.read_mode'), true)
      })
      .catch((error: BusinessError): void => {
        logger.error(`阅读模式提取失败: ${error.code} ${error.message} url=${tab.url}`)
        toastUtil.showToast({ message: $r('app.string.reader_not_supported') })
      })
  }

  /** 地址栏阅读按钮入口：read_mode_confirm 开启时先二次确认（菜单入口不确认，直接 enterReader） */
  enterReaderWithConfirm(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome || this.isReaderActive(tab.id)) {
      return
    }
    if (!appSettings.read_mode_confirm) {
      this.enterReader()
      return
    }
    toastUtil.showAlertDialog({
      title: $r('app.string.read_mode'),
      message: ResourceUtils.getString($r('app.string.reader_confirm_message')),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        },
        {
          value: $r('app.string.reader_enter'),
          action: (): void => {
            this.enterReader()
          }
        }
      ]
    }, 'readerConfirm')
  }

  /**
   * 地址栏提交：URL 直达或搜索引擎
   */
  submitAddress(input: string): void {
    const text = input.trim()
    if (!text) return
    const tab = tabsVM.activeTab
    if (!tab) return
    this.closeReader()
    let target: string
    if (UrlUtils.isLikelyUrl(text)) {
      target = UrlUtils.normalizeUrl(text)
    } else {
      target = SearchEngines.buildSearchUrl(SearchEngines.getCurrentEngine(), text)
      searchVM.saveSearch(text, tab.isIncognito)
    }
    this.isEditingAddress = false
    tabsVM.navigate(tab, target)
  }

  /**
   * 以指定引擎提交地址栏（搜索工具菜单）
   */
  submitAddressWithEngine(input: string, engineId: string): void {
    const text = input.trim()
    if (!text) return
    const tab = tabsVM.activeTab
    if (!tab) return
    this.closeReader()
    let target: string
    if (UrlUtils.isLikelyUrl(text)) {
      target = UrlUtils.normalizeUrl(text)
    } else {
      target = SearchEngines.buildSearchUrl(SearchEngines.getEngine(engineId), text)
      searchVM.saveSearch(text, tab.isIncognito)
    }
    this.isEditingAddress = false
    tabsVM.navigate(tab, target)
  }

  /**
   * 打开指定地址（联想条目点击）
   */
  openUrl(url: string): void {
    const tab = tabsVM.activeTab
    if (!tab || !url) return
    this.closeReader()
    this.isEditingAddress = false
    tabsVM.navigate(tab, url)
  }

  /**
   * 查询控制器刷新标签回退/前进可用性（页面事件后调用）
   */
  updateNavState(tab: TabInfo): void {
    if (!tab.controller) return
    try {
      const c = tab.controller as webview.WebviewController
      // 网页历史可回退，或可返回主页态，返回按钮均应可用
      tab.canBack = c.accessBackward() || !tab.isHome
      tab.canForward = c.accessForward()
    } catch (e) {
      logger.error('updateNavState', `${e}`)
    }
  }

  /**
   * 刷新当前页
   */
  refresh(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome || !tab.controller) return
    try {
      (tab.controller as webview.WebviewController).refresh()
    } catch (e) {
      logger.error('refresh', `${e}`)
    }
  }

  /**
   * 网页内回退；历史耗尽时按标签栈回退（关闭由其他标签打开的"后面"标签，
   * 切回打开它的标签），栈底标签才回主页态。返回 true 表示已消费返回事件
   */
  goBack(): boolean {
    const tab = tabsVM.activeTab
    if (!tab) return false
    // 阅读模式打开时优先退出阅读模式
    if (this.isReaderActive(tab.id)) {
      this.closeReader()
      return true
    }
    // 主页态：后开的标签（有打开者）返回即关闭回退，栈底交给系统
    if (tab.isHome) {
      return this.popTabStack(tab)
    }
    // 源码视图标签：Web 里仅有 about:blank→loadData 两条无意义历史，
    // 跳过 backward，返回直接走标签栈回退（关闭本标签切回打开它的标签）
    if (tab.controller && tab.viewSourceHtml === '') {
      try {
        const c = tab.controller as webview.WebviewController
        // 有网页历史才走 backward
        if (c.accessBackward()) {
          tab.programmaticNav = true
          c.backward()
          return true
        }
      } catch (e) {
        logger.error('goBack', `${e}`)
      }
    }
    // 网页历史耗尽：优先标签栈回退（关闭本标签切回打开它的标签），而非退到主页
    if (this.popTabStack(tab)) {
      return true
    }
    // 网页模式主页：已在主页网页上，返回交给系统（退出应用）
    if (tabsVM.isWebHome(tab)) {
      return false
    }
    tabsVM.goHome(tab)
    return true
  }

  /**
   * 标签栈回退：本标签由其他仍存在的标签打开时，关闭本标签并切回打开者。
   * 返回 true 表示已消费返回事件
   */
  private popTabStack(tab: TabInfo): boolean {
    const openerId = tab.openerTabId
    if (openerId < 0 || openerId === tab.id || !tabsVM.hasTab(openerId)) {
      return false
    }
    tabsVM.closeTabAndSwitch(tab.id, openerId)
    return true
  }

  /**
   * 前进：网页态走 Web 历史；主页态返回离开主页前的页面
   */
  goForward(): void {
    const tab = tabsVM.activeTab
    if (!tab) return
    if (tab.isHome) {
      if (tab.lastWebUrl) {
        tabsVM.navigate(tab, tab.lastWebUrl)
      }
      return
    }
    if (!tab.controller || !tab.canForward) return
    try {
      tab.programmaticNav = true
      const c = tab.controller as webview.WebviewController
      c.forward()
    } catch (e) {
      logger.error('goForward', `${e}`)
    }
  }

  /**
   * 复制当前页链接
   */
  async copyLink(): Promise<boolean> {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome || !tab.url) return false
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, tab.url)
      await pasteboard.getSystemPasteboard().setData(data)
      return true
    } catch (e) {
      logger.error('copyLink', `${e}`)
      return false
    }
  }

  /**
   * 页内查找
   */
  findInPage(keyword: string): void {
    const tab = tabsVM.activeTab
    this.findKeyword = keyword
    if (!tab || tab.isHome || !tab.controller || !keyword) return
    try {
      (tab.controller as webview.WebviewController).searchAllAsync(keyword)
    } catch (e) {
      logger.error('findInPage', `${e}`)
    }
  }

  /**
   * 查找结果回调（Web onSearchResultReceive）
   */
  onFindResult(activeMatchOrdinal: number, numberOfMatches: number, isDoneCounting: boolean): void {
    this.findOrdinal = activeMatchOrdinal
    this.findTotal = numberOfMatches
  }

  /**
   * 查找上一个/下一个（ArkWeb 无原生 findNext，用 window.find 兜底）
   */
  findJump(forward: boolean): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome || !tab.controller || !this.findKeyword) return
    const kw = this.findKeyword.replace(/\\/g, '\\\\').replace(/'/g, "\\'")
    const script = `window.find('${kw}', false, ${forward ? 'false' : 'true'}, true)`
    try {
      (tab.controller as webview.WebviewController).runJavaScript(script)
    } catch (e) {
      logger.error('findJump', `${e}`)
    }
  }

  /**
   * 关闭页内查找并清除高亮
   */
  closeFind(): void {
    const tab = tabsVM.activeTab
    this.showFindBar = false
    this.findKeyword = ''
    this.findOrdinal = 0
    this.findTotal = 0
    if (!tab || tab.isHome || !tab.controller) return
    try {
      (tab.controller as webview.WebviewController).clearMatches()
    } catch (e) {
      logger.error('closeFind', `${e}`)
    }
  }

  /**
   * Web 页面加载完成回调统一处理（记录历史）
   */
  onPageEnded(tab: TabInfo, url: string): void {
    if (!tab.isIncognito && url && !url.startsWith('about:') && !url.startsWith('view-source:')) {
      historyVM.addVisit(tab.title, url)
    }
  }
}

export const browserVM = new BrowserViewModel()
