import { webview } from '@kit.ArkWeb';
import { QhState } from '../entryability/AppState';
import { AppConstants } from '../common/constants/AppConstants';
import { kvDbUtil } from '../common/utils/KVdbUtil';
import { appSettings } from '../common/entity/SettingsModel';
import { createLogger } from '../common/utils/Logger';
import { toastUtil } from '../common/utils/ToastUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { SiteSettingsViewModel, siteSettingsVM } from './SiteSettingsViewModel';
import { ViewSourceScripts } from '../common/utils/ViewSourceScripts';

const logger = createLogger('TabsViewModel')

/**
 * 会话序列化结构
 */
interface TabSessionData {
  id: number
  title: string
  url: string
  isHome: boolean
}

interface SessionData {
  tabs: TabSessionData[]
  activeTabId: number
  nextId: number
}

/**
 * 标签信息
 */
@ObservedV2
export class TabInfo {
  readonly id: number
  /** 页面标题，主页态为"轻鸿" */
  @Trace title: string = '轻鸿'
  /** 当前地址 */
  @Trace url: string = ''
  /** 加载进度 0-100 */
  @Trace progress: number = 0
  /** 是否主页态 */
  @Trace isHome: boolean = true
  /** 无痕模式 */
  @Trace isIncognito: boolean = false
  /** 可回退 */
  @Trace canBack: boolean = false
  /** 可前进 */
  @Trace canForward: boolean = false
  /** 离开主页前的网页地址（主页态点"前进"返回该页） */
  @Trace lastWebUrl: string = ''
  /** 页面加载完成后检测为适合阅读模式（地址栏阅读按钮显隐依据） */
  @Trace readerable: boolean = false
  /** 应用主动导航标记（返回/前进，重定向拦截用；首次主框架请求消费） */
  programmaticNav: boolean = false
  /** 弹出式窗口转开的标签（window.close 时可整标签关闭） */
  isPopupWindow: boolean = false
  /** 查看源码：捕获的页面 HTML（非空 = 源码视图标签；瞬态，不随会话持久化） */
  viewSourceHtml: string = ''
  /** 原生视图标签（非空 = 标签容器渲染原生组件而非 Web；瞬态，不随会话持久化）：network-log */
  @Trace nativeView: string = ''
  /** 原生视图参数（网络日志 = 源标签 id） */
  nativeParam: string = ''
  /** 打开本标签的标签 id（-1=无；返回键标签栈回退用，不持久化） */
  openerTabId: number = -1
  /** Web 控制器（非 UI 状态，不参与观察） */
  controller: webview.WebviewController | null = null

  constructor(id: number, isIncognito: boolean = false) {
    this.id = id
    this.isIncognito = isIncognito
  }
}

@ObservedV2
export class TabsViewModel {
  @Trace tabs: TabInfo[] = []
  @Trace activeTabId: number = -1

  /** 最近关闭的标签（撤销关闭用，非 UI 状态） */
  recentClosed: TabInfo | null = null
  /** 是否显示撤销关闭提示条 */
  @Trace showUndoTip: boolean = false
  private undoTipTimer: number = -1

  private nextId: number = 1
  private saveTimer: number = -1

  constructor() {
  }

  /**
   * 当前激活标签
   */
  @Computed
  get activeTab(): TabInfo | null {
    for (const t of this.tabs) {
      if (t.id === this.activeTabId) return t
    }
    return null
  }

  get tabCount(): number {
    return this.tabs.length
  }

  /**
   * 恢复上次会话（KV）：
   * - never：不恢复
   * - always：直接恢复
   * - ask：有网页态标签时弹窗询问
   * 失败或无会话则新建单标签主页
   */
  async restoreSession(): Promise<void> {
    if (appSettings.restore_mode === 'never') {
      this.freshStart()
      return
    }
    let session: SessionData | null = null
    let retry = 3
    while (retry > 0 && !session) {
      try {
        const raw = await kvDbUtil.getData<string>(AppConstants.KV_KEY_SESSION, '')
        if (raw) {
          const parsed = JSON.parse(raw) as SessionData
          if (parsed && parsed.tabs && parsed.tabs.length > 0) {
            session = parsed
          }
        }
        break
      } catch (e) {
        retry--
        if (retry > 0) {
          await new Promise<void>((resolve: (value: void) => void) => {
            setTimeout(() => resolve(), 100)
          })
        } else {
          logger.error('restoreSession', `KVStore 未就绪，放弃恢复: ${e}`)
        }
      }
    }
    if (!session) {
      this.freshStart()
      return
    }
    if (appSettings.restore_mode === 'ask' && this.hasRestorableTab(session)) {
      const uiReady = await this.waitForUIContext()
      if (uiReady) {
        const ok = await this.promptRestore()
        if (!ok) {
          this.freshStart()
          return
        }
      }
      // UIContext 未就绪时默认恢复，避免阻塞启动
    }
    const restored: TabInfo[] = []
    for (const t of session.tabs) {
      const tab = new TabInfo(t.id, false)
      tab.title = t.title || '轻鸿'
      tab.url = t.url || ''
      tab.isHome = !!t.isHome
      restored.push(tab)
    }
    this.tabs = restored
    this.nextId = session.nextId || (restored[restored.length - 1].id + 1)
    const activeId = session.activeTabId
    const activeExists = restored.some((t: TabInfo) => t.id === activeId)
    this.activeTabId = activeExists ? activeId : restored[0].id
    // 网页模式：主页态标签转为加载配置的主页网页
    const home = this.homeWebUrl()
    if (home !== '') {
      for (const t of restored) {
        if (t.isHome) {
          this.navigate(t, home)
        }
      }
    }
    logger.info('restoreSession', `恢复会话成功，标签数: ${restored.length}`)
  }

