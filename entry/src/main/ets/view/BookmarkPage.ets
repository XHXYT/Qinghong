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

/** 编辑态行基准几何（拖拽命中计算用，onAreaChange 持续更新） */
class RowGeom {
  top: number = 0
  height: number = 0

  constructor(top: number, height: number) {
    this.top = top
    this.height = height
  }
}

/** 编辑（多选）模式列表行：@ObservedV2 深度观测，行内勾选/文案/拖拽预览变化精准刷新单行 */
@ObservedV2
class EditRowInfo {
  @Trace title: string = ''
  @Trace subtitle: string = ''
  @Trace checked: boolean = false
  /** 拖拽中：原行隐藏（ghost 顶替） */
  @Trace dragging: boolean = false
  /** 书签拖到本文件夹行上：放大接收反馈 */
  @Trace receiving: boolean = false
  /** 排序插入避让位移（0 / ±被拖行高） */
  @Trace shift: number = 0
  readonly key: string
  readonly isFolder: boolean
  readonly folderPath: string
  readonly bookmark: BookmarkInfo | null

  constructor(key: string, isFolder: boolean, folderPath: string,
    bookmark: BookmarkInfo | null) {
    this.key = key
    this.isFolder = isFolder
    this.folderPath = folderPath
    this.bookmark = bookmark
  }
}

/** 普通模式行（统一交错序）：预构 CustomItemInfo，文件夹/书签共用一套渲染 */
class NormalRow {
  readonly key: string
  readonly isFolder: boolean
  readonly folderPath: string
  readonly bookmark: BookmarkInfo | null
  readonly item: CustomItemInfo

  constructor(key: string, isFolder: boolean, folderPath: string,
    bookmark: BookmarkInfo | null, item: CustomItemInfo) {
    this.key = key
    this.isFolder = isFolder
    this.folderPath = folderPath
    this.bookmark = bookmark
    this.item = item
  }
}

/**
 * 编辑模式行组件。行内不放任何手势识别器（onTouch 判定单击），
 * 否则会按"更深节点手势优先"规则拦截父级 ListItem 上的长按拖拽手势组。
 */
@ComponentV2
struct EditRowItem {
  @Require @Param row: EditRowInfo
  @BuilderParam avatar: CustomBuilder
  @Event onToggle: (row: EditRowInfo) => void = (row: EditRowInfo): void => {
  }
  /** 手指抬起（无论是否点击）：拖拽结束信号 */
  @Event onRelease: () => void = (): void => {
  }

  private downTime: number = 0
  private downX: number = 0
  private downY: number = 0

