import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { UISettings } from '../../common/entity/SettingsModel';
import { MenuEntry } from '../../common/constants/MenuEntries';
import { SheetPicker } from '../SheetPicker';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { BookmarkEditor } from './BookmarkEditor';
import { addressDisplayText } from './AddressBar';
import { ActionBarColor } from '../../common/utils/ActionBarColor';

/**
 * 合并操作栏（返回/前进/地址胶囊/标签/菜单单行合并），
 * position 'top'/'bottom' 决定是否避让底部小白条
 */
@ComponentV2
export struct MergedActionBar {
  @Param barPosition: string = 'bottom'

  @Builder
  menuEntryItem(e: MenuEntry) {
    Column({ space: 4 }) {
      SymbolGlyph(e.symbol)
        .fontSize(26)
        .fontColor([menuVM.entryIconColor(e.id)])
      Text(menuVM.entryTitle(e))
        .fontSize(11)
        .fontColor(menuVM.entryTitleColor(e.id))
        .maxLines(1)
    }
    .width('100%')
    .height(46)
    .justifyContent(FlexAlign.Center)
  }

  /** 工具栏半模态内容：选择器或字号滑杆（menuVM.sheetKind 决定） */
  @Builder
  sheetBuilder() {
    if (menuVM.sheetKind === 'font') {
      Column() {
        Row() {
          Text($r('app.string.font_size'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Text(`${menuVM.fontZoomValue}%`)
            .fontSize(16)
            .fontColor(QhState.currentThemeColor)
        }
        .width('100%')
        .height(48)
        Slider({ value: menuVM.fontZoomValue, min: 50, max: 200, step: 5, style: SliderStyle.InSet })
          .selectedColor(QhState.currentThemeColor)
          .width('100%')
          .margin({ top: 8, bottom: 12 })
          .onChange((value: number, mode: SliderChangeMode) => {
            menuVM.applyFontZoom(value)
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              menuVM.persistFontZoom()
            }
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 8 })
    } else {
      SheetPicker({
        config: menuVM.picker,
        close: (): void => {
          menuVM.showSheet = false
        }
      })
    }
  }

  /** 添加书签编辑器：sheet 内局部 Navigation 路由 */
  @Builder
  bookmarkEditorBuilder() {
    BookmarkEditor()
  }

  @Builder
  menuSheetBuilder() {
    Column() {
      Swiper() {
        ForEach(menuVM.menuPages, (page: MenuEntry[]) => {
          Column() {
            Grid() {
              ForEach(page, (e: MenuEntry) => {
                GridItem() {
                  this.menuEntryItem(e)
                }
              .onClick(() => {
                if (menuVM.isEntryDisabled(e.id)) {
                  return
                }
                if (menuVM.onMenuEntry(e)) {
                  menuVM.showMenu = false
                }
              })
              }, (e: MenuEntry): string => e.id)
            }
            .rowsTemplate('1fr 1fr')
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
            .scrollBar(BarState.Off)
            .columnsGap(4)
            .rowsGap(19)
            .width('100%')
            .height(111)
            .padding({ left: 4, right: 4 })
            Row()
              .width('100%')
              .height(29)
          }
          .width('100%')
        }, (page: MenuEntry[], pageIndex: number): string => pageIndex.toString())
      }
      .indicator(true)
      .loop(false)
      .index(menuVM.menuPageIndex)
      .onChange((index: number) => {
        menuVM.menuPageIndex = index
      })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: 18, bottom: QhState.bottomRectHeight - 12 })
  }

  /** 地址胶囊文本：主页态搜索提示，网页态按地址栏内容设置 */
  private pillText(): ResourceStr {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      return $r('app.string.search_hint')
    }
    return addressDisplayText(tab.url, tab.title)
  }

  private pillIcon(): Resource {
    const tab = tabsVM.activeTab
    if (tab !== null && !tab.isHome && tab.url.startsWith('https://')) {
      return $r('sys.symbol.lock')
    }
    return $r('sys.symbol.website')
  }

