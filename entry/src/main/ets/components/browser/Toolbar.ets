import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { toastUtil } from '../../common/utils/ToastUtils';
import { UISettings, appSettings } from '../../common/entity/SettingsModel';

/**
 * 底部工具栏：返回/前进/主页/标签管理/菜单
 */
class MenuActionInfo {
  icon: Resource
  label: Resource
  action: () => void
  isToggle: boolean
  isOn?: () => boolean

  constructor(icon: Resource, label: Resource, action: () => void,
    isToggle: boolean = false, isOn?: () => boolean) {
    this.icon = icon
    this.label = label
    this.action = action
    this.isToggle = isToggle
    this.isOn = isOn
  }
}

@ComponentV2
export struct BrowserToolbar {
  @Local showMenu: boolean = false
  private menuItems: MenuActionInfo[] = []

  aboutToAppear(): void {
    // Grid 仅设 rowsTemplate 时按列优先排列，此顺序使两行按原菜单顺序展示
    this.menuItems = [
      new MenuActionInfo($r('sys.symbol.arrow_counterclockwise_clock'), $r('app.string.refresh'),
        (): void => {
          browserVM.refresh()
        }),
      new MenuActionInfo($r('sys.symbol.list_book'), $r('app.string.bookmarks'),
        (): void => {
          QhState.pushPage('bookmarks', null)
        }),
      new MenuActionInfo($r('sys.symbol.eye'), $r('app.string.incognito_tab'),
        (): void => {
          // 无痕模式为全局开关：切换「默认无痕浏览」并应用到全部标签
          const target = !appSettings.default_incognito
          appSettings.default_incognito = target
          tabsVM.applyGlobalIncognito(target)
        },
        true,
        (): boolean => {
          return appSettings.default_incognito
        }),
      new MenuActionInfo($r('sys.symbol.clock'), $r('app.string.history'),
        (): void => {
          QhState.pushPage('history', null)
        }),
      new MenuActionInfo($r('sys.symbol.bookmark'), $r('app.string.add_bookmark'),
        (): void => {
          this.addBookmark()
        }),
      new MenuActionInfo($r('sys.symbol.circle_and_arrow_down'), $r('app.string.downloads'),
        (): void => {
          QhState.pushPage('downloads', null)
        }),
      new MenuActionInfo($r('sys.symbol.magnifyingglass'), $r('app.string.find_in_page'),
        (): void => {
          browserVM.showFindBar = true
        }),
      new MenuActionInfo($r('sys.symbol.gearshape_fill'), $r('app.string.settings'),
        (): void => {
          QhState.pushPage('settings', null)
        }),
      new MenuActionInfo($r('sys.symbol.doc_text'), $r('app.string.copy_link'),
        (): void => {
          this.copyLink()
        })
    ]
  }

  private addBookmark(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) return
    bookmarkVM.addBookmark(tab.title, tab.url)
    toastUtil.showToast({ message: $r('app.string.bookmark_added') })
  }

  private async copyLink(): Promise<void> {
    const ok = await browserVM.copyLink()
    if (ok) {
      toastUtil.showToast({ message: $r('app.string.link_copied') })
    }
  }

  @Builder
  menuSheetBuilder() {
    Column() {
      Grid() {
        ForEach(this.menuItems, (item: MenuActionInfo, index: number) => {
          GridItem() {
            Column({ space: 4 }) {
              SymbolGlyph(item.icon)
                .fontSize(26)
                .fontColor([
                  item.isToggle && item.isOn && item.isOn()
                    ? QhState.currentThemeColor
                    : $r('sys.color.font_primary')
                ])
              Text(item.label)
                .fontSize(11)
                .fontColor($r('sys.color.font_secondary'))
                .maxLines(1)
            }
            .width(84)
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
          .onClick(() => {
            if (item.isToggle) {
              item.action()
            } else {
              this.showMenu = false
              item.action()
            }
          })
        }, (item: MenuActionInfo, index: number): string => index.toString())
      }
      .rowsTemplate('1fr 1fr')
      .scrollBar(BarState.Off)
      .columnsGap(4)
      .rowsGap(4)
      .width('100%')
      .height(160)
      .padding({ left: 4, right: 4 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  build() {
    // 底部工具栏：背景通过底部内边距延伸到小白条区域
    Column() {
      Row() {
      // 返回
      Row() {
        Stack({ alignContent: Alignment.TopStart }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(26)
            .fontColor([this.navColor(tabsVM.activeTab ? tabsVM.activeTab.canBack : false)])
        }
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        browserVM.goBack()
      })

      // 前进
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(26)
          .fontColor([this.navColor(tabsVM.activeTab ? tabsVM.activeTab.canForward : false)])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        browserVM.goForward()
      })

      // 主页
      Row() {
        SymbolGlyph($r('sys.symbol.house'))
          .fontSize(25)
          .fontColor([$r('sys.color.font_primary')])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        const tab = tabsVM.activeTab
        if (tab) {
          tabsVM.goHome(tab)
        }
      })

      // 标签管理：方框 + 中间数字
      Row() {
        Stack() {
          Text(`${tabsVM.tabCount}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
        }
        .width(21)
        .height(21)
        .border({
          width: 1.5,
          color: $r('sys.color.font_primary'),
          radius: 4
        })
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        browserVM.showTabSwitcher = true
      })

      // 菜单
      Row() {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(25)
          .fontWeight(FontWeight.Normal)
          .fontColor([$r('sys.color.font_primary')])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.showMenu = true
      })
      .bindSheet(this.showMenu!!, this.menuSheetBuilder(), {
        height: 210,
        dragBar: true,
        showClose: false,
        backgroundColor: $r('sys.color.comp_background_primary'),
        onDisappear: () => {
          this.showMenu = false
        }
      })
    }
    .width('100%')
    .height(52)
    .backgroundColor($r('sys.color.comp_background_primary'))
    }
    .width('100%')
    .padding({
      bottom: UISettings.toolbar_position !== 'top' ? QhState.bottomRectHeight : 0
    })
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  navColor(enabled: boolean): ResourceColor {
    return enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')
  }

}


