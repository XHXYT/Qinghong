import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { MenuEntry } from '../../common/constants/MenuEntries';
import { SheetPicker } from '../SheetPicker';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { sniffVM } from '../../viewmodel/SniffViewModel';
import { ResourceSniffPanel } from './ResourceSniffPanel';
import { BookmarkEditor } from './BookmarkEditor';
import { ActionBarColor } from '../../common/utils/ActionBarColor';
import { HomeImmersive } from '../../common/utils/HomeImmersive';
import { toolbarEventRunner } from '../../common/utils/ToolbarEventRunner';

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

  /** 工具栏半模态内容：选择器、字号滑杆或保存网页（menuVM.sheetKind 决定） */
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
    } else if (menuVM.sheetKind === 'save') {
      this.saveSheetContent()
    } else {
      SheetPicker({
        config: menuVM.picker,
        close: (): void => {
          menuVM.showSheet = false
        }
      })
    }
  }

  /** 保存网页弹窗：名称输入 + 保存为PDF 勾选 + 操作按钮（标题与 SheetPicker 同款居中样式） */
  @Builder
  saveSheetContent() {
    Column() {
      Text($r('app.string.save_dialog_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .height(48)
      Column({ space: 12 }) {
        TextInput({ text: menuVM.saveName })
          .fontSize(15)
          .height(44)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onChange((v: string) => {
            menuVM.saveName = v
          })
        Row({ space: 8 }) {
          Checkbox()
            .select(menuVM.saveAsPdf)
            .selectedColor(QhState.currentThemeColor)
            .onChange((v: boolean) => {
              menuVM.saveAsPdf = v
            })
          Text($r('app.string.save_as_pdf'))
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
        }
        .width('100%')
        Row({ space: 12 }) {
          Button($r('app.string.cancel'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              menuVM.showSheet = false
            })
          Button($r('app.string.save'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(QhState.currentThemeColor)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              menuVM.confirmSave()
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 20 })
    }
    .width('100%')
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
      .gesture(LongPressGesture().onAction((): void => {
        toolbarEventRunner.run('back_long')
      }))

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
      .gesture(LongPressGesture().onAction((): void => {
        toolbarEventRunner.run('forward_long')
      }))

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
      .gesture(LongPressGesture().onAction((): void => {
        toolbarEventRunner.run('home_long')
      }))

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
        // 打开标签管理前截取当前标签窗口快照（卡片缩略图）
        tabsVM.captureActiveSnapshot()
        browserVM.showTabSwitcher = true
      })
      .gesture(LongPressGesture().onAction((): void => {
        toolbarEventRunner.run('tabs_long')
      }))

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
      .gesture(LongPressGesture().onAction((): void => {
        toolbarEventRunner.run('menu_long')
      }))
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
    // 工具栏左滑/右滑事件（onTouch 检测，见 handleToolbarTouch）；拖动整行跟手位移
    .translate({ x: this.swipeOffsetX })
    .onTouch((event: TouchEvent): void => {
      this.handleToolbarTouch(event)
    })
    .backgroundColor(HomeImmersive.active() ? Color.Transparent
      : ActionBarColor.bg($r('sys.color.comp_background_primary')))
    .bindSheet(menuVM.showSheet!!, this.sheetBuilder(), {
      height: menuVM.sheetKind === 'font' ? 172 : (menuVM.sheetKind === 'save' ? 252 : menuVM.pickerHeight),
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
    // 主页沉浸时背景透明，透出全屏主页背景层
    .backgroundColor(HomeImmersive.active() ? Color.Transparent
      : ActionBarColor.bg($r('sys.color.comp_background_primary')))
    .bindSheet(menuVM.showBookmarkEditor!!, this.bookmarkEditorBuilder(), {
      height: 560,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        menuVM.showBookmarkEditor = false
      }
    })
    .bindSheet(sniffVM.showPanel!!, this.sniffPanelBuilder(), {
      height: 560,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        sniffVM.showPanel = false
      }
    })
  }

  /** 资源嗅探半模态面板 */
  @Builder
  sniffPanelBuilder() {
    ResourceSniffPanel()
  }

  navColor(enabled: boolean): ResourceColor {
    return enabled ? ActionBarColor.fg($r('sys.color.font_primary')) : ActionBarColor.fg($r('sys.color.font_tertiary'))
  }

  /** 横滑起点（工具栏左滑/右滑事件，onTouch 检测） */
  private swipeDownX: number = 0
  private swipeDownY: number = 0
  private swipeTracking: boolean = false
  /** 拖动中工具栏整行实时位移（抬指回弹动画归零） */
  @Local swipeOffsetX: number = 0

  /**
   * 工具栏横滑检测：onTouch 直收触摸流（沿 hit-test 链必达，不受手势仲裁影响）；
   * 拖动中整行跟手位移（±80vp 封顶），抬指横向主导且 ≥25vp 时触发左滑/右滑事件并回弹
   */
  handleToolbarTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (event.touches.length !== 1) {
        this.swipeTracking = false
        return
      }
      const t: TouchObject = event.changedTouches[0]
      this.swipeDownX = t.x
      this.swipeDownY = t.y
      this.swipeTracking = true
      this.swipeOffsetX = 0
    } else if (event.type === TouchType.Move && this.swipeTracking) {
      if (event.touches.length !== 1) {
        return
      }
      const t: TouchObject = event.changedTouches[0]
      const dx: number = t.x - this.swipeDownX
      this.swipeOffsetX = Math.max(-80, Math.min(80, dx))
    } else if (event.type === TouchType.Up && this.swipeTracking) {
      this.swipeTracking = false
      const t: TouchObject = event.changedTouches[0]
      const dx: number = t.x - this.swipeDownX
      const dy: number = t.y - this.swipeDownY
      this.reboundSwipe()
      if (Math.abs(dx) >= 25 && Math.abs(dx) > Math.abs(dy)) {
        toolbarEventRunner.run(dx < 0 ? 'swipe_left' : 'swipe_right')
      }
    } else if (event.type === TouchType.Cancel) {
      this.swipeTracking = false
      this.reboundSwipe()
    }
  }

  /** 抬指回弹：整行位移动画归零 */
  private reboundSwipe(): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
      this.swipeOffsetX = 0
    })
  }

}
