import { NaviContainer } from '../../components/NaviContainer';
import { QhState } from '../../entryability/AppState';
import { CustomItemInfo, ItemActionType } from '../../common/entity/CusItemInfo';
import { CustomListItem } from '../../components/CusItemBuilder';
import { appSettings } from '../../common/entity/SettingsModel';

@Builder
export function SettingsBuilder() {
  SettingsPage()
}

@ComponentV2
struct SettingsPage {

  @Local items: CustomItemInfo[] = []
  /** 大屏分栏模式当前选中的菜单项 id */
  @Local selectedId: string = ''

  /** 大屏分栏右侧子导航栈 */
  private splitStack: NavPathStack = new NavPathStack()

  /** 大屏（widthBp > 1）启用分栏布局 */
  @Computed
  get isSplit(): boolean {
    return QhState.widthBp > 1
  }

  aboutToAppear(): void {
    const items: CustomItemInfo[] = []
    items.push(this.routerItem('settings_general', $r('app.string.settings_general')))
    items.push(this.routerItem('settings_custom', $r('app.string.settings_custom')))
    items.push(this.routerItem('settings_privacy', $r('app.string.settings_privacy')))
    items.push(this.routerItem('settings_advanced', $r('app.string.settings_advanced')))
    items.push(this.routerItem('settings_script', $r('app.string.settings_script')))
    items.push(this.routerItem('settings_extension', $r('app.string.settings_extension_entry')))
    items.push(this.routerItem('about', $r('app.string.about')))
    this.items = items
    this.syncSplitState()
  }

  aboutToDisappear(): void {
    if (QhState.settingsSplitStack === this.splitStack) {
      QhState.settingsSplitStack = null
    }
  }

  @Monitor('isSplit')
  onSplitChange(): void {
    this.syncSplitState()
  }

  /** 分栏开关切换：激活时注册右侧子栈（默认选中"通用"）；收起时把右侧当前栏目带回全屏路由 */
  private syncSplitState(): void {
    if (this.isSplit) {
      QhState.settingsSplitStack = this.splitStack
      if (this.splitStack.size() === 0) {
        this.selectCategory('settings_general')
      }
      return
    }
    if (QhState.settingsSplitStack === this.splitStack) {
      QhState.settingsSplitStack = null
      const names: string[] = this.splitStack.getAllPathName()
      this.splitStack.clear()
      this.selectedId = ''
      if (names.length > 0) {
        QhState.pushPage(names[0], null, false)
      }
    }
  }

  /** 分栏模式：点击左栏菜单项，右侧子导航展示对应设置页 */
  private selectCategory(id: string): void {
    if (this.selectedId === id && this.splitStack.size() > 0) {
      return
    }
    this.splitStack.clear()
    this.selectedId = id
    this.splitStack.replacePathByName(id, null, true)
  }

  private routerItem(id: string, title: ResourceStr): CustomItemInfo {
    return new CustomItemInfo({
      id: id,
      title: title,
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage(id, null)
      }
    })
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings'),
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

  @Builder
  pageContent() {
    if (this.isSplit) {
      this.splitContent()
    } else {
      this.listContent()
    }
  }

  /** 大屏分栏：Navigation Split 模式——左侧菜单为 NavBar，右侧展示路由的设置子页 */
  @Builder
  splitContent() {
    Navigation(this.splitStack) {
      List() {
        Repeat<CustomItemInfo>(this.items)
          .each((ri: RepeatItem<CustomItemInfo>) => {
            ListItem() {
              Text(ri.item.title)
                .fontSize(16)
                .fontFamily(appSettings.font_family)
                .fontColor(this.selectedId === ri.item.id ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 12 })
            .borderRadius(12)
            .backgroundColor(this.selectedId === ri.item.id ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
            .margin({ top: 2, bottom: 2 })
            .onClick(() => {
              this.selectCategory(ri.item.id)
            })
          })
          .key((item: CustomItemInfo) => item.id)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .padding({ left: 12, right: 12 })
      .width('100%')
      .height('100%')
    }
    .mode(NavigationMode.Split)
    .navBarWidth(240)
    .navBarWidthRange([220, 340])
    .hideTitleBar(true)
    .hideToolBar(true)
    .width('100%')
    .height('100%')
  }

  /** 普通单栏菜单列表 */
  @Builder
  listContent() {
    List() {
      ListItem() {
        Column() {
          Repeat<CustomItemInfo>(this.items)
            .each((ri: RepeatItem<CustomItemInfo>) => {
              CustomListItem({
                item: ri.item,
                itemPadding: { left: 16, right: 16, top: 14, bottom: 14 }
              })
            })
            .key((item: CustomItemInfo) => item.id)
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.background_color'))
        .clip(true)
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(56)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }
}
