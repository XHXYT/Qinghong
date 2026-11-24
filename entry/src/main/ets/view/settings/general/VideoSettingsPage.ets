import { SettingsScaffold, SettingsSection, SettingsCard } from '../../../components/SettingsScaffold';
import { appSettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType, MenuOption } from '../../../common/entity/CusItemInfo';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { ResourceUtils } from '../../../common/utils/app/ResourceUtil';
import { VIDEO_KB_SHORTCUTS, kbKeyNameOf, kbIsModifierCode, parseVideoKbOverrides } from '../../../common/constants/KbShortcuts';
import { QhState } from '../../../entryability/AppState';
import { toastUtil } from '../../../common/utils/ui/ToastUtils';

function videoPlayerLabel(v: string): ResourceStr {
  if (v === 'none') {
    return $r('app.string.vp_none')
  }
  return $r('app.string.vp_system')
}

@Builder
export function VideoSettingsBuilder() {
  VideoSettingsPage()
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
 * 视频设置：外置播放器、网页视频（手势作用开关）、
 * 网页视频手势（三区双击/滑动/长按）、键盘快捷键（开关 + 键位自定义）；
 * 手势/快捷键修改在新加载的页面生效
 */
@ComponentV2
struct VideoSettingsPage {

  @Local groups: SettingsSection[] = []
  /** 键盘快捷键行 */
  @Local kbRows: VideoKbRow[] = []
  /** 正在改键的行 id（空 = 无） */
  @Local editingId: string = ''
  @Local picker: PickerConfig = new PickerConfig()
  @Local showSheet: boolean = false

  aboutToAppear(): void {
    this.buildItems()
    this.loadKbRows()
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

  /** 菜单选择行（三区双击/上下滑动作选择） */
  private menuItem(id: string, title: ResourceStr, subtitle: ResourceStr,
    get: () => string, set: (v: string) => void, options: MenuOption[]): CustomItemInfo {
    return new CustomItemInfo({
      id: id,
      title: title,
      subtitle: subtitle,
      type: ItemActionType.MENU,
      value: get(),
      menuOptions: options,
      onChange: (v: string | boolean | number): void => {
        set(v as string)
      }
    })
  }

  /**
   * 双击区行组：动作菜单行 +（动作=快退/快进时）下方秒数行（右侧小数字输入框）；
   * 动作切换后重建列表，秒数行随动作显隐
   */
  private dtapZone(out: CustomItemInfo[], id: string, title: ResourceStr, subtitle: ResourceStr,
    getAct: () => string, setAct: (v: string) => void,
    getSec: () => number, setSec: (v: number) => void,
    actOptions: MenuOption[]): void {
    out.push(this.menuItem(id, title, subtitle, getAct, (v: string): void => {
      setAct(v)
      this.buildItems()
    }, actOptions))
    const act: string = getAct()
    if (act === 'rewind' || act === 'forward') {
      out.push(new CustomItemInfo({
        id: id + '_sec',
        title: $r('app.string.video_dtap_sec'),
        subtitle: $r('app.string.video_dtap_sec_desc'),
        type: ItemActionType.INPUT_INLINE,
        value: String(getSec()),
        onChange: (v: string | boolean | number): void => {
          const n: number = Number(v)
          if (!Number.isNaN(n) && n >= 1 && n <= 600) {
            setSec(Math.floor(n))
          }
        }
      }))
    }
  }

  private buildItems(): void {
    const groups: SettingsSection[] = []

    // 播放器
    const gPlayer = new SettingsSection('player', $r('app.string.video_settings_group_player'))
    // 外置视频播放器：功能未接线，置灰待后续实现
    const videoPlayerItem: CustomItemInfo = new CustomItemInfo({
      id: 'video_player',
      title: $r('app.string.video_player'),
      type: ItemActionType.TEXT,
      value: ResourceUtils.getString(videoPlayerLabel(appSettings.video_player)),
      onChange: (v: string | boolean | number): void => {
        this.openVideoPlayerPicker()
      }
    })
    videoPlayerItem.enabled = false
    videoPlayerItem.disabledHint = $r('app.string.feature_not_available')
    gPlayer.items.push(videoPlayerItem)
    groups.push(gPlayer)

    // 网页视频：手势作用开关（关闭仅停用网页内手势，各项设置仍可修改）
    const gWeb = new SettingsSection('web', $r('app.string.video_settings_group_web'))
    gWeb.items.push(this.toggleItem('gesture_master',
      $r('app.string.video_gesture_enable'), $r('app.string.video_gesture_enable_desc'),
      (): boolean => appSettings.video_gesture_enabled,
      (v: boolean): void => {
        appSettings.video_gesture_enabled = v
      }))
    groups.push(gWeb)

    // 三区双击动作选项（无 / 快退 / 快进 / 播放暂停）
    const dtapOptions: MenuOption[] = [
      new MenuOption('none', $r('app.string.video_action_none')),
      new MenuOption('rewind', $r('app.string.video_action_rewind')),
      new MenuOption('forward', $r('app.string.video_action_forward')),
      new MenuOption('playpause', $r('app.string.video_action_playpause'))
    ]
    // 上下滑动作选项（无 / 亮度 / 音量）
    const slideOptions: MenuOption[] = [
      new MenuOption('none', $r('app.string.video_action_none')),
      new MenuOption('brightness', $r('app.string.video_action_brightness')),
      new MenuOption('volume', $r('app.string.video_action_volume'))
    ]
    // 长按倍速档位选项（无 / 2 / 2.5 / 3 / 4 倍速）
    const lpRateOptions: MenuOption[] = [
      new MenuOption('off', $r('app.string.video_action_none')),
      new MenuOption('2', '2X'),
      new MenuOption('2.5', '2.5X'),
      new MenuOption('3', '3X'),
      new MenuOption('4', '4X')
    ]

    // 网页视频手势
    const gGesture = new SettingsSection('gestures', $r('app.string.video_control_group_gestures'))
    // 三区双击：动作行 +（动作=快退/快进时的）秒数行
    const dtapRows: CustomItemInfo[] = []
    this.dtapZone(dtapRows, 'dtap_left', $r('app.string.video_dtap_left'), $r('app.string.video_dtap_left_desc'),
      (): string => appSettings.video_dtap_left,
      (v: string): void => {
        appSettings.video_dtap_left = v
      },
      (): number => appSettings.video_dtap_left_sec,
      (v: number): void => {
        appSettings.video_dtap_left_sec = v
      }, dtapOptions)
    this.dtapZone(dtapRows, 'dtap_middle', $r('app.string.video_dtap_middle'), $r('app.string.video_dtap_middle_desc'),
      (): string => appSettings.video_dtap_middle,
      (v: string): void => {
        appSettings.video_dtap_middle = v
      },
      (): number => appSettings.video_dtap_middle_sec,
      (v: number): void => {
        appSettings.video_dtap_middle_sec = v
      }, dtapOptions)
    this.dtapZone(dtapRows, 'dtap_right', $r('app.string.video_dtap_right'), $r('app.string.video_dtap_right_desc'),
      (): string => appSettings.video_dtap_right,
      (v: string): void => {
        appSettings.video_dtap_right = v
      },
      (): number => appSettings.video_dtap_right_sec,
      (v: number): void => {
        appSettings.video_dtap_right_sec = v
      }, dtapOptions)
    for (const r of dtapRows) {
      gGesture.items.push(r)
    }
    gGesture.items.push(
      this.toggleItem('gesture_swipe_seek',
        $r('app.string.video_gesture_swipe_seek'), $r('app.string.video_gesture_swipe_seek_desc'),
        (): boolean => appSettings.video_gesture_swipe_seek,
        (v: boolean): void => {
          appSettings.video_gesture_swipe_seek = v
        }),
      this.menuItem('slide_left',
        $r('app.string.video_slide_left'), $r('app.string.video_slide_left_desc'),
        (): string => appSettings.video_slide_left,
        (v: string): void => {
          appSettings.video_slide_left = v
        }, slideOptions),
      this.menuItem('slide_right',
        $r('app.string.video_slide_right'), $r('app.string.video_slide_right_desc'),
        (): string => appSettings.video_slide_right,
        (v: string): void => {
          appSettings.video_slide_right = v
        }, slideOptions),
      this.menuItem('long_press_rate',
        $r('app.string.video_gesture_long_press'), $r('app.string.video_gesture_long_press_desc'),
        (): string => appSettings.video_long_press_rate,
        (v: string): void => {
          appSettings.video_long_press_rate = v
        }, lpRateOptions)
    )
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

  private openVideoPlayerPicker(): void {
    this.picker.title = $r('app.string.video_player')
    this.picker.options = [
      new PickerOption('system', $r('app.string.vp_system')),
      new PickerOption('none', $r('app.string.vp_none'))
    ]
    this.picker.selected = appSettings.video_player
    this.picker.onSelect = (v: string): void => {
      appSettings.video_player = v
      this.setPlayerValue(ResourceUtils.getString(videoPlayerLabel(v)))
    }
    this.showSheet = true
  }

  private setPlayerValue(v: string): void {
    for (const group of this.groups) {
      for (const item of group.items) {
        if (item.id === 'video_player') {
          item.value = v
          return
        }
      }
    }
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
      title: $r('app.string.video_settings'),
      sections: this.groups,
      footer: (): void => {
        this.kbCard()
        this.pageFooter()
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

  /** 列表末尾锚点：挂载半模态 bindSheet */
  @Builder
  pageFooter() {
    Row()
      .height(1)
      .width('100%')
      .bindSheet(this.showSheet!!, this.sheetContent(), {
        preferType: SheetType.CENTER,
        height: pickerSheetHeight(2),
        dragBar: true,
        showClose: false,
        backgroundColor: $r('sys.color.comp_background_primary'),
        onDisappear: (): void => {
          this.showSheet = false
        }
      })
  }

  @Builder
  sheetContent() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showSheet = false
      }
    })
  }
}
