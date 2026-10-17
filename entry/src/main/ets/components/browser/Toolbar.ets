import { QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { toastUtil } from '../../common/utils/ToastUtils';
import { UISettings, appSettings } from '../../common/entity/SettingsModel';
import { MenuEntry, MenuEntries } from '../../common/constants/MenuEntries';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../SheetPicker';
import { UaUtils } from '../../common/utils/UaUtils';
import { SettingsUtils } from '../../common/utils/SettingsUtils';
import { ResourceUtils } from '../../common/utils/ResourceUtil';
import { SiteSettingsViewModel, SitePolicy, siteSettingsVM } from '../../viewmodel/SiteSettingsViewModel';

/**
 * 底部工具栏：返回/前进/主页/标签管理/菜单
 */
@ComponentV2
export struct BrowserToolbar {
  @Local showMenu: boolean = false
  @Local picker: PickerConfig = new PickerConfig()
  @Local showPicker: boolean = false
  @Local pickerHeight: number = pickerSheetHeight(3)
  @Local showFontSlider: boolean = false
  @Local fontZoomValue: number = 100
  private menuPages: MenuEntry[][] = []

  aboutToAppear(): void {
    this.buildMenuPages()
  }

  /** 按定制菜单布局构建分页：每页 2 行 × 5 列共 10 项 */
  private buildMenuPages(): void {
    const ids = appSettings.menu_layout !== ''
      ? appSettings.menu_layout.split(',')
      : MenuEntries.DEFAULT_MENU
    const entries: MenuEntry[] = []
    for (const id of ids) {
      const e = MenuEntries.byId(id)
      if (e) {
        entries.push(e)
      }
    }
    const pages: MenuEntry[][] = []
    for (let i = 0; i < entries.length; i += 10) {
      pages.push(entries.slice(i, i + 10))
    }
    this.menuPages = pages
  }

  /** 只能作用于网页的条目（主页/无页面时置灰） */
  private static readonly WEB_ONLY: Set<string> = new Set<string>([
    'share', 'add_bookmark', 'mark_ad', 'translate',
    'view_source', 'fullscreen', 'resource_sniff', 'browser_id', 'network_log',
    'find_in_page', 'save', 'refresh_page', 'site_settings', 'font_size',
    'print_pdf', 'read_aloud', 'add_to_home', 'read_mode', 'open_with',
    'game_mode', 'add_home_favorite', 'report_site'
  ])

  /** 是否为带状态条目（非默认状态时图标高亮） */
  private isToggleEntry(id: string): boolean {
    return id === 'incognito' || id === 'ad_block' || id === 'image_mode'
      || id === 'browser_id' || id === 'screen_orientation' || id === 'font_size'
      || id === 'night_mode' || id === 'desktop_mode' || id === 'read_mode'
  }

  /** 条目当前是否处于高亮状态 */
  private toggleStateOf(id: string): boolean {
    if (id === 'incognito') {
      return appSettings.default_incognito
    }
    if (id === 'ad_block') {
      return appSettings.ad_block_enabled
    }
    if (id === 'image_mode') {
      return this.currentImageMode() !== 'allow'
    }
    if (id === 'browser_id') {
      return appSettings.ua_mode !== 'default'
    }
    if (id === 'screen_orientation') {
      return appSettings.screen_orientation !== 'auto'
    }
    if (id === 'font_size') {
      return this.currentFontZoom() !== 100
    }
    if (id === 'night_mode') {
      return appSettings.force_dark_web
    }
    if (id === 'desktop_mode') {
      return appSettings.desktop_mode
    }
    if (id === 'read_mode') {
      return browserVM.isReaderActive(tabsVM.activeTab ? tabsVM.activeTab.id : -1)
    }
    return false
  }

  /** 条目是否置灰不可用（网页专属功能在主页/非网页上下文置灰） */
  private isEntryDisabled(id: string): boolean {
    if (!BrowserToolbar.WEB_ONLY.has(id)) {
      return false
    }
    const tab = tabsVM.activeTab
    return !tab || tab.isHome
  }

  /** 全局图片显示模式：'allow' 有图 | 'block' 无图 | 'wifi' 仅WiFi有图 */
  private currentImageMode(): string {
    if (appSettings.no_image_mode) {
      return 'block'
    }
    const v: string = SiteSettingsViewModel.getDefault('site_image')
    return v === 'block' || v === 'wifi' ? v : 'allow'
  }

  /** 当前网页字号缩放（%） */
  private currentFontZoom(): number {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return 100
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      return 100
    }
    const p: SitePolicy | null = siteSettingsVM.livePolicyOf(host) ?? siteSettingsVM.cachedPolicy(host)
    if (p !== null) {
      return p.fontZoom
    }
    const n: number = Number(SiteSettingsViewModel.getDefault('site_font_size'))
    return Number.isNaN(n) || n <= 0 ? 100 : Math.round(n)
  }

  /** 弹出半模态单选（复用设置页同款 SheetPicker） */
  private openPickerSheet(title: ResourceStr, options: PickerOption[], selected: string,
    onSelect: (v: string) => void): void {
    this.picker.title = title
    this.picker.options = options
    this.picker.selected = selected
    this.picker.onSelect = onSelect
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showPicker = true
  }

  /** 解析选项显示文案（Resource 或字符串） */
  private labelOfOption(options: PickerOption[], v: string): string {
    for (const o of options) {
      if (o.value === v) {
        return typeof o.label === 'string' ? o.label : ResourceUtils.getString(o.label as Resource)
      }
    }
    return v
  }

  /** 菜单设置变更统一播报：传入菜单项与作用结果（如「电脑模式：已开启」） */
  private announceMenuChange(item: ResourceStr, result: string): void {
    const itemLabel: string = typeof item === 'string' ? item : ResourceUtils.getString(item as Resource)
    toastUtil.showToast({
      message: ResourceUtils.getStringWithArgs($r('app.string.menu_change_toast'), [itemLabel, result])
    })
  }

  /** 开关状态 → 播报文案（已开启/已关闭） */
  private toggleLabel(on: boolean): string {
    return ResourceUtils.getString(on ? $r('app.string.toast_state_on') : $r('app.string.toast_state_off'))
  }

  private openUaPicker(): void {
    const options: PickerOption[] = []
    for (const p of UaUtils.PRESETS) {
      options.push(new PickerOption(p.id, p.nameRes))
    }
    for (const c of appSettings.custom_uas) {
      options.push(new PickerOption(c.id, c.name))
    }
    this.openPickerSheet($r('app.string.browser_id'), options, appSettings.ua_mode, (v: string): void => {
      appSettings.ua_mode = v
      UaUtils.applyToAll()
      // 切换标识后自动刷新当前页，使新 UA 立即生效
      browserVM.refresh()
      this.announceMenuChange($r('app.string.browser_id'), this.labelOfOption(options, v))
    })
  }

  private openOrientationPicker(): void {
    const options: PickerOption[] = [
      new PickerOption('auto', $r('app.string.orientation_auto')),
      new PickerOption('portrait', $r('app.string.orientation_portrait')),
      new PickerOption('landscape', $r('app.string.orientation_landscape'))
    ]
    this.openPickerSheet($r('app.string.screen_orientation'), options,
      appSettings.screen_orientation, (v: string): void => {
        appSettings.screen_orientation = v
        SettingsUtils.applyOrientation()
        this.announceMenuChange($r('app.string.screen_orientation'), this.labelOfOption(options, v))
      })
  }

  private openImageModePicker(): void {
    const options: PickerOption[] = [
      new PickerOption('allow', $r('app.string.site_opt_image_show')),
      new PickerOption('block', $r('app.string.site_opt_image_none')),
      new PickerOption('wifi', $r('app.string.site_opt_image_wifi'))
    ]
    this.openPickerSheet($r('app.string.image_mode'), options,
      this.currentImageMode(), (v: string): void => {
        SiteSettingsViewModel.setDefault('site_image', v)
        appSettings.no_image_mode = v === 'block'
        this.refreshLiveImageModes()
        this.announceMenuChange($r('app.string.image_mode'), this.labelOfOption(options, v))
      })
  }

  /**
   * 阅读模式切换：直接 Readability 提取正文（提取逻辑收敛在 browserVM.enterReader，
   * 与地址栏阅读按钮共用）；已打开时退出
   */
  private toggleReadMode(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return
    }
    if (browserVM.isReaderActive(tab.id)) {
      browserVM.closeReader()
      this.announceMenuChange($r('app.string.read_mode'), this.toggleLabel(false))
      return
    }
    browserVM.enterReader()
  }

  /** 图片模式切换后，把新档位同步到已打开页面正在使用的策略实例（无需刷新页面） */
  private refreshLiveImageModes(): void {
    for (const t of tabsVM.tabs) {
      if (t.isHome) {
        continue
      }
      const host: string = SiteSettingsViewModel.hostOf(t.url)
      if (host === '') {
        continue
      }
      const live: SitePolicy | null = siteSettingsVM.livePolicyOf(host)
      if (live === null) {
        continue
      }
      siteSettingsVM.resolvePolicy(host).then((fresh: SitePolicy): void => {
        live.imageMode = fresh.imageMode
      }).catch(() => {
      })
    }
  }

  private openFontSlider(): void {
    this.fontZoomValue = this.currentFontZoom()
    this.showFontSlider = true
  }

  /** 滑动条实时应用字号到当前网页（改 TabWeb 持有的同一份策略对象，Web 属性自动刷新） */
  private applyFontZoom(v: number): void {
    const zoom: number = Math.round(v / 5) * 5
    if (zoom === this.fontZoomValue) {
      return
    }
    this.fontZoomValue = zoom
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      return
    }
    const p: SitePolicy | null = siteSettingsVM.livePolicyOf(host) ?? siteSettingsVM.cachedPolicy(host)
    if (p !== null) {
      p.fontZoom = zoom
    }
  }

  /** 松手后按站点持久化字号并提示 */
  private persistFontZoom(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      return
    }
    siteSettingsVM.setOverride(host, 'site_font_size', String(this.fontZoomValue)).catch(() => {
    })
    this.announceMenuChange($r('app.string.font_size'), `${this.fontZoomValue}%`)
  }

  /** 菜单条目点击分发；返回 false 表示保持面板打开（开关类） */
  private onMenuEntry(e: MenuEntry): boolean {
    switch (e.id) {
      case 'bookmarks':
        QhState.pushPage('bookmarks', null)
        return true
      case 'history':
        QhState.pushPage('history', null)
        return true
      case 'downloads':
        QhState.pushPage('downloads', null)
        return true
      case 'incognito': {
        // 无痕模式为全局开关：切换「默认无痕浏览」并应用到全部标签
        const target = !appSettings.default_incognito
        appSettings.default_incognito = target
        tabsVM.applyGlobalIncognito(target)
        this.announceMenuChange(e.title, this.toggleLabel(target))
        return false
      }
      case 'add_bookmark':
        this.addBookmark()
        return true
      case 'settings':
        QhState.pushPage('settings', null)
        return true
      case 'find_in_page':
        browserVM.showFindBar = true
        return true
      case 'refresh_page':
        browserVM.refresh()
        return true
      case 'browser_id':
        this.openUaPicker()
        return false
      case 'site_settings':
        QhState.pushPage('settings_site', null)
        return true
      case 'font_size':
        this.openFontSlider()
        return false
      case 'customize_menu':
        QhState.pushPage('settings_menu_custom', null)
        return true
      case 'desktop_mode':
        // 电脑模式开关：UA 改用「电脑模式标识」并刷新当前页使其生效
        appSettings.desktop_mode = !appSettings.desktop_mode
        UaUtils.applyToAll()
        browserVM.refresh()
        this.announceMenuChange(e.title, this.toggleLabel(appSettings.desktop_mode))
        return false
      case 'offline_page':
        QhState.pushPage('offline_page', null)
        return true
      case 'night_mode':
        // 直接切换网页强制深色（TabWeb darkMode/forceDarkAccess 随状态联动），不进设置页
        appSettings.force_dark_web = !appSettings.force_dark_web
        this.announceMenuChange(e.title, this.toggleLabel(appSettings.force_dark_web))
        return false
      case 'read_mode':
        // 阅读模式：Readability 提取正文后独立渲染，再点退出
        this.toggleReadMode()
        return false
      case 'screen_orientation':
        this.openOrientationPicker()
        return false
      case 'ad_block':
        appSettings.ad_block_enabled = !appSettings.ad_block_enabled
        this.announceMenuChange(e.title, this.toggleLabel(appSettings.ad_block_enabled))
        return false
      case 'image_mode':
        this.openImageModePicker()
        return false
      default:
        toastUtil.showToast({ message: $r('app.string.menu_item_wip') })
        return false
    }
  }

  private addBookmark(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) return
    bookmarkVM.addBookmark(tab.title, tab.url)
    toastUtil.showToast({ message: $r('app.string.bookmark_added') })
  }

  /** 条目图标颜色：置灰/高亮/默认 */
  private entryIconColor(id: string): ResourceColor {
    if (this.isEntryDisabled(id)) {
      return $r('sys.color.font_tertiary')
    }
    return this.isToggleEntry(id) && this.toggleStateOf(id)
      ? QhState.currentThemeColor
      : $r('sys.color.font_primary')
  }

  /** 条目标题颜色：置灰/高亮/默认 */
  private entryTitleColor(id: string): ResourceColor {
    if (this.isEntryDisabled(id)) {
      return $r('sys.color.font_tertiary')
    }
    return this.isToggleEntry(id) && this.toggleStateOf(id)
      ? QhState.currentThemeColor
      : $r('sys.color.font_secondary')
  }

  /** 条目标题：图片模式按当前档位动态显示（有图/无图/仅WIFI有图） */
  private entryTitle(e: MenuEntry): ResourceStr {
    if (e.id === 'image_mode') {
      const mode: string = this.currentImageMode()
      if (mode === 'block') {
        return $r('app.string.no_image_mode')
      }
      if (mode === 'wifi') {
        return $r('app.string.site_opt_image_wifi')
      }
    }
    return e.title
  }

  @Builder
  menuEntryItem(e: MenuEntry) {
    Column({ space: 4 }) {
      SymbolGlyph(e.symbol)
        .fontSize(26)
        .fontColor([this.entryIconColor(e.id)])
      Text(this.entryTitle(e))
        .fontSize(11)
        .fontColor(this.entryTitleColor(e.id))
        .maxLines(1)
    }
    .width('100%')
    .height(46)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  fontSliderBuilder() {
    Column() {
      Row() {
        Text($r('app.string.font_size'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(`${this.fontZoomValue}%`)
          .fontSize(16)
          .fontColor(QhState.currentThemeColor)
      }
      .width('100%')
      .height(48)
      Slider({ value: this.fontZoomValue, min: 50, max: 200, step: 5, style: SliderStyle.InSet })
        .selectedColor(QhState.currentThemeColor)
        .width('100%')
        .margin({ top: 8, bottom: 12 })
        .onChange((value: number, mode: SliderChangeMode) => {
          this.applyFontZoom(value)
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.persistFontZoom()
          }
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, bottom: 8 })
  }

  @Builder
  pickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showPicker = false
      }
    })
  }

  @Builder
  menuSheetBuilder() {
    Column() {
      Swiper() {
        ForEach(this.menuPages, (page: MenuEntry[]) => {
          Column() {
            Grid() {
              ForEach(page, (e: MenuEntry) => {
                GridItem() {
                  this.menuEntryItem(e)
                }
              .onClick(() => {
                if (this.isEntryDisabled(e.id)) {
                  return
                }
                if (this.onMenuEntry(e)) {
                  this.showMenu = false
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
          .fontColor([$r('sys.color.font_primary')])
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
        this.buildMenuPages()
        this.showMenu = true
      })
      .bindSheet(this.showMenu!!, this.menuSheetBuilder(), {
        height: 175,
        dragBar: false,
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
    .bindSheet(this.showFontSlider!!, this.fontSliderBuilder(), {
      height: 172,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showFontSlider = false
      }
    })
    }
    .width('100%')
    .padding({
      bottom: UISettings.toolbar_position !== 'top' ? QhState.bottomRectHeight : 0
    })
    .backgroundColor($r('sys.color.comp_background_primary'))
    .bindSheet(this.showPicker!!, this.pickerBuilder(), {
      height: this.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showPicker = false
      }
    })
  }

  navColor(enabled: boolean): ResourceColor {
    return enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')
  }

}


