import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import BookmarkInfo from '../../common/entity/BookmarkInfo';
import { browserVM } from '../../viewmodel/BrowserViewModel';

/** 覆盖层行描述：kind 'folder' | 'bookmark'，depth 为缩进层级 */
class MenuRow {
  kind: string
  name: string
  path: string
  depth: number
  bookmark: BookmarkInfo | null
  constructor(kind: string, name: string, path: string, depth: number, bookmark: BookmarkInfo | null) {
    this.kind = kind
    this.name = name
    this.path = path
    this.depth = depth
    this.bookmark = bookmark
  }
}

/**
 * 书签文件夹树覆盖层（Index 全屏 Stack 兄弟节点，替代 bindPopup——其 autoCancel 与
 * chip 点击存在竞态导致无法关闭）：
 * 透明 scrim 点击关闭；面板固定四行一页（4×40=160，超出滚动），宽度按内容自适应；
 * 子文件夹就地展开/收起（缩进），不替换列表。
 * edgeAnchor 'top'：面板贴顶边向下展开（合并栏在上）；'bottom'：面板贴底边向上展开（合并栏在下）
 */
@ComponentV2
export struct BookmarkFolderMenu {
  @Param edgeAnchor: string = 'top'
  @Param edgeOffset: number = 90
  /** 打开的文件夹路径（菜单只显示该文件夹自己的子项） */
  @Param rootFolder: string = ''

  @Local expandedFolders: string[] = []

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

  private folderPath(parent: string, name: string): string {
    return parent === '' ? name : `${parent}/${name}`
  }

  private toggleFolder(path: string): void {
    const idx = this.expandedFolders.indexOf(path)
    if (idx >= 0) {
      this.expandedFolders.splice(idx, 1)
    } else {
      this.expandedFolders.push(path)
    }
  }

  /** 收集可见行：每层先文件夹后书签，展开的文件夹递归插入子级并加深缩进 */
  private collectRows(folder: string, depth: number, rows: MenuRow[]): void {
    for (const name of this.childFolders(folder)) {
      const path = this.folderPath(folder, name)
      rows.push(new MenuRow('folder', name, path, depth, null))
      if (this.expandedFolders.includes(path)) {
        this.collectRows(path, depth + 1, rows)
      }
    }
    for (const b of this.bookmarksIn(folder)) {
      rows.push(new MenuRow('bookmark', b.title, b.url, depth, b))
    }
  }

  private visibleRows(): MenuRow[] {
    const rows: MenuRow[] = []
    this.collectRows(this.rootFolder, 0, rows)
    return rows
  }

  @Builder
  menuRow(row: MenuRow) {
    Row({ space: 10 }) {
      if (row.kind === 'folder') {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(17)
          .fontColor([$r('sys.color.font_secondary')])
        Text(row.name)
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 150 })
          .fontColor($r('sys.color.font_primary'))
        SymbolGlyph(this.expandedFolders.includes(row.path) ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('sys.color.font_secondary')])
      } else {
        SymbolGlyph($r('sys.symbol.star'))
          .fontSize(17)
          .fontColor([$r('sys.color.font_secondary')])
        Text(row.name)
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 170 })
          .fontColor($r('sys.color.font_primary'))
      }
    }
    .height(40)
    .padding({ left: 16 + row.depth * 16, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (row.kind === 'folder') {
        this.toggleFolder(row.path)
      } else if (row.bookmark !== null) {
        browserVM.showBookmarkMenu = false
        browserVM.openUrl(row.bookmark.url)
      }
    })
  }

  /** 面板：固定四行一页（4×40=160，超出滚动），宽度按内容自适应 */
  @Builder
  menuPanel() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.visibleRows(), (row: MenuRow) => {
            this.menuRow(row)
          }, (row: MenuRow): string => `${row.kind}_${row.path}`)
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: 280 })
      }
      .constraintSize({ maxHeight: 160 })
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: 280 })
    .borderRadius(16)
    .backgroundColor($r('app.color.background_color'))
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)', offsetY: 4 })
    .clip(true)
  }

  build() {
    Stack({
      alignContent: this.edgeAnchor === 'top' ? Alignment.TopStart : Alignment.BottomStart
    }) {
      // 透明 scrim：点击任意空白处关闭
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          browserVM.showBookmarkMenu = false
        })

      if (this.edgeAnchor === 'top') {
        Column() {
          this.menuPanel()
        }
        .margin({ top: this.edgeOffset, left: 8 })
        .alignItems(HorizontalAlign.Start)
      } else {
        Column() {
          this.menuPanel()
        }
        .margin({ bottom: this.edgeOffset, left: 8 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
  }
}