  /**
   * 全新启动：单标签主页
   */
  private freshStart(): void {
    this.tabs = []
    this.nextId = 1
    this.newTab('', null, false)
  }

  /**
   * 会话中是否存在网页态标签（ask 询问的前提）
   */
  private hasRestorableTab(session: SessionData): boolean {
    return session.tabs.some((t: TabSessionData): boolean => !t.isHome && !!t.url)
  }

  /**
   * 等待 UIContext 就绪（loadContent 回调完成前弹窗不可用）
   */
  private async waitForUIContext(timeoutMs: number = 3000): Promise<boolean> {
    const start = Date.now()
    while (!toastUtil.UIContext && Date.now() - start < timeoutMs) {
      await new Promise<void>((resolve: (value: void) => void) => {
        setTimeout(() => resolve(), 50)
      })
    }
    return toastUtil.UIContext !== undefined
  }

  /**
   * 弹窗询问是否恢复上次会话
   */
  private promptRestore(): Promise<boolean> {
    return new Promise<boolean>((resolve: (v: boolean) => void) => {
      toastUtil.showAlertDialog({
        title: $r('app.string.restore_prompt_title'),
        message: $r('app.string.restore_prompt_message'),
        autoCancel: false,
        alignment: DialogAlignment.Center,
        buttons: [
          {
            value: $r('app.string.restore_no'),
            style: DialogButtonStyle.DEFAULT,
            action: (): void => {
              resolve(false)
            }
          },
          {
            value: $r('app.string.restore_yes'),
            action: (): void => {
              resolve(true)
            }
          }
        ]
      }, 'restorePrompt')
    })
  }

  /**
   * 新建标签
   * @param skipHomeNav 跳过网页模式主页导航（弹窗转标签场景由内核自行加载）
   */
  newTab(url: string = '', incognito: boolean | null = null,
    toastOnLimit: boolean = true, skipHomeNav: boolean = false): TabInfo | null {
    if (this.tabs.length >= AppConstants.MAX_TABS) {
      if (toastOnLimit) {
        toastUtil.showToast({ message: $r('app.string.tab_limit_reached') })
      }
      return this.activeTab
    }
    const tab = new TabInfo(this.nextId++, incognito ?? appSettings.default_incognito)
    // 标签栈：记录打开者，返回键耗尽网页历史后关闭本标签回退到它
    tab.openerTabId = this.activeTabId
    this.tabs.push(tab)
    this.activeTabId = tab.id
    if (url) {
      this.navigate(tab, url)
    } else {
      const home = this.homeWebUrl()
      if (!skipHomeNav && home !== '') {
        this.navigate(tab, home)
      } else {
        this.saveSessionDebounced()
      }
    }
    return tab
  }

  /**
   * 新建无痕标签
   */
  newIncognitoTab(): TabInfo | null {
    return this.newTab('', true)
  }

  /**
   * 新标签页打开源码视图：捕获的 HTML 经 loadData 渲染，不走主流程导航
   */
  newViewSourceTab(srcUrl: string, html: string, title: string, incognito: boolean): TabInfo | null {
    const tab = this.newTab('', incognito, true, true)
    if (tab === null) {
      return null
    }
    tab.isHome = false
    tab.url = `${ViewSourceScripts.URL_PREFIX}${srcUrl}`
    tab.title = title
    tab.viewSourceHtml = html
    this.saveSessionDebounced()
    return tab
  }

