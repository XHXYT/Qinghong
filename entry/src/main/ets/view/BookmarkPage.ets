import { NaviContainer, NaviBarButton } from '../components/NaviContainer';
import { QhState, _QhState } from '../entryability/AppState';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { bookmarkVM } from '../viewmodel/BookmarkViewModel';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import { menuVM } from '../viewmodel/MenuViewModel';
import { tabsVM } from '../viewmodel/TabsViewModel';
import { CustomListItem } from '../components/CusItemBuilder';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../common/entity/CusItemInfo';
import { toastUtil } from '../common/utils/ToastUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { BookmarkEditor } from '../components/browser/BookmarkEditor';
import { shortcutVM } from '../viewmodel/ShortcutViewModel';
import { faviconCache, FaviconCache } from '../viewmodel/FaviconCache';

@Builder
export function BookmarkBuilder() {
  BookmarkPage()
}

@ComponentV2
struct BookmarkPage {
  private pageStack: NavPathStack = new NavPathStack()
  /** 当前层级文件夹路径（'' = 根） */
  @Local currentFolder: string = ''
  /** 编辑（多选）模式 */
  @Local selectMode: boolean = false
  /** 已选中项：b_<id> | f_<path> */
  @Local selectedKeys: string[] = []
  /** 编辑栏「更多」菜单可见性 */
  @Local showMoreMenu: boolean = false
  /** 书签页自建编辑器 sheet（添加书签 / 编辑书签 / 编辑文件夹复用） */
  @Local showEditorSheet: boolean = false

  aboutToAppear(): void {
    bookmarkVM.loadAll()
      .then((): void => {
        this.prefetchFavicons()
      })
      .catch((): void => {
      })
  }

  /** 书签列表懒加载 favicon：无缓存的条目按书签 URL 补抓（成功后 version 自增刷新行图标） */
  private prefetchFavicons(): void {
    for (const b of bookmarkVM.bookmarks) {
      faviconCache.fetchAsync(b.url)
        .catch((): void => {
        })
    }
  }

  private displayName(path: string): string {
    const segs: string[] = path.split('/')
    return segs.length > 0 ? segs[segs.length - 1] : path
  }

  private bookmarksIn(folder: string): BookmarkInfo[] {
    const out: BookmarkInfo[] = []
    for (const b of bookmarkVM.bookmarks) {
      if (b.folder === folder) {
        out.push(b)
      }
    }
    return out
  }

  private findBookmarkById(id: number): BookmarkInfo | null {
    for (const b of bookmarkVM.bookmarks) {
      if (b.id === id) {
        return b
      }
    }
    return null
  }

  private openBookmark(b: BookmarkInfo): void {
    browserVM.openUrl(b.url)
    // 弹出全部书签路由页（含各级文件夹页），回到浏览器
    while (this.pageStack.size() > 0) {
      this.pageStack.pop(false)
    }
  }

  // —— 编辑（多选）模式 ——

  private enterSelect(key: string): void {
    this.selectMode = true
    this.selectedKeys = [key]
  }

  private exitSelectMode(): void {
    this.selectMode = false
    this.selectedKeys = []
  }

  private isSelected(key: string): boolean {
    return this.selectedKeys.includes(key)
  }

  private toggleKey(key: string): void {
    if (this.isSelected(key)) {
      const next: string[] = []
      for (const k of this.selectedKeys) {
        if (k !== key) {
          next.push(k)
        }
      }
      this.selectedKeys = next
      return
    }
    const next: string[] = this.selectedKeys.slice(0)
    next.push(key)
    this.selectedKeys = next
  }

  private selectedFolderPaths(): string[] {
    const out: string[] = []
    for (const k of this.selectedKeys) {
      if (k.startsWith('f_')) {
        out.push(k.substring(2))
      }
    }
    return out
  }

  private selectedBookmarkIds(): number[] {
    const out: number[] = []
    for (const k of this.selectedKeys) {
      if (k.startsWith('b_')) {
        const n: number = Number(k.substring(2))
        if (!Number.isNaN(n)) {
          out.push(n)
        }
      }
    }
    return out
  }

  private allKeysAtLevel(): string[] {
    const keys: string[] = []
    for (const p of menuVM.childFolders(this.currentFolder)) {
      keys.push(`f_${p}`)
    }
    for (const b of this.bookmarksIn(this.currentFolder)) {
      keys.push(`b_${b.id}`)
    }
    return keys
  }

