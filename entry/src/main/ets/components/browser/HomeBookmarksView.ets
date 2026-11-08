import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import BookmarkInfo from '../../common/entity/BookmarkInfo';
import { QhState } from '../../entryability/AppState';
import { toastUtil } from '../../common/utils/ui/ToastUtils';

/**
 * 书签模式主页：主页态渲染书签列表
 */
@ComponentV2
export struct HomeBookmarksView {
  aboutToAppear(): void {
    bookmarkVM.loadAll()
  }

  private openBookmark(b: BookmarkInfo): void {
    browserVM.openUrl(b.url)
  }

  private showItemActions(b: BookmarkInfo): void {
    toastUtil.showAlertDialog({
      title: b.title,
      message: b.url,
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      buttons: [
        {
          value: $r('app.string.open'),
          action: (): void => {
            this.openBookmark(b)
          }
        },
        {
          value: b.isQuick ? $r('app.string.remove_quick') : $r('app.string.set_quick'),
          action: (): void => {
            bookmarkVM.setQuick(b.url, !b.isQuick)
          }
        },
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            if (b.id !== null) {
              bookmarkVM.deleteBookmark(b.id)
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
    }, 'homeBookmarkActions')
  }

  @Builder
  bookmarkRow(b: BookmarkInfo) {
    Row({ space: 12 }) {
      Text(b.title.length > 0 ? b.title.substring(0, 1) : '?')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .borderRadius(18)
        .backgroundColor(QhState.currentThemeColor)
      Column({ space: 3 }) {
        Text(b.title)
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
        Text(b.url)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (b.isQuick) {
        SymbolGlyph($r('sys.symbol.house_fill'))
          .fontSize(16)
          .fontColor([$r('sys.color.font_secondary')])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openBookmark(b)
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 400 })
        .onAction(() => {
          this.showItemActions(b)
        })
    )
  }

  build() {
    if (bookmarkVM.bookmarks.length === 0) {
      Column() {
        Text($r('app.string.empty_bookmarks'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        ForEach(bookmarkVM.bookmarks, (b: BookmarkInfo) => {
          ListItem() {
            this.bookmarkRow(b)
          }
        }, (b: BookmarkInfo) => b.id !== null ? `${b.id}` : b.url)
      }
      .width('100%')
      .height('100%')
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
        startMargin: 64,
        endMargin: 16
      })
      .scrollBar(BarState.Off)
      .backgroundColor($r('app.color.background_color_accent'))
    }
  }
}
