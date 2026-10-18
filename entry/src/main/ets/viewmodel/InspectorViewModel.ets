import { tabsVM, TabInfo } from './TabsViewModel';
import { toastUtil } from '../common/utils/ToastUtils';
import { adBlockEngine } from '../common/utils/AdBlockEngine';
import { InspectScripts } from '../common/utils/InspectScripts';
import { SiteSettingsViewModel } from './SiteSettingsViewModel';
import { createLogger } from '../common/utils/Logger';
import { webview } from '@kit.ArkWeb';

const logger = createLogger('InspectorVM')

/** 控制台日志条目 */
export class InspectLog {
  /** 递增序号（ForEach key 用） */
  readonly seq: number
  /** 等级：log | warn | error | result */
  readonly level: string
  readonly msg: string
  readonly src: string
  readonly line: string
  /** 展示时间（HH:MM:SS） */
  readonly time: string

  constructor(seq: number, level: string, msg: string, src: string, line: string, time: string) {
    this.seq = seq
    this.level = level
    this.msg = msg
    this.src = src
    this.line = line
    this.time = time
  }
}

/** 页内选点回传负载（JSON.parse 目标类型） */
class InspectPickPayload {
  t: string = 'pick'
  html: string = ''
  sel: string = ''
  desc: string = ''
}

/** 控制台求值结果（JSON.parse 目标类型） */
class InspectEvalResult {
  v?: string
  e?: string
}

/**
 * 元素审查面板视图模型：
 * - 元素页：选点蒙版（页内 JS）→ __qhNative.inspectEvent 回传 → 源码/结构双视图展示
 * - 调试页：onConsole 捕获的分级日志 + JS 求值输入
 * - AD：选中元素 → custom_rules.txt 追加「域名##选择器」元素隐藏规则 + 页内即时隐藏样式
 */
@ObservedV2
export class InspectorViewModel {
  /** 面板是否展示（标签切换/阅读模式由渲染条件隐藏，状态保留待恢复） */
  @Trace showInspector: boolean = false
  /** 功能页：element 元素 | console 调试 */
  @Trace mode: string = 'element'
  /** 元素页显示效果：false 源码 | true 结构 */
  @Trace treeView: boolean = false
  /** 是否处于选点模式（面板收窄、页面出现预选蒙版） */
  @Trace selecting: boolean = false
  /** 面板是否撑满页面高度 */
  @Trace fullHeight: boolean = false
  /** 当前选中元素（'' = 未选中） */
  @Trace pickedHtml: string = ''
  @Trace pickedSelector: string = ''
  @Trace pickedDesc: string = ''
  /** 父级导航深度（>0 时「子」按钮可用，用于回退） */
  @Trace childDepth: number = 0
  /** 调试页当前展示的日志列表 */
  @Trace currentLogs: InspectLog[] = []
  /** 面板绑定的标签 id（-1 = 未绑定） */
  @Trace boundTabId: number = -1

  /** 按标签存的日志（上限 MAX_LOGS，超出丢头部） */
  private logsByTab: Map<number, InspectLog[]> = new Map()
  private logSeq: number = 0
  private static readonly MAX_LOGS: number = 500
  /** 选择器字符白名单（防注入 blockStyleScript） */
  private static readonly SEL_OK: RegExp = /^[A-Za-z0-9_\-#.>:+() ]+$/

  /** 打开面板（绑定当前网页标签） */
  open(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      return
    }
    this.boundTabId = tab.id
    this.mode = 'element'
    this.treeView = false
    this.selecting = false
    this.pickedHtml = ''
    this.pickedSelector = ''
    this.pickedDesc = ''
    this.childDepth = 0
    this.bindLogs(tab.id)
    this.showInspector = true
  }

  /** 关闭面板并清理页内蒙版 */
  close(): void {
    this.runInspectScript(InspectScripts.exitScript())
    this.selecting = false
    this.showInspector = false
  }

  /** 面板被渲染条件隐藏（标签切换/阅读模式/关闭）时清理页内状态 */
  onPanelHidden(): void {
    this.runInspectScript(InspectScripts.exitScript())
    this.selecting = false
  }

  /** 返回键：选点中先退选点（保持面板），否则关面板 */
  handleBack(): void {
    if (this.selecting) {
      this.cancelSelect()
      return
    }
    this.close()
  }

  /** 进入选点模式 */
  startSelect(): void {
    if (this.boundTabId < 0) {
      return
    }
    this.selecting = true
    this.runInspectScript(InspectScripts.enterSelectScript())
  }

  /** 退出选点模式（保持面板与已选元素） */
  cancelSelect(): void {
    this.runInspectScript(InspectScripts.exitScript())
    this.selecting = false
  }

  /** 切到当前选中元素的父元素 */
  pickParent(): void {
    if (this.pickedSelector === '') {
      toastUtil.showToast({ message: $r('app.string.inspect_pick_first') })
      return
    }
    this.runInspectScript(InspectScripts.parentScript())
  }

  /** 回退到上一个选中元素（对应父级导航） */
  pickChild(): void {
    if (this.childDepth <= 0) {
      return
    }
    this.childDepth--
    this.runInspectScript(InspectScripts.childScript())
  }