  private toggleSelectAll(): void {
    const all: string[] = this.allKeysAtLevel()
    const everySelected: boolean = all.length > 0 &&
      all.every((k: string): boolean => this.isSelected(k))
    this.selectedKeys = everySelected ? [] : all
  }

  /** 更多菜单可用：单文件夹 或 任意数量书签（混合/多文件夹置灰） */
  private moreMenuAvailable(): boolean {
    const f: number = this.selectedFolderPaths().length
    const b: number = this.selectedBookmarkIds().length
    return (f === 1 && b === 0) || (f === 0 && b >= 1)
  }

  private moveSelection(): void {
    const paths: string[] = this.selectedFolderPaths()
    const ids: number[] = this.selectedBookmarkIds()
    if (paths.length === 0 && ids.length === 0) {
      return
    }
    this.exitSelectMode()
    menuVM.openMovePicker(this.pageStack, paths, ids)
  }

  private deleteSelection(): void {
    const ids: number[] = this.selectedBookmarkIds()
    const paths: string[] = this.selectedFolderPaths()
    for (const id of ids) {
      bookmarkVM.deleteBookmark(id)
    }
    for (const p of paths) {
      menuVM.deleteFolder(p)
    }
    this.exitSelectMode()
    toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
  }

  private openSelectionInNewTabs(): void {
    for (const id of this.selectedBookmarkIds()) {
      const b: BookmarkInfo | null = this.findBookmarkById(id)
      if (b !== null) {
        tabsVM.newTab(b.url)
      }
    }
    this.exitSelectMode()
  }

  private shareSelection(): void {
    const b: BookmarkInfo | null = this.findBookmarkById(this.selectedBookmarkIds()[0])
    if (b !== null) {
      this.shareBookmark(b)
    }
  }

  // —— 单项操作 ——

  private shareBookmark(b: BookmarkInfo): void {
    try {
      const data = new systemShare.SharedData({
        utd: 'general.hyperlink',
        content: b.url,
        title: b.title
      })
      const controller = new systemShare.ShareController(data)
      controller.show(_QhState.Context, {})
        .catch((error: BusinessError): void => {
          console.error(`[BookmarkPage] 分享失败: ${error.code} ${error.message}`)
        })
    } catch (e) {
      console.error(`[BookmarkPage] 分享异常: ${e}`)
    }
  }

  private openInNewTab(b: BookmarkInfo): void {
    tabsVM.newTab(b.url)
  }

  private openBookmarkEdit(id: number): void {
    const b: BookmarkInfo | null = this.findBookmarkById(id)
    if (b === null) {
      return
    }
    if (this.selectMode) {
      this.exitSelectMode()
    }
    menuVM.prepareEditBookmark(b)
    menuVM.onEditorClosed = (): void => {
      this.showEditorSheet = false
    }
    this.showEditorSheet = true
  }

  private openFolderEdit(path: string): void {
    if (this.selectMode) {
      this.exitSelectMode()
    }
    menuVM.prepareEditFolder(path)
    menuVM.onEditorClosed = (): void => {
      this.showEditorSheet = false
    }
    this.showEditorSheet = true
  }

  /** 右上角添加书签：半模态编辑器（默认落在当前层级） */
  private openAddEditor(): void {
    menuVM.prepareNewBookmark(this.currentFolder)
    menuVM.onEditorClosed = (): void => {
      this.showEditorSheet = false
    }
    this.showEditorSheet = true
  }

  private folderCtxMenu(path: string): ContextMenuItem[] {
    const items: ContextMenuItem[] = []
    items.push(new ContextMenuItem($r('app.string.bookmark_multi_select'), (): void => {
      this.enterSelect(`f_${path}`)
    }, $r('sys.symbol.checkmark_circle')))
    items.push(new ContextMenuItem($r('app.string.bookmark_edit_folder'), (): void => {
      this.openFolderEdit(path)
    }, $r('sys.symbol.square_and_pencil')))
    items.push(new ContextMenuItem($r('app.string.bookmark_move_to'), (): void => {
      menuVM.openMovePicker(this.pageStack, [path], [])
    }, $r('sys.symbol.arrow_right_circle')))
    items.push(new ContextMenuItem($r('app.string.delete'), (): void => {
      menuVM.deleteFolder(path)
      toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
    }, $r('sys.symbol.trash'), true))
    return items
  }

