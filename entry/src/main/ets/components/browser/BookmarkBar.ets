import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import BookmarkInfo from '../../common/entity/BookmarkInfo';
import { browserVM } from '../../viewmodel/BrowserViewModel';

/**
 * 书签栏：横向书签条（合并布局启用书签栏时渲染，贴操作栏内容侧）。
 * 文件夹渲染在书签前，点击文件夹开关书签树覆盖层（BookmarkFolderMenu，由 Index 挂载）
 */
@ComponentV2
export struct BookmarkBar {

  aboutToAppear(): void {
    if (bookmarkVM.bookmarks.length === 0) {
      bookmarkVM.loadAll()
    }
  }

  /** 指定目录的直接子文件夹名（按出现顺序去重，文件夹为路径字符串非独立记录） */
  private childFolders(folder: string): string[] {
    const prefix: string = folder === '' ? '' : `${folder}/`
    const names: string[] = []
    for (const b of bookmarkVM.bookmarks) {
      const f: string = b.folder
      if (f === '' || !f.startsWith(prefix)) {
        continue
      }
      const rest: string = f.substring(prefix.length)
      const name: string = rest.includes('/') ? rest.substring(0, rest.indexOf('/')) : rest
      if (name !== '' && !names.includes(name)) {
        names.push(name)
      }
    }
    return names
  }

  /** 指定目录下的直接书签 */
  private bookmarksIn(folder: string): BookmarkInfo[] {
    return bookmarkVM.bookmarks.filter((b: BookmarkInfo) => b.folder === folder)
  }

  /** 根目录有文件夹或书签即渲染书签栏 */
  private rootNotEmpty(): boolean {
    return this.childFolders('').length > 0 || this.bookmarksIn('').length > 0
  }

  @Builder
  folderChip(name: string) {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(12)
        .fontColor([$r('sys.color.font_secondary')])
      Text(name)
        .fontSize(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 100 })
        .fontColor($r('sys.color.font_primary'))
    }
    .height(24)
    .padding({ left: 10, right: 10 })
    .borderRadius(12)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (browserVM.showBookmarkMenu && browserVM.bookmarkMenuFolder === name) {
        browserVM.showBookmarkMenu = false
      } else {
        browserVM.bookmarkMenuFolder = name
        browserVM.showBookmarkMenu = true
      }
    })
  }

  @Builder
  bookmarkChip(b: BookmarkInfo) {
    Text(b.title)
      .fontSize(12)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 120 })
      .fontColor($r('sys.color.font_primary'))
      .height(24)
      .padding({ left: 10, right: 10 })
      .borderRadius(12)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onClick(() => {
        browserVM.openUrl(b.url)
      })
  }

  build() {
    if (this.rootNotEmpty()) {
      Scroll() {
        Row({ space: 6 }) {
          Repeat<string>(this.childFolders(''))
            .each((ri: RepeatItem<string>) => {
              this.folderChip(ri.item)
            })
            .key((name: string) => `folder_${name}`)

          Repeat<BookmarkInfo>(this.bookmarksIn(''))
            .each((ri: RepeatItem<BookmarkInfo>) => {
              this.bookmarkChip(ri.item)
            })
            .key((b: BookmarkInfo) => b.id === null ? `url_${b.url}` : `id_${b.id}`)
        }
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height(33)
      .align(Alignment.Start)
      .backgroundColor($r('sys.color.comp_background_primary'))
    }
  }
}
