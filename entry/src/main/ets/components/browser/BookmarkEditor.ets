import { menuVM } from '../../viewmodel/MenuViewModel';
import { CustomListItem } from '../CusItemBuilder';
import { QhState } from '../../entryability/AppState';
import { fileUri } from '@kit.CoreFileKit';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';

/**
 * 添加书签编辑器宿主：sheet 内局部 Navigation。
 * 主编辑页直接作为 Navigation 主页；选择文件夹/新建文件夹由系统路由表按名推入，独立于主路由栈。
 */
@ComponentV2
export struct BookmarkEditor {
  build() {
    Navigation(menuVM.editorStack) {
      Column() {
        this.titleBar()
        Column() {
          if (menuVM.folderEditMode) {
            this.folderEditContent()
          } else {
            this.addPageContent()
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_color_accent'))
    }
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }

  /** 标题栏（对齐 NaviContainer.titleBar 风格） */
  @Builder
  titleBar() {
    Row() {
      Text(this.editorTitle())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  private editorTitle(): ResourceStr {
    if (menuVM.folderEditMode) {
      return $r('app.string.bookmark_edit_folder')
    }
    return menuVM.editorIsEdit ? $r('app.string.bookmark_edit_title') : $r('app.string.add_bookmark_title')
  }

  /** 编辑文件夹页：名称/位置 + 保存（sheet 内直出，不走路由） */
  @Builder
  folderEditContent() {
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
        Text($r('app.string.save'))
          .fontSize(16)
          .fontColor(Color.White)
          .width('100%')
          .height(48)
          .textAlign(TextAlign.Center)
          .backgroundColor(QhState.currentThemeColor)
          .borderRadius(24)
          .onClick(() => {
            menuVM.confirmFolderEditor()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 + QhState.bottomRectHeight })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 8 })
  }

  /** 主编辑页：图标/名称/网址/文件夹位置/主页收藏 + 保存 */
  @Builder
  addPageContent() {
    Column() {
      Scroll() {
        Column() {
          Column() {
            this.iconRow()
            CustomListItem({
              item: menuVM.nameItem,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
            CustomListItem({
              item: menuVM.urlItem,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
            CustomListItem({
              item: menuVM.folderItem,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
            CustomListItem({
              item: menuVM.quickItem,
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
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

      Column() {
        Text($r('app.string.save'))
          .fontSize(16)
          .fontColor(Color.White)
          .width('100%')
          .height(48)
          .textAlign(TextAlign.Center)
          .backgroundColor(QhState.currentThemeColor)
          .borderRadius(24)
          .onClick(() => {
            menuVM.saveBookmark()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 + QhState.bottomRectHeight })
    }
    .width('100%')
    .height('100%')
  }

  /** 图标行：预览当前图标，点击从相册选图替换 */
  @Builder
  iconRow() {
    Row() {
      this.iconPreview()
      Column({ space: 2 }) {
        Text($r('app.string.bookmark_field_icon'))
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
        Text($r('app.string.bookmark_icon_hint'))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      menuVM.pickBookmarkIcon()
    })
  }

  /** 图标预览：自定义图标 > favicon 缓存 > 首字头像 */
  @Builder
  iconPreview() {
    if (menuVM.bmIcon !== '') {
      Image(fileUri.getUriFromPath(menuVM.bmIcon))
        .width(44)
        .height(44)
        .borderRadius(10)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else if (faviconCache.has(FaviconCache.hostOf(menuVM.bmUrl))) {
      Image(fileUri.getUriFromPath(faviconCache.pathOf(FaviconCache.hostOf(menuVM.bmUrl))))
        .width(44)
        .height(44)
        .borderRadius(10)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Text(menuVM.bmTitle.length > 0 ? menuVM.bmTitle.substring(0, 1) : '?')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor(QhState.currentThemeColor)
    }
  }
}