  private bookmarkCtxMenu(b: BookmarkInfo): ContextMenuItem[] {
    const items: ContextMenuItem[] = []
    items.push(new ContextMenuItem($r('app.string.bookmark_multi_select'), (): void => {
      this.enterSelect(`b_${b.id}`)
    }, $r('sys.symbol.checkmark_circle')))
    items.push(new ContextMenuItem($r('app.string.share'), (): void => {
      this.shareBookmark(b)
    }, $r('sys.symbol.share')))
    items.push(new ContextMenuItem($r('app.string.bookmark_edit_title'), (): void => {
      if (b.id !== null) {
        this.openBookmarkEdit(b.id)
      }
    }, $r('sys.symbol.square_and_pencil')))
    items.push(new ContextMenuItem($r('app.string.bookmark_add_desktop'), (): void => {
      shortcutVM.addToDesktop(`bm_${b.id}`, b.title, b.url)
    }, $r('sys.symbol.house')))
    items.push(new ContextMenuItem($r('app.string.bookmark_open_new_tab'), (): void => {
      this.openInNewTab(b)
    }, $r('sys.symbol.arrow_up_right')))
    items.push(new ContextMenuItem($r('app.string.delete'), (): void => {
      if (b.id !== null) {
        bookmarkVM.deleteBookmark(b.id)
        toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
      }
    }, $r('sys.symbol.trash'), true))
    return items
  }

  private folderItem(path: string): CustomItemInfo {
    const key: string = `f_${path}`
    if (this.selectMode) {
      return new CustomItemInfo({
        id: key,
        symbol: $r('sys.symbol.folder'),
        title: this.displayName(path),
        type: ItemActionType.CHECK,
        value: this.isSelected(key),
        onChange: (): void => {
          this.toggleKey(key)
        }
      })
    }
    return new CustomItemInfo({
      id: key,
      symbol: $r('sys.symbol.folder'),
      title: this.displayName(path),
      type: ItemActionType.ROUTER,
      value: '',
      contextMenuItems: this.folderCtxMenu(path),
      onChange: (): void => {
        this.pageStack.pushPathByName('bookmarks', path)
      }
    })
  }

  private bookmarkItem(b: BookmarkInfo): CustomItemInfo {
    const key: string = `b_${b.id}`
    if (this.selectMode) {
      return new CustomItemInfo({
        id: key,
        title: b.title,
        subtitle: b.url,
        type: ItemActionType.CHECK,
        value: this.isSelected(key),
        onChange: (): void => {
          this.toggleKey(key)
        }
      })
    }
    return new CustomItemInfo({
      id: key,
      title: b.title,
      subtitle: b.url,
      type: ItemActionType.ROUTER_BLANK,
      value: '',
      contextMenuItems: this.bookmarkCtxMenu(b),
      onChange: (): void => {
        this.openBookmark(b)
      }
    })
  }

  private pageTitle(): ResourceStr {
    if (this.selectMode) {
      return ResourceUtils.getStringWithArgs($r('app.string.bookmark_selected_count'),
        [this.selectedKeys.length])
    }
    return this.currentFolder === '' ? $r('app.string.bookmarks') : this.displayName(this.currentFolder)
  }

  private navButtons(): NaviBarButton[] {
    if (this.selectMode) {
      return [
        new NaviBarButton({
          symbol: $r('sys.symbol.xmark'),
          action: (): void => {
            this.exitSelectMode()
          }
        })
      ]
    }
    return [
      new NaviBarButton({
        symbol: $r('sys.symbol.plus'),
        action: (): void => {
          this.openAddEditor()
        }
      })
    ]
  }

