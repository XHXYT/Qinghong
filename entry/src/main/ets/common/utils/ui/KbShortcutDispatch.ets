import { KeyCode } from '@kit.InputKit';
import { KB_SHORTCUTS, KbShortcutDef, kbKeyNameOf, kbIsModifierCode, kbDigitOf } from '../../constants/KbShortcuts';
import { appSettings } from '../../entity/SettingsModel';
import { browserVM } from '../../../viewmodel/BrowserViewModel';
import { tabsVM, TabInfo } from '../../../viewmodel/TabsViewModel';
import { menuVM } from '../../../viewmodel/MenuViewModel';
import { QhState } from '../../../entryability/AppState';

/**
 * 键盘快捷键执行侧分发器：
 * 匹配设置页同源的 KB_SHORTCUTS 定义表（含自定义覆盖），
 * 命中后执行对应浏览器动作；返回 true 表示已消费
 */
class KbShortcutDispatch {

  handle(e: KeyEvent): boolean {
    if (e.type !== KeyType.Down || kbIsModifierCode(e.keyCode)) {
      return false
    }
    // Esc：仅当有本应用浮层可关闭时消费，否则透传给网页（退出全屏视频、关闭网页弹窗等）
    if (e.keyCode === KeyCode.KEYCODE_ESCAPE && !this.modOn(e, 'Ctrl')
      && !this.modOn(e, 'Shift') && !this.modOn(e, 'Alt')) {
      if (browserVM.showFindBar) {
        browserVM.showFindBar = false
        return true
      }
      if (menuVM.showMenu) {
        menuVM.showMenu = false
        return true
      }
      return false
    }
    for (const def of KB_SHORTCUTS) {
      if (this.match(e, def)) {
        this.run(def.id)
        return true
      }
    }
    // Ctrl+数字直达标签：1-8 第 n 个标签，9 最后一个；置于自定义表之后，用户改键优先
    if (this.modOn(e, 'Ctrl') && !this.modOn(e, 'Shift') && !this.modOn(e, 'Alt')) {
      const n: number = kbDigitOf(e.keyCode)
      if (n >= 1) {
        this.switchTabByNumber(n)
        return true
      }
    }
    return false
  }

  /** 单条定义匹配：固定组合（F5）或 修饰键精确匹配+末位按键 */
  private match(e: KeyEvent, def: KbShortcutDef): boolean {
    if (def.fixedKeyCode >= 0) {
      return e.keyCode === def.fixedKeyCode
        && !this.modOn(e, 'Ctrl') && !this.modOn(e, 'Shift') && !this.modOn(e, 'Alt')
    }
    const needCtrl: boolean = def.mods.indexOf('Ctrl') >= 0
    const needShift: boolean = def.mods.indexOf('Shift') >= 0
    const needAlt: boolean = def.mods.indexOf('Alt') >= 0
    if (needCtrl !== this.modOn(e, 'Ctrl') || needShift !== this.modOn(e, 'Shift')
      || needAlt !== this.modOn(e, 'Alt')) {
      return false
    }
    const pressed: string = kbKeyNameOf(e.keyCode)
    if (pressed === '') {
      return false
    }
    return pressed.toLowerCase() === this.activeKey(def).toLowerCase()
  }

  /** 修饰键是否按下（KeyEvent.getModifierKeyState，API 12+，可能不存在需容错） */
  private modOn(e: KeyEvent, key: string): boolean {
    return e.getModifierKeyState?.([key]) === true
  }

  /** 末位按键：自定义覆盖优先，否则默认 */
  private activeKey(def: KbShortcutDef): string {
    const raw: string = appSettings.keyboard_shortcuts
    if (raw !== '') {
      for (const part of raw.split(',')) {
        const idx: number = part.indexOf(':')
        if (idx > 0 && part.substring(0, idx) === def.id) {
          const k: string = part.substring(idx + 1)
          if (k !== '') {
            return k
          }
        }
      }
    }
    return def.defKeyName
  }

  /** 执行动作 */
  private run(id: string): void {
    switch (id) {
      case 'new_tab':
        tabsVM.newTab('', null, false)
        break
      case 'next_tab':
        this.switchTabStep(1)
        break
      case 'prev_tab':
        this.switchTabStep(-1)
        break
      case 'go_back':
        browserVM.goBack()
        break
      case 'go_forward':
        browserVM.goForward()
        break
      case 'close_tab': {
        const tab: TabInfo | null = tabsVM.tabById(tabsVM.activeTabId)
        if (tab !== null) {
          tabsVM.closeTab(tab.id)
        }
        break
      }
      case 'menu':
        menuVM.showMenu = !menuVM.showMenu
        break
      case 'bookmarks':
        QhState.pushPage('bookmarks', null)
        break
      case 'history':
        QhState.pushPage('history', null)
        break
      case 'find_in_page':
        browserVM.showFindBar = true
        break
      case 'enter_url':
        browserVM.isEditingAddress = true
        break
      case 'refresh':
        browserVM.refresh()
        break
      case 'zoom_in':
        browserVM.zoomStep(1)
        break
      case 'zoom_out':
        browserVM.zoomStep(-1)
        break
      case 'zoom_reset':
        browserVM.zoomStep(0)
        break
      case 'view_source':
        menuVM.openViewSource()
        break
      case 'add_bookmark':
        menuVM.openBookmarkEditor()
        break
      case 'print_page':
        menuVM.printPageToPdf()
        break
      default:
        break
    }
  }

  /** 相对当前标签步进切换（循环） */
  private switchTabStep(step: number): void {
    const count: number = tabsVM.tabs.length
    if (count <= 1) {
      return
    }
    const idx: number = tabsVM.tabs.findIndex((t: TabInfo): boolean => t.id === tabsVM.activeTabId)
    if (idx < 0) {
      return
    }
    const next: number = (idx + step + count) % count
    tabsVM.switchTab(tabsVM.tabs[next].id)
  }

  /** 数字直达标签（1-8 第 n 个，9 最后一个；越界不切换但仍消费按键） */
  private switchTabByNumber(n: number): void {
    const count: number = tabsVM.tabs.length
    if (count === 0) {
      return
    }
    const idx: number = n === 9 ? count - 1 : n - 1
    if (idx >= 0 && idx < count) {
      tabsVM.switchTab(tabsVM.tabs[idx].id)
    }
  }
}

export const kbShortcutDispatch = new KbShortcutDispatch()
