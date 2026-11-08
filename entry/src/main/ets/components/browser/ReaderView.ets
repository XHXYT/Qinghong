import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { ReaderArticle } from '../../viewmodel/BrowserViewModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { readAloudVM } from '../../viewmodel/ReadAloudViewModel';
import { appSettings } from '../../common/entity/SettingsModel';
import { ReaderScripts } from '../../common/utils/scripts/ReaderScripts';
import { QhState } from '../../entryability/AppState';
import { CustomListItem } from '../CusItemBuilder';
import { CustomItemInfo, ItemActionType } from '../../common/entity/CusItemInfo';

/**
 * 阅读模式背景色预设（与设置页共用色值）
 */
class ReaderBgPreset {
  readonly key: string
  label: ResourceStr
  readonly hex: string

  constructor(key: string, label: ResourceStr, hex: string) {
    this.key = key
    this.label = label
    this.hex = hex
  }
}

const BG_PRESETS: ReaderBgPreset[] = [
  new ReaderBgPreset('paper', $r('app.string.read_mode_bg_paper'), '#F6F1E7'),
  new ReaderBgPreset('green', $r('app.string.read_mode_bg_green'), '#C7EDCC'),
  new ReaderBgPreset('white', $r('app.string.read_mode_bg_white'), '#FFFFFF'),
  new ReaderBgPreset('black', $r('app.string.read_mode_bg_black'), '#1C1C1C')
]

/**
 * 阅读页滚动桥：JS scroll 监听经 javaScriptProxy 回传滚动方向（1 下滚 / -1 上滚）与是否回顶
 */
class ReaderScrollBridge {
  private readonly handler: (dir: number, atTop: boolean) => void

  constructor(handler: (dir: number, atTop: boolean) => void) {
    this.handler = handler
  }

  onScroll(dir: number, atTop: boolean): void {
    this.handler(dir, atTop)
  }
}

/**
 * 阅读模式覆盖层：Readability 提取结果以独立模板渲染（loadData + CSP 禁脚本）；
 * 顶栏退出/排版（字号/背景色/衬线，即时改 CSS 变量），正文链接转回浏览器标签打开
 */
@ComponentV2
export struct ReaderView {
  @Require @Param article: ReaderArticle
  @Param onClose: () => void = (): void => {
  }
  private controller: webview.WebviewController = new webview.WebviewController()
  @Local showAa: boolean = false
  private loadRetried: boolean = false
  @Local serifItem: CustomItemInfo = new CustomItemInfo({ id: 'reader_serif', type: ItemActionType.TOGGLE })
  @Local routeItem: CustomItemInfo =
    new CustomItemInfo({ id: 'reader_settings', type: ItemActionType.ROUTER, value: '' })
  /** 顶栏随滚动显隐 */
  @Local barVisible: boolean = true
  private scrollBridge: ReaderScrollBridge = new ReaderScrollBridge(
    (dir: number, atTop: boolean): void => {
      this.onReaderScroll(dir, atTop)
    })