  /**
   * 新建网络日志原生页标签（Via 式独立标签；记录源标签 id 供日志展示；瞬态不持久化）
   */
  newNetworkLogTab(): TabInfo | null {
    const sourceId = this.activeTabId
    const tab = this.newTab('', null, true, true)
    if (tab === null) {
      return null
    }
    tab.isHome = false
    tab.nativeView = 'network-log'
    tab.nativeParam = `${sourceId}`
    tab.title = ResourceUtils.getString($r('app.string.network_log'))
    this.saveSessionDebounced()
    return tab
  }

  /**
   * 全局无痕模式应用：将全部标签切换到目标无痕状态（全局开关变更时调用）
   */
  applyGlobalIncognito(target: boolean): void {
    for (const t of this.tabs) {
      if (t.isIncognito !== target) {
        this.toggleIncognito(t)
      }
    }
  }

  /**
   * 切换当前标签无痕状态（不新开标签）：
   * 网页态下走 主页态→网页态 重挂载流程，使 Web 以新 incognitoMode 重建
   */
  toggleIncognito(tab: TabInfo): void {
    tab.isIncognito = !tab.isIncognito
    if (tab.isHome) {
      return
    }
    const url = tab.url
    tab.controller = null
    tab.isHome = true
    tab.progress = 0
    tab.canBack = false
    tab.canForward = false
    // 用户手动切换无痕：重挂载时保持手动选择，不按站点覆盖重新过滤
    setTimeout(() => {
      this.navigate(tab, url, false)
    }, 50)
  }

  /**
   * 网页模式主页地址（未启用/未配置返回空串）
   */
  homeWebUrl(): string {
    if (appSettings.home_page_mode !== 'web') {
      return ''
    }
    return appSettings.home_page_url.trim()
  }

  /**
   * 当前标签是否停在网页模式主页上（返回到底交给系统退出）
   */
  isWebHome(tab: TabInfo): boolean {
    const home = this.homeWebUrl()
    return home !== '' && !tab.isHome && tab.url === home
  }

  /**
   * 确保 Web 控制器存在（渲染层挂载 Web 时调用）
   */
  ensureController(tab: TabInfo): webview.WebviewController {
    if (!tab.controller) {
      tab.controller = new webview.WebviewController()
    }
    return tab.controller as webview.WebviewController
  }

  /**
   * 导航到 URL
   * - 主页态：置 url、退出主页态，Web 挂载时以 src 自动加载
   * - 网页态：直接 controller.loadUrl
   * @param siteFilter 主页态时按站点无痕覆盖过滤创建（默认开；用户手动切换无痕/异常重挂载时关闭）
   */
  navigate(tab: TabInfo, url: string, siteFilter: boolean = true): void {
    const target = url.trim()
    if (!target) return
    if (tab.isHome) {
      // Web 创建期过滤：站点无痕覆盖优先于全局默认无痕开关
      if (siteFilter) {
        const incognito: boolean | null = siteSettingsVM.siteIncognitoOf(SiteSettingsViewModel.hostOf(target))
        if (incognito !== null) {
          tab.isIncognito = incognito
        }
      }
      tab.url = target
      tab.title = target
      tab.isHome = false
      // 离开主页即消耗/失效 lastWebUrl，前进态归位
      tab.lastWebUrl = ''
      tab.canForward = false
      if (!tab.controller) {
        tab.controller = new webview.WebviewController()
      }
    } else {
      tab.url = target
      try {
        (tab.controller as webview.WebviewController).loadUrl(target)
      } catch (e) {
        logger.error('navigate', `loadUrl 失败，重置标签重挂载: ${e}`)
        tab.controller = null
        tab.isHome = true
        tab.progress = 0
        // 下一帧重新走主页态→网页态挂载流程（保持当前无痕状态，不重新过滤）
        setTimeout(() => {
          this.navigate(tab, target, false)
        }, 50)
        return
      }
    }
    this.saveSessionDebounced()
  }

  /**
   * 回到主页态（释放 Web 实例）；网页模式下主页即配置网页
   */
  goHome(tab: TabInfo): void {
    const home = this.homeWebUrl()
    if (home !== '') {
      if (!tab.isHome && tab.url === home) {
        return
      }
      this.navigate(tab, home)
      return
    }
    if (!tab.isHome) {
      // 记录离开主页前的页面，主页态"前进"可返回该页
      tab.lastWebUrl = tab.url
    }
    tab.isHome = true
    tab.url = ''
    tab.title = '轻鸿'
    tab.progress = 0
    tab.canBack = false
    tab.canForward = tab.lastWebUrl !== ''
    tab.controller = null
    this.saveSessionDebounced()
  }

  /**
   * 切换标签
   */
  switchTab(id: number): void {
    this.activeTabId = id
    this.saveSessionDebounced()
  }

