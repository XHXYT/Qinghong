import { NaviContainer } from '../components/NaviContainer';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { historyVM } from '../viewmodel/HistoryViewModel';
import HistoryInfo from '../common/entity/HistoryInfo';
import { toastUtil } from '../common/utils/ToastUtils';

@Builder
export function HistoryBuilder() {
  HistoryPage()
}

@ComponentV2
struct HistoryPage {
  private pageStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    historyVM.loadAll()
  }

  private formatTime(time: number): string {
    const d = new Date(time)
    const month = `${d.getMonth() + 1}`.padStart(2, '0')
    const day = `${d.getDate()}`.padStart(2, '0')
    const hour = `${d.getHours()}`.padStart(2, '0')
    const minute = `${d.getMinutes()}`.padStart(2, '0')
    return `${month}-${day} ${hour}:${minute}`
  }

  private openHistory(h: HistoryInfo): void {
    browserVM.openUrl(h.url)
    this.pageStack.pop()
  }

  private confirmDelete(h: HistoryInfo): void {
    toastUtil.showAlertDialog({
      title: h.title,
      message: $r('app.string.delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            if (h.id !== null) {
              historyVM.deleteById(h.id)
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
    }, 'deleteHistory')
  }

  private confirmClearAll(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.clear_history'),
      message: $r('app.string.clear_history_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.clear'),
          fontColor: Color.Red,
          action: (): void => {
            historyVM.clearAll()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'clearHistory')
  }

  @Builder
  historyRow(h: HistoryInfo) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(h.title)
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
        Text(h.url)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.formatTime(h.visitTime))
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openHistory(h)
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 400 })
        .onAction(() => {
          this.confirmDelete(h)
        })
    )
  }

  @Builder
  pageContent() {
    Column() {
      if (historyVM.histories.length === 0) {
        Column() {
          Text($r('app.string.empty_history'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(historyVM.histories, (h: HistoryInfo) => {
            ListItem() {
              this.historyRow(h)
            }
          }, (h: HistoryInfo) => h.id !== null ? `${h.id}` : h.url)
        }
        .layoutWeight(1)
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider'),
          startMargin: 16,
          endMargin: 16
        })
        .scrollBar(BarState.Off)
      }

      // 清空历史
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.ohos_trash_circle'))
          .fontSize(18)
          .fontColor([Color.Red])
        Text($r('app.string.clear_history'))
          .fontSize(15)
          .fontColor(Color.Red)
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {
        this.confirmClearAll()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.history'),
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
