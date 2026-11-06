import { CustomContentDialog } from '@kit.ArkUI';
import { NaviBarButton } from '../../../components/NaviContainer';
import { SettingsScaffold, SettingsCard } from '../../../components/SettingsScaffold';
import { QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { KB_SHORTCUTS, kbKeyNameOf, kbIsModifierCode } from '../../../common/constants/KbShortcuts';


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

/** 按键码转显示名与修饰键判定见 common/constants/KbShortcuts.ets */

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

  /** 默认快捷键表（顺序即显示顺序，定义共享自 common/constants/KbShortcuts.ets） */
  private defaultShortcuts(): KbShortcut[] {
    const list: KbShortcut[] = []
    for (const d of KB_SHORTCUTS) {
      list.push(new KbShortcut(d.id, d.label, d.mods, d.fixedCombo, d.defKeyName))
    }
    return list
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

  /** 快捷键卡片（自定义行 + 固定组合行） */
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
    Divider()
      .color($r('sys.color.comp_divider'))
      .margin({ left: 16, right: 16 })
    this.fixedKeyRow(['Ctrl', '1…8'], $r('app.string.kb_switch_tab_num'))
    this.fixedKeyRow(['Ctrl', '9'], $r('app.string.kb_switch_tab_last'))
    this.fixedKeyRow(['Esc'], $r('app.string.kb_esc_close'))
  }

  /** 固定组合行（键帽展示，不可编辑） */
  @Builder
  fixedKeyRow(keys: string[], label: ResourceStr) {
    Row() {
      Row({ space: 4 }) {
        ForEach(keys, (k: string, idx: number) => {
          if (idx > 0) {
            Text('+')
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
          }
          this.keyCap(k)
        }, (k: string) => k)
      }
      .alignItems(VerticalAlign.Center)

      Text(label)
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
      if (kbIsModifierCode(e.keyCode)) {
        return
      }
      const name: string = kbKeyNameOf(e.keyCode)
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