  /** 地址胶囊底色：色彩模式时按页面色深浅取半透明黑/白 */
  private pillBg(): ResourceColor {
    const tab = tabsVM.activeTab
    if (tab !== null && tab.themeColor !== '') {
      return ActionBarColor.isDarkColor(tab.themeColor) ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.08)'
    }
    return $r('sys.color.comp_background_tertiary')
  }

  navColor(enabled: boolean): ResourceColor {
    return enabled ? ActionBarColor.fg($r('sys.color.font_primary')) : ActionBarColor.fg($r('sys.color.font_tertiary'))
  }

  build() {
    Column() {
      Row() {
        // 返回
        Stack() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([this.navColor(tabsVM.activeTab ? tabsVM.activeTab.canBack : false)])
        }
        .width(40)
        .height('100%')
        .alignContent(Alignment.Center)
        .padding({ top: 4 })
        .onClick(() => {
          browserVM.goBack()
        })

        // 前进
        Stack() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(24)
            .fontColor([this.navColor(tabsVM.activeTab ? tabsVM.activeTab.canForward : false)])
        }
        .width(40)
        .height('100%')
        .alignContent(Alignment.Center)
        .padding({ top: 4 })
        .onClick(() => {
          browserVM.goForward()
        })

        // 主页按钮（可选）
        if (UISettings.show_home_button) {
          Stack() {
            SymbolGlyph($r('sys.symbol.house'))
              .fontSize(23)
              .fontColor([ActionBarColor.fg($r('sys.color.font_primary'))])
          }
          .width(40)
          .height('100%')
          .alignContent(Alignment.Center)
          .padding({ top: 4 })
          .onClick(() => {
            const tab = tabsVM.activeTab
            if (tab !== null) {
              browserVM.closeReader()
              tabsVM.goHome(tab)
            }
          })
        }

        // 地址胶囊：点击进入地址编辑
        Row({ space: 6 }) {
          SymbolGlyph(this.pillIcon())
            .fontSize(13)
            .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'))])
          Text(this.pillText())
            .fontSize(14)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .layoutWeight(1)
        }
        .layoutWeight(1)
        .height(30)
        .margin({ top: 4, left: 8, right: 8 })
        .padding({ left: 12, right: 12 })
        .borderRadius(15)
        .backgroundColor(this.pillBg())
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          browserVM.isEditingAddress = true
        })

        // 下载按钮（可选）
        if (UISettings.show_download_button) {
          Stack() {
            SymbolGlyph($r('sys.symbol.arrow_down_circle'))
              .fontSize(23)
              .fontColor([ActionBarColor.fg($r('sys.color.font_primary'))])
          }
          .width(40)
          .height('100%')
          .alignContent(Alignment.Center)
          .padding({ top: 4 })
          .onClick(() => {
            QhState.pushPage('downloads', null)
          })
        }

        // 标签管理：方框 + 中间数字（启用标签栏时常驻标签栏承担切换，不再显示）；
        // 外层占位 40 宽与左侧按钮一致，保证搜索框左右对称
        if (!UISettings.show_tab_bar) {
          Stack() {
            Stack() {
              Text(`${tabsVM.tabCount}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(ActionBarColor.fg($r('sys.color.font_primary')))
                .maxLines(1)
            }
            .width(19)
            .height(19)
            .alignContent(Alignment.Center)
            .border({
              width: 1.5,
              color: ActionBarColor.fg($r('sys.color.font_primary')),
              radius: 4
            })
          }
          .width(40)
          .height('100%')
          .alignContent(Alignment.Center)
          .padding({ top: 4 })
          .onClick(() => {
            browserVM.showTabSwitcher = true
          })
        }

        // 菜单
        Stack() {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(23)
            .fontColor([ActionBarColor.fg($r('sys.color.font_primary'))])
        }
        .width(40)
        .height('100%')
        .alignContent(Alignment.Center)
        .padding({ top: 4 })
        .onClick(() => {
          menuVM.buildMenuPages()
          menuVM.showMenu = true
        })
        .bindSheet(menuVM.showMenu!!, this.menuSheetBuilder(), {
          height: 175,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('sys.color.comp_background_primary'),
          onDisappear: () => {
            menuVM.showMenu = false
          }
        })
      }
      .width('100%')
      .height(34)
      .padding({ left: 4, right: 4 })
      .alignItems(VerticalAlign.Center)

      // 进度条
      if (tabsVM.activeTab && tabsVM.activeTab.progress < 100) {
        Progress({ value: tabsVM.activeTab.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(ActionBarColor.fg(QhState.currentThemeColor))
          .backgroundColor(Color.Transparent)
      }
    }
    .width('100%')
    .padding({
      bottom: this.barPosition === 'bottom' ? QhState.bottomRectHeight : 0
    })
    .backgroundColor(ActionBarColor.bg($r('sys.color.comp_background_primary')))
    .bindSheet(menuVM.showSheet!!, this.sheetBuilder(), {
      height: menuVM.sheetKind === 'font' ? 172 : menuVM.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        menuVM.showSheet = false
      }
    })
    .bindSheet(menuVM.showBookmarkEditor!!, this.bookmarkEditorBuilder(), {
      height: 560,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        menuVM.showBookmarkEditor = false
      }
    })
  }
}