  /** 拦截选中元素：追加域名级元素隐藏规则 + 页内即时隐藏 */
  blockPicked(): void {
    if (this.pickedSelector === '') {
      toastUtil.showToast({ message: $r('app.string.inspect_pick_first') })
      return
    }
    const tab = tabsVM.tabById(this.boundTabId)
    const host = tab === null ? '' : SiteSettingsViewModel.hostOf(tab.url)
    const rule = `${host}##${this.pickedSelector}`
    const existing = adBlockEngine.loadCustomRulesSync()
    if (existing.split('\n').indexOf(rule) < 0) {
      const trimmed = existing.replace(/\s+$/, '')
      const next = trimmed === '' ? rule : `${trimmed}\n${rule}`
      adBlockEngine.saveCustomRules(next).catch((e: Object): void => {
        logger.error(`blockPicked 保存规则失败: ${e}`)
      })
    }
    if (this.pickedSelector.match(InspectorViewModel.SEL_OK) !== null) {
      this.runInspectScript(InspectScripts.blockStyleScript(this.pickedSelector))
    }
    toastUtil.showToast({ message: $r('app.string.inspect_blocked') })
  }

  /** 页内选点回传（__qhNative.inspectEvent） */
  onInspectEvent(tabId: number, payloadJson: string): void {
    if (tabId !== this.boundTabId) {
      return
    }
    try {
      const p = JSON.parse(payloadJson) as InspectPickPayload
      logger.info(`onInspectEvent 收到选点 t=${p.t} htmlLen=${p.html.length} sel=${p.sel}`)
      this.pickedHtml = p.html
      this.pickedSelector = p.sel
      this.pickedDesc = p.desc
      if (p.t === 'parent') {
        this.childDepth++
      } else if (p.t === 'pick') {
        this.childDepth = 0
      }
      this.selecting = false
    } catch (e) {
      logger.error(`onInspectEvent 解析失败: ${e}`)
    }
  }

  /** 绑定标签导航（onPageBegin）：清选点与选中态（面板保留） */
  resetForNavigation(tabId: number): void {
    if (tabId !== this.boundTabId || !this.showInspector) {
      return
    }
    this.runInspectScript(InspectScripts.exitScript())
    this.selecting = false
    this.pickedHtml = ''
    this.pickedSelector = ''
    this.pickedDesc = ''
    this.childDepth = 0
  }

  /** 控制台求值（调试页输入框） */
  evalConsole(expr: string): void {
    const c = this.boundController()
    if (c === null || expr.trim() === '') {
      return
    }
    c.runJavaScript(InspectScripts.evalScript(expr))
      .then((raw: string): void => {
        let inner: string = raw
        try {
          inner = JSON.parse(raw) as string
        } catch (e) {
          // 保留原始返回
        }
        try {
          const r = JSON.parse(inner) as InspectEvalResult
          if (r.e !== undefined) {
            this.pushLog(this.boundTabId, 'error', `Uncaught ${r.e}`, '', '')
          } else {
            this.pushLog(this.boundTabId, 'result', r.v ?? 'undefined', '', '')
          }
        } catch (e) {
          this.pushLog(this.boundTabId, 'result', inner, '', '')
        }
      })
      .catch((): void => {
      })
  }

  /** 追加日志（onConsole 捕获 / 求值结果） */
  pushLog(tabId: number, level: string, msg: string, src: string, line: string): void {
    let list = this.logsByTab.get(tabId)
    if (list === undefined) {
      list = []
      this.logsByTab.set(tabId, list)
    }
    const d = new Date()
    const hh = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`
    const mm = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`
    const ss = d.getSeconds() < 10 ? `0${d.getSeconds()}` : `${d.getSeconds()}`
    list.push(new InspectLog(this.logSeq++, level, msg, src, line, `${hh}:${mm}:${ss}`))
    if (list.length > InspectorViewModel.MAX_LOGS) {
      list.splice(0, list.length - InspectorViewModel.MAX_LOGS)
    }
    if (tabId === this.boundTabId) {
      this.currentLogs = list
    }
  }

  /** 清空调试页日志（当前绑定标签） */
  clearLogs(): void {
    if (this.boundTabId < 0) {
      return
    }
    this.logsByTab.set(this.boundTabId, [])
    this.currentLogs = []
  }

  /** 标签关闭时释放日志 */
  removeLogs(tabId: number): void {
    this.logsByTab.delete(tabId)
  }

  private bindLogs(tabId: number): void {
    const list = this.logsByTab.get(tabId)
    this.currentLogs = list === undefined ? [] : list
  }

  private boundController(): webview.WebviewController | null {
    const tab = tabsVM.tabById(this.boundTabId)
    if (tab === null) {
      return null
    }
    return tab.controller
  }

  private runInspectScript(script: string): void {
    const c = this.boundController()
    if (c === null) {
      return
    }
    try {
      c.runJavaScript(script).catch((): void => {
      })
    } catch (e) {
      logger.error(`runInspectScript 失败: ${e}`)
    }
  }
}

/** 元素审查面板全局单例 */
export const inspectorVM = new InspectorViewModel()