  /** 是否存在指定标签 */
  hasTab(id: number): boolean {
    return this.tabs.some((t: TabInfo): boolean => t.id === id)
  }

  /** 按 id 查找标签（不存在返回 null） */
  tabById(id: number): TabInfo | null {
    const t = this.tabs.find((x: TabInfo): boolean => x.id === id)
    return t === undefined ? null : t
  }

  /**
   * 关闭标签并切换到指定标签（标签栈返回：关闭"后面"的标签回退到打开它的标签）
   */
  closeTabAndSwitch(id: number, targetId: number): void {
    this.closeTab(id)
    if (this.hasTab(targetId)) {
      this.activeTabId = targetId
      this.saveSessionDebounced()
    }
  }

  /**
   * 关闭标签，自动选中相邻标签；开启提示时展示撤销关闭提示
   */
  closeTab(id: number): void {
    const idx = this.tabs.findIndex((t: TabInfo) => t.id === id)
    if (idx < 0) return
    const tab = this.tabs[idx]
    tab.controller = null
    this.tabs.splice(idx, 1)
    this.scheduleUndoTip(tab)
    if (this.tabs.length === 0) {
      this.newTab('', null, false)
      return
    }
    if (this.activeTabId === id) {
      const nextIdx = Math.min(idx, this.tabs.length - 1)
      this.activeTabId = this.tabs[nextIdx].id
    }
    this.saveSessionDebounced()
  }

  /**
   * 展示撤销关闭提示（4 秒后自动消失）
   */
  private scheduleUndoTip(tab: TabInfo): void {
    // 无痕标签关闭不留痕迹，不展示撤销提示
    if (tab.isIncognito) {
      return
    }
    this.recentClosed = tab
    if (!appSettings.show_undo_close_tip) {
      return
    }
    if (this.undoTipTimer >= 0) {
      clearTimeout(this.undoTipTimer)
    }
    this.showUndoTip = true
    this.undoTipTimer = setTimeout(() => {
      this.undoTipTimer = -1
      this.showUndoTip = false
      this.recentClosed = null
    }, AppConstants.UNDO_TIP_DURATION)
  }

  /**
   * 撤销关闭：恢复最近关闭的标签并激活
   */
  undoClose(): void {
    if (this.undoTipTimer >= 0) {
      clearTimeout(this.undoTipTimer)
      this.undoTipTimer = -1
    }
    const tab = this.recentClosed
    this.showUndoTip = false
    this.recentClosed = null
    if (!tab) return
    if (this.tabs.length >= AppConstants.MAX_TABS) {
      toastUtil.showToast({ message: $r('app.string.tab_limit_reached') })
      return
    }
    this.tabs.push(tab)
    this.activeTabId = tab.id
    this.saveSessionDebounced()
  }

  /**
   * 清除撤销关闭状态
   */
  private clearUndoTip(): void {
    if (this.undoTipTimer >= 0) {
      clearTimeout(this.undoTipTimer)
      this.undoTipTimer = -1
    }
    this.showUndoTip = false
    this.recentClosed = null
  }

  /**
   * 关闭全部标签（保留一个主页态标签）
   */
  closeAll(): void {
    for (const t of this.tabs) {
      t.controller = null
    }
    this.clearUndoTip()
    this.tabs = []
    this.newTab('', null, false)
  }

  /**
   * 防抖保存会话
   */
  saveSessionDebounced(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer)
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1
      this.saveSession()
    }, AppConstants.SESSION_SAVE_DEBOUNCE)
  }

  /**
   * 序列化会话到 KV（无痕标签不保存）
   */
  private saveSession(): void {
    try {
      const savedTabs: TabSessionData[] = []
      for (const t of this.tabs) {
        if (t.isIncognito) continue
        // 源码视图为瞬态内容，不随会话恢复
        if (t.viewSourceHtml !== '') continue
        // 原生视图标签为瞬态内容，不随会话恢复
        if (t.nativeView !== '') continue
        const data: TabSessionData = {
          id: t.id,
          title: t.title,
          url: t.url,
          isHome: t.isHome
        }
        savedTabs.push(data)
      }
      const session: SessionData = {
        tabs: savedTabs,
        activeTabId: this.activeTabId,
        nextId: this.nextId
      }
      kvDbUtil.putData(AppConstants.KV_KEY_SESSION, JSON.stringify(session)).catch((e: Object) => {
        logger.error('saveSession', `会话保存失败: ${e}`)
      })
    } catch (e) {
      logger.error('saveSession', `会话序列化失败: ${e}`)
    }
  }
}

export const tabsVM = new TabsViewModel()
