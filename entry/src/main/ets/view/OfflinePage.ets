import { NaviContainer } from '../components/NaviContainer';
import { offlinePageVM } from '../viewmodel/OfflinePageViewModel';
import OfflinePageInfo from '../common/entity/OfflinePageInfo';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { QhState } from '../entryability/AppState';
import { toastUtil } from '../common/utils/ToastUtils';

@Builder
export function OfflinePageBuilder() {
  OfflinePage()
}

@ComponentV2
struct OfflinePage {
  private pageStack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    offlinePageVM.loadAll()
  }

  private formatTime(time: number): string {
    const d = new Date(time)
    const month = `${d.getMonth() + 1}`.padStart(2, '0')
    const day = `${d.getDate()}`.padStart(2, '0')
    const hour = `${d.getHours()}`.padStart(2, '0')
    const minute = `${d.getMinutes()}`.padStart(2, '0')
    return `${month}-${day} ${hour}:${minute}`
  }

  /** 当前标签打开离线档，弹出全部路由页回到浏览器 */
  private openOffline(r: OfflinePageInfo): void {
    if (r.path === '') {
      return
    }
    browserVM.openUrl(`file://${r.path}`)
    while (this.pageStack.size() > 0) {
      this.pageStack.pop(false)
    }
  }

  private confirmDelete(r: OfflinePageInfo): void {
    toastUtil.showAlertDialog({
      title: r.name,
      message: $r('app.string.delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            if (r.id !== null) {
              offlinePageVM.deleteRecord(r.id, r.path)
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
    }, 'deleteOfflinePage')
  }

  @Builder
  pageRow(r: OfflinePageInfo) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.square_stack_3d'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_secondary')])
      Column({ space: 3 }) {
        Text(r.name)
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

      Text(this.formatTime(r.createTime))
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openOffline(r)
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
      if (offlinePageVM.records.length === 0) {
        Column() {
          Text($r('app.string.empty_offline'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(offlinePageVM.records, (r: OfflinePageInfo) => {
            ListItem() {
              this.pageRow(r)
            }
          }, (r: OfflinePageInfo) => r.id !== null ? `${r.id}` : r.path)
        }
        .layoutWeight(1)
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider'),
          startMargin: 56,
          endMargin: 16
        })
        .scrollBar(BarState.Off)
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ left: 16, right: 16, top: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color_accent'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.offline_page'),
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
