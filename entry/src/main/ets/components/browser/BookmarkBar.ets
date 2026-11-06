import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import BookmarkInfo from '../../common/entity/BookmarkInfo';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { HomeImmersive } from '../../common/utils/HomeImmersive';
import { homeBg } from '../../common/utils/HomeBg';
import { ActionBarColor } from '../../common/utils/ActionBarColor';
import { UISettings } from '../../common/entity/SettingsModel';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { QhState } from '../../entryability/AppState';
import { toastUtil } from '../../common/utils/ToastUtils';
import { fileIo, fileUri } from '@kit.CoreFileKit';

/** 芯片窗口几何（拖拽命中判定用） */
class ChipGeom {
  readonly left: number
  readonly width: number

  constructor(left: number, width: number) {
    this.left = left
    this.width = width
  }
}

/** 书签栏条目：文件夹与书签统一交错（key = f_路径 / b_id，与几何缓存键一致） */
class BarItem {
  readonly key: string
  readonly isFolder: boolean
  readonly folderName: string
  readonly bookmark: BookmarkInfo | null

  constructor(key: string, isFolder: boolean, folderName: string, bookmark: BookmarkInfo | null) {
    this.key = key
    this.isFolder = isFolder
    this.folderName = folderName
    this.bookmark = bookmark
  }
}

/** 芯片横向间距（Row space，避让位移计算用） */
const CHIP_GAP: number = 6

/**
 * 书签栏：横向书签条（合并布局启用书签栏时渲染，贴操作栏内容侧）。
 * 文件夹与书签按统一行序交错渲染（menuVM.levelItemOrder，与书签管理页一致）；
 * 点击文件夹开关书签树覆盖层（BookmarkFolderMenu，由 Index 挂载）；
 * 长按任意芯片拖拽：书签落文件夹芯片 = 移入该文件夹，其余落点 = 统一重排序（文件夹与书签自由交错）
 */
@ComponentV2
export struct BookmarkBar {

  /** 芯片底色：主页沉浸暗背景用浅色半透明（白字可读），色彩模式按页面色明暗叠层，其余用通用底 */
  private chipBg(): ResourceColor {
    if (HomeImmersive.active() && homeBg.dark) {
      return 'rgba(255,255,255,0.14)'
    }
    return ActionBarColor.chipBg($r('sys.color.comp_background_tertiary'), UISettings.app_layout === 'top')
  }

  aboutToAppear(): void {
    if (bookmarkVM.bookmarks.length === 0) {
      bookmarkVM.loadAll()
    }
  }

  /** 指定目录下的直接书签 */
  private bookmarksIn(folder: string): BookmarkInfo[] {
    return bookmarkVM.bookmarks.filter((b: BookmarkInfo) => b.folder === folder)
  }

  /** 根目录有文件夹（含注册表中的空文件夹）或书签即渲染书签栏 */
  private rootNotEmpty(): boolean {
    return menuVM.childFolders('').length > 0 || this.bookmarksIn('').length > 0
  }

  /** 根目录统一条目序列（文件夹+书签交错，键序与书签管理页一致） */
  private barItems(): BarItem[] {
    const byId: Map<number, BookmarkInfo> = new Map<number, BookmarkInfo>()
    for (const b of this.bookmarksIn('')) {
      if (b.id !== null) {
        byId.set(b.id, b)
      }
    }
    const out: BarItem[] = []
    for (const key of menuVM.levelItemOrder('')) {
      if (key.startsWith('f_')) {
        out.push(new BarItem(key, true, key.substring(2), null))
      } else {
        const b: BookmarkInfo | undefined = byId.get(Number(key.substring(2)))
        if (b !== undefined) {
          out.push(new BarItem(key, false, '', b))
        }
      }
    }
    return out
  }

  // ---- 拖拽排序 / 移入文件夹（长按芯片启动） ----

