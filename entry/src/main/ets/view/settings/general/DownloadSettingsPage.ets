import { SettingsScaffold, SettingsSection } from '../../../components/SettingsScaffold';
import { QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { PublicDownloadDir } from '../../../common/utils/PublicDownloadDir';

/** 并发数选项（1-8） */
function concurrencyOptions(): PickerOption[] {
  const opts: PickerOption[] = []
  for (let n = 1; n <= 8; n++) {
    opts.push(new PickerOption(`${n}`, `${n}`))
  }
  return opts
}

/** 同时任务数选项（1-4） */
function taskLimitOptions(): PickerOption[] {
  const opts: PickerOption[] = []
  for (let n = 1; n <= 4; n++) {
    opts.push(new PickerOption(`${n}`, `${n}`))
  }
  return opts
}

@Builder
export function DownloadSettingsBuilder() {
  DownloadSettingsPage()
}

/**
 * 下载配置：下载目录 / 分片并发数 / 同时任务数 / 下载通知 / 下载记录入口
 */
@ComponentV2
struct DownloadSettingsPage {

  @Local groups: SettingsSection[] = []
  @Local picker: PickerConfig = new PickerConfig()
  @Local showPicker: boolean = false
  @Local pickerHeight: number = pickerSheetHeight(3)

  aboutToAppear(): void {
    this.buildItems()
  }

  private setItemValue(id: string, v: string): void {
    for (const group of this.groups) {
      for (const item of group.items) {
        if (item.id === id) {
          item.value = v
          return
        }
      }
    }
  }

  private buildItems(): void {
    const g: SettingsSection = new SettingsSection('download')
    // 下载目录（暂不支持修改，点击提示当前路径）
    g.items.push(new CustomItemInfo({
      id: 'download_dir',
      title: $r('app.string.download_dir'),
      subtitle: PublicDownloadDir.labelOf('Download'),
      type: ItemActionType.ROUTER,
      value: '',
      onChange: (): void => {
        toastUtil.showToast({ message: PublicDownloadDir.labelOf('Download') })
      }
    }))
    // 分片并发数（HLS 视频下载同时保持的连接数）
    g.items.push(new CustomItemInfo({
      id: 'download_concurrency',
      title: $r('app.string.download_concurrency'),
      subtitle: $r('app.string.download_concurrency_desc'),
      type: ItemActionType.ROUTER,
      value: `${appSettings.download_concurrency}`,
      onChange: (): void => {
        this.openPicker($r('app.string.download_concurrency'), concurrencyOptions(),
          `${appSettings.download_concurrency}`, (v: string): void => {
            appSettings.download_concurrency = Number(v)
            this.setItemValue('download_concurrency', v)
          })
      }
    }))
    // 同时下载任务数（超出排队等待）
    g.items.push(new CustomItemInfo({
      id: 'download_task_limit',
      title: $r('app.string.download_task_limit'),
      subtitle: $r('app.string.download_task_limit_desc'),
      type: ItemActionType.ROUTER,
      value: `${appSettings.download_task_limit}`,
      onChange: (): void => {
        this.openPicker($r('app.string.download_task_limit'), taskLimitOptions(),
          `${appSettings.download_task_limit}`, (v: string): void => {
            appSettings.download_task_limit = Number(v)
            this.setItemValue('download_task_limit', v)
          })
      }
    }))
    // 下载通知
    g.items.push(new CustomItemInfo({
      id: 'download_notify',
      title: $r('app.string.download_notify'),
      subtitle: $r('app.string.download_notify_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.download_notify,
      onChange: (v: string | boolean | number): void => {
        appSettings.download_notify = v as boolean
      }
    }))
    // 下载记录入口
    g.items.push(new CustomItemInfo({
      id: 'download_records',
      title: $r('app.string.download_records'),
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('downloads', null)
      }
    }))
    this.groups = [g]
  }

  private openPicker(title: ResourceStr, options: PickerOption[], selected: string,
    onSelect: (v: string) => void): void {
    this.picker.title = title
    this.picker.options = options
    this.picker.selected = selected
    this.picker.onSelect = onSelect
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showPicker = true
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.download_settings'),
      sections: this.groups,
      footer: (): void => {
        this.pageFooter()
      }
    })
  }

  /** 列表末尾锚点：挂载选择器 bindSheet */
  @Builder
  pageFooter() {
    Row()
      .height(1)
      .width('100%')
      .bindSheet(this.showPicker!!, this.pickerBuilder(), {
        height: this.pickerHeight,
        dragBar: true,
        showClose: false,
        backgroundColor: $r('sys.color.comp_background_primary'),
        onDisappear: (): void => {
          this.showPicker = false
        }
      })
  }

  @Builder
  pickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showPicker = false
      }
    })
  }
}
