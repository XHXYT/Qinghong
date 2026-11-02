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
import { homeBg } from '../../common/utils/HomeBg';

/** 联想面板可见高度上限（6 行 × 46 行高）：超出部分面板内滚动，不为长列表把搜索框顶飞 */
const SUGGEST_CAP_HEIGHT = 276

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
  /** 搜索框聚焦中 */
  @Local searchFocused: boolean = false
  /** 键盘高度（vp，0=收起） */
  @Local kbHeight: number = 0
  /** 搜索框底边窗口坐标（vp，onAreaChange 持续刷新） */
  @Local searchBoxBottom: number = 0
  /** 根布局顶边窗口坐标（vp，联想面板相对根定位用） */
  @Local rootTop: number = 0
  /** 键盘避让上移量（vp，0=未避让；translate 平移内容，不依赖滚动溢出） */
  @Local avoidLift: number = 0
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

  /** 搜索框高度（vp，0=默认 46） */
  private searchH(): number {
    return appSettings.home_search_height > 0 ? appSettings.home_search_height : 46
  }

  /** Logo 顶部间距（56 + 搜索区域垂直偏移，下限 0） */
  private logoTop(): number {
    return Math.max(0, 56 + appSettings.home_search_offset)
  }

  /** 输入法避让：键盘盖住搜索框/联想面板时内容整体上移让位（与 HTML 主页 qhKbAvoid 同逻辑）。
      translate 平移实现：主页内容通常不足一屏，滚动 scrollTo 拉不动；平移是纯视觉位移，
      搜索框布局坐标（searchBoxBottom）不变，面板定位/限高按 avoidLift 补偿 */
  private kbAvoid(): void {
    let lift: number = 0
    if (this.searchFocused && this.kbHeight > 0) {
      const kbTop: number = QhState.windowHeight - this.kbHeight
      // 输入框保底：高于键盘 24
      lift = this.searchBoxBottom + 24 - kbTop
      // 面板展开：按面板期望高度（联想行数 × 46 行高，120 ~ 面板可见上限 276 夹紧）再抬升整页；
      // 上限与 suggestMaxHeight 一致——超过 6 行面板内部滚动，不再为长列表把整页顶飞
      if (searchVM.suggestions.length > 0 && appSettings.home_show_search_area) {
        const want: number = Math.min(Math.max(searchVM.suggestions.length * 46, 120), SUGGEST_CAP_HEIGHT)
        const panelLift: number = this.searchBoxBottom + 6 + want - (kbTop - 12)
        if (panelLift > lift) {
          lift = panelLift
        }
      }
      // 硬上限：搜索框顶边（底边 - 框高）不越过主页区域顶（rootTop 下 8），即绝不飞进顶部操作栏；
      // 面板放不下时由 suggestMaxHeight 限高收缩兜底，宁短不飞
      const maxLift: number = this.searchBoxBottom - this.searchH() - this.rootTop - 8
      if (lift > maxLift) {
        lift = Math.max(0, maxLift)
      }
      if (lift < 0) {
        lift = 0
      }
    }
    if (lift !== this.avoidLift) {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.Friction }, (): void => {
        this.avoidLift = lift
      })
    }
  }

  /**
   * 联想面板限高：搜索框视觉底边（布局底边 - 避让上移量）与键盘顶边之间的可视空间
   * （键盘收起时取面板可见上限）。最低保一行 46，空间不足时面板收缩滚动，宁短也不压到键盘后面
   */
  private suggestMaxHeight(): number {
    const kbTop: number = this.kbHeight > 0 ? QhState.windowHeight - this.kbHeight : QhState.windowHeight
    const avail: number = kbTop - (this.searchBoxBottom - this.avoidLift) - 18
    return Math.max(46, Math.min(SUGGEST_CAP_HEIGHT, avail))
  }

  /**
   * 联想面板显式高度：行数 × 46 行高，受可见上限与键盘可视空间双重约束。
   * 显式高度消除 wrap 容器内 100% 背景层的高度歧义（面板曾整页全高、行被居中挤到中下部）
   */
  private panelH(): number {
    const contentH: number = Math.max(searchVM.suggestions.length, 1) * 46
    return Math.min(contentH, SUGGEST_CAP_HEIGHT, this.suggestMaxHeight())
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

  /** 主页背景是否偏暗（背景图采样/背景主题综合判定，决定文字黑/白） */
  private bgDark(): boolean {
    return homeBg.dark
  }

  /** 主文字色（暗背景用浅色字，亮背景用深色字） */
  private fgColor(): ResourceColor {
    if (this.bgDark()) {
      return '#E6E6E6'
    }
    return '#1A1A1A'
  }

  /** 次级文字色 */
  private fgSecondary(): ResourceColor {
    if (this.bgDark()) {
      return '#99FFFFFF'
    }
    return '#66000000'
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
        .margin({ top: this.logoTop() })
    } else if (appSettings.home_logo_mode === 'text') {
      Text(appSettings.home_logo_text !== '' ? appSettings.home_logo_text : $r('app.string.app_name'))
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.fgColor())
        .maxLines(1)
        .margin({ top: this.logoTop() })
    } else if (appSettings.home_logo_mode === 'none') {
      Blank().height(this.logoTop())
    } else if (appSettings.home_logo_mode !== 'html') {
      Text($r('app.string.app_name'))
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.fgColor())
        .margin({ top: this.logoTop() })
    } else {
      Blank().height(this.logoTop())
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
        // 占位符显式对齐正文字号（默认 16fp 会显大）
        .placeholderFont({ size: 15 })
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
      .height(this.searchH())
      .onAreaChange((_o: Area, n: Area): void => {
        this.searchBoxBottom = ((n.globalPosition.y ?? 0) as number) + (n.height as number)
        // 布局实测变化后重算避让：系统窗口压缩（KeyboardAvoidMode.RESIZE）等外部避让
        // 会实时改变搜索框位置，用实测坐标自校正，避免系统避让 + translate 二次抬升
        this.kbAvoid()
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
            .backdropBlur(appSettings.home_search_blur > 0 ? appSettings.home_search_blur : 0)
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
      .height(this.searchH())
      .clip(true)
      .onAreaChange((_o: Area, n: Area): void => {
        this.searchBoxBottom = ((n.globalPosition.y ?? 0) as number) + (n.height as number)
        // 布局实测变化后重算避让：系统窗口压缩（KeyboardAvoidMode.RESIZE）等外部避让
        // 会实时改变搜索框位置，用实测坐标自校正，避免系统避让 + translate 二次抬升
        this.kbAvoid()
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
      Scroll() {
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

          // Logo + 搜索框（搜索区域）：Logo 常驻，「显示搜索区域」开关只控制搜索框
          this.logoArea()
          if (appSettings.home_show_search_area) {
            this.searchBox()
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
      // 键盘避让：内容整体上移（translate 平移，与 HTML 主页 qhKbAvoid 同思路；背景层不动）
      .translate({ y: -this.avoidLift })

      // 搜索联想面板：浮于快捷图标上方，键盘弹出时限高避让（见 suggestMaxHeight）；
      // 仅主页搜索框聚焦时显示（共享 suggestions，避免地址栏输入联动弹出本面板）；
      // 背景属性与搜索框逐项同步：模糊半径/底色不透明度/描边宽度/颜色/不透明度/圆角
      if (searchVM.suggestions.length > 0 && this.searchFocused && appSettings.home_show_search_area) {
        SearchSuggestPanel({
          panelMaxHeight: this.suggestMaxHeight(),
          panelHeight: this.panelH(),
          panelBlur: appSettings.home_search_style !== 'line' && appSettings.home_search_effect === 'blur',
          panelBlurRadius: appSettings.home_search_style !== 'line' && appSettings.home_search_effect === 'blur'
            ? appSettings.home_search_blur : 0,
          panelOpacity: appSettings.home_search_opacity,
          panelBorderWidth: appSettings.home_search_style !== 'line' ? appSettings.home_search_border_width : 0,
          panelBorderOpacity: appSettings.home_search_border_opacity,
          panelBorderColor: this.fgSecondary(),
          panelBg: this.bgColor(),
          panelRadius: appSettings.home_search_style === 'line'
            ? 16 : appSettings.home_search_radius,
          onPick: (): void => {
            this.searchText = ''
            this.getUIContext().getFocusController().clearFocus()
          }
        })
          .width('86%')
          // y 按避让上移量补偿：内容 translate 后布局坐标不变，面板视觉上跟随搜索框
          .position({ x: '7%', y: this.searchBoxBottom - this.rootTop - this.avoidLift })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.immersive ? Color.Transparent : this.bgColor())
    .onAreaChange((_o: Area, n: Area): void => {
      this.rootTop = ((n.globalPosition.y ?? 0) as number)
      // 主页区域顶边变化（栏显隐/窗口压缩）后同样自校正避让
      this.kbAvoid()
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