  /** 芯片几何缓存（onAreaChange 记录，拖拽期间布局不变、命中映射稳定） */
  private chipGeom: Map<string, ChipGeom> = new Map()
  /** 书签栏左缘窗口坐标（幽灵芯片定位基准） */
  private barLeftX: number = 0
  /** 拖拽抓取偏移（手指 - 芯片左缘） */
  private grabOffsetX: number = 0
  /** 拖动是否已启动（区分长按即抬手与拖动后抬手） */
  private panActive: boolean = false
  /** 拖拽中的条目（null = 未拖拽） */
  @Local dragItem: BarItem | null = null
  /** 拖拽条目在统一序列中的下标 */
  @Local dragIndex: number = -1
  /** 拖拽芯片宽度（避让位移用） */
  @Local dragChipWidth: number = 0
  /** 排序落位下标（移除拖拽项后的目标下标，-1 = 无排序落点） */
  @Local dropFinal: number = -1
  /** 接收移入的文件夹名（'' = 非接收模式） */
  @Local dropFolderName: string = ''
  /** 幽灵芯片横坐标（栏内坐标） */
  @Local ghostX: number = 0

  /** 长按启动拖拽（文件夹与书签通用） */
  private startDragItem(item: BarItem, index: number, fingerX: number): void {
    if (this.dragItem !== null) {
      return
    }
    const g: ChipGeom | undefined = this.chipGeom.get(item.key)
    if (g === undefined) {
      return
    }
    this.panActive = false
    this.dragItem = item
    this.dragIndex = index
    this.dragChipWidth = g.width
    this.grabOffsetX = fingerX - g.left
    this.ghostX = g.left - this.barLeftX
    this.dropFinal = -1
    this.dropFolderName = ''
  }

  /** 拖动跟手：书签落文件夹芯片 = 接收移入；其余 = 统一序列排序插入 */
  private updateDrag(fingerX: number): void {
    if (this.dragItem === null || this.dragIndex < 0) {
      return
    }
    const items: BarItem[] = this.barItems()
    if (this.dragIndex >= items.length) {
      return
    }
    this.ghostX = fingerX - this.grabOffsetX - this.barLeftX
    if (!this.dragItem.isFolder) {
      for (const it of items) {
        if (!it.isFolder) {
          continue
        }
        const g: ChipGeom | undefined = this.chipGeom.get(it.key)
        if (g !== undefined && fingerX >= g.left && fingerX <= g.left + g.width) {
          this.dropFolderName = it.folderName
          this.dropFinal = -1
          return
        }
      }
    }
    this.dropFolderName = ''
    let slot: number = items.length
    for (let j: number = 0; j < items.length; j++) {
      const g: ChipGeom | undefined = this.chipGeom.get(items[j].key)
      if (g === undefined) {
        continue
      }
      if (fingerX < g.left + g.width / 2) {
        slot = j
        break
      }
    }
    const final: number = slot > this.dragIndex ? slot - 1 : slot
    this.dropFinal = final === this.dragIndex ? -1 : final
  }

  /** 排序避让位移：落位点与原位之间的芯片让位（translate 不影响布局几何） */
  private chipShift(i: number): number {
    if (this.dragItem === null || this.dropFinal < 0 || i === this.dragIndex) {
      return 0
    }
    const w: number = this.dragChipWidth + CHIP_GAP
    const from: number = this.dragIndex
    const final: number = this.dropFinal
    if (final > from && i > from && i <= final) {
      return -w
    }
    if (final < from && i >= final && i < from) {
      return w
    }
    return 0
  }

  /** 抬手落位：书签落文件夹 = 移入该文件夹，其余落点 = 统一重排序 */
  private endDrag(): void {
    if (this.dragItem === null) {
      return
    }
    const item: BarItem = this.dragItem
    const from: number = this.dragIndex
    const final: number = this.dropFinal
    const folder: string = this.dropFolderName
    this.dragItem = null
    this.dragIndex = -1
    this.dropFinal = -1
    this.dropFolderName = ''
    this.panActive = false
    if (!item.isFolder && folder !== '' && item.bookmark !== null && item.bookmark.id !== null) {
      bookmarkVM.moveBookmarksTo([item.bookmark.id], folder)
      toastUtil.showToast({ message: $r('app.string.bookmark_moved') })
      return
    }
    if (final >= 0 && final !== from) {
      const items: BarItem[] = this.barItems()
      if (from < items.length) {
        items.splice(from, 1)
        items.splice(final, 0, item)
        this.persistBarOrder(items)
      }
    }
  }

