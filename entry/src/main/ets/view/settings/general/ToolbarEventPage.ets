import { SettingsScaffold, SettingsSection } from '../../../components/SettingsScaffold';
import { QhState } from '../../../entryability/AppState';
import {
  toolbarActionGroups,
  toolbarEventLabel,
  getToolbarEventAction,
  setToolbarEventAction
} from '../../../common/entity/ToolbarEvent';
import { CustomItemInfo, ItemActionType, RadioConfig } from '../../../common/entity/CusItemInfo';
import { ResourceUtils } from '../../../common/utils/app/ResourceUtil';


@Builder
export function ToolbarEventBuilder() {
  ToolbarEventPage()
}

@ComponentV2
struct ToolbarEventPage {

  /** 事件 id（back_long/forward_long/home_long/tabs_long/menu_long/swipe_left/swipe_right） */
  @Local eventId: string = ''
  @Local selected: string = 'none'
  @Local sections: SettingsSection[] = []
  private scroller: Scroller = new Scroller()

  /** 页面标题：选择行为 - 事件说明（如「选择行为 - 左箭头长按」） */
  private pageTitle(): string {
    const base: string = ResourceUtils.getString($r('app.string.select_behavior'))
    if (this.eventId === '') {
      return base
    }
    return `${base} - ${ResourceUtils.getString(toolbarEventLabel(this.eventId))}`
  }

  /** 行为目录转为脚手架分组（单选行） */
  private buildSections(): void {
    const sections: SettingsSection[] = []
    for (const g of toolbarActionGroups()) {
      const section: SettingsSection = new SettingsSection(g.id, g.title)
      for (const a of g.actions) {
        section.items.push(new CustomItemInfo({
          id: a.id,
          title: a.label,
          type: ItemActionType.RADIO,
          value: this.selected,
          iconColor: QhState.currentThemeColor,
          radioConfig: new RadioConfig(a.id, this.eventId),
          onChange: (v: string | boolean | number): void => {
            this.selectAction(`${v}`)
          }
        }))
      }
      sections.push(section)
    }
    this.sections = sections
  }

  /** 选中行为所在分组序号 */
  private selectedSectionIndex(): number {
    for (let i = 0; i < this.sections.length; i++) {
      for (const item of this.sections[i].items) {
        if (item.id === this.selected) {
          return i
        }
      }
    }
    return -1
  }

  /** 进入页面自动滚动到已选中的行为所在分组（等待布局完成） */
  private scrollToSelected(): void {
    const index: number = this.selectedSectionIndex()
    if (index < 0) {
      return
    }
    setTimeout(() => {
      this.scroller.scrollToIndex(index, false, ScrollAlign.CENTER)
    }, 150)
  }

  build() {
    SettingsScaffold({
      title: this.pageTitle(),
      sections: this.sections,
      scroller: this.scroller,
      onReady: (ctx: NavDestinationContext): void => {
        const param: string = ctx.pathInfo.param as string
        if (param !== null && param !== undefined && param !== '') {
          this.eventId = param
          this.selected = getToolbarEventAction(this.eventId)
          this.buildSections()
          this.scrollToSelected()
        }
      }
    })
  }

  /** 选中并保存后返回上一页 */
  private selectAction(actionId: string): void {
    if (this.eventId === '') {
      return
    }
    if (actionId !== this.selected) {
      setToolbarEventAction(this.eventId, actionId)
      this.selected = actionId
    }
    QhState.popPage(true)
  }
}
