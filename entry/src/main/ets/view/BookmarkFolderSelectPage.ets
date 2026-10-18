import { NaviContainer } from '../components/NaviContainer';
import { menuVM, FolderRowInfo } from '../viewmodel/MenuViewModel';
import { CustomListItem } from '../components/CusItemBuilder';
import { QhState } from '../entryability/AppState';

@Builder
export function BookmarkFolderSelectBuilder() {
  BookmarkFolderSelectPage()
}

@ComponentV2
struct BookmarkFolderSelectPage {
  build() {
    NaviContainer({
      title: $r('app.string.bookmark_select_folder'),
      // 编辑器 sheet 内无状态栏避让；主栈全屏路由（移动至）需状态栏高度
      topPadding: menuVM.folderPickerTarget === 'move' ? undefined : 0,
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onBackPressed: (): boolean => false
    })
  }

  /** 文件夹选择页：树形缩进列表 + 底部添加文件夹（newFolder 目标时不展示） */
  @Builder
  pageContent() {
    Column() {
      Scroll() {
        Column() {
          Column() {
            ForEach(menuVM.folderRows, (row: FolderRowInfo) => {
              CustomListItem({
                item: row.item,
                itemPadding: { left: 16 + row.indent * 16, right: 16, top: 12, bottom: 12 }
              })
            }, (row: FolderRowInfo) => row.item.id)
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor($r('app.color.background_color'))
          .clip(true)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (menuVM.folderPickerTarget === 'bookmark') {
        Column() {
          Text($r('app.string.bookmark_add_folder'))
            .fontSize(16)
            .fontColor(QhState.currentThemeColor)
            .width('100%')
            .height(48)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.background_color'))
            .borderRadius(16)
            .onClick(() => {
              menuVM.openNewFolderPage()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 + QhState.bottomRectHeight })
      }
    }
    .width('100%')
    .height('100%')
  }
}
