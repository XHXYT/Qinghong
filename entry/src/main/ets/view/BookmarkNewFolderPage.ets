import { NaviContainer } from '../components/NaviContainer';
import { menuVM } from '../viewmodel/MenuViewModel';
import { CustomListItem } from '../components/CusItemBuilder';
import { QhState } from '../entryability/AppState';

@Builder
export function BookmarkNewFolderBuilder() {
  BookmarkNewFolderPage()
}

@ComponentV2
struct BookmarkNewFolderPage {
  build() {
    NaviContainer({
      title: $r('app.string.bookmark_new_folder'),
      topPadding: 0,
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onBackPressed: (): boolean => false
    })
  }

  /** 新建文件夹页：名称输入 + 位置选择 */
  @Builder
  pageContent() {
    Column() {
      Column() {
        CustomListItem({
          item: menuVM.newFolderNameItem,
          itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
        })
        CustomListItem({
          item: menuVM.newFolderParentItem,
          itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.background_color'))
      .clip(true)

      Blank()

      Column() {
        Text($r('app.string.bookmark_add_folder'))
          .fontSize(16)
          .fontColor(Color.White)
          .width('100%')
          .height(48)
          .textAlign(TextAlign.Center)
          .backgroundColor(QhState.currentThemeColor)
          .borderRadius(24)
          .onClick(() => {
            menuVM.createFolder()
          })
      }
      .width('100%')
      .padding({ bottom: 16 + QhState.bottomRectHeight })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 8 })
  }
}
