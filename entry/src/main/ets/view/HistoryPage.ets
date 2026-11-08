import { NaviContainer } from '../components/NaviContainer';
import { QhState } from '../entryability/AppState';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { historyVM } from '../viewmodel/HistoryViewModel';
import { tabsVM } from '../viewmodel/TabsViewModel';
import HistoryInfo from '../common/entity/HistoryInfo';
import { toastUtil } from '../common/utils/ToastUtils';
import { faviconCache, FaviconCache } from '../viewmodel/FaviconCache';
import { fileUri } from '@kit.CoreFileKit';

/**
 * 历史记录行（渲染模型）。
 * 行内可变状态（编辑态/选中态）必须挂 @Trace：ForEach item 生成器内读取页面级 @Local
 * 不会建立更新订阅，只有行对象自身的 @Trace 属性才能驱动行 UI 细粒度刷新。
 */
@ObservedV2
class HistoryRowModel {
  /** 行键（ForEach diff 用，稳定唯一） */
  key: string
  info: HistoryInfo
  @Trace edit: boolean = false
  @Trace selected: boolean = false

  constructor(key: string, info: HistoryInfo) {
    this.key = key
    this.info = info
  }
}

/** 历史记录按日分组（渲染模型） */
class HistoryGroup {
  key: string = ''
  title: string = ''
  items: HistoryRowModel[] = []

  constructor(key: string, title: string, items: HistoryRowModel[]) {
    this.key = key
    this.title = title
    this.items = items
  }
}

const WEEKDAY_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六']

@Builder
export function HistoryBuilder() {
  HistoryPage()
}

@ComponentV2
struct HistoryPage {
  private pageStack: NavPathStack = new NavPathStack()
  // ListScroller（Scroller 子类）：额外提供 closeAllSwipeActions（进编辑态收起左滑滑块）
  private scroller: ListScroller = new ListScroller()
  /** 首可见分组索引（onScrollIndex 维护） */
  @Local firstVisibleIndex: number = 0
  /** 吸顶分组索引（-1 = 无吸顶；组头标题滚出视口时浮出胶囊） */
  @Local stuckGroupIndex: number = -1
  /** 编辑（多选）模式（行内显示状态由行模型 edit 承载，此处仅驱动底栏/返回键） */
  @Local editMode: boolean = false
  /** 已选中记录 id（驱动底栏按钮可用态） */
  @Local selectedIds: number[] = []

  aboutToAppear(): void {
    historyVM.loadAll()
  }

  /** 吸顶分组（越界容错） */
  @Computed
  get stuckGroup(): HistoryGroup | null {
    if (this.stuckGroupIndex >= 0 && this.stuckGroupIndex < this.groups.length) {
      return this.groups[this.stuckGroupIndex]
    }
    return null
  }

  /** 行模型复用缓存（key → 行实例）：groups 重算时复用同一行对象；否则每次重算 new 新实例，而 ForEach 按 key 复用旧 UI 子树仍渲染旧行，setRows 改不到界面持有的对象，编辑态失联 */
  private rowCache: Map<string, HistoryRowModel> = new Map()

  /** 按访问日分组（histories 已按访问时间倒序，同日记录归入同组；行实例跨重算复用） */
  @Computed
  get groups(): HistoryGroup[] {
    const result: HistoryGroup[] = []
    const nextCache: Map<string, HistoryRowModel> = new Map()
    let lastKey: string = ''
    for (const h of historyVM.histories) {
      const key: string = this.dayKey(h.visitTime)
      if (key !== lastKey) {
        result.push(new HistoryGroup(key, this.groupTitle(h.visitTime), []))
        lastKey = key
      }
      const rowKey: string = h.id !== null ? `i${h.id}` : `u${h.url}`
      let row: HistoryRowModel | undefined = this.rowCache.get(rowKey)
      if (row === undefined) {
        row = new HistoryRowModel(rowKey, h)
      } else {
        row.info = h
      }
      nextCache.set(rowKey, row)
      result[result.length - 1].items.push(row)
    }
    this.rowCache = nextCache
    return result
  }

  /** 分组键：年-月-日（本地时区） */
  private dayKey(t: number): string {
    const d = new Date(t)
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`
  }

  /** 分组标题：年月日 星期 */
  private groupTitle(t: number): string {
    const d = new Date(t)
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 星期${WEEKDAY_NAMES[d.getDay()]}`
  }