  aboutToAppear(): void {
    this.serifItem = new CustomItemInfo({
      id: 'reader_serif',
      title: $r('app.string.read_mode_serif'),
      type: ItemActionType.TOGGLE,
      value: appSettings.read_mode_serif,
      onChange: (v: string | boolean | number): void => {
        appSettings.read_mode_serif = v as boolean
        this.applyFontFamily()
      }
    })
    this.routeItem = new CustomItemInfo({
      id: 'reader_settings',
      title: $r('app.string.read_mode_settings_entry'),
      type: ItemActionType.ROUTER,
      value: '',
      onChange: (v: string | boolean | number): void => {
        this.showAa = false
        QhState.pushPage('settings_read_mode', null)
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Web({ src: 'about:blank', controller: this.controller, incognitoMode: this.article.isIncognito })
        .onControllerAttached(() => {
          this.loadArticle()
        })
        .javaScriptAccess(true)
        .fileAccess(false)
        .onlineImageAccess(true)
        .darkMode(WebDarkMode.Off)
        .javaScriptProxy({
          object: this.scrollBridge,
          methodList: ['onScroll'],
          name: '__qhReaderBridge',
          controller: this.controller
        })
        .onPageBegin(() => {
          console.info(`[ReaderView] onPageBegin url=${this.tryGetUrl()}`)
        })
        .onPageEnd(() => {
          console.info(`[ReaderView] onPageEnd url=${this.tryGetUrl()}`)
          this.attachScrollHook()
          this.verifyLoadedOnce()
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          console.error(`[ReaderView] onErrorReceive url=${event.request.getRequestUrl()} ` +
            `${event.error.getErrorInfo()}`)
        })
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          return this.interceptLink(event)
        })
        .width('100%')
        .height('100%')

      // 顶栏浮层：背景色延伸至状态栏，行内容压在状态栏下方
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
            .onClick(() => {
              this.onClose()
            })
          Text(this.article.title)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .margin({ left: 12, right: 12 })
          SymbolGlyph($r('sys.symbol.speaker_wave_2'))
            .fontSize(22)
            .fontColor([$r('sys.color.font_primary')])
            .margin({ right: 20 })
            .onClick(() => {
              readAloudVM.startFromTab()
            })
          Text('Aa')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.showAa = true
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 20 })
      }
      .width('100%')
      .height(this.barVisible ? QhState.topRectHeight + 48 : 0)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .justifyContent(FlexAlign.End)
      .clip(true)
      .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(appSettings.readModeBgHex())
    .bindSheet(this.showAa!!, this.aaPanelBuilder(), {
      height: 420,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showAa = false
      }
    })
  }

  /** 加载阅读模板页（baseUrl/historyUrl 传空格以兼容特殊字符） */
  private loadArticle(): void {
    try {
      const html: string = ReaderScripts.buildReaderHtml(this.article)
      this.controller.loadData(html, 'text/html', 'UTF-8', ' ', ' ')
      console.info(`[ReaderView] loadData 已提交 htmlLen=${html.length}`)
    } catch (e) {
      console.error(`[ReaderView] 阅读页加载失败: ${e}`)
    }
  }

  private tryGetUrl(): string {
    try {
      return this.controller.getUrl()
    } catch (e) {
      return '(unavailable)'
    }
  }

  /** 页面加载完成后注入滚动监听（幂等，随 loadData 新文档重新挂载） */
  private attachScrollHook(): void {
    this.controller.runJavaScript(ReaderScripts.readerScrollHookJs())
      .catch((error: BusinessError): void => {
        console.error(`[ReaderView] 滚动监听注入失败: ${error.code} ${error.message}`)
      })
  }

  /** 滚动方向回调：下滚隐藏顶栏，上滚或回顶显示 */
  private onReaderScroll(dir: number, atTop: boolean): void {
    const visible: boolean = dir < 0 || atTop
    if (visible !== this.barVisible) {
      this.barVisible = visible
    }
  }

  /**
   * 加载完成后校验一次正文：loadData 与初始 about:blank 存在竞态，
   * 若页面被空白页覆盖则自愈重载一次（retried 标志防死循环）
   */
  private verifyLoadedOnce(): void {
    this.controller.runJavaScript('JSON.stringify(document.body ? document.body.innerText.length : -1)')
      .then((raw: string) => {
        const text: string = (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"'))
          ? this.jsonDecode(raw) : raw
        const len: number = Number(text)
        console.info(`[ReaderView] 正文长度校验 textLen=${text}`)
        if (len <= 0 && !this.loadRetried) {
          this.loadRetried = true
          console.error('[ReaderView] 阅读页内容为空，自愈重载')
          this.loadArticle()
        }
      })
      .catch((error: BusinessError): void => {
        console.error(`[ReaderView] 正文校验失败: ${error.code} ${error.message}`)
        if (!this.loadRetried) {
          this.loadRetried = true
          this.loadArticle()
        }
      })
  }

  private jsonDecode(raw: string): string {
    try {
      return JSON.parse(raw) as string
    } catch (e) {
      return raw
    }
  }

  /** 阅读页正文链接点击：转回浏览器标签打开并退出阅读模式 */
  private interceptLink(event: OnLoadInterceptEvent): boolean {
    try {
      if (!event.data.isMainFrame()) {
        return false
      }
      const url: string = event.data.getRequestUrl()
      if (url === 'about:blank' || url.startsWith('data:')) {
        return false
      }
      if (url.startsWith('http://') || url.startsWith('https://')) {
        const tab = tabsVM.activeTab
        if (tab !== null) {
          tabsVM.navigate(tab, url)
        }
        this.onClose()
        return true
      }
      return false
    } catch (e) {
      return false
    }
  }

  /** 排版属性即时应用到阅读页（改 CSS 变量，无需重载） */
  private setCssVar(name: string, value: string): void {
    const js: string =
      `document.documentElement.style.setProperty(${JSON.stringify(name)}, ${JSON.stringify(value)})`
    this.controller.runJavaScript(js)
      .catch((error: BusinessError): void => {
        console.error(`[ReaderView] 排版更新失败: ${error.code} ${error.message}`)
      })
  }

  private applyFontSize(): void {
    this.setCssVar('--qh-size', `${appSettings.read_mode_font_size}px`)
  }

  private applyThemeVars(): void {
    const bg: string = appSettings.readModeBgHex()
    const dark: boolean = ReaderScripts.isDarkHex(bg)
    this.setCssVar('--qh-bg', bg)
    this.setCssVar('--qh-text', dark ? '#EAEAEA' : '#3A3A3A')
    this.setCssVar('--qh-link', dark ? '#7FB2FF' : '#1A5FB4')
  }

  private applyFontFamily(): void {
    this.setCssVar('--qh-font', ReaderScripts.fontFamilyOf(appSettings.read_mode_serif))
  }

  @Builder
  aaPanelBuilder() {
    Column({ space: 14 }) {
      // 标题
      Text($r('app.string.read_mode_typography'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ bottom: 14 })

      // 字体大小
      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.read_mode_font_size'))
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Text(`${appSettings.read_mode_font_size}`)
            .fontSize(15)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        Slider({
          value: appSettings.read_mode_font_size,
          min: 12,
          max: 28,
          step: 1,
          style: SliderStyle.OutSet
        })
          .width('100%')
          .selectedColor(QhState.currentThemeColor)
          .blockColor(QhState.currentThemeColor)
          .onChange((v: number): void => {
            appSettings.read_mode_font_size = Math.round(v)
            this.applyFontSize()
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 背景色
      Column({ space: 12 }) {
        Text($r('app.string.read_mode_bg_color'))
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
        Row({ space: 16 }) {
          ForEach(BG_PRESETS, (preset: ReaderBgPreset) => {
            this.bgSwatch(preset)
          }, (preset: ReaderBgPreset) => preset.key)
          this.customSwatch()
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 衬线字体 + 设置路由（通用行组件，行间不另设间距）
      Column() {
        CustomListItem({
          item: this.serifItem,
          itemPadding: { left: 0, right: 0, top: 12, bottom: 12 }
        })
        CustomListItem({
          item: this.routeItem,
          itemPadding: { left: 0, right: 0, top: 12, bottom: 12 }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  bgSwatch(preset: ReaderBgPreset) {
    Column({ space: 6 }) {
      Column()
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(preset.hex)
        .border({
          width: appSettings.read_mode_bg_color === preset.key ? 2 : 1,
          color: appSettings.read_mode_bg_color === preset.key
            ? QhState.currentThemeColor : $r('sys.color.comp_divider')
        })
      Text(preset.label)
        .fontSize(11)
        .fontColor(appSettings.read_mode_bg_color === preset.key
          ? QhState.currentThemeColor : $r('sys.color.font_secondary'))
    }
    .onClick(() => {
      if (appSettings.read_mode_bg_color !== preset.key) {
        appSettings.read_mode_bg_color = preset.key
        this.applyThemeVars()
      }
    })
  }

  @Builder
  customSwatch() {
    Column({ space: 6 }) {
      Column()
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(appSettings.read_mode_custom_bg)
        .border({
          width: appSettings.read_mode_bg_color === 'custom' ? 2 : 1,
          color: appSettings.read_mode_bg_color === 'custom'
            ? QhState.currentThemeColor : $r('sys.color.comp_divider')
        })
      Text($r('app.string.read_mode_bg_custom'))
        .fontSize(11)
        .fontColor(appSettings.read_mode_bg_color === 'custom'
          ? QhState.currentThemeColor : $r('sys.color.font_secondary'))
    }
    .onClick(() => {
      if (appSettings.read_mode_bg_color !== 'custom') {
        appSettings.read_mode_bg_color = 'custom'
        this.applyThemeVars()
      }
    })
  }
}
