import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { TabInfo, tabsVM } from './TabsViewModel';
import { historyVM } from './HistoryViewModel';
import { searchVM } from './SearchViewModel';
import { SearchEngines, UrlUtils } from '../common/constants/SearchEngines';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('BrowserViewModel')

/**
 * 浏览器外壳交互状态与动作
 */
@ObservedV2
export class BrowserViewModel {
  /** 地址栏编辑态 */
  @Trace isEditingAddress: boolean = false
  /** 标签管理覆盖层 */
  @Trace showTabSwitcher: boolean = false
  /** 页内查找栏 */
  @Trace showFindBar: boolean = false
  /** 查找：当前命中序号（1 起） */
  @Trace findOrdinal: number = 0
  /** 查找：命中总数 */
  @Trace findTotal: number = 0
  /** 查找关键词 */
  @Trace findKeyword: string = ''

  constructor() {
  }

  get activeTab(): TabInfo | null {
    return tabsVM.activeTab
  }

  /**
   * 地址栏提交：URL 直达或搜索引擎
   */
  submitAddress(input: string): void {
    const text = input.trim()
    if (!text) return
    const tab = tabsVM.activeTab
    if (!tab) return
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
   * 打开指定地址（联想条目点击）
   */
  openUrl(url: string): void {
    const tab = tabsVM.activeTab
    if (!tab || !url) return
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
      tab.canBack = c.accessBackward()
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
   * 网页内回退，无法回退则回主页态。返回 true 表示已消费返回事件
   */
  goBack(): boolean {
    const tab = tabsVM.activeTab
    if (!tab) return false
    if (tab.isHome) return false
    if (tab.canBack && tab.controller) {
      try {
        (tab.controller as webview.WebviewController).backward()
        return true
      } catch (e) {
        logger.error('goBack', `${e}`)
      }
    }
    tabsVM.goHome(tab)
    return true
  }

  /**
   * 前进
   */
  goForward(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome || !tab.controller || !tab.canForward) return
    try {
      (tab.controller as webview.WebviewController).forward()
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
    if (!tab.isIncognito && url && !url.startsWith('about:')) {
      historyVM.addVisit(tab.title, url)
    }
  }
}

export const browserVM = new BrowserViewModel()