  build() {
    Row({ space: 12 }) {
      if (this.row.isFolder) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(24)
          .fontColor([this.row.receiving ? QhState.currentThemeColor : $r('sys.color.icon_emphasize')])
      } else {
        if (this.avatar) {
          this.avatar()
        }
      }
      Column({ space: 2 }) {
        Text(this.row.title)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
        if (this.row.subtitle !== '') {
          Text(this.row.subtitle)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Checkbox()
        .select(this.row.checked)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.row.receiving ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
    .border(this.row.receiving ? { width: 2, color: QhState.currentThemeColor } : { width: 0, color: Color.Transparent })
    .opacity(this.row.dragging ? 0 : 1)
    .scale(this.row.receiving ? { x: 1.08, y: 1.08 } : { x: 1, y: 1 })
    .translate({ y: this.row.shift })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.downTime = new Date().getTime()
        const down: TouchObject | undefined = event.touches[0]
        this.downX = down === undefined ? 0 : down.x
        this.downY = down === undefined ? 0 : down.y
        return
      }
      if (event.type === TouchType.Up) {
        const up: TouchObject | undefined = event.changedTouches[0]
        const upX: number = up === undefined ? this.downX : up.x
        const upY: number = up === undefined ? this.downY : up.y
        const duration: number = new Date().getTime() - this.downTime
        const distance: number = Math.abs(upX - this.downX) + Math.abs(upY - this.downY)
        // 短按且无明显位移才算点击；长按/滑动留给拖拽排序与列表滚动
        if (duration < 400 && distance < 20) {
          this.row.checked = !this.row.checked
          this.onToggle(this.row)
        }
        this.onRelease()
      }
    })
  }
}

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
  /** 编辑模式统一行列表（文件夹 + 书签，供拖拽排序） */
  @Local editRows: EditRowInfo[] = []
  /** 编辑态自绘拖拽：当前被拖行（null = 未拖拽）；ghost 跟手 Y（相对内容 Stack 顶部） */
  @Local dragRow: EditRowInfo | null = null
  @Local ghostY: number = 0
  private dragFromIndex: number = -1
  private dragHeight: number = 0
  private grabOffsetY: number = 0
  /** 内容 Stack 顶部全局 Y（ghost 坐标换算基准） */
  private stackTopY: number = 0
  private dropFolderRow: EditRowInfo | null = null
  private dropFinal: number = -1
  /** 行基准几何：key → 全局 top / height（onAreaChange 持续更新） */
  private rowGeom: Map<string, RowGeom> = new Map()

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
    this.buildEditRows()
  }

  private exitSelectMode(): void {
    this.selectMode = false
    this.selectedKeys = []
  }

  private isSelected(key: string): boolean {
    return this.selectedKeys.includes(key)
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
    // 行勾选态由 @Trace 深度观测精准刷新，无需重建列表
    for (const row of this.editRows) {
      row.checked = this.isSelected(row.key)
    }
  }

  private removeSelectedKey(key: string): void {
    if (!this.isSelected(key)) {
      return
    }
    const next: string[] = []
    for (const k of this.selectedKeys) {
      if (k !== key) {
        next.push(k)
      }
    }
    this.selectedKeys = next
  }

  /** 编辑模式统一行列表：文件夹与书签按统一布局交错排列 */
  private buildEditRows(): void {
    this.rowGeom.clear()
    const rows: EditRowInfo[] = []
    for (const key of menuVM.levelItemOrder(this.currentFolder)) {
      if (key.startsWith('f_')) {
        const p: string = key.substring(2)
        const row: EditRowInfo = new EditRowInfo(key, true, p, null)
        row.title = this.displayName(p)
        row.checked = this.isSelected(row.key)
        rows.push(row)
        continue
      }
      const id: number = Number(key.substring(2))
      const b: BookmarkInfo | null = this.findBookmarkById(id)
      if (b !== null) {
        const row: EditRowInfo = new EditRowInfo(key, false, '', b)
        row.title = b.title
        row.subtitle = b.url
        row.checked = this.isSelected(row.key)
        rows.push(row)
      }
    }
    this.editRows = rows
  }

  /** 行内勾选变化 → 同步页面选中集（行 UI 由 @Trace 深度观测自行刷新） */
  private syncRowToggle(row: EditRowInfo): void {
    if (row.checked) {
      if (!this.selectedKeys.includes(row.key)) {
        const next: string[] = this.selectedKeys.slice(0)
        next.push(row.key)
        this.selectedKeys = next
      }
      return
    }
    this.removeSelectedKey(row.key)
  }

  /** 编辑态自定义拖拽：长按 500ms 启动，文件夹接收 / 排序插入两种落点 ——
   书签停在文件夹行中段 = 接收模式（文件夹放大、无避让，抬手移入）；
   其余位置 = 排序插入（文件夹与书签自由交错，相邻行平移避让） */

  private clearDragPreview(): void {
    for (const r of this.editRows) {
      r.shift = 0
      r.receiving = false
    }
  }

  private startDrag(row: EditRowInfo, index: number, fingerY: number): void {
    if (this.dragRow !== null) {
      return
    }
    const geom: RowGeom | undefined = this.rowGeom.get(row.key)
    if (geom === undefined) {
      return
    }
    this.dragFromIndex = index
    this.dragRow = row
    this.dragHeight = geom.height
    this.grabOffsetY = fingerY - geom.top
    this.ghostY = geom.top - this.stackTopY
    this.dropFolderRow = null
    this.dropFinal = -1
    row.dragging = true
  }

  private updateDrag(fingerY: number): void {
    if (this.dragRow === null || this.dragFromIndex < 0 ||
      this.dragFromIndex >= this.editRows.length) {
      return
    }
    this.ghostY = fingerY - this.grabOffsetY - this.stackTopY
    const from: number = this.dragFromIndex
    const dragged: EditRowInfo = this.editRows[from]
    // 基准几何上找命中行（translate 避让不改变布局位置，映射稳定无抖动）
    let hitIdx: number = -1
    let hitGeom: RowGeom | null = null
    let belowAll: boolean = true
    for (let j: number = 0; j < this.editRows.length; j++) {
      if (j === from) {
        continue
      }
      const g: RowGeom | undefined = this.rowGeom.get(this.editRows[j].key)
      if (g === undefined) {
        continue
      }
      belowAll = false
      if (fingerY < g.top + g.height) {
        if (fingerY >= g.top) {
          hitIdx = j
          hitGeom = g
        }
        break
      }
    }
    // 书签拖到文件夹行中段 → 接收模式：文件夹放大，不做避让；
    // 行的上下边缘带（各 25%）滑过 → 落入排序插入，文件夹之间也可插书签
    if (hitIdx >= 0 && hitGeom !== null && !dragged.isFolder && this.editRows[hitIdx].isFolder) {
      const rel: number = (fingerY - hitGeom.top) / hitGeom.height
      if (rel > 0.25 && rel < 0.75) {
        this.dropFinal = -1
        const folderRow: EditRowInfo = this.editRows[hitIdx]
        if (this.dropFolderRow !== folderRow) {
          this.clearDragPreview()
          this.dropFolderRow = folderRow
          folderRow.receiving = true
        }
        return
      }
    }
    // 排序插入（跨类自由交错）：命中行上半 = 插到其前，下半 = 插到其后
    this.dropFolderRow = null
    let final: number = -1
    if (hitIdx < 0) {
      if (belowAll) {
        final = this.editRows.length - 1
      } else {
        this.dropFinal = -1
        this.clearDragPreview()
        return
      }
    } else if (hitGeom !== null) {
      const upper: boolean = fingerY < hitGeom.top + hitGeom.height / 2
      if (hitIdx < from) {
        final = upper ? hitIdx : hitIdx + 1
      } else {
        final = upper ? hitIdx - 1 : hitIdx
      }
    }
    if (final === from) {
      this.dropFinal = -1
      this.clearDragPreview()
      return
    }
    this.dropFinal = final
    for (let j: number = 0; j < this.editRows.length; j++) {
      if (j === from) {
        continue
      }
      const r: EditRowInfo = this.editRows[j]
      let shift: number = 0
      if (final > from && j > from && j <= final) {
        shift = -this.dragHeight
      } else if (final < from && j >= final && j < from) {
        shift = this.dragHeight
      }
      r.shift = shift
      r.receiving = false
    }
  }

  private endDrag(): void {
    if (this.dragRow === null) {
      return
    }
    const from: number = this.dragFromIndex
    const dragged: EditRowInfo = this.editRows[from]
    const folderRow: EditRowInfo | null = this.dropFolderRow
    const final: number = this.dropFinal
    this.dragRow = null
    this.dropFolderRow = null
    this.dropFinal = -1
    this.dragFromIndex = -1
    if (folderRow !== null) {
      // 落到文件夹行上：移入该文件夹
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
        this.clearDragPreview()
        dragged.dragging = false
        this.editRows.splice(from, 1)
      })
      const b: BookmarkInfo | null = dragged.bookmark
      if (b !== null && b.id !== null) {
        this.removeSelectedKey(`b_${b.id}`)
        bookmarkVM.moveBookmarksTo([b.id], folderRow.folderPath)
        toastUtil.showToast({ message: $r('app.string.bookmark_moved') })
      }
      this.persistEditOrder()
      return
    }
    if (final >= 0 && final !== from) {
      // 排序插入
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
        this.clearDragPreview()
        dragged.dragging = false
        this.editRows.splice(from, 1)
        this.editRows.splice(final, 0, dragged)
      })
      this.persistEditOrder()
      return
    }
    // 无有效落点：复位
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
      this.clearDragPreview()
      dragged.dragging = false
    })
  }

  /** 拖拽落位后持久化统一行序：按行号收集交错槽位，文件夹走 applyFolderOrder、书签走 reorderBookmarksWithSlots */
  private persistEditOrder(): void {
    const folderPaths: string[] = []
    const folderSlots: number[] = []
    const orderedBooks: BookmarkInfo[] = []
    const bookSlots: number[] = []
    for (let i: number = 0; i < this.editRows.length; i++) {
      const r: EditRowInfo = this.editRows[i]
      if (r.isFolder) {
        folderPaths.push(r.folderPath)
        folderSlots.push(i)
      } else if (r.bookmark !== null) {
        orderedBooks.push(r.bookmark)
        bookSlots.push(i)
      }
    }
    if (folderPaths.length > 0) {
      menuVM.applyFolderOrder(folderPaths, folderSlots)
    }
    if (orderedBooks.length > 0) {
      bookmarkVM.reorderBookmarksWithSlots(orderedBooks, bookSlots)
    }
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
    // deleteFolder 现已连带删除文件夹内书签
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

  // —— 左滑删除 ——

  private deleteFolderSwipe(path: string): void {
    menuVM.deleteFolder(path)
    toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
  }

  private deleteBookmarkSwipe(b: BookmarkInfo): void {
    if (b.id !== null) {
      bookmarkVM.deleteBookmark(b.id)
      toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
    }
  }

  /** 多选模式下禁用左滑 */
  private folderSwipeOptions(path: string): SwipeActionOptions {
    if (this.selectMode) {
      return {}
    }
    return {
      end: (): void => {
        this.swipeDeleteButton((): void => {
          this.deleteFolderSwipe(path)
        })
      }
    }
  }

  private bookmarkSwipeOptions(b: BookmarkInfo): SwipeActionOptions {
    if (this.selectMode) {
      return {}
    }
    return {
      end: (): void => {
        this.swipeDeleteButton((): void => {
          this.deleteBookmarkSwipe(b)
        })
      }
    }
  }

  @Builder
  swipeDeleteButton(onTap: () => void) {
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(24)
        .fontColor([Color.Red])
    }
    .backgroundColor(Color.Transparent)
    .margin({ right: 6 })
    .onClick(onTap)
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

  /** 右上角新建文件夹：半模态编辑器（默认落在当前层级） */
  private openAddFolderEditor(): void {
    menuVM.prepareNewFolder(this.currentFolder)
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
    items.push(new ContextMenuItem($r('app.string.bookmark_move_to'), (): void => {
      if (b.id !== null) {
        menuVM.openMovePicker(this.pageStack, [], [b.id])
      }
    }, $r('sys.symbol.arrow_right_circle')))
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
    return new CustomItemInfo({
      id: key,
      symbol: $r('sys.symbol.folder'),
      title: this.displayName(path),
      type: ItemActionType.ROUTER,
      value: '',
      contextMenuItems: this.folderCtxMenu(path),
      contextMenuPlacement: Placement.BottomRight,
      onChange: (): void => {
        this.pageStack.pushPathByName('bookmarks', path)
      }
    })
  }

  private bookmarkItem(b: BookmarkInfo): CustomItemInfo {
    const key: string = `b_${b.id}`
    return new CustomItemInfo({
      id: key,
      title: b.title,
      subtitle: b.url,
      type: ItemActionType.ROUTER_BLANK,
      value: '',
      contextMenuItems: this.bookmarkCtxMenu(b),
      contextMenuPlacement: Placement.BottomRight,
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
        symbol: $r('sys.symbol.folder_badge_plus'),
        action: (): void => {
          this.openAddFolderEditor()
        }
      }),
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
  rowAvatar(row: EditRowInfo | null) {
    if (row !== null && row.bookmark !== null) {
      this.avatar(row.bookmark)
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
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: QhState.bottomRectHeight })
    .margin({ top: 8 })
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

  /** 普通模式总行数：文件夹 + 书签，用于首末行圆角判定 */
  private normalRowCount(): number {
    return menuVM.childFolders(this.currentFolder).length + this.bookmarksIn(this.currentFolder).length
  }

  /** 行圆角：首行只留上圆角、末行只留下圆角、中间行无圆角；单行四角全圆 */
  private rowCorner(globalIndex: number): BorderRadiuses {
    const total: number = this.normalRowCount()
    if (globalIndex === 0 && globalIndex === total - 1) {
      return { topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 16 }
    }
    if (globalIndex === 0) {
      return { topLeft: 16, topRight: 16 }
    }
    if (globalIndex === total - 1) {
      return { bottomLeft: 16, bottomRight: 16 }
    }
    return { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 }
  }

  /** 普通模式统一行序（文件夹与书签自由交错，布局序优先） */
  private normalRows(): NormalRow[] {
    const rows: NormalRow[] = []
    for (const key of menuVM.levelItemOrder(this.currentFolder)) {
      if (key.startsWith('f_')) {
        const p: string = key.substring(2)
        rows.push(new NormalRow(key, true, p, null, this.folderItem(p)))
        continue
      }
      const id: number = Number(key.substring(2))
      const b: BookmarkInfo | null = this.findBookmarkById(id)
      if (b !== null) {
        rows.push(new NormalRow(key, false, '', b, this.bookmarkItem(b)))
      }
    }
    return rows
  }

  private rowSwipeOptions(row: NormalRow): SwipeActionOptions {
    if (row.isFolder) {
      return this.folderSwipeOptions(row.folderPath)
    }
    if (row.bookmark !== null) {
      return this.bookmarkSwipeOptions(row.bookmark)
    }
    return {}
  }

  /** 行首图标：文件夹显示 folder 字形，书签显示头像 */
  @Builder
  normalRowAvatar(row: NormalRow) {
    if (row.isFolder) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(24)
        .fontColor([$r('sys.color.icon_emphasize')])
    } else if (row.bookmark !== null) {
      this.avatar(row.bookmark)
    }
  }

  /** 普通模式列表：左滑删除 + 长按菜单，无拖拽 */
  @Builder
  normalList() {
    Column() {
      List() {
        ForEach(this.normalRows(), (row: NormalRow, index: number) => {
          ListItem() {
            CustomListItem({
              item: row.item,
              icon: (): void => {
                this.normalRowAvatar(row)
              },
              itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
            })
          }
          .backgroundColor($r('app.color.background_color'))
          .borderRadius(this.rowCorner(index))
          .swipeAction(this.rowSwipeOptions(row))
        }, (row: NormalRow, index: number) => `${index}_${row.key}`)
      }
      .constraintSize({ maxHeight: '100%' })
      .width('100%')
      .clip(true)
      .contentEndOffset(QhState.bottomRectHeight)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  /** 编辑（多选）模式列表：统一行模型 + 自绘拖拽（长按启动、文件夹接收 / 排序避让插入） */
  @Builder
  editList() {
    Column() {
      List() {
        ForEach(this.editRows, (row: EditRowInfo, index: number) => {
          ListItem() {
            EditRowItem({
              row: row,
              avatar: (): void => {
                this.rowAvatar(row)
              },
              onToggle: (r: EditRowInfo): void => {
                this.syncRowToggle(r)
              },
              onRelease: (): void => {
                this.endDrag()
              }
            })
          }
          .margin({ left: 16, right: 16 })
          .zIndex(row.receiving ? 100 : 0)
          .gesture(GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction((event?: GestureEvent) => {
                if (event !== undefined && event.fingerList.length > 0) {
                  this.startDrag(row, index, event.fingerList[0].globalY)
                }
              }),
            PanGesture({ fingers: 1, direction: PanDirection.All })
              .onActionUpdate((event: GestureEvent) => {
                if (event.fingerList.length > 0) {
                  this.updateDrag(event.fingerList[0].globalY)
                }
              })
          ))
          .onAreaChange((_old: Area, newArea: Area) => {
            const gp: Position = newArea.globalPosition
            const gy: number = typeof gp.y === 'number' ? gp.y : 0
            const gh: number = typeof newArea.height === 'number' ? newArea.height : 0
            this.rowGeom.set(row.key, new RowGeom(gy, gh))
          })
        }, (row: EditRowInfo) => row.key)
      }
      .constraintSize({ maxHeight: '100%' })
      .width('100%')
      .clip(true)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ top: 8 })
  }

  /** 拖拽幽灵卡片：全宽浮层，跟手移动（dragRow 非空时显示） */
  @Builder
  dragGhost() {
    Row({ space: 12 }) {
      if (this.dragRow !== null && this.dragRow.isFolder) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_emphasize')])
      } else {
        this.rowAvatar(this.dragRow)
      }
      Column({ space: 2 }) {
        Text(this.dragRow === null ? '' : this.dragRow.title)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
        if (this.dragRow !== null && this.dragRow.subtitle !== '') {
          Text(this.dragRow.subtitle)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.background_color'))
    .borderRadius(16)
    .shadow({ radius: 16, color: 'rgba(0,0,0,0.15)', offsetY: 4 })
    .scale({ x: 1.03, y: 1.03 })
    .position({ x: 0, y: this.ghostY })
  }

  @Builder
  pageContent() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.selectMode) {
          this.editList()
        } else if (menuVM.childFolders(this.currentFolder).length === 0 &&
          this.bookmarksIn(this.currentFolder).length === 0) {
          Column() {
            Text($r('app.string.empty_bookmarks'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.normalList()
        }
        if (this.selectMode) {
          this.editBar()
        }
      }
      .width('100%')
      .height('100%')

      if (this.dragRow !== null) {
        this.dragGhost()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color_accent'))
    .onAreaChange((_old: Area, newArea: Area) => {
      const gp: Position = newArea.globalPosition
      this.stackTopY = typeof gp.y === 'number' ? gp.y : 0
    })
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
      preferType: SheetType.CENTER,
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