  /** 行内时间：时:分（日期由分组标题承载） */
  private formatTime(t: number): string {
    const d = new Date(t)
    const hour = `${d.getHours()}`.padStart(2, '0')
    const minute = `${d.getMinutes()}`.padStart(2, '0')
    return `${hour}:${minute}`
  }

  /**
   * 重估吸顶态：首可见分组顶部高于视口顶 36vp（组头标题完全滚出）时浮出胶囊，
   * 标题回到视口内即收回，与真标题交叉过渡
   */
  private updateStuckGroup(): void {
    const idx: number = this.firstVisibleIndex
    if (idx < 0 || idx >= this.groups.length) {
      this.stuckGroupIndex = -1
      return
    }
    try {
      const rect: RectResult = this.scroller.getItemRect(idx)
      const stuck: number = rect.y < -36 ? idx : -1
      if (stuck !== this.stuckGroupIndex) {
        this.stuckGroupIndex = stuck
      }
    } catch (e) {
      this.stuckGroupIndex = -1
    }
  }

  private openHistory(h: HistoryInfo): void {
    browserVM.openUrl(h.url)
    this.pageStack.pop()
  }

  // —— 编辑（多选）模式 ——

  /** 行记录 id（无 id 视为 -1，不参与多选） */
  private histId(h: HistoryInfo): number {
    return h.id !== null ? h.id : -1
  }

  /** 同步行内编辑/选中标记（ForEach 内只认行对象自身的 @Trace） */
  private setRows(edit: boolean, clearSelected: boolean): void {
    for (const g of this.groups) {
      for (const r of g.items) {
        r.edit = edit
        if (clearSelected) {
          r.selected = false
        }
      }
    }
  }

  private enterEdit(): void {
    this.scroller.closeAllSwipeActions()
    this.editMode = true
    this.selectedIds = []
    this.setRows(true, true)
  }

  /** 左滑删除按钮：直接删除并提示 */
  private async deleteSwiped(r: HistoryRowModel): Promise<void> {
    const id: number | null = r.info.id
    if (id === null) {
      return
    }
    await historyVM.deleteById(id)
    this.updateStuckGroup()
    toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
  }

  private exitEdit(): void {
    this.editMode = false
    this.selectedIds = []
    this.setRows(false, true)
  }

  private collectSelectedIds(): number[] {
    const next: number[] = []
    for (const g of this.groups) {
      for (const r of g.items) {
        if (r.selected) {
          next.push(this.histId(r.info))
        }
      }
    }
    return next
  }

  private toggleSelect(r: HistoryRowModel): void {
    r.selected = !r.selected
    this.selectedIds = this.collectSelectedIds()
  }

  private toggleSelectAll(): void {
    let total: number = 0
    let count: number = 0
    for (const g of this.groups) {
      for (const row of g.items) {
        total++
        if (row.selected) {
          count++
        }
      }
    }
    const select: boolean = count < total
    const next: number[] = []
    for (const g of this.groups) {
      for (const row of g.items) {
        row.selected = select
        if (select) {
          next.push(this.histId(row.info))
        }
      }
    }
    this.selectedIds = next
  }

  /** 多选删除：确认后批量删除并退出编辑态 */
  private confirmDeleteSelected(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.delete_selected_records'),
      message: $r('app.string.history_delete_selected_confirm', this.selectedIds.length),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            this.deleteSelection()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteHistorySelected')
  }

  private async deleteSelection(): Promise<void> {
    const ids: number[] = this.selectedIds.slice(0)
    this.exitEdit()
    await historyVM.deleteByIds(ids)
    this.updateStuckGroup()
    toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
  }

  /** 所选记录逐条在新标签页打开（提示打开数量，保留编辑态便于继续操作） */
  private openSelectionInNewTabs(): void {
    const urls: string[] = []
    for (const g of this.groups) {
      for (const r of g.items) {
        if (r.selected) {
          urls.push(r.info.url)
        }
      }
    }
    if (urls.length === 0) {
      return
    }
    for (const u of urls) {
      tabsVM.newTab(u)
    }
    toastUtil.showToast({ message: $r('app.string.history_opened_new_tabs', urls.length) })
  }

