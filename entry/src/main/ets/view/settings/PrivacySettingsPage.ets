import { NaviContainer } from '../../components/NaviContainer';
import { appSettings } from '../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../common/entity/CusItemInfo';
import { CustomListItem } from '../../components/CusItemBuilder';
import { tabsVM } from '../../viewmodel/TabsViewModel';

@Builder
export function PrivacySettingsBuilder() {
  PrivacySettingsPage()
}

@ComponentV2
struct PrivacySettingsPage {

  @Local items: CustomItemInfo[] = []

  aboutToAppear(): void {
    const items: CustomItemInfo[] = []
    items.push(new CustomItemInfo({
      id: 'do_not_track',
      title: $r('app.string.do_not_track'),
      subtitle: $r('app.string.do_not_track_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.do_not_track,
      onChange: (v: string | boolean | number): void => {
        appSettings.do_not_track = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'disable_webrtc',
      title: $r('app.string.disable_webrtc'),
      subtitle: $r('app.string.disable_webrtc_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.disable_webrtc,
      onChange: (v: string | boolean | number): void => {
        appSettings.disable_webrtc = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'geolocation_access',
      title: $r('app.string.geolocation_access'),
      subtitle: $r('app.string.geolocation_access_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.geolocation_access,
      onChange: (v: string | boolean | number): void => {
        appSettings.geolocation_access = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'do_not_sell',
      title: $r('app.string.do_not_sell'),
      subtitle: $r('app.string.do_not_sell_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.do_not_sell,
      onChange: (v: string | boolean | number): void => {
        appSettings.do_not_sell = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'default_incognito',
      title: $r('app.string.default_incognito'),
      type: ItemActionType.TOGGLE,
      value: appSettings.default_incognito,
      onChange: (v: string | boolean | number): void => {
        const target = v === true
        appSettings.default_incognito = target
        tabsVM.applyGlobalIncognito(target)
      }
    }))
    this.items = items
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_privacy'),
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
                itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
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
