import { NaviContainer } from '../components/NaviContainer';
import { downloadVM } from '../viewmodel/DownloadViewModel';
import DownloadRecordInfo from '../common/entity/DownloadRecordInfo';
import { AppConstants } from '../common/constants/AppConstants';
import { toastUtil } from '../common/utils/ToastUtils';

@Builder
export function DownloadsBuilder() {
  DownloadsPage()
}

@ComponentV2
struct DownloadsPage {
  private pageStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    downloadVM.loadAll()
  }

  private formatTime(time: number): string {
    const d = new Date(time)
    const month = `${d.getMonth() + 1}`.padStart(2, '0')
    const day = `${d.getDate()}`.padStart(2, '0')
    const hour = `${d.getHours()}`.padStart(2, '0')
    const minute = `${d.getMinutes()}`.padStart(2, '0')
    return `${month}-${day} ${hour}:${minute}`
  }

  private statusText(status: string): ResourceStr {
    if (status === 'completed') {
      return $r('app.string.status_completed')
    }
    if (status === 'failed') {
      return $r('app.string.status_failed')
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
    return $r('sys.color.font_secondary')
  }

  private confirmDelete(r: DownloadRecordInfo): void {
    toastUtil.showAlertDialog({
      title: r.fileName,
      message: $r('app.string.delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
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

  @Builder
  recordRow(r: DownloadRecordInfo) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_secondary')])
      Column({ space: 3 }) {
        Text(r.fileName)
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
        Text(r.url)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 2 }) {
        Text(this.statusText(r.status))
          .fontSize(12)
          .fontColor(this.statusColor(r.status))
        Text(this.formatTime(r.createTime))
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      toastUtil.showToast({
        message: `${AppConstants.DOWNLOAD_DIR}/${r.fileName}`
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
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider'),
          startMargin: 56,
          endMargin: 16
        })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.downloads'),
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