  private confirmDelete(h: HistoryInfo): void {
    toastUtil.showAlertDialog({
      title: h.title,
      message: $r('app.string.delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            if (h.id !== null) {
              this.deleteOne(h.id)
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
    }, 'deleteHistory')
  }

  private async deleteOne(id: number): Promise<void> {
    await historyVM.deleteById(id)
    this.updateStuckGroup()
  }

  private confirmClearAll(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.clear_history'),
      message: $r('app.string.clear_history_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.clear'),
          fontColor: Color.Red,
          action: (): void => {
            historyVM.clearAll()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'clearHistory')
  }

  /** 网站图标：缓存 favicon 优先，无则标题首字母圆圈（同书签页） */
  @Builder
  favicon(h: HistoryInfo) {
    if (faviconCache.has(FaviconCache.hostOf(h.url))) {
      Image(fileUri.getUriFromPath(faviconCache.pathOf(FaviconCache.hostOf(h.url))))
        .width(36)
        .height(36)
        .borderRadius(18)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Text(h.title.length > 0 ? h.title.substring(0, 1) : '?')
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

  /** 多选指示器：选中主题色圆底白勾，未选中灰圈（直接读行模型 @Trace） */
  @Builder
  selectIndicator(r: HistoryRowModel) {
    Stack() {
      Circle()
        .width(22)
        .height(22)
        .fill(r.selected ? QhState.currentThemeColor : Color.Transparent)
        .stroke(r.selected ? Color.Transparent : $r('sys.color.icon_tertiary'))
        .strokeWidth(1.5)
      if (r.selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(13)
          .fontColor([Color.White])
      }
    }
    .width(36)
    .height(36)
    .alignContent(Alignment.Center)
  }

  /** 左滑划出的删除按钮：圆形图标按钮（同标题栏返回键样式，comp_background_tertiary 底）+ 红色垃圾桶图标；编辑态渲染零尺寸占位禁用左滑 */
  @Builder
  swipeDeleteButton(r: HistoryRowModel) {
    if (r.edit) {
      Row().width(0).height(0)
    } else {
      Stack() {
        Row() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(20)
            .fontColor([Color.Red])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          this.deleteSwiped(r)
        })
      }
      .width(64)
      .height('100%')
      .alignContent(Alignment.Center)
    }
  }

  @Builder
  historyRow(r: HistoryRowModel) {
    Row({ space: 12 }) {
      if (r.edit) {
        this.selectIndicator(r)
      } else {
        this.favicon(r.info)
      }
      Column({ space: 3 }) {
        Text(r.info.title)
          .fontSize(15)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
        Text(r.info.url)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.formatTime(r.info.visitTime))
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    // 不透明底：遮住左滑划出区域，与组卡片同色不露破绽
    .backgroundColor($r('app.color.background_color'))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (r.edit) {
        this.toggleSelect(r)
      } else {
        this.openHistory(r.info)
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 400 })
        .onAction(() => {
          if (!r.edit) {
            this.confirmDelete(r.info)
          }
        })
    )
  }

  /** 分组头：常规样式（同设置页分组标题）；吸顶胶囊由列表覆盖层单独渲染 */
  @Builder
  groupHeader(g: HistoryGroup, groupIndex: number) {
    Text(g.title)
      .fontSize(14)
      .fontColor($r('sys.color.font_secondary'))
      .margin({ left: 4, bottom: 6, top: groupIndex === 0 ? 10 : 18 })
  }

  /**
   * 编辑栏按钮颜色。必须在 Builder 内的属性表达式里求值——
   * @Builder 值参数挂载后不随状态重传，调用点预计算的颜色不会刷新。
   * reactive: 随选中数联动可用态；danger: 可用态用警示红。
   */
  private itemColor(reactive: boolean, danger: boolean): ResourceColor {
    if (!reactive) {
      return $r('sys.color.font_primary')
    }
    const enabled: boolean = this.selectedIds.length > 0
    if (danger) {
      return enabled ? Color.Red : $r('sys.color.font_tertiary')
    }
    return enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')
  }

  /** 编辑栏按钮（图标 + 文案，同书签页样式） */
  @Builder
  barItem(label: ResourceStr, symbol: Resource, reactive: boolean, danger: boolean, onTap: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([this.itemColor(reactive, danger)])
      Text(label)
        .fontSize(11)
        .fontColor(this.itemColor(reactive, danger))
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }

