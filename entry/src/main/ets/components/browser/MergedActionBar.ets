import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { UISettings, appSettings } from '../../common/entity/SettingsModel';
import { MenuEntry } from '../../common/constants/MenuEntries';
import { SheetPicker } from '../SheetPicker';
import { menuVM } from '../../viewmodel/MenuViewModel';
import { sniffVM } from '../../viewmodel/SniffViewModel';
import { ResourceSniffPanel } from './ResourceSniffPanel';
import { BookmarkEditor } from './BookmarkEditor';
import { addressDisplayText, AddressEntryIcon } from './AddressBar';
import { searchVM } from '../../viewmodel/SearchViewModel';
import { SearchSuggestPanel } from './SearchSuggestPanel';
import { ActionBarColor } from '../../common/utils/ActionBarColor';
import { HomeImmersive } from '../../common/utils/HomeImmersive';
import { homeBg } from '../../common/utils/HomeBg';
import { toolbarEventRunner } from '../../common/utils/ToolbarEventRunner';
import { scriptVM } from '../../viewmodel/ScriptViewModel';
import { GmMenuCommand } from '../../common/utils/GmRuntime';
import { ExtToolbarButton } from '../extension/ExtToolbarButton';

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
                .fontColor(ActionBarColor.fg(QhState.currentThemeColor, this.barPosition === 'top'))
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
        ForEach(menuVM.menuPages, (page: MenuEntry[], pageIndex: number) => {
          Column() {
            Grid() {
              ForEach(menuVM.menuPages[pageIndex], (e: MenuEntry, idx: number) => {
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
              .gesture(LongPressGesture().onAction((): void => {
                if (menuVM.onMenuEntryLongPress(e.id)) {
                  menuVM.showMenu = false
                }
              }))
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY
                  .animation({ duration: 180, delay: Math.floor(idx / 5) * 40, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ y: 14 })
                    .animation({ duration: 180, delay: Math.floor(idx / 5) * 40, curve: Curve.EaseOut })),
                TransitionEffect.OPACITY.animation({ duration: 100, curve: Curve.EaseIn })
              ))
              }, (e: MenuEntry): string => e.id)
            }
            .rowsTemplate(menuVM.menuEffectiveRows() === 4 ? '1fr 1fr 1fr 1fr' : '1fr 1fr')
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
            .scrollBar(BarState.Off)
            .columnsGap(4)
            .rowsGap(19)
            .width('100%')
            .height(menuVM.menuEffectiveRows() * 46 + (menuVM.menuEffectiveRows() - 1) * 19)
            .padding({ left: 4, right: 4 })
            Row()
              .width('100%')
              .height(menuVM.menuEffectiveRows() === 4 ? 36 : 29)
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
    .justifyContent(menuVM.menuEffectiveRows() === 4 ? FlexAlign.End : FlexAlign.Start)
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

  /** 地址胶囊底色：色彩模式且位于顶部时按页面色深浅取半透明黑/白；主页沉浸时按主页背景明暗取半透明底 */
  private pillBg(): ResourceColor {
    const tab = tabsVM.activeTab
    if (this.barPosition === 'top' && UISettings.action_bar_color_mode && tab !== null && tab.themeColor !== '') {
      return ActionBarColor.isDarkColor(tab.themeColor) ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.08)'
    }
    if (HomeImmersive.active()) {
      return homeBg.dark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.06)'
    }
    return $r('sys.color.comp_background_tertiary')
  }

  navColor(enabled: boolean): ResourceColor {
    return enabled ? ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top') : ActionBarColor.fg($r('sys.color.font_tertiary'), this.barPosition === 'top')
  }

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
              .fontColor([ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top')])
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

        // 地址胶囊：内联输入，回车直达或搜索；最左图标与地址栏同款（盾牌/搜索，点击=顶弹面板，长按=引擎菜单）
        Row({ space: 6 }) {
          AddressEntryIcon({ iconSize: 14, atTop: this.barPosition === 'top' })
          TextInput({
            text: this.editing ? this.editText : this.pillText(),
            placeholder: $r('app.string.search_hint')
          })
            .fontSize(14)
            // 占位符显式对齐正文字号：不设时按默认 16fp 渲染，获焦切占位符后显大且 30 高胶囊显示不全
            .placeholderFont({ size: 14 })
            .maxLines(1)
            .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top'))
            .placeholderColor(ActionBarColor.fg($r('sys.color.font_secondary'), this.barPosition === 'top'))
            .caretColor(ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top'))
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
              const t = tabsVM.activeTab
              searchVM.updateSuggestions(v, t !== null && t.isIncognito)
            })
            .onBlur(() => {
              this.editing = false
              searchVM.clearSoon()
            })
            .onSubmit(() => {
              browserVM.submitAddress(this.editText)
              searchVM.clear()
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
              .fontColor([ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top')])
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
                .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top'))
                .maxLines(1)
            }
            .width(19)
            .height(19)
            .alignContent(Alignment.Center)
            .border({
              width: 1.5,
              color: ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top'),
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

        // 扩展（拼图按钮：PC 浏览器扩展入口样式，菜单按钮左侧；操作栏设置开关 + 扩展总开关控制）
        if (UISettings.show_extension_button && appSettings.extension_enabled) {
          ExtToolbarButton({ anchor: this.barPosition })
            .margin({ top: 3 })
        }

        // 菜单
        Stack() {
          SymbolGlyph($r('sys.symbol.square_grid_2x2'))
            .fontSize(23)
            .fontColor([ActionBarColor.fg($r('sys.color.font_primary'), this.barPosition === 'top')])
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
          height: menuVM.menuSheetOpenHeight(scriptVM.activeTabMenuCommands().length > 0 ? 240 : 175),
          detents: menuVM.menuSheetDetents(scriptVM.activeTabMenuCommands().length > 0 ? 240 : 175),
          enableOutsideInteractive: false,
          dragBar: false,
          showClose: false,
          backgroundColor: $r('sys.color.comp_background_primary'),
          onHeightDidChange: (height: number): void => {
            const base: number = scriptVM.activeTabMenuCommands().length > 0 ? 240 : 175
            menuVM.onMenuSheetHeightChange(height, base, base + menuVM.menuExpandHeightDelta())
          },
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
          .color(ActionBarColor.fg(QhState.currentThemeColor, this.barPosition === 'top'))
          .backgroundColor(Color.Transparent)
      }

      // 搜索联想面板：顶部合并栏向下展开、底部合并栏向上展开；
      // 仅地址胶囊编辑中显示（共享 suggestions，避免主页搜索框输入联动弹出本面板）
      if (searchVM.suggestions.length > 0 && this.editing) {
        if (this.barPosition === 'top') {
          SearchSuggestPanel({
            onPick: (): void => {
              this.editing = false
              this.editText = ''
              this.getUIContext().getFocusController().clearFocus()
            }
          })
            .position({ x: 0, y: 36 })
        } else {
          SearchSuggestPanel({
            onPick: (): void => {
              this.editing = false
              this.editText = ''
              this.getUIContext().getFocusController().clearFocus()
            }
          })
            .position({ x: 0, y: 0 })
            .markAnchor({ x: 0, y: '100%' })
        }
      }
    }
    .width('100%')
    .padding({
      bottom: this.barPosition === 'bottom' ? QhState.bottomRectHeight : 0
    })
    // 主页沉浸时背景透明，透出全屏主页背景层
    .backgroundColor(HomeImmersive.active() ? Color.Transparent
      : ActionBarColor.bg($r('sys.color.comp_background_primary'), this.barPosition === 'top'))
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
