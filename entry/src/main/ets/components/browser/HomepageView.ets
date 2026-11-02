import { fileIo } from '@kit.CoreFileKit';
import { QhState, _QhState } from '../../entryability/AppState';
import { TabInfo } from '../../viewmodel/TabsViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { appSettings } from '../../common/entity/SettingsModel';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';
import BookmarkInfo from '../../common/entity/BookmarkInfo';
import { HomepageQuickColumns, gridColumnsTemplate } from '../../common/utils/breakpoint/BreakPoint';
import { toastUtil } from '../../common/utils/ToastUtils';
import { hitokoto } from '../../common/utils/Hitokoto';
import { searchVM } from '../../viewmodel/SearchViewModel';
import { SearchSuggestPanel } from './SearchSuggestPanel';

/**
 * 主页：Logo + 搜索框 + 快捷图标（支持定制：Logo 模式 / 搜索框样式 / 背景 / 收藏块）
 */
@ComponentV2
export struct HomepageView {
  @Require @Param tab: TabInfo
  /** 沉浸模式：主页背景由 Index 全屏背景层绘制（延伸至状态栏与底部栏），本组件不再自绘背景 */
  @Param immersive: boolean = false
  /** 搜索框内联输入内容 */
  @Local searchText: string = ''
  /** 主页滚动控制器：输入法避让用 */
  scroller: Scroller = new Scroller()
  /** 搜索框聚焦中 */
  @Local searchFocused: boolean = false
  /** 键盘高度（vp，0=收起） */
  @Local kbHeight: number = 0
  /** 搜索框底边窗口坐标（vp，onAreaChange 持续刷新） */
  @Local searchBoxBottom: number = 0
  /** 根布局顶边窗口坐标（vp，联想面板相对根定位用） */
  @Local rootTop: number = 0
  /** 避让前滚动偏移（键盘收起还原） */
  private savedOffset: number = 0
  private avoidSaved: boolean = false
  private kbListener: (px: number) => void = (px: number): void => {
    this.kbHeight = QhState.windowWidth > 0 && _QhState.windowWidth_px > 0
      ? px / (_QhState.windowWidth_px / QhState.windowWidth)
      : 0
    this.kbAvoid()
  }

  aboutToAppear(): void {
    bookmarkVM.loadAll()
    this.ensureFavicons()
    try {
      _QhState.window.on('keyboardHeightChange', this.kbListener)
    } catch (error) {
    }
  }

  aboutToDisappear(): void {
    try {
      _QhState.window.off('keyboardHeightChange', this.kbListener)
    } catch (error) {
    }
  }

