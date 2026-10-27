import { KeyCode } from '@kit.InputKit';

/**
 * 键盘快捷键定义（操作设定-键盘快捷键）：
 * 修饰键固定（Ctrl/Shift/Alt），仅末位按键可自定义；
 * fixedKeyCode 为额外固定组合（<0 无，如刷新的 F5）
 */
export class KbShortcutDef {
  readonly id: string = ''
  readonly label: ResourceStr = ''
  readonly mods: string[] = []
  readonly fixedKeyCode: number = -1
  readonly fixedCombo: string = ''
  readonly defKeyName: string = ''

  constructor(id: string, label: ResourceStr, mods: string[], fixedKeyCode: number,
    fixedCombo: string, defKeyName: string) {
    this.id = id
    this.label = label
    this.mods = mods
    this.fixedKeyCode = fixedKeyCode
    this.fixedCombo = fixedCombo
    this.defKeyName = defKeyName
  }
}

/** 默认快捷键表（顺序即设置页显示顺序） */
export const KB_SHORTCUTS: KbShortcutDef[] = [
  new KbShortcutDef('new_tab', $r('app.string.new_tab'), ['Ctrl'], -1, '', 'T'),
  new KbShortcutDef('next_tab', $r('app.string.next_tab'), ['Ctrl'], -1, '', 'Tab'),
  new KbShortcutDef('prev_tab', $r('app.string.previous_tab'), ['Ctrl', 'Shift'], -1, '', 'Tab'),
  new KbShortcutDef('go_back', $r('app.string.web_back'), ['Alt'], -1, '', '←'),
  new KbShortcutDef('go_forward', $r('app.string.web_forward'), ['Alt'], -1, '', '→'),
  new KbShortcutDef('close_tab', $r('app.string.close_tab'), ['Ctrl'], -1, '', 'W'),
  new KbShortcutDef('menu', $r('app.string.menu'), ['Alt'], -1, '', 'F'),
  new KbShortcutDef('bookmarks', $r('app.string.bookmarks'), ['Ctrl', 'Shift'], -1, '', 'B'),
  new KbShortcutDef('history', $r('app.string.history'), ['Ctrl'], -1, '', 'H'),
  new KbShortcutDef('find_in_page', $r('app.string.find_in_page'), ['Ctrl'], -1, '', 'F'),
  new KbShortcutDef('enter_url', $r('app.string.enter_url'), ['Ctrl'], -1, '', '1'),
  new KbShortcutDef('refresh', $r('app.string.refresh_page'), ['Ctrl'], KeyCode.KEYCODE_F5, 'F5', 'R'),
  new KbShortcutDef('view_source', $r('app.string.view_source'), ['Ctrl'], -1, '', 'U'),
  new KbShortcutDef('add_bookmark', $r('app.string.add_bookmark'), ['Ctrl'], -1, '', 'D'),
  new KbShortcutDef('print_page', $r('app.string.print_web_page'), ['Ctrl'], -1, '', 'P')
]

/** 按键码转显示名（字母/数字/F1-F12/Tab/方向键/空格） */
export function kbKeyNameOf(code: number): string {
  if (code >= KeyCode.KEYCODE_A && code <= KeyCode.KEYCODE_Z) {
    return String.fromCharCode(65 + code - KeyCode.KEYCODE_A)
  }
  if (code >= KeyCode.KEYCODE_0 && code <= KeyCode.KEYCODE_9) {
    return String.fromCharCode(48 + code - KeyCode.KEYCODE_0)
  }
  if (code >= KeyCode.KEYCODE_F1 && code <= KeyCode.KEYCODE_F12) {
    return `F${code - KeyCode.KEYCODE_F1 + 1}`
  }
  if (code === KeyCode.KEYCODE_TAB) {
    return 'Tab'
  }
  if (code === KeyCode.KEYCODE_DPAD_LEFT) {
    return '←'
  }
  if (code === KeyCode.KEYCODE_DPAD_RIGHT) {
    return '→'
  }
  if (code === KeyCode.KEYCODE_DPAD_UP) {
    return '↑'
  }
  if (code === KeyCode.KEYCODE_DPAD_DOWN) {
    return '↓'
  }
  if (code === KeyCode.KEYCODE_SPACE) {
    return 'Space'
  }
  return ''
}

/** 是否修饰键（Ctrl/Shift/Alt/Meta 左右键） */
export function kbIsModifierCode(code: number): boolean {
  return code === KeyCode.KEYCODE_CTRL_LEFT || code === KeyCode.KEYCODE_CTRL_RIGHT
    || code === KeyCode.KEYCODE_SHIFT_LEFT || code === KeyCode.KEYCODE_SHIFT_RIGHT
    || code === KeyCode.KEYCODE_ALT_LEFT || code === KeyCode.KEYCODE_ALT_RIGHT
    || code === KeyCode.KEYCODE_META_LEFT || code === KeyCode.KEYCODE_META_RIGHT
}
