import { NaviContainer } from '../components/NaviContainer';
import { QhState } from '../entryability/AppState';
import { CustomContentDialog } from '@kit.ArkUI';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { bookmarkVM } from '../viewmodel/BookmarkViewModel';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import { buildDialogButtons } from '../components/dialog/AppContentDialog';
import { toastUtil } from '../common/utils/ToastUtils';

@Builder
export function BookmarkBuilder() {
  BookmarkPage()
}

@ComponentV2
struct BookmarkPage {
  private pageStack: NavPathStack = new NavPathStack()
  @Local inputTitle: string = ''
  @Local inputUrl: string = ''
  private addDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    bookmarkVM.loadAll()
    this.addDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.add_bookmark_title'),
        contentBuilder: (): void => {
          this.addDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doAdd()
            }
            this.addDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.inputTitle = ''
        this.inputUrl = ''
      }
    })
  }

  private doAdd(): void {
    const url = this.inputUrl.trim()
    if (!url) return
    bookmarkVM.addBookmark(this.inputTitle.trim() || url, url)
  }

  private openBookmark(b: BookmarkInfo): void {
    browserVM.openUrl(b.url)
    this.pageStack.pop()
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
    }, 'bookmarkActions')
  }

  @Builder
  addDialogContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: $r('app.string.bookmark_title_hint') })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.inputTitle = v
        })
      TextInput({ placeholder: $r('app.string.bookmark_url_hint') })
        .height(44)
        .fontSize(15)
        .type(InputType.URL)
        .onChange((v: string) => {
          this.inputUrl = v
        })
    }
    .width('100%')
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

  @Builder
  pageContent() {
    Column() {
      if (bookmarkVM.bookmarks.length === 0) {
        Column() {
          Text($r('app.string.empty_bookmarks'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(bookmarkVM.bookmarks, (b: BookmarkInfo) => {
            ListItem() {
              this.bookmarkRow(b)
            }
          }, (b: BookmarkInfo) => b.id !== null ? `${b.id}` : b.url)
        }
        .layoutWeight(1)
        .divider({
          strokeWidth: 0.5,
          color: $r('sys.color.comp_divider'),
          startMargin: 64,
          endMargin: 16
        })
        .scrollBar(BarState.Off)
      }

      // 添加书签
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([QhState.currentThemeColor])
        Text($r('app.string.add_bookmark_title'))
          .fontSize(15)
          .fontColor(QhState.currentThemeColor)
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {
        this.addDialog?.open()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.bookmarks'),
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
