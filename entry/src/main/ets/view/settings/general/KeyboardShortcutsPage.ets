import { CustomContentDialog } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import { NaviBarButton } from '../../../components/NaviContainer';
import { SettingsScaffold, SettingsCard } from '../../../components/SettingsScaffold';
import { QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';


@Builder
export function KeyboardShortcutsBuilder() {
  KeyboardShortcutsPage()
}

/** 键盘快捷键条目：修饰键固定，仅最后一位按键可自定义 */
@ObservedV2
export class KbShortcut {
  id: string = ''
  label: ResourceStr = ''
  mods: string[] = []
  /** 额外固定组合显示（如刷新行的 F5 /） */
  fixedCombo: string = ''
  defKey: string = ''
  @Trace key: string = ''

  constructor(id: string, label: ResourceStr, mods: string[], fixedCombo: string, defKey: string) {
    this.id = id
    this.label = label
    this.mods = mods
    this.fixedCombo = fixedCombo
    this.defKey = defKey
    this.key = defKey
  }
}

/** 按键码转显示名（字母/数字/F1-F12/Tab/方向键/空格） */
function keyNameOf(code: number): string {
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
function isModifierCode(code: number): boolean {
  return code === KeyCode.KEYCODE_CTRL_LEFT || code === KeyCode.KEYCODE_CTRL_RIGHT
    || code === KeyCode.KEYCODE_SHIFT_LEFT || code === KeyCode.KEYCODE_SHIFT_RIGHT
    || code === KeyCode.KEYCODE_ALT_LEFT || code === KeyCode.KEYCODE_ALT_RIGHT
    || code === KeyCode.KEYCODE_META_LEFT || code === KeyCode.KEYCODE_META_RIGHT
}

@ComponentV2
struct KeyboardShortcutsPage {

  @Local shortcuts: KbShortcut[] = []
  @Local editingId: string = ''

  private resetDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.shortcuts = this.defaultShortcuts()
    this.loadOverrides()
    this.initDialogs()
  }

  /** 默认快捷键表（顺序即显示顺序） */
  private defaultShortcuts(): KbShortcut[] {
    return [
      new KbShortcut('new_tab', $r('app.string.new_tab'), ['Ctrl'], '', 'T'),
      new KbShortcut('next_tab', $r('app.string.next_tab'), ['Ctrl'], '', 'Tab'),
      new KbShortcut('prev_tab', $r('app.string.previous_tab'), ['Ctrl', 'Shift'], '', 'Tab'),
      new KbShortcut('go_back', $r('app.string.web_back'), ['Alt'], '', '←'),
      new KbShortcut('go_forward', $r('app.string.web_forward'), ['Alt'], '', '→'),
      new KbShortcut('close_tab', $r('app.string.close_tab'), ['Ctrl'], '', 'W'),
      new KbShortcut('menu', $r('app.string.menu'), ['Alt'], '', 'F'),
      new KbShortcut('bookmarks', $r('app.string.bookmarks'), ['Ctrl', 'Shift'], '', 'B'),
      new KbShortcut('history', $r('app.string.history'), ['Ctrl'], '', 'H'),
      new KbShortcut('find_in_page', $r('app.string.find_in_page'), ['Ctrl'], '', 'F'),
      new KbShortcut('enter_url', $r('app.string.enter_url'), ['Ctrl'], '', '1'),
      new KbShortcut('refresh', $r('app.string.refresh_page'), ['Ctrl'], 'F5', 'R'),
      new KbShortcut('view_source', $r('app.string.view_source'), ['Ctrl'], '', 'U'),
      new KbShortcut('add_bookmark', $r('app.string.add_bookmark'), ['Ctrl'], '', 'D')
    ]
  }

  /** 应用已保存的自定义按键覆盖项 */
  private loadOverrides(): void {
    const raw: string = appSettings.keyboard_shortcuts
    if (raw === '') {
      return
    }
    const map: Record<string, string> = {}
    for (const part of raw.split(',')) {
      const idx: number = part.indexOf(':')
      if (idx > 0) {
        map[part.substring(0, idx)] = part.substring(idx + 1)
      }
    }
    for (const s of this.shortcuts) {
      const k: string = map[s.id]
      if (k !== undefined && k !== '') {
        s.key = k
      }
    }
  }

  /** 导出自定义覆盖项（仅与默认不同的条目） */
  private persistOverrides(): void {
    const parts: string[] = []
    for (const s of this.shortcuts) {
      if (s.key !== s.defKey) {
        parts.push(`${s.id}:${s.key}`)
      }
    }
    appSettings.keyboard_shortcuts = parts.join(',')
  }

  /** 同修饰键组合下按键是否已被其他条目占用（忽略大小写） */
  private hasConflict(target: KbShortcut, newKey: string): boolean {
    const modsSig: string = target.mods.join('+')
    const lower: string = newKey.toLowerCase()
    for (const s of this.shortcuts) {
      if (s.id !== target.id && s.mods.join('+') === modsSig
        && s.key.toLowerCase() === lower) {
        return true
      }
    }
    return false
  }

  private initDialogs(): void {
    this.resetDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.reset_shortcuts'),
        secondaryTitle: $r('app.string.reset_shortcuts_confirm'),
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.reset')], true,
          (index: number): void => {
            if (index === 1) {
              this.doReset()
            }
            this.resetDialog?.close()
          })
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  /** 恢复全部快捷键为默认设置 */
  private doReset(): void {
    this.editingId = ''
    appSettings.keyboard_shortcuts = ''
    this.shortcuts = this.defaultShortcuts()
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.keyboard_shortcuts'),
      buttons: [new NaviBarButton({
        text: $r('app.string.reset'),
        backgroundColor: Color.Transparent,
        action: (): void => {
          this.editingId = ''
          this.resetDialog?.open()
        }
      })],
      footer: (): void => {
        this.pageFooter()
      }
    })
  }

  /** 快捷键卡片 */
  @Builder
  pageFooter() {
    SettingsCard({
      topMargin: 10,
      content: (): void => {
        this.KeyContent()
      }
    })
  }

  @Builder
  KeyContent() {
    ForEach(this.shortcuts, (s: KbShortcut) => {
      this.shortcutRow(s)
    }, (s: KbShortcut) => s.id)
  }

  /** 键帽 */
  @Builder
  keyCap(label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .borderRadius(6)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .border({ width: 1, color: $r('sys.color.comp_divider') })
  }

  /** 快捷键行：左键帽组合，右功能 */
  @Builder
  shortcutRow(s: KbShortcut) {
    Row() {
      Row({ space: 4 }) {
        if (s.fixedCombo !== '') {
          this.keyCap(s.fixedCombo)
          Text('/')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
        ForEach(s.mods, (m: string) => {
          this.keyCap(m)
          Text('+')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }, (m: string) => m)
        if (this.editingId === s.id) {
          Text($r('app.string.press_new_key'))
            .fontSize(13)
            .fontColor(QhState.currentThemeColor)
            .padding({ left: 4, right: 4 })
        } else {
          this.keyCap(s.key)
        }
      }
      .alignItems(VerticalAlign.Center)

      Text(s.label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .padding({ left: 12 })
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.editingId === s.id ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .focusable(true)
    .onClick(() => {
      this.editingId = this.editingId === s.id ? '' : s.id
    })
    .onKeyEvent((e: KeyEvent) => {
      if (this.editingId !== s.id || e.type !== KeyType.Down) {
        return
      }
      if (isModifierCode(e.keyCode)) {
        return
      }
      const name: string = keyNameOf(e.keyCode)
      if (name === '') {
        return
      }
      this.editingId = ''
      if (this.hasConflict(s, name)) {
        toastUtil.showToast({ message: $r('app.string.shortcut_key_conflict') })
        return
      }
      s.key = name
      this.persistOverrides()
    })
  }
}
