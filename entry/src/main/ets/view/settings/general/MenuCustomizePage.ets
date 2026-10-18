import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { MenuEntry, MenuEntries } from '../../../common/constants/MenuEntries';
import { appSettings } from '../../../common/entity/SettingsModel';
import { QhState } from '../../../entryability/AppState';

/** 网格单元格高度（图标 28 + 间距 + 两行标签） */
const CELL_HEIGHT = 96

@Builder
export function SettingsMenuCustomBuilder() {
  MenuCustomizePage()
}

/** 菜单条目格：细线条图标 + 居中小字标签（最多两行） */
@ComponentV2
struct MenuEntryItem {
  @Require @Param entry: MenuEntry

  build() {
    Column({ space: 8 }) {
      SymbolGlyph(this.entry.symbol)
        .fontSize(28)
        .fontColor([$r('sys.color.font_primary')])
      Text(this.entry.title)
        .fontSize(11)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@ComponentV2
struct MenuCustomizePage {

  /** 区域①：已在菜单中的条目 */
  @Local menuEntries: MenuEntry[] = []
  /** 区域②：可添加的条目 */
  @Local addableEntries: MenuEntry[] = []

  /** 拖动来源是否为菜单区 */
  private dragFromMenu: boolean = false
  /** 拖动起始下标 */
  private dragIndex: number = -1

  aboutToAppear(): void {
    this.loadEntries()
  }

  /** 依据持久化布局构建两组条目 */
  private loadEntries(): void {
    const layoutIds: string[] = appSettings.menu_layout !== '' ? appSettings.menu_layout.split(',') : []
    const menu: MenuEntry[] = []
    const usedIds: string[] = []
    if (layoutIds.length > 0) {
      for (const id of layoutIds) {
        const e: MenuEntry | undefined = MenuEntries.byId(id)
        if (e !== undefined) {
          menu.push(e)
          usedIds.push(e.id)
        }
      }
    } else {
      for (const id of MenuEntries.DEFAULT_MENU) {
        const e: MenuEntry | undefined = MenuEntries.byId(id)
        if (e !== undefined) {
          menu.push(e)
          usedIds.push(e.id)
        }
      }
    }
    const addable: MenuEntry[] = []
    for (const e of MenuEntries.ALL) {
      if (!usedIds.includes(e.id)) {
        addable.push(e)
      }
    }
    this.menuEntries = menu
    this.addableEntries = addable
  }

  /** 保存菜单布局（@Monitor 自动持久化） */
  private persistLayout(): void {
    appSettings.menu_layout = this.menuEntries.map((e: MenuEntry): string => e.id).join(',')
  }

  /** 恢复默认菜单布局 */
  private resetEntries(): void {
    appSettings.menu_layout = ''
    this.loadEntries()
  }

  private gridHeight(count: number): number {
    return Math.ceil(count / 5) * CELL_HEIGHT
  }

  /** 菜单区接收拖放：区内重排 / 从可添加区拖入 */
  private dropToMenu(insertIndex: number): void {
    let to: number = insertIndex
    if (to < 0 || to > this.menuEntries.length) {
      to = this.menuEntries.length
    }
    if (this.dragFromMenu) {
      if (this.dragIndex < 0 || this.dragIndex >= this.menuEntries.length) {
        return
      }
      const moved: MenuEntry = this.menuEntries.splice(this.dragIndex, 1)[0]
      this.menuEntries.splice(to, 0, moved)
    } else {
      if (this.dragIndex < 0 || this.dragIndex >= this.addableEntries.length) {
        return
      }
      const moved: MenuEntry = this.addableEntries.splice(this.dragIndex, 1)[0]
      this.menuEntries.splice(to, 0, moved)
    }
    this.persistLayout()
  }

  /** 可添加区接收拖放：从菜单区拖出 = 移除；区内重排仅当次生效 */
  private dropToAddable(insertIndex: number): void {
    let to: number = insertIndex
    if (to < 0 || to > this.addableEntries.length) {
      to = this.addableEntries.length
    }
    if (this.dragFromMenu) {
      if (this.dragIndex < 0 || this.dragIndex >= this.menuEntries.length) {
        return
      }
      const moved: MenuEntry = this.menuEntries.splice(this.dragIndex, 1)[0]
      this.addableEntries.splice(to, 0, moved)
      this.persistLayout()
    } else {
      if (this.dragIndex < 0 || this.dragIndex >= this.addableEntries.length) {
        return
      }
      const moved: MenuEntry = this.addableEntries.splice(this.dragIndex, 1)[0]
      this.addableEntries.splice(to, 0, moved)
    }
  }

  /** 点击可添加条目：加入菜单末尾（带衔接动画） */
  private addToMenu(e: MenuEntry): void {
    const idx: number = this.addableEntries.indexOf(e)
    if (idx >= 0) {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, (): void => {
        this.addableEntries.splice(idx, 1)
        this.menuEntries.push(e)
        this.persistLayout()
      })
    }
  }

  /** 点击菜单条目：移回可添加区（带衔接动画；可添加区为空时也能由此找回条目） */
  private removeFromMenu(e: MenuEntry): void {
    const idx: number = this.menuEntries.indexOf(e)
    if (idx >= 0) {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, (): void => {
        this.menuEntries.splice(idx, 1)
        this.addableEntries.push(e)
        this.persistLayout()
      })
    }
  }

  build() {
    NaviContainer({
      title: $r('app.string.customize_menu'),
      buttons: [new NaviBarButton({
        text: $r('app.string.reset'),
        width: 56,
        backgroundColor: Color.Transparent,
        action: (): void => {
          this.resetEntries()
        }
      })],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  /** 拖动跟随预览 */
  @Builder
  dragPreviewBuilder(e: MenuEntry) {
    Column({ space: 8 }) {
      SymbolGlyph(e.symbol)
        .fontSize(28)
        .fontColor([$r('sys.color.font_primary')])
      Text(e.title)
        .fontSize(11)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .width('20%')
    .height(CELL_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
  }

  @Builder
  pageContent() {
    List() {
      // 提示：拖动排序
      ListItem() {
        Text($r('app.string.menu_reorder_hint'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 14, bottom: 6 })
      }

      // 区域①：已在菜单中（5 列网格，长按拖动排序/拖出移除）
      ListItem() {
        Grid() {
          ForEach(this.menuEntries, (e: MenuEntry) => {
            GridItem() {
              MenuEntryItem({ entry: e })
            }
            .height(CELL_HEIGHT)
            .onClick(() => {
              this.removeFromMenu(e)
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.Friction }))
          }, (e: MenuEntry) => e.id)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .height(this.gridHeight(this.menuEntries.length))
        .width('100%')
        .editMode(true)
        .supportAnimation(true)
        .scrollBar(BarState.Off)
        .onItemDragStart((event: ItemDragInfo, itemIndex: number): CustomBuilder => {
          this.dragFromMenu = true
          this.dragIndex = itemIndex
          return this.dragPreviewBuilder(this.menuEntries[itemIndex])
        })
        .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
          if (!isSuccess) {
            return
          }
          this.dropToMenu(insertIndex)
        })
      }

      // 提示：添加条目
      ListItem() {
        Text($r('app.string.menu_add_hint'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 24, bottom: 6 })
      }

      // 区域②：可添加（5 列网格，点击加入；也可拖入上方）
      ListItem() {
        Grid() {
          ForEach(this.addableEntries, (e: MenuEntry) => {
            GridItem() {
              MenuEntryItem({ entry: e })
            }
            .height(CELL_HEIGHT)
            .onClick(() => {
              this.addToMenu(e)
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.Friction }))
          }, (e: MenuEntry) => e.id)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .height(this.gridHeight(this.addableEntries.length))
        .width('100%')
        .editMode(true)
        .supportAnimation(true)
        .scrollBar(BarState.Off)
        .onItemDragStart((event: ItemDragInfo, itemIndex: number): CustomBuilder => {
          this.dragFromMenu = false
          this.dragIndex = itemIndex
          return this.dragPreviewBuilder(this.addableEntries[itemIndex])
        })
        .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
          if (!isSuccess) {
            return
          }
          this.dropToAddable(insertIndex)
        })
      }
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