  @Builder
  avatar(b: BookmarkInfo) {
    if (b.icon !== '' && fileIo.accessSync(b.icon)) {
      // 用户自定义图标（编辑器相册选图）
      Image(fileUri.getUriFromPath(b.icon))
        .width(36)
        .height(36)
        .borderRadius(18)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else if (faviconCache.has(FaviconCache.hostOf(b.url))) {
      // 已访问过的网页：显示缓存的 favicon（页面加载时自动抓取）
      Image(fileUri.getUriFromPath(faviconCache.pathOf(FaviconCache.hostOf(b.url))))
        .width(36)
        .height(36)
        .borderRadius(18)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Text(b.title.length > 0 ? b.title.substring(0, 1) : '?')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .borderRadius(18)
        .backgroundColor(QhState.currentThemeColor)
    }
  }

  @Builder
  barItem(label: ResourceStr, symbol: Resource, color: ResourceColor, onTap: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([color])
      Text(label)
        .fontSize(11)
        .fontColor(color)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }

  @Builder
  editBar() {
    Column() {
      Row() {
        this.barItem($r('app.string.bookmark_move_to'), $r('sys.symbol.arrow_right_circle'),
          this.selectedKeys.length > 0 ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'),
          (): void => {
            if (this.selectedKeys.length > 0) {
              this.moveSelection()
            }
          })
        this.barItem($r('app.string.delete'), $r('sys.symbol.trash'),
          this.selectedKeys.length > 0 ? Color.Red : $r('sys.color.font_tertiary'),
          (): void => {
            if (this.selectedKeys.length > 0) {
              this.deleteSelection()
            }
          })
        this.barItem($r('app.string.select_all'), $r('sys.symbol.checkmark_circle'),
          $r('sys.color.font_primary'),
          (): void => {
            this.toggleSelectAll()
          })
        this.moreBarItem()
      }
      .width('100%')
      .height(56)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_color'))
    .padding({ bottom: QhState.bottomRectHeight })
  }

  /** 更多按钮：菜单直接锚定在本按钮上方 */
  @Builder
  moreBarItem() {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(22)
        .fontColor([this.moreMenuAvailable() ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')])
      Text($r('app.string.more'))
        .fontSize(11)
        .fontColor(this.moreMenuAvailable() ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.moreMenuAvailable()) {
        this.showMoreMenu = true
      }
    })
    .bindMenu(this.showMoreMenu, this.moreMenu, {
      placement: Placement.Top,
      onDisappear: (): void => {
        this.showMoreMenu = false
      }
    })
  }

  @Builder
  moreMenu() {
    Menu() {
      if (this.selectedFolderPaths().length === 1 && this.selectedBookmarkIds().length === 0) {
        MenuItem({ content: $r('app.string.edit') })
          .onClick(() => {
            this.openFolderEdit(this.selectedFolderPaths()[0])
          })
      } else {
        MenuItem({ content: $r('app.string.bookmark_open_new_tab') })
          .onClick(() => {
            this.openSelectionInNewTabs()
          })
        if (this.selectedBookmarkIds().length === 1) {
          MenuItem({ content: $r('app.string.edit') })
            .onClick(() => {
              this.openBookmarkEdit(this.selectedBookmarkIds()[0])
            })
          MenuItem({ content: $r('app.string.share') })
            .onClick(() => {
              this.shareSelection()
            })
        }
      }
    }
    .backgroundColor($r('app.color.start_window_background'))
    .borderRadius(20)
  }

  @Builder
  pageContent() {
    Column() {
      if (!this.selectMode && menuVM.childFolders(this.currentFolder).length === 0 &&
        this.bookmarksIn(this.currentFolder).length === 0) {
        Column() {
          Text($r('app.string.empty_bookmarks'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Column() {
              ForEach(menuVM.childFolders(this.currentFolder), (path: string) => {
                CustomListItem({
                  item: this.folderItem(path),
                  itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                })
              }, (path: string) => `f_${path}`)
              ForEach(this.bookmarksIn(this.currentFolder), (b: BookmarkInfo) => {
                CustomListItem({
                  item: this.bookmarkItem(b),
                  icon: (): void => {
                    this.avatar(b)
                  },
                  itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                })
              }, (b: BookmarkInfo) => `b_${b.id}`)
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
      }
      if (this.selectMode) {
        this.editBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color_accent'))
  }

  /** 书签页自建编辑器 sheet（与浏览器菜单同款半模态） */
  @Builder
  editorSheetBuilder() {
    BookmarkEditor()
  }

  build() {
    NaviContainer({
      title: this.pageTitle(),
      buttons: this.navButtons(),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.pageStack = ctx.pathStack
        const p: Object | undefined = ctx.pathInfo.param
        if (p !== undefined && typeof p === 'string') {
          this.currentFolder = p
        }
      },
      onBackPressed: (): boolean => {
        if (this.selectMode) {
          this.exitSelectMode()
          return true
        }
        return false
      }
    })
    .bindSheet(this.showEditorSheet, this.editorSheetBuilder(), {
      height: 560,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showEditorSheet = false
      }
    })
  }
}
