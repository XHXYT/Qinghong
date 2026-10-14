import { NaviContainer } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { CustomItemInfo, ItemActionType } from '../../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../../components/CusItemBuilder';
import { ResourceUtils } from '../../../../common/utils/ResourceUtil';
import { appSettings } from '../../../../common/entity/SettingsModel';
import { UaUtils } from '../../../../common/utils/UaUtils';
import { SiteItemConfig, SiteSettingsViewModel } from '../../../../viewmodel/SiteSettingsViewModel';

/** 分组渲染包装 */
class GroupWrapper {
  readonly key: string
  readonly title: ResourceStr
  readonly items: CustomItemInfo[] = []

  constructor(key: string, title: ResourceStr) {
    this.key = key
    this.title = title
  }
}

@Builder
export function SettingsSiteBuilder() {
  SiteSettingsPage()
}

@ComponentV2
struct SiteSettingsPage {

  @Local allSitesItem: CustomItemInfo = new CustomItemInfo({ id: 'all_sites', type: ItemActionType.ROUTER })
  @Local groups: GroupWrapper[] = []

  aboutToAppear(): void {
    this.allSitesItem.title = $r('app.string.site_all_sites')
    this.allSitesItem.onChange = (v: string | boolean | number): void => {
      QhState.pushPage('settings_site_list', null)
    }
    this.buildGroups()
    this.refreshValues()
  }

  /** 分组结构仅构建一次（keyed Repeat 不重执行 builder），数据变化靠 @Trace 原地刷新 */
  private buildGroups(): void {
    const groups: GroupWrapper[] = []
    for (const g of SiteSettingsViewModel.groups()) {
      const w: GroupWrapper = new GroupWrapper(g.key, g.title)
      for (const config of g.items) {
        w.items.push(this.itemOf(config))
      }
      groups.push(w)
    }
    this.groups = groups
  }

  private itemOf(config: SiteItemConfig): CustomItemInfo {
    return new CustomItemInfo({
      id: config.key,
      title: config.title,
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('settings_site_item', config.key)
      }
    })
  }

  /** 刷新各行默认档位副标（@Trace 原地更新） */
  private refreshValues(): void {
    for (const g of this.groups) {
      for (const item of g.items) {
        const config: SiteItemConfig | null = SiteSettingsViewModel.config(item.id)
        if (config === null) {
          continue
        }
        if (config.key === 'site_ua') {
          // 全局浏览器标识即应用 UA，显示应用当前标识名
          const name: ResourceStr = UaUtils.presetName(appSettings.ua_mode)
          item.value = typeof name === 'string' ? name : ResourceUtils.getString(name as Resource)
        } else if (config.key === 'site_font_size') {
          item.value = `${Number(SiteSettingsViewModel.getDefault(config.key))}%`
        } else if (config.key === 'site_cookies') {
          // Cookies 为全局双开关，显示总开关状态
          item.value = ResourceUtils.getString(appSettings.cookies_enabled
            ? $r('app.string.site_opt_on') : $r('app.string.site_opt_off'))
        } else if (config.key === 'site_incognito') {
          // 全局默认即「默认无痕浏览」开关，显示其状态
          item.value = ResourceUtils.getString(appSettings.default_incognito
            ? $r('app.string.site_opt_on') : $r('app.string.site_opt_off'))
        } else if (config.key === 'site_vibration') {
          // 网页振动为全局开关（无站点例外），显示其状态
          item.value = ResourceUtils.getString(appSettings.web_vibration_enabled
            ? $r('app.string.site_opt_on') : $r('app.string.site_opt_off'))
        } else if (config.key === 'site_popup') {
          // 弹出式窗口为全局开关（无站点例外），显示其状态
          item.value = ResourceUtils.getString(appSettings.popup_allowed
            ? $r('app.string.site_opt_on') : $r('app.string.site_opt_off'))
        } else {
          item.value = SiteSettingsViewModel.labelOf(config, SiteSettingsViewModel.getDefault(config.key))
        }
      }
    }
  }

  build() {
    NaviContainer({
      title: $r('app.string.site_settings'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onShown: (): void => {
        // 二级页改过默认值，返回刷新副标
        this.refreshValues()
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      // 所有网站（按站点管理）
      ListItem() {
        CustomListItem({
          item: this.allSitesItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 分组
      Repeat<GroupWrapper>(this.groups)
        .each((ri: RepeatItem<GroupWrapper>) => {
          ListItem() {
            Column() {
              Text(ri.item.title)
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
                .margin({ left: 4, bottom: 6, top: 18 })
              Column() {
                Repeat<CustomItemInfo>(ri.item.items)
                  .each((ci: RepeatItem<CustomItemInfo>) => {
                    CustomListItem({
                      item: ci.item,
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
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        })
        .key((group: GroupWrapper) => group.key)
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }
}