  /**
   * 常态底部栏：编辑入口 | 清空历史。
   * 全宽底部面板：背景色延伸至屏幕底（小白条后方），按钮经 bottomRectHeight 避让安全区。
   */
  @Builder
  normalBar() {
    Column() {
      Row() {
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_primary')])
          Text($r('app.string.edit'))
            .fontSize(13)
            .fontColor($r('sys.color.font_primary'))
        }
        .layoutWeight(1)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.enterEdit()
        })

        Divider()
          .vertical(true)
          .height(24)
          .color($r('sys.color.comp_divider'))

        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.ohos_trash_circle'))
            .fontSize(18)
            .fontColor([Color.Red])
          Text($r('app.string.clear_history'))
            .fontSize(13)
            .fontColor(Color.Red)
        }
        .layoutWeight(1)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.confirmClearAll()
        })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_color'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: QhState.bottomRectHeight })
    .margin({ top: 8 })
  }

  /** 多选编辑栏：新标签页打开 | 删除 | 全选 | 完成 */
  @Builder
  editBar() {
    Column() {
      Row() {
        this.barItem($r('app.string.bookmark_open_new_tab'), $r('sys.symbol.plus'), true, false,
          (): void => {
            if (this.selectedIds.length > 0) {
              this.openSelectionInNewTabs()
            }
          })
        this.barItem($r('app.string.delete'), $r('sys.symbol.trash'), true, true,
          (): void => {
            if (this.selectedIds.length > 0) {
              this.confirmDeleteSelected()
            }
          })
        this.barItem($r('app.string.select_all'), $r('sys.symbol.checkmark_circle'), false, false,
          (): void => {
            this.toggleSelectAll()
          })
        this.barItem($r('app.string.done'), $r('sys.symbol.checkmark'), false, false,
          (): void => {
            this.exitEdit()
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .backgroundColor($r('app.color.background_color'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: QhState.bottomRectHeight })
    .margin({ top: 8 })
  }

  @Builder
  pageContent() {
    Column() {
      if (historyVM.histories.length === 0) {
        Column() {
          Text($r('app.string.empty_history'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          List({ scroller: this.scroller }) {
            ForEach(this.groups, (g: HistoryGroup, groupIndex: number) => {
              // 分组卡片：组容器承载圆角卡片与行间分隔线；每个记录行为独立 ListItem（原生左滑删除）
              ListItemGroup({ header: this.groupHeader(g, groupIndex) }) {
                ForEach(g.items, (r: HistoryRowModel) => {
                  ListItem() {
                    this.historyRow(r)
                  }
                  .swipeAction({
                    end: (): void => {
                      this.swipeDeleteButton(r)
                    },
                    edgeEffect: SwipeEdgeEffect.Spring
                  })
                }, (r: HistoryRowModel) => r.key)
              }
              .width('100%')
              .borderRadius(16)
              .backgroundColor($r('app.color.background_color'))
              .clip(true)
              .divider({
                strokeWidth: 0.5,
                color: $r('sys.color.comp_divider'),
                startMargin: 64,
                endMargin: 16
              })
            }, (g: HistoryGroup) => `${g.key}#${g.items.length}#${g.items.length > 0 ? g.items[0].key : ''}`)
          }
          .onScrollIndex((first: number, last: number) => {
            this.firstVisibleIndex = first
            this.updateStuckGroup()
          })
          .onDidScroll(() => {
            this.updateStuckGroup()
          })
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: 16, right: 16 })

          // 吸顶胶囊：组头标题滚出视口后浮出，悬浮于列表顶部
          if (this.stuckGroup !== null) {
            Text(this.stuckGroup.title)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(14)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .shadow({ radius: 8, color: 'rgba(0,0,0,0.10)', offsetY: 2 })
              .margin({ left: 20, top: 6 })
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.translate({ y: -8 }))
                .animation({ duration: 150, curve: Curve.EaseOut }))
          }
        }
        .layoutWeight(1)
        .width('100%')
      }

      // 底部编辑栏：常态（编辑入口 + 清空历史）/ 多选态（批量操作）
      if (this.editMode) {
        this.editBar()
      } else {
        this.normalBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color_accent'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.history'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.pageStack = ctx.pathStack
      },
      onBackPressed: (): boolean => {
        if (this.editMode) {
          this.exitEdit()
          return true
        }
        return false
      }
    })
  }
}