  /** 拖拽落位后持久化统一行序：文件夹走 applyFolderOrder、书签走 reorderBookmarksWithSlots（槽位 = 统一行号） */
  private persistBarOrder(items: BarItem[]): void {
    const folderPaths: string[] = []
    const folderSlots: number[] = []
    const orderedBooks: BookmarkInfo[] = []
    const bookSlots: number[] = []
    for (let i: number = 0; i < items.length; i++) {
      const it: BarItem = items[i]
      if (it.isFolder) {
        folderPaths.push(it.folderName)
        folderSlots.push(i)
      } else if (it.bookmark !== null) {
        orderedBooks.push(it.bookmark)
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

  /** 拖拽取消（手势被系统接管）：仅复位，不落位 */
  private cancelDrag(): void {
    this.dragItem = null
    this.dragIndex = -1
    this.dropFinal = -1
    this.dropFolderName = ''
    this.panActive = false
  }

  /** 书签图标：自定义图标 > favicon 缓存 > 星标（区分书签与文件夹） */
  @Builder
  bookmarkIcon(b: BookmarkInfo) {
    if (b.icon !== '' && fileIo.accessSync(b.icon)) {
      Image(fileUri.getUriFromPath(b.icon))
        .width(14)
        .height(14)
        .borderRadius(7)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else if (faviconCache.has(FaviconCache.hostOf(b.url))) {
      Image(fileUri.getUriFromPath(faviconCache.pathOf(FaviconCache.hostOf(b.url))))
        .width(14)
        .height(14)
        .borderRadius(7)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      SymbolGlyph($r('sys.symbol.star'))
        .fontSize(12)
        .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
    }
  }

  @Builder
  folderChip(item: BarItem, index: number) {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(12)
        .fontColor([this.dropFolderName === item.folderName ? Color.White
          : ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
      Text(item.folderName)
        .fontSize(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 100 })
        .fontColor(this.dropFolderName === item.folderName ? Color.White
          : ActionBarColor.fg($r('sys.color.font_primary'), UISettings.app_layout === 'top'))
    }
    .height(24)
    .padding({ left: 10, right: 10 })
    .borderRadius(12)
    .backgroundColor(this.dropFolderName === item.folderName ? QhState.currentThemeColor : this.chipBg())
    .opacity(this.dragItem !== null && this.dragIndex === index ? 0.25 : 1)
    .translate({ x: this.chipShift(index) })
    .scale({
      x: this.dropFolderName === item.folderName ? 1.1 : 1,
      y: this.dropFolderName === item.folderName ? 1.1 : 1
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.dragItem !== null) {
        return
      }
      if (browserVM.showBookmarkMenu && browserVM.bookmarkMenuFolder === item.folderName) {
        browserVM.showBookmarkMenu = false
      } else {
        browserVM.bookmarkMenuFolder = item.folderName
        browserVM.showBookmarkMenu = true
      }
    })
    .gesture(GestureGroup(GestureMode.Sequence,
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((event?: GestureEvent) => {
          if (event !== undefined && event.fingerList.length > 0) {
            this.startDragItem(item, index, event.fingerList[0].globalX)
          }
        })
        .onActionEnd(() => {
          if (!this.panActive) {
            this.endDrag()
          }
        }),
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
        .onActionUpdate((event?: GestureEvent) => {
          if (event !== undefined && event.fingerList.length > 0) {
            this.panActive = true
            this.updateDrag(event.fingerList[0].globalX)
          }
        })
        .onActionEnd(() => {
          this.endDrag()
        })
        .onActionCancel(() => {
          this.cancelDrag()
        })
    ))
    .onAreaChange((_old: Area, newArea: Area) => {
      const gp: Position = newArea.globalPosition
      const gx: number = typeof gp.x === 'number' ? gp.x : 0
      const gw: number = typeof newArea.width === 'number' ? newArea.width : 0
      this.chipGeom.set(item.key, new ChipGeom(gx, gw))
    })
  }

  @Builder
  bookmarkChip(item: BarItem, index: number) {
    if (item.bookmark !== null) {
      Row({ space: 3 }) {
        this.bookmarkIcon(item.bookmark)
        Text(item.bookmark.title)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 120 })
          .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), UISettings.app_layout === 'top'))
      }
      .height(24)
      .padding({ left: 10, right: 10 })
      .borderRadius(12)
      .backgroundColor(this.chipBg())
      .opacity(this.dragItem !== null && this.dragIndex === index ? 0.25 : 1)
      .translate({ x: this.chipShift(index) })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.dragItem === null && item.bookmark !== null) {
          browserVM.openUrl(item.bookmark.url)
        }
      })
      .gesture(GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction((event?: GestureEvent) => {
            if (event !== undefined && event.fingerList.length > 0) {
              this.startDragItem(item, index, event.fingerList[0].globalX)
            }
          })
          .onActionEnd(() => {
            if (!this.panActive) {
              this.endDrag()
            }
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
          .onActionUpdate((event?: GestureEvent) => {
            if (event !== undefined && event.fingerList.length > 0) {
              this.panActive = true
              this.updateDrag(event.fingerList[0].globalX)
            }
          })
          .onActionEnd(() => {
            this.endDrag()
          })
          .onActionCancel(() => {
            this.cancelDrag()
          })
      ))
      .onAreaChange((_old: Area, newArea: Area) => {
        const gp: Position = newArea.globalPosition
        const gx: number = typeof gp.x === 'number' ? gp.x : 0
        const gw: number = typeof newArea.width === 'number' ? newArea.width : 0
        this.chipGeom.set(item.key, new ChipGeom(gx, gw))
      })
    }
  }

  /** 拖拽幽灵芯片：跟手浮动（dragItem 非空时显示，文件夹/书签各自样式） */
  @Builder
  dragGhost() {
    if (this.dragItem !== null) {
      if (this.dragItem.isFolder) {
        Row({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(12)
            .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
          Text(this.dragItem.folderName)
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 140 })
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), UISettings.app_layout === 'top'))
        }
        .height(24)
        .padding({ left: 10, right: 10 })
        .borderRadius(12)
        .backgroundColor(this.chipBg())
        .alignItems(VerticalAlign.Center)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.25)', offsetY: 2 })
        .scale({ x: 1.08, y: 1.08 })
        .position({ x: this.ghostX, y: 0 })
      } else if (this.dragItem.bookmark !== null) {
        Row({ space: 3 }) {
          this.bookmarkIcon(this.dragItem.bookmark)
          Text(this.dragItem.bookmark.title)
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 140 })
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), UISettings.app_layout === 'top'))
        }
        .height(24)
        .padding({ left: 10, right: 10 })
        .borderRadius(12)
        .backgroundColor(this.chipBg())
        .alignItems(VerticalAlign.Center)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.25)', offsetY: 2 })
        .scale({ x: 1.08, y: 1.08 })
        .position({ x: this.ghostX, y: 0 })
      }
    }
  }

  build() {
    if (this.rootNotEmpty()) {
      Stack() {
        Scroll() {
          Row({ space: CHIP_GAP }) {
            Repeat<BarItem>(this.barItems())
              .each((ri: RepeatItem<BarItem>) => {
                if (ri.item.isFolder) {
                  this.folderChip(ri.item, ri.index)
                } else {
                  this.bookmarkChip(ri.item, ri.index)
                }
              })
              .key((it: BarItem): string => it.key)
          }
          .padding({ left: 8, right: 8 })
          .alignItems(VerticalAlign.Center)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        .align(Alignment.Start)
        // 主页沉浸时背景透明透出全屏主页背景层；色彩模式随操作栏自适应（渐变时透明由栏组渐变接管）
        .backgroundColor(HomeImmersive.active() ? Color.Transparent
          : ActionBarColor.bg($r('sys.color.comp_background_primary'), UISettings.app_layout === 'top'))

        if (this.dragItem !== null) {
          this.dragGhost()
        }
      }
      .width('100%')
      .height(33)
      .onAreaChange((_old: Area, newArea: Area) => {
        const gp: Position = newArea.globalPosition
        this.barLeftX = typeof gp.x === 'number' ? gp.x : 0
      })
    }
  }
}
