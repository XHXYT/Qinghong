import { NaviContainer, NaviBarButton } from '../components/NaviContainer';
import { ContextMenuItem } from '../common/entity/CusItemInfo';
import { downloadVM, DownloadViewModel } from '../viewmodel/DownloadViewModel';
import DownloadRecordInfo from '../common/entity/DownloadRecordInfo';
import { toastUtil } from '../common/utils/ToastUtils';
import { QhState } from '../entryability/AppState';

/** 文件类型扩展名表（按图标类别分组，小写比较） */
const VIDEO_EXT: string[] = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'm4v', 'ts',
  'webm', '3gp', 'mpg', 'mpeg', 'rmvb', 'rm', 'm2ts']
const AUDIO_EXT: string[] = ['mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a', 'wma', 'ape', 'opus', 'amr']
const IMAGE_EXT: string[] = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic', 'ico', 'tiff', 'avif']
const ARCHIVE_EXT: string[] = ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso']
const INSTALL_EXT: string[] = ['apk', 'hap', 'ipa', 'exe', 'dmg', 'pkg', 'msi', 'app']

@Builder
export function DownloadsBuilder() {
  DownloadsPage()
}

@ComponentV2
struct DownloadsPage {
  private pageStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    downloadVM.loadAll().then((): void => {
      downloadVM.syncStale()
    })
  }

  private formatTime(time: number): string {
    const d = new Date(time)
    const month = `${d.getMonth() + 1}`.padStart(2, '0')
    const day = `${d.getDate()}`.padStart(2, '0')
    const hour = `${d.getHours()}`.padStart(2, '0')
    const minute = `${d.getMinutes()}`.padStart(2, '0')
    return `${month}-${day} ${hour}:${minute}`
  }

  /** 按扩展名映射文件类型图标：视频/音频/图片/压缩包/安装包，其余默认文档 */
  private fileIcon(fileName: string): Resource {
    const dot: number = fileName.lastIndexOf('.')
    const ext: string = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : ''
    if (VIDEO_EXT.indexOf(ext) >= 0) {
      return $r('sys.symbol.video')
    }
    if (AUDIO_EXT.indexOf(ext) >= 0) {
      return $r('sys.symbol.music')
    }
    if (IMAGE_EXT.indexOf(ext) >= 0) {
      return $r('sys.symbol.picture')
    }
    if (ARCHIVE_EXT.indexOf(ext) >= 0) {
      return $r('sys.symbol.doc_zipper')
    }
    if (INSTALL_EXT.indexOf(ext) >= 0) {
      return $r('sys.symbol.install')
    }
    return $r('sys.symbol.doc_text')
  }

  /** 进度百分比（-1 = 总大小未知） */
  private percentOf(r: DownloadRecordInfo): number {
    const v: number | undefined = downloadVM.progressOf.get(r.path)
    return v ?? -1
  }

  /** 进度条右侧标签：已知总大小显示百分比，未知显示已接收字节数 */
  private progressLabel(r: DownloadRecordInfo): string {
    const percent: number = this.percentOf(r)
    if (percent >= 0) {
      return `${Math.floor(percent)}%`
    }
    return DownloadViewModel.formatSize(this.displayRecv(r))
  }

  /** 显示用已收字节：下载中取实时值（HLS 含乱序缓冲与在途），其余取落盘记录值 */
  private displayRecv(r: DownloadRecordInfo): number {
    if (r.status === 'downloading') {
      const v: number | undefined = downloadVM.displayRecvOf.get(r.path)
      if (v !== undefined && v > 0) {
        return v
      }
    }
    return r.receivedSize
  }

  /** 副标题：已下载 / 总大小 · 速度（总大小未知时用分片估算值；保存类记录无大小则留空） */
  private sizeLabel(r: DownloadRecordInfo): string {
    if (r.status === 'completed' && r.receivedSize <= 0) {
      return ''
    }
    const speed: number = downloadVM.speedOf.get(r.path) ?? 0
    return DownloadViewModel.subtitleOf(this.displayRecv(r), downloadVM.displayTotalOf(r), speed, r.status === 'downloading')
  }

  private statusText(status: string): ResourceStr {
    if (status === 'completed') {
      return $r('app.string.status_completed')
    }
    if (status === 'failed') {
      return $r('app.string.status_failed')
    }
    if (status === 'paused') {
      return $r('app.string.status_paused')
    }
    return $r('app.string.status_downloading')
  }

  private statusColor(status: string): ResourceColor {
    if (status === 'completed') {
      return Color.Green
    }
    if (status === 'failed') {
      return Color.Red
    }
    if (status === 'paused') {
      return Color.Orange
    }
    return $r('sys.color.font_secondary')
  }

  private confirmDelete(r: DownloadRecordInfo): void {
    toastUtil.showAlertDialog({
      title: r.fileName,
      message: $r('app.string.delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            if (r.id !== null) {
              downloadVM.deleteRecord(r.id)
            }
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteDownload')
  }

  /** 清空所有任务（危险操作，二次确认） */
  private confirmClearAll(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.clear_all_tasks'),
      message: $r('app.string.clear_all_tasks_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.clear'),
          fontColor: Color.Red,
          action: (): void => {
            downloadVM.clearAll()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'clearAllDownloads')
  }

  /** 标题栏「更多」按钮的下拉菜单 */
  private moreMenuItems(): ContextMenuItem[] {
    return [
      new ContextMenuItem($r('app.string.retry_all_failed'), (): void => {
        downloadVM.retryAllFailed()
      }, $r('sys.symbol.arrow_clockwise')),
      new ContextMenuItem($r('app.string.pause_all_tasks'), (): void => {
        downloadVM.pauseAll()
      }, $r('sys.symbol.pause')),
      new ContextMenuItem($r('app.string.resume_all_tasks'), (): void => {
        downloadVM.resumeAll()
      }, $r('sys.symbol.play')),
      new ContextMenuItem($r('app.string.clear_all_tasks'), (): void => {
        this.confirmClearAll()
      }, $r('sys.symbol.trash'), true)
    ]
  }

  @Builder
  actionButton(icon: Resource, action: () => void) {
    SymbolGlyph(icon)
      .fontSize(20)
      .fontColor([$r('sys.color.font_secondary')])
      .padding(8)
      .onClick(() => action())
  }

  @Builder
  recordRow(r: DownloadRecordInfo) {
    Row({ space: 12 }) {
      SymbolGlyph(this.fileIcon(r.fileName))
        .fontSize(24)
        .fontColor([$r('sys.color.font_secondary')])
      Column({ space: 3 }) {
        Text(r.fileName)
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
        if (r.status === 'downloading' || r.status === 'paused') {
          Row({ space: 8 }) {
            Progress({ value: Math.max(0, this.percentOf(r)), total: 100, type: ProgressType.Linear })
              .layoutWeight(1)
              .height(4)
              .color(r.status === 'downloading'
                ? QhState.currentThemeColor : this.statusColor(r.status))
              .backgroundColor($r('sys.color.comp_divider'))
            Text(this.progressLabel(r))
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
        }
        Text(this.sizeLabel(r))
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 2 }) {
        if (r.status === 'downloading') {
          this.actionButton($r('sys.symbol.pause'), (): void => {
            downloadVM.pause(r)
          })
        } else if (r.status === 'paused') {
          this.actionButton($r('sys.symbol.play'), (): void => {
            downloadVM.retry(r)
          })
        } else if (r.status === 'failed') {
          this.actionButton($r('sys.symbol.arrow_clockwise'), (): void => {
            downloadVM.retry(r)
          })
        } else {
          Text(this.statusText(r.status))
            .fontSize(12)
            .fontColor(this.statusColor(r.status))
        }
        Text(this.formatTime(r.createTime))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.background_color'))
    .borderRadius(16)
    .margin({ top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      toastUtil.showToast({
        message: r.path
      })
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 400 })
        .onAction(() => {
          this.confirmDelete(r)
        })
    )
  }

  @Builder
  pageContent() {
    Column() {
      if (downloadVM.records.length === 0) {
        Column() {
          Text($r('app.string.empty_downloads'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(downloadVM.records, (r: DownloadRecordInfo) => {
            ListItem() {
              this.recordRow(r)
            }
          }, (r: DownloadRecordInfo) => r.id !== null ? `${r.id}` : r.url)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color_accent'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.downloads'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.dot_grid_2x2'),
          menuItems: this.moreMenuItems()
        })
      ],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.pageStack = ctx.pathStack
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }
}