  /** 输入法避让：键盘盖住搜索框时内容整体上滚让位；联想面板展开时按面板期望高度补一次
      上滚（与 HTML 主页 qhKbAvoid 同逻辑）；原始坐标底边 = 实时底边 + 当前已上滚量，
      滚动是真实布局位移，实时值随上滚变小，须加回还原，避免重复调用误判已避开 */
  private kbAvoid(): void {
    if (!this.searchFocused || this.kbHeight <= 0) {
      this.restoreScroll()
      return
    }
    const kbTop: number = QhState.windowHeight - this.kbHeight
    const cur: number = this.scroller.currentOffset().yOffset
    const lifted: number = this.avoidSaved ? Math.max(0, cur - this.savedOffset) : 0
    const boxBottom: number = this.searchBoxBottom + lifted
    // 输入框保底：高于键盘 24
    let lift: number = boxBottom + 24 - kbTop
    // 面板展开：按面板期望高度（联想行数 × 46 行高，120~420 夹紧）再抬升整页
    if (searchVM.suggestions.length > 0 && appSettings.home_show_search_area) {
      const want: number = Math.min(Math.max(searchVM.suggestions.length * 46, 120), 420)
      const panelLift: number = boxBottom + 6 + want - (kbTop - 12)
      if (panelLift > lift) {
        lift = panelLift
      }
    }
    // 别把搜索框抬出屏幕顶（留 96），抬不够时由面板限高收缩兜底
    const maxLift: number = boxBottom - 96
    if (lift > maxLift) {
      lift = Math.max(0, maxLift)
    }
    if (lift < 0) {
      lift = 0
    }
    if (lift > 0) {
      if (!this.avoidSaved) {
        this.avoidSaved = true
        this.savedOffset = cur
      }
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: this.savedOffset + lift,
        animation: { duration: 200, curve: Curve.Friction }
      })
    } else {
      this.restoreScroll()
    }
  }

  /** 还原避让前滚动位置（键盘收起 / 失焦 / 无需避让时） */
  private restoreScroll(): void {
    if (this.avoidSaved) {
      this.avoidSaved = false
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: this.savedOffset,
        animation: { duration: 200, curve: Curve.Friction }
      })
    }
  }

  /**
   * 联想面板限高：搜索框底边与输入法键盘顶边之间的可视空间（键盘收起时上限 420）。
   * 最低保一行 46，空间不足时面板收缩滚动，宁短也不压到键盘后面
   */
  private suggestMaxHeight(): number {
    const kbTop: number = this.kbHeight > 0 ? QhState.windowHeight - this.kbHeight : QhState.windowHeight
    const avail: number = kbTop - this.searchBoxBottom - 18
    return Math.max(46, Math.min(420, avail))
  }

  /** 图标优先模式：为快捷图标懒加载 favicon */
  private ensureFavicons(): void {
    if (appSettings.home_quick_icon_style !== 'icon') {
      return
    }
    for (const b of bookmarkVM.quickLinks) {
      faviconCache.fetchAsync(b.url)
    }
  }

  /** 背景主题是否强制暗色 */
  private forcedDark(): boolean {
    return appSettings.home_bg_theme === 'dark'
  }

  /** 背景主题是否强制亮色 */
  private forcedLight(): boolean {
    return appSettings.home_bg_theme === 'light'
  }

  /** 主文字色（强制主题下用固定色，跟随系统时用资源色） */
  private fgColor(): ResourceColor {
    if (this.forcedDark()) {
      return '#E6E6E6'
    }
    if (this.forcedLight()) {
      return '#1A1A1A'
    }
    return $r('sys.color.font_primary')
  }

  /** 次级文字色 */
  private fgSecondary(): ResourceColor {
    if (this.forcedDark()) {
      return '#99FFFFFF'
    }
    if (this.forcedLight()) {
      return '#66000000'
    }
    return $r('sys.color.font_secondary')
  }

  /** 主页底色 */
  private bgColor(): ResourceColor {
    if (this.forcedDark()) {
      return '#121212'
    }
    if (this.forcedLight()) {
      return '#F1F3F5'
    }
    return $r('app.color.background_color_accent')
  }

  /** 收藏块宽度（0=自适应 48） */
  private quickW(): number {
    return appSettings.home_quick_width > 0 ? appSettings.home_quick_width : 48
  }

  /** 收藏块高度（0=自适应 48） */
  private quickH(): number {
    return appSettings.home_quick_height > 0 ? appSettings.home_quick_height : 48
  }

  /** 收藏块头像字号（随块尺寸缩放） */
  private quickFont(): number {
    return Math.max(12, Math.min(28, this.quickH() * 0.42))
  }

  /**
   * 快捷图标长按：移除快捷（保留书签）
   */
  private confirmRemoveQuick(b: BookmarkInfo): void {
    toastUtil.showAlertDialog({
      title: b.title,
      message: b.url,
      buttons: [
        {
          value: $r('app.string.remove_quick'),
          action: (): void => {
            bookmarkVM.setQuick(b.url, false)
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'removeQuick')
  }

  @Builder
  quickAvatar(b: BookmarkInfo) {
    if (appSettings.home_quick_icon_style === 'icon' && faviconCache.has(FaviconCache.hostOf(b.url))) {
      Image(`file://${faviconCache.pathOf(FaviconCache.hostOf(b.url))}`)
        .width(this.quickW())
        .height(this.quickH())
        .borderRadius(appSettings.home_quick_radius)
        .objectFit(ImageFit.Cover)
        .clip(true)
    } else {
      Text(b.title.length > 0 ? b.title.substring(0, 1) : '?')
        .fontSize(this.quickFont())
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(this.quickW())
        .height(this.quickH())
        .textAlign(TextAlign.Center)
        .borderRadius(appSettings.home_quick_radius)
        .backgroundColor(QhState.currentThemeColor)
    }
  }

  @Builder
  quickGridItem(b: BookmarkInfo) {
    GridItem() {
      Column({ space: 6 }) {
        this.quickAvatar(b)
        Text(b.title)
          .fontSize(11)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.fgColor())
          .constraintSize({ maxWidth: '90%' })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 4, bottom: 4 })
    }
    .onClick(() => {
      browserVM.openUrl(b.url)
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.confirmRemoveQuick(b)
        })
    )
  }

  /** Logo 区（default 默认 / image 图片 / text 文字 / none 无；html 模式走 HTML 主页不会进入） */
  @Builder
  logoArea() {
    if (appSettings.home_logo_mode === 'image' && appSettings.home_logo_image !== ''
      && fileIo.accessSync(appSettings.home_logo_image)) {
      Image(`file://${appSettings.home_logo_image}`)
        .width(56)
        .height(56)
        .borderRadius(28)
        .clip(true)
        .objectFit(ImageFit.Cover)
        .margin({ top: 56 })
    } else if (appSettings.home_logo_mode === 'text') {
      Text(appSettings.home_logo_text !== '' ? appSettings.home_logo_text : $r('app.string.app_name'))
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.fgColor())
        .maxLines(1)
        .margin({ top: 56 })
    } else if (appSettings.home_logo_mode === 'none') {
      Blank().height(56)
    } else if (appSettings.home_logo_mode !== 'html') {
      Text($r('app.string.app_name'))
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.fgColor())
        .margin({ top: 56 })
    } else {
      Blank().height(56)
    }
  }

  /** 搜索内容行（放大镜 + 内联输入，回车直达或搜索） */
  @Builder
  searchContent() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor([this.fgSecondary()])
      TextInput({ text: this.searchText, placeholder: hitokoto.quote !== '' ? hitokoto.quote : $r('app.string.search_hint') })
        .layoutWeight(1)
        .height('100%')
        .fontSize(15)
        .fontColor(this.fgColor())
        .placeholderColor(this.fgSecondary())
        .caretColor(this.fgColor())
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .borderRadius(0)
        .enterKeyType(EnterKeyType.Search)
        .onFocus((): void => {
          this.searchFocused = true
          this.kbAvoid()
        })
        .onBlur((): void => {
          this.searchFocused = false
          searchVM.clearSoon()
          this.kbAvoid()
        })
        .onChange((v: string) => {
          this.searchText = v
          // 联想结果落地后补算避让：面板展开时按其期望高度再上滚、清空时回落一档
          searchVM.updateSuggestions(v, this.tab.isIncognito).then((): void => {
            this.kbAvoid()
          })
        })
        .onSubmit(() => {
          browserVM.submitAddress(this.searchText)
          searchVM.clear()
          this.searchText = ''
          this.getUIContext().getFocusController().clearFocus()
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
  }

  /** 搜索框（矩形：圆角/底色不透明度/描边；线条：仅下边框；透明效果=底色不透明度归零） */
  @Builder
  searchBox() {
    if (appSettings.home_search_style === 'line') {
      Stack() {
        // 线条描边层（下边框）
        Column()
          .width('100%')
          .height('100%')
          .border({
            width: { bottom: appSettings.home_search_border_width > 0 ? appSettings.home_search_border_width : 1.5 },
            color: this.fgSecondary()
          })
          .opacity(appSettings.home_search_border_opacity / 100)
        this.searchContent()
      }
      .width('86%')
      .height(46)
      .onAreaChange((_o: Area, n: Area): void => {
        this.searchBoxBottom = ((n.globalPosition.y ?? 0) as number) + (n.height as number)
      })
    } else {
      Stack() {
        // 底色层（透明效果 = 底色不透明度归零；模糊效果 = 毛玻璃底）
        if (appSettings.home_search_effect === 'blur') {
          Column()
            .width('100%')
            .height('100%')
            .borderRadius(appSettings.home_search_radius)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .opacity(appSettings.home_search_opacity / 100)
            .backgroundBlurStyle(BlurStyle.Thin)
        }
        // 描边层
        if (appSettings.home_search_border_width > 0) {
          Column()
            .width('100%')
            .height('100%')
            .borderRadius(appSettings.home_search_radius)
            .border({
              width: appSettings.home_search_border_width,
              color: this.fgSecondary()
            })
            .opacity(appSettings.home_search_border_opacity / 100)
        }
        this.searchContent()
      }
      .width('86%')
      .height(46)
      .clip(true)
      .onAreaChange((_o: Area, n: Area): void => {
        this.searchBoxBottom = ((n.globalPosition.y ?? 0) as number) + (n.height as number)
      })
    }
  }

  build() {
    Stack() {
      // 背景图片层（沉浸模式由 Index 全屏背景层绘制）
      if (!this.immersive && appSettings.home_bg_image !== '' && fileIo.accessSync(appSettings.home_bg_image)) {
        Image(`file://${appSettings.home_bg_image}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(appSettings.home_bg_opacity / 100)
          .blur(appSettings.home_bg_blur > 0 ? appSettings.home_bg_blur : 0)
      }
      Scroll(this.scroller) {
        Column({ space: 28 }) {
          // 无痕提示
          if (this.tab.isIncognito) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.eye_slash'))
                .fontSize(16)
                .fontColor([this.fgSecondary()])
              Text($r('app.string.incognito_hint'))
                .fontSize(12)
                .fontColor(this.fgSecondary())
            }
          }

          // Logo + 搜索框（搜索区域）
          if (appSettings.home_show_search_area) {
            this.logoArea()
            this.searchBox()
          } else {
            Blank().height(72)
          }

          // 快捷图标
          if (bookmarkVM.quickLinks.length > 0) {
            Grid() {
              ForEach(bookmarkVM.quickLinks, (b: BookmarkInfo) => {
                this.quickGridItem(b)
              }, (b: BookmarkInfo) => b.id !== null ? `${b.id}` : b.url)
            }
            .columnsTemplate(gridColumnsTemplate(HomepageQuickColumns(QhState.widthBp)))
            .columnsGap(12)
            .rowsGap(16)
            .width('90%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor(Color.Transparent)

      // 搜索联想面板：浮于快捷图标上方，键盘弹出时限高避让（见 suggestMaxHeight）；
      // 背景风格与搜索框同步：毛玻璃效果同步底色不透明度，其余效果底色与主页背景一致
      if (searchVM.suggestions.length > 0 && appSettings.home_show_search_area) {
        SearchSuggestPanel({
          panelMaxHeight: this.suggestMaxHeight(),
          panelBlur: appSettings.home_search_style !== 'line' && appSettings.home_search_effect === 'blur',
          panelOpacity: appSettings.home_search_opacity,
          panelBg: this.bgColor(),
          panelRadius: appSettings.home_search_style === 'line'
            ? 16 : Math.max(16, appSettings.home_search_radius),
          onPick: (): void => {
            this.searchText = ''
            this.getUIContext().getFocusController().clearFocus()
          }
        })
          .width('86%')
          .position({ x: '7%', y: this.searchBoxBottom - this.rootTop })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.immersive ? Color.Transparent : this.bgColor())
    .onAreaChange((_o: Area, n: Area): void => {
      this.rootTop = ((n.globalPosition.y ?? 0) as number)
    })
  }
}

/**
 * 主页沉浸背景层：背景色 + 背景图，供 Index 全屏铺底（延伸至状态栏与底部操作栏/小白条区域）
 */
@ComponentV2
export struct HomeBgLayer {
  /** 主页底色（强制主题逻辑与 HomepageView 一致） */
  private bgColor(): ResourceColor {
    if (appSettings.home_bg_theme === 'dark') {
      return '#121212'
    }
    if (appSettings.home_bg_theme === 'light') {
      return '#F1F3F5'
    }
    return $r('app.color.background_color_accent')
  }

  build() {
    Stack() {
      if (appSettings.home_bg_image !== '' && fileIo.accessSync(appSettings.home_bg_image)) {
        Image(`file://${appSettings.home_bg_image}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(appSettings.home_bg_opacity / 100)
          .blur(appSettings.home_bg_blur > 0 ? appSettings.home_bg_blur : 0)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor())
  }
}
