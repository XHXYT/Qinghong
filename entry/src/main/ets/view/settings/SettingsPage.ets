import { webview } from '@kit.ArkWeb';
import { NaviContainer } from '../../components/NaviContainer';
import { QhState } from '../../entryability/AppState';
import { appSettings, UISettings } from '../../common/entity/SettingsModel';
import { historyVM } from '../../viewmodel/HistoryViewModel';
import { searchHistoryVM } from '../../viewmodel/SearchViewModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { SearchEngines } from '../../common/constants/SearchEngines';
import { CustomItemInfo, ItemActionType, MenuOption, makeItemGroups, ItemGroupData } from '../../common/entity/CusItemInfo';
import { CustomListItem } from '../../components/CusItemBuilder';
import { toastUtil } from '../../common/utils/ToastUtils';

@Builder
export function SettingsBuilder() {
  SettingsPage()
}

@ComponentV2
struct SettingsPage {

  @Local groups: ItemGroupData[] = []

  aboutToAppear(): void {
    this.rebuildItems()
  }

  private rebuildItems(): void {
    const items: CustomItemInfo[] = []

    // 通用
    items.push(new CustomItemInfo({
      id: 'g_general', title: $r('app.string.settings'),
      type: ItemActionType.GROUP
    }))
    items.push(new CustomItemInfo({
      id: 'search_engine',
      symbol: $r('sys.symbol.curve_magnifyingglass'),
      title: $r('app.string.search_engine'),
      value: SearchEngines.getCurrentEngine().name,
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('search_engine', null)
      }
    }))
    items.push(new CustomItemInfo({
      id: 'restore_session',
      symbol: $r('sys.symbol.arrow_2_circlepath'),
      title: $r('app.string.restore_session'),
      type: ItemActionType.TOGGLE,
      value: appSettings.restore_session,
      onChange: (v: string | boolean | number): void => {
        appSettings.restore_session = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'default_incognito',
      symbol: $r('sys.symbol.eye'),
      title: $r('app.string.default_incognito'),
      type: ItemActionType.TOGGLE,
      value: appSettings.default_incognito,
      onChange: (v: string | boolean | number): void => {
        appSettings.default_incognito = v as boolean
      }
    }))

    // 界面
    items.push(new CustomItemInfo({
      id: 'g_ui', title: $r('app.string.toolbar_position'),
      type: ItemActionType.GROUP
    }))
    items.push(new CustomItemInfo({
      id: 'toolbar_position',
      symbol: $r('sys.symbol.square_grid_2x2'),
      title: $r('app.string.toolbar_position'),
      type: ItemActionType.MENU,
      value: UISettings.toolbar_position,
      menuOptions: [
        new MenuOption('bottom', $r('app.string.toolbar_bottom')),
        new MenuOption('top', $r('app.string.toolbar_top'))
      ],
      onChange: (v: string | boolean | number): void => {
        UISettings.toolbar_position = v as string
      }
    }))
    items.push(new CustomItemInfo({
      id: 'homepage_settings',
      symbol: $r('sys.symbol.house'),
      title: $r('app.string.homepage_settings'),
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('homepage_settings', null)
      }
    }))
    items.push(new CustomItemInfo({
      id: 'show_logo',
      symbol: $r('sys.symbol.picture_star_fill'),
      title: $r('app.string.show_homepage_logo'),
      type: ItemActionType.TOGGLE,
      value: appSettings.show_homepage_logo,
      onChange: (v: string | boolean | number): void => {
        appSettings.show_homepage_logo = v as boolean
      }
    }))

    // 数据
    items.push(new CustomItemInfo({
      id: 'g_data', title: $r('app.string.clear_browsing_data'),
      type: ItemActionType.GROUP
    }))
    items.push(new CustomItemInfo({
      id: 'clear_history',
      symbol: $r('sys.symbol.clock'),
      title: $r('app.string.clear_history_label'),
      type: ItemActionType.TEXT,
      isDanger: true,
      onChange: (v: string | boolean | number): void => {
        this.confirmClearHistory()
      }
    }))
    items.push(new CustomItemInfo({
      id: 'clear_search_history',
      symbol: $r('sys.symbol.magnifyingglass'),
      title: $r('app.string.clear_search_history_label'),
      type: ItemActionType.TEXT,
      isDanger: true,
      onChange: (v: string | boolean | number): void => {
        searchHistoryVM.clearAll()
        toastUtil.showToast({ message: $r('app.string.cleared') })
      }
    }))
    items.push(new CustomItemInfo({
      id: 'clear_cache',
      symbol: $r('sys.symbol.doc_text'),
      title: $r('app.string.clear_cache_label'),
      type: ItemActionType.TEXT,
      onChange: (v: string | boolean | number): void => {
        this.clearWebCache()
      }
    }))
    items.push(new CustomItemInfo({
      id: 'clear_cookies',
      symbol: $r('sys.symbol.lock'),
      title: $r('app.string.clear_cookies_label'),
      type: ItemActionType.TEXT,
      onChange: (v: string | boolean | number): void => {
        webview.WebCookieManager.clearAllCookiesSync()
        toastUtil.showToast({ message: $r('app.string.cleared') })
      }
    }))

    // 关于
    items.push(new CustomItemInfo({
      id: 'g_about', title: $r('app.string.about'),
      type: ItemActionType.GROUP
    }))
    items.push(new CustomItemInfo({
      id: 'about',
      symbol: $r('sys.symbol.info_circle'),
      title: $r('app.string.about'),
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('about', null)
      }
    }))

    this.groups = makeItemGroups(items)
  }

  private confirmClearHistory(): void {
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
            toastUtil.showToast({ message: $r('app.string.cleared') })
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

  private clearWebCache(): void {
    const tab = tabsVM.activeTab
    if (tab && tab.controller) {
      try {
        (tab.controller as webview.WebviewController).removeCache(true)
        toastUtil.showToast({ message: $r('app.string.cleared') })
      } catch (e) {
        toastUtil.showToast({ message: `${e}` })
      }
    } else {
      toastUtil.showToast({ message: $r('app.string.cleared') })
    }
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
    Scroll() {
      Column() {
        ForEach(this.groups, (g: ItemGroupData, gi: number) => {
          Column() {
            if (g.group) {
              Row() {
                Text(g.group.title)
                  .fontSize(13)
                  .fontColor($r('sys.color.font_secondary'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })
            }
            Column() {
              ForEach(g.items, (item: CustomItemInfo, ii: number) => {
                CustomListItem({
                  item: item,
                  itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                })
                if (ii < g.items.length - 1) {
                  Divider()
                    .strokeWidth(0.5)
                    .color($r('sys.color.comp_divider'))
                    .margin({ left: 56, right: 16 })
                }
              }, (item: CustomItemInfo) => item.id)
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor($r('sys.color.comp_background_primary'))
          }
          .width('100%')
          .margin({ left: 12, right: 12, top: gi === 0 ? 12 : 4 })
        }, (g: ItemGroupData, gi: number) => `g${gi}_${g.items.length}`)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
