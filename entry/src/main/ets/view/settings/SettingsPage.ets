import { NaviContainer } from '../../components/NaviContainer';
import { QhState } from '../../entryability/AppState';
import { CustomItemInfo, ItemActionType } from '../../common/entity/CusItemInfo';
import { CustomListItem } from '../../components/CusItemBuilder';

@Builder
export function SettingsBuilder() {
  SettingsPage()
}

@ComponentV2
struct SettingsPage {

  @Local items: CustomItemInfo[] = []

  aboutToAppear(): void {
    const items: CustomItemInfo[] = []
    items.push(this.routerItem('settings_general', $r('app.string.settings_general')))
    items.push(this.routerItem('settings_custom', $r('app.string.settings_custom')))
    items.push(this.routerItem('settings_privacy', $r('app.string.settings_privacy')))
    items.push(this.routerItem('settings_advanced', $r('app.string.settings_advanced')))
    items.push(this.routerItem('settings_script', $r('app.string.settings_script')))
    items.push(this.routerItem('settings_extension', $r('app.string.settings_extension')))
    items.push(this.routerItem('about', $r('app.string.about')))
    this.items = items
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
