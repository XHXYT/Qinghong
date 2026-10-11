import { webview } from '@kit.ArkWeb';
import { QhState } from '../entryability/AppState';
import { AppConstants } from '../common/constants/AppConstants';
import { kvDbUtil } from '../common/utils/KVdbUtil';
import { appSettings } from '../common/entity/SettingsModel';
import { createLogger } from '../common/utils/Logger';
import { toastUtil } from '../common/utils/ToastUtils';

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

  private nextId: number = 1
  private saveTimer: number = -1

  constructor() {
  }

  /**
   * 当前激活标签
   */
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
   * 恢复上次会话（KV），失败或无会话则新建单标签主页
   */
  async restoreSession(): Promise<void> {
    if (appSettings.restore_session) {
      let retry = 3
      while (retry > 0) {
        try {
          const raw = await kvDbUtil.getData<string>(AppConstants.KV_KEY_SESSION, '')
          if (raw) {
            const session = JSON.parse(raw) as SessionData
            if (session && session.tabs && session.tabs.length > 0) {
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
              const activeExists = restored.some((t: TabInfo) => t.id === session.activeTabId)
              this.activeTabId = activeExists ? session.activeTabId : restored[0].id
              logger.info('restoreSession', `恢复会话成功，标签数: ${restored.length}`)
              return
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
    }
    // 全新启动：单标签主页
    this.tabs = []
    this.nextId = 1
    this.newTab('', null, false)
  }

  /**
   * 新建标签
   */
  newTab(url: string = '', incognito: boolean | null = null,
    toastOnLimit: boolean = true): TabInfo | null {
    if (this.tabs.length >= AppConstants.MAX_TABS) {
      if (toastOnLimit) {
        toastUtil.showToast({ message: $r('app.string.tab_limit_reached') })
      }
      return this.activeTab
    }
    const tab = new TabInfo(this.nextId++, incognito ?? appSettings.default_incognito)
    this.tabs.push(tab)
    this.activeTabId = tab.id
    if (url) {
      this.navigate(tab, url)
    } else {
      this.saveSessionDebounced()
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
   */
  navigate(tab: TabInfo, url: string): void {
    const target = url.trim()
    if (!target) return
    if (tab.isHome) {
      tab.url = target
      tab.title = target
      tab.isHome = false
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
        // 下一帧重新走主页态→网页态挂载流程
        setTimeout(() => {
          this.navigate(tab, target)
        }, 50)
        return
      }
    }
    this.saveSessionDebounced()
  }

  /**
   * 回到主页态（释放 Web 实例）
   */
  goHome(tab: TabInfo): void {
    tab.isHome = true
    tab.url = ''
    tab.title = '轻鸿'
    tab.progress = 0
    tab.canBack = false
    tab.canForward = false
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

  /**
   * 关闭标签，自动选中相邻标签
   */
  closeTab(id: number): void {
    const idx = this.tabs.findIndex((t: TabInfo) => t.id === id)
    if (idx < 0) return
    const tab = this.tabs[idx]
    tab.controller = null
    this.tabs.splice(idx, 1)
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
   * 关闭全部标签（保留一个主页态标签）
   */
  closeAll(): void {
    for (const t of this.tabs) {
      t.controller = null
    }
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
