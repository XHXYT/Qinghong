import { SettingsScaffold, SettingsSection, SettingsCard } from '../../../components/SettingsScaffold';
import { appSettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { VIDEO_KB_SHORTCUTS, kbKeyNameOf, kbIsModifierCode, parseVideoKbOverrides } from '../../../common/constants/KbShortcuts';
import { QhState } from '../../../entryability/AppState';
import { toastUtil } from '../../../common/utils/ToastUtils';

@Builder
export function VideoControlBuilder() {
  VideoControlPage()
}

/** 视频快捷键行：动作 + 当前键位（键位可自定义） */
@ObservedV2
class VideoKbRow {
  id: string = ''
  label: ResourceStr = ''
  defKey: string = ''
  @Trace key: string = ''

  constructor(id: string, label: ResourceStr, defKey: string) {
    this.id = id
    this.label = label
    this.defKey = defKey
    this.key = defKey
  }
}

/**
 * 视频控制：网页视频触屏手势（总开关 + 细项）、键盘快捷键（开关 + 键位自定义）；
 * 修改在新加载的页面生效
 */
@ComponentV2
struct VideoControlPage {

  @Local groups: SettingsSection[] = []
  /** 手势细项引用：总开关切换时改 enabled/disabledHint（@Trace 精准刷新） */
  private gestureSubItems: CustomItemInfo[] = []
  /** 键盘快捷键行 */
  @Local kbRows: VideoKbRow[] = []
  /** 正在改键的行 id（空 = 无） */
  @Local editingId: string = ''

  aboutToAppear(): void {
    this.buildItems()
    this.loadKbRows()
  }

  /** 手势总开关开启时细项才可用 */
  private gestureOn(): boolean {
    return appSettings.video_gesture_enabled
  }

  private toggleItem(id: string, title: ResourceStr, subtitle: ResourceStr,
    get: () => boolean, set: (v: boolean) => void): CustomItemInfo {
    const item: CustomItemInfo = new CustomItemInfo({
      id: id,
      title: title,
      subtitle: subtitle,
      type: ItemActionType.TOGGLE,
      value: get(),
      onChange: (v: string | boolean | number): void => {
        set(v as boolean)
      }
    })
    return item
  }

  /** 总开关切换后联动细项可用态（V2 @Trace 自动刷新，无需重建列表） */
  private updateGestureItems(): void {
    const on = this.gestureOn()
    for (const it of this.gestureSubItems) {
      it.enabled = on
      it.disabledHint = on ? '' : $r('app.string.video_gesture_disabled_hint')
    }
  }

  private buildItems(): void {
    const groups: SettingsSection[] = []

    // 手势操作
    const gGesture = new SettingsSection('gestures', $r('app.string.video_control_group_gestures'))
    const master = this.toggleItem('gesture_master',
      $r('app.string.video_gesture_enable'), $r('app.string.video_gesture_enable_desc'),
      (): boolean => appSettings.video_gesture_enabled,
      (v: boolean): void => {
        appSettings.video_gesture_enabled = v
        this.updateGestureItems()
      })
    gGesture.items.push(master)
    this.gestureSubItems = []
    const subDefs: CustomItemInfo[] = [
      this.toggleItem('gesture_double_tap',
        $r('app.string.video_gesture_double_tap'), $r('app.string.video_gesture_double_tap_desc'),
        (): boolean => appSettings.video_gesture_double_tap,
        (v: boolean): void => {
          appSettings.video_gesture_double_tap = v
        }),
      this.toggleItem('gesture_swipe_seek',
        $r('app.string.video_gesture_swipe_seek'), $r('app.string.video_gesture_swipe_seek_desc'),
        (): boolean => appSettings.video_gesture_swipe_seek,
        (v: boolean): void => {
          appSettings.video_gesture_swipe_seek = v
        }),
      this.toggleItem('gesture_side_slide',
        $r('app.string.video_gesture_side_slide'), $r('app.string.video_gesture_side_slide_desc'),
        (): boolean => appSettings.video_gesture_side_slide,
        (v: boolean): void => {
          appSettings.video_gesture_side_slide = v
        }),
      this.toggleItem('gesture_tap_toggle',
        $r('app.string.video_gesture_tap_toggle'), $r('app.string.video_gesture_tap_toggle_desc'),
        (): boolean => appSettings.video_gesture_tap_toggle,
        (v: boolean): void => {
          appSettings.video_gesture_tap_toggle = v
        }),
      this.toggleItem('gesture_long_press',
        $r('app.string.video_gesture_long_press'), $r('app.string.video_gesture_long_press_desc'),
        (): boolean => appSettings.video_gesture_long_press,
        (v: boolean): void => {
          appSettings.video_gesture_long_press = v
        })
    ]
    for (const it of subDefs) {
      if (!this.gestureOn()) {
        it.enabled = false
        it.disabledHint = $r('app.string.video_gesture_disabled_hint')
      }
      this.gestureSubItems.push(it)
      gGesture.items.push(it)
    }
    groups.push(gGesture)

    // 键盘快捷键（开关；键位自定义在下方键位卡片）
    const gKb = new SettingsSection('keyboard', $r('app.string.video_control_group_keyboard'))
    gKb.items.push(this.toggleItem('keyboard_shortcuts',
      $r('app.string.video_keyboard_shortcuts'), $r('app.string.video_keyboard_shortcuts_desc'),
      (): boolean => appSettings.video_keyboard_shortcuts,
      (v: boolean): void => {
        appSettings.video_keyboard_shortcuts = v
      }))
    groups.push(gKb)

    this.groups = groups
  }

  /** 从设置加载快捷键行（含用户自定义覆盖） */
  private loadKbRows(): void {
    const rows: VideoKbRow[] = []
    const ov: Record<string, string> = parseVideoKbOverrides(appSettings.video_kb_keys)
    for (const d of VIDEO_KB_SHORTCUTS) {
      const row: VideoKbRow = new VideoKbRow(d.id, d.label, d.defKeyName)
      const k: string = ov[d.id]
      if (k !== undefined && k !== '') {
        row.key = k
      }
      rows.push(row)
    }
    this.kbRows = rows
  }

  /** 导出自定义覆盖项（仅与默认不同的条目） */
  private persistKb(): void {
    const parts: string[] = []
    for (const r of this.kbRows) {
      if (r.key !== r.defKey) {
        parts.push(`${r.id}:${r.key}`)
      }
    }
    appSettings.video_kb_keys = parts.join(',')
  }

  /** 键位是否已被其他条目占用（忽略大小写） */
  private hasKbConflict(target: VideoKbRow, newKey: string): boolean {
    const lower: string = newKey.toLowerCase()
    for (const r of this.kbRows) {
      if (r.id !== target.id && r.key.toLowerCase() === lower) {
        return true
      }
    }
    return false
  }

  /** 恢复全部键位为默认 */
  private resetKb(): void {
    this.editingId = ''
    appSettings.video_kb_keys = ''
    this.loadKbRows()
    toastUtil.showToast({ message: $r('app.string.video_kb_reset_done') })
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.video_control'),
      sections: this.groups,
      footer: (): void => {
        this.kbCard()
      }
    })
  }

  /** 键位自定义卡片 */
  @Builder
  kbCard() {
    SettingsCard({
      topMargin: 10,
      content: (): void => {
        this.kbContent()
      }
    })
  }

  @Builder
  kbContent() {
    ForEach(this.kbRows, (r: VideoKbRow) => {
      this.kbRow(r)
    }, (r: VideoKbRow) => r.id)
    this.kbResetRow()
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

  /** 快捷键行：左键帽，右功能；点击进入改键，按键捕获后保存 */
  @Builder
  kbRow(r: VideoKbRow) {
    Row() {
      if (this.editingId === r.id) {
        Text($r('app.string.press_new_key'))
          .fontSize(13)
          .fontColor(QhState.currentThemeColor)
          .padding({ left: 4, right: 4 })
      } else {
        this.keyCap(r.key)
      }
      Text(r.label)
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
    .backgroundColor(this.editingId === r.id ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .focusable(true)
    .onClick(() => {
      this.editingId = this.editingId === r.id ? '' : r.id
    })
    .onKeyEvent((e: KeyEvent) => {
      if (this.editingId !== r.id || e.type !== KeyType.Down) {
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
      if (this.hasKbConflict(r, name)) {
        toastUtil.showToast({ message: $r('app.string.shortcut_key_conflict') })
        return
      }
      r.key = name
      this.persistKb()
    })
  }

  /** 恢复默认按键行 */
  @Builder
  kbResetRow() {
    Row() {
      Text($r('app.string.video_kb_reset'))
        .fontSize(15)
        .fontColor(QhState.currentThemeColor)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.resetKb()
    })
  }
}
