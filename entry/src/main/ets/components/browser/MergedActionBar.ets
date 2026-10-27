import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { UISettings } from '../../common/entity/SettingsModel';
import { MenuEntry } from '../../common/constants/MenuEntries';
import { SheetPicker } from '../SheetPicker';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { sniffVM } from '../../viewmodel/SniffViewModel';
import { ResourceSniffPanel } from './ResourceSniffPanel';
import { BookmarkEditor } from './BookmarkEditor';
import { addressDisplayText } from './AddressBar';
import { ActionBarColor } from '../../common/utils/ActionBarColor';
import { HomeImmersive } from '../../common/utils/HomeImmersive';
import { toolbarEventRunner } from '../../common/utils/ToolbarEventRunner';
import { scriptVM } from '../../viewmodel/ScriptViewModel';
import { GmMenuCommand } from '../../common/utils/GmRuntime';

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

  /** 添加书签编辑器：sheet 内局部 Navigation 路由 */
  @Builder
  bookmarkEditorBuilder() {
    BookmarkEditor()
  }

  @Builder
  menuSheetBuilder() {
    Column() {
      // 用户脚本菜单命令（GM_registerMenuCommand 注册，当前标签页的命令）
      if (scriptVM.activeTabMenuCommands().length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(scriptVM.activeTabMenuCommands(), (c: GmMenuCommand) => {
              Text(c.name)
                .fontSize(13)
                .fontColor(ActionBarColor.fg(QhState.currentThemeColor))
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .borderRadius(16)
                .maxLines(1)
                .constraintSize({ maxWidth: 160 })
                .onClick(() => {
                  menuVM.showMenu = false
                  scriptVM.dispatchMenuCommand(c)
                })
            }, (c: GmMenuCommand): string => `${c.tabId}:${c.scriptId}:${c.menuId}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(38)
        Divider()
          .color($r('sys.color.comp_divider'))
          .margin({ left: 16, right: 16 })
      }
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

  /** 横滑起点（工具栏左滑/右滑事件，onTouch 检测） */
  private swipeDownX: number = 0
  private swipeDownY: number = 0
  private swipeTracking: boolean = false
  /** 拖动中工具栏整行实时位移（抬指回弹动画归零） */
  @Local swipeOffsetX: number = 0
  /** 地址胶囊内联输入（编辑中聚焦完整地址，失焦回退显示文本） */
  @Local editing: boolean = false
  @Local editText: string = ''

  /** 主页态监测：回到主页时重置编辑状态，地址胶囊恢复默认展示 */
  @Computed
  get inHomeMode(): boolean {
    const tab = tabsVM.activeTab
    return tab === null || tab.isHome
  }

  @Monitor('inHomeMode')
  onHomeModeChange(): void {
    this.editing = false
    this.editText = ''
  }

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
        .gesture(LongPressGesture().onAction((): void => {
          toolbarEventRunner.run('back_long')
        }))

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
        .gesture(LongPressGesture().onAction((): void => {
          toolbarEventRunner.run('forward_long')
        }))

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
          .gesture(LongPressGesture().onAction((): void => {
            toolbarEventRunner.run('home_long')
          }))
        }

        // 地址胶囊：内联输入，回车直达或搜索
        Row({ space: 6 }) {
          SymbolGlyph(this.pillIcon())
            .fontSize(13)
            .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'))])
          TextInput({
            text: this.editing ? this.editText : this.pillText(),
            placeholder: $r('app.string.search_hint')
          })
            .fontSize(14)
            .maxLines(1)
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .placeholderColor(ActionBarColor.fg($r('sys.color.font_secondary')))
            .caretColor(ActionBarColor.fg($r('sys.color.font_primary')))
            .layoutWeight(1)
            .height('100%')
            .backgroundColor(Color.Transparent)
            .padding({ left: 0, right: 0 })
            .borderRadius(0)
            .enterKeyType(EnterKeyType.Search)
            .onFocus(() => {
              this.editing = true
              const tab = tabsVM.activeTab
              this.editText = tab !== null && !tab.isHome ? tab.url : ''
            })
            .onChange((v: string) => {
              this.editText = v
            })
            .onBlur(() => {
              this.editing = false
            })
            .onSubmit(() => {
              browserVM.submitAddress(this.editText)
              this.editing = false
              this.editText = ''
              this.getUIContext().getFocusController().clearFocus()
            })
        }
        .layoutWeight(1)
        .height(30)
        .margin({ top: 4, left: 8, right: 8 })
        .padding({ left: 12, right: 12 })
        .borderRadius(15)
        .backgroundColor(this.pillBg())
        .alignItems(VerticalAlign.Center)

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
            // 打开标签管理前截取当前标签窗口快照（卡片缩略图）
            tabsVM.captureActiveSnapshot()
            browserVM.showTabSwitcher = true
          })
          .gesture(LongPressGesture().onAction((): void => {
            toolbarEventRunner.run('tabs_long')
          }))
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
        .gesture(LongPressGesture().onAction((): void => {
          toolbarEventRunner.run('menu_long')
        }))
        .bindSheet(menuVM.showMenu!!, this.menuSheetBuilder(), {
          height: scriptVM.activeTabMenuCommands().length > 0 ? 240 : 175,
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
      // 工具栏左滑/右滑事件（onTouch 检测，见 handleToolbarTouch）；拖动整行跟手位移
      .translate({ x: this.swipeOffsetX })
      .onTouch((event: TouchEvent): void => {
        this.handleToolbarTouch(event)
      })

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
    // 主页沉浸时背景透明，透出全屏主页背景层
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
}
