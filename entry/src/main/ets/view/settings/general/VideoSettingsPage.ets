import { QhState } from '../../../entryability/AppState';
import { SettingsScaffold, SettingsSection } from '../../../components/SettingsScaffold';
import { appSettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';

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

/**
 * 视频设置：外置视频播放器 + 视频控制（手势/快捷键）入口
 */
@ComponentV2
struct VideoSettingsPage {

  @Local groups: SettingsSection[] = []
  @Local picker: PickerConfig = new PickerConfig()
  @Local showSheet: boolean = false

  aboutToAppear(): void {
    this.buildItems()
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

    // 网页视频
    const gWeb = new SettingsSection('web', $r('app.string.video_settings_group_web'))
    gWeb.items.push(new CustomItemInfo({
      id: 'video_control',
      title: $r('app.string.video_control'),
      subtitle: $r('app.string.video_control_desc'),
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('settings_video_control', null)
      }
    }))
    groups.push(gWeb)

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

  build() {
    SettingsScaffold({
      title: $r('app.string.video_settings'),
      sections: this.groups,
      footer: (): void => {
        this.pageFooter()
      }
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
