import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { MenuEntry } from '../../common/constants/MenuEntries';
import { SheetPicker } from '../SheetPicker';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { BookmarkEditor } from './BookmarkEditor';
import { ActionBarColor } from '../../common/utils/ActionBarColor';

/**
 * 底部工具栏（纯视图）：返回/前进/主页/标签管理/菜单
 * 菜单状态与交互逻辑收敛在 MenuViewModel（menuVM）
 */
@ComponentV2
export struct BrowserToolbar {

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

  /** 添加书签编辑器：sheet 内局部 Navigation 路由（独立组件挂载，页由系统路由表解析） */
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
          .fontColor([ActionBarColor.fg($r('sys.color.font_primary'))])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        const tab = tabsVM.activeTab
        if (tab) {
          browserVM.closeReader()
          tabsVM.goHome(tab)
        }
      })

      // 标签管理：方框 + 中间数字
      Row() {
        Stack() {
          Text(`${tabsVM.tabCount}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .maxLines(1)
        }
        .width(21)
        .height(21)
        .alignContent(Alignment.Center)
        .border({
          width: 1.5,
          color: ActionBarColor.fg($r('sys.color.font_primary')),
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
          .fontColor([ActionBarColor.fg($r('sys.color.font_primary'))])
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
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
    .height(52)
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
    }
    .width('100%')
    .padding({
      bottom: QhState.bottomRectHeight
    })
    .backgroundColor(ActionBarColor.bg($r('sys.color.comp_background_primary')))
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

  navColor(enabled: boolean): ResourceColor {
    return enabled ? ActionBarColor.fg($r('sys.color.font_primary')) : ActionBarColor.fg($r('sys.color.font_tertiary'))
  }

}
