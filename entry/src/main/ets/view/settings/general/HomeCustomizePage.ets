import { NaviContainer } from '../../../components/NaviContainer';
import { QhState, _QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { TabInfo } from '../../../viewmodel/TabsViewModel';
import { HomepageView } from '../../../components/browser/HomepageView';
import { HomeHtmlView } from '../../../components/browser/HomeHtmlView';
import { homeHtmlRefresh } from '../../../common/utils/HomeHtmlRefresh';
import { HomeImageUtil } from '../../../common/utils/HomeImageUtil';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { createLogger } from '../../../common/utils/Logger';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const logger = createLogger('HomeCustomizePage')

/** 单选项（模式/主题/样式芯片组） */
class HomeOption {
  readonly label: ResourceStr
  readonly value: string

  constructor(label: ResourceStr, value: string) {
    this.label = label
    this.value = value
  }
}

/** 面板分区 tab */
class HomeTabItem {
  readonly label: ResourceStr
  readonly id: number

  constructor(label: ResourceStr, id: number) {
    this.label = label
    this.id = id
  }
}

const TAB_LOGO: number = 0
const TAB_SEARCH: number = 1
const TAB_BG: number = 2
const TAB_FAV: number = 3
const TAB_ADV: number = 4

/**
 * 主页定制页：上方大面积实时预览，底部 tab 栏 + 向上展开的配置面板
 * 编辑即时生效：原生主页由 @Trace 实时重渲染；HTML 主页经 homeHtmlRefresh 重推配置
 * 注意：@Builder 按值传参不响应状态变化，状态一律经 getter 在 Builder 内部读取
 */
@ComponentV2
struct HomeCustomizePage {
  @Local activeTab: number = TAB_LOGO
  @Local panelOpen: boolean = true
  @Local panelExpanded: boolean = false
  @Local previewFullscreen: boolean = false
  @Local logoText: string = appSettings.home_logo_text
  @Local logoHtml: string = appSettings.home_logo_html
  @Local customCss: string = appSettings.home_custom_css

  /** 预览用假标签（非无痕主页态） */
  private previewTab: TabInfo = new TabInfo(-100)

  private readonly tabs: HomeTabItem[] = [
    new HomeTabItem($r('app.string.home_tab_logo'), TAB_LOGO),
    new HomeTabItem($r('app.string.home_tab_search'), TAB_SEARCH),
    new HomeTabItem($r('app.string.home_tab_background'), TAB_BG),
    new HomeTabItem($r('app.string.home_tab_favorites'), TAB_FAV),
    new HomeTabItem($r('app.string.home_tab_advanced'), TAB_ADV)
  ]

  /** 编辑后通知 HTML 主页刷新（原生主页靠 @Trace 自动刷新） */
  private changed(): void {
    homeHtmlRefresh.request()
  }

  /** 点 tab：当前分区收起面板，其余分区切换内容 */
  private pickTab(id: number): void {
    if (this.panelOpen && this.activeTab === id) {
      this.panelOpen = false
    } else {
      this.activeTab = id
      this.panelOpen = true
    }
  }

  private async pickLogoImage(): Promise<void> {
    const uri: string = await HomeImageUtil.pickImage()
    if (uri === '') {
      return
    }
    const dir: string = HomeImageUtil.ensureDir(`${_QhState.Context.filesDir}/home_media`)
    const ok: boolean = await HomeImageUtil.savePicked(uri, `${dir}/logo.png`, 1024, 100)
    if (ok) {
      appSettings.home_logo_image = `${dir}/logo.png`
      this.changed()
    } else {
      logger.error('save logo image failed')
    }
  }

  private async pickBgImage(): Promise<void> {
    const uri: string = await HomeImageUtil.pickImage()
    if (uri === '') {
      return
    }
    const dir: string = HomeImageUtil.ensureDir(`${_QhState.Context.filesDir}/home_media`)
    const ok: boolean = await HomeImageUtil.savePicked(uri, `${dir}/bg.png`, 2560, 100)
    if (ok) {
      appSettings.home_bg_image = `${dir}/bg.png`
      this.changed()
    } else {
      logger.error('save bg image failed')
    }
  }

  /** 选择本地文本文件并读取内容（≤2MB） */
  private pickTextFile(suffixes: string[], onLoaded: (text: string) => void): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const options: picker.DocumentSelectOptions = {
      maxSelectNumber: 1,
      fileSuffixFilters: suffixes
    }
    docPicker.select(options).then((uris: string[]): void => {
      if (uris.length === 0) {
        return
      }
      try {
        const src: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY)
        const stat: fileIo.Stat = fileIo.statSync(src.fd)
        if (stat.size <= 0 || stat.size > 2 * 1024 * 1024) {
          fileIo.closeSync(src)
          return
        }
        const buf: ArrayBuffer = new ArrayBuffer(stat.size)
        fileIo.readSync(src.fd, buf)
        fileIo.closeSync(src)
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
        onLoaded(decoder.decodeToString(new Uint8Array(buf)))
      } catch (e) {
        logger.error(`pickTextFile: ${e}`)
      }
    })
  }

  /** 导入 Logo HTML：本地 .txt/.html/.htm 文件，仅填入编辑框，点应用后生效 */
  private importLogoHtml(): void {
    this.pickTextFile(['.txt', '.html', '.htm'], (text: string): void => {
      this.logoHtml = text
    })
  }

  /** 导入自定义 CSS：本地 .css/.txt 文件，仅填入编辑框，点应用后生效 */
  private importCustomCss(): void {
    this.pickTextFile(['.css', '.txt'], (text: string): void => {
      this.customCss = text
    })
  }

  /** 应用编辑框中的 Logo HTML（写入设置并刷新 HTML 主页） */
  private applyLogoHtml(): void {
    appSettings.home_logo_html = this.logoHtml
    this.changed()
  }

  /** 应用编辑框中的自定义 CSS */
  private applyCustomCss(): void {
    appSettings.home_custom_css = this.customCss
    this.changed()
  }

  private confirmReset(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.home_reset'),
      message: $r('app.string.home_reset_message'),
      buttons: [
        {
          value: $r('app.string.home_reset'),
          fontColor: Color.Red,
          action: (): void => {
            appSettings.resetHomeCustomize()
            this.logoText = appSettings.home_logo_text
            this.logoHtml = appSettings.home_logo_html
            this.customCss = appSettings.home_custom_css
            this.changed()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'homeReset')
  }

  /** 分区标题（静态，面板内不折叠）；首个标题行内嵌面板展开/收起箭头 */
  @Builder
  groupHeader(label: ResourceStr, withArrow: boolean) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      if (withArrow) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_up'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
            .rotate({ angle: this.panelExpanded ? 180 : 0 })
        }
        .width(56)
        .height(32)
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, (): void => {
            this.panelExpanded = !this.panelExpanded
          })
        })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 6 })
  }

  /** 选项芯片组（current 为 getter：在 Builder 内读取才能响应状态变化） */
  @Builder
  chipGroup(options: HomeOption[], current: () => string, onPick: (v: string) => void) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(options, (o: HomeOption) => {
        Text(o.label)
          .fontSize(13)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(current() === o.value
            ? QhState.currentThemeColor
            : $r('sys.color.comp_background_tertiary'))
          .fontColor(current() === o.value ? Color.White : $r('sys.color.font_primary'))
          .margin({ right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            onPick(o.value)
          })
      }, (o: HomeOption) => o.value)
    }
    .width('100%')
  }

  /** 滑条行（value 为 getter：左标签 + 右数值 + 滑条） */
  @Builder
  sliderRow(label: ResourceStr, value: () => number, min: number, max: number,
    onChange: (v: number) => void) {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Text(label)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Text(`${Math.round(value())}`)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      Slider({ value: value(), min: min, max: max })
        .width('100%')
        .onChange((v: number) => {
          onChange(v)
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 6, bottom: 6 })
  }

  /** 开关行（on 为 getter） */
  @Builder
  toggleRow(label: ResourceStr, on: () => boolean, onToggle: (v: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on() })
        .onChange((v: boolean) => {
          onToggle(v)
        })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  /** 图片选择行（hasImage 为 getter：选择/清除按钮） */
  @Builder
  imagePickRow(pick: () => void, clear: () => void, hasImage: () => boolean) {
    Row({ space: 10 }) {
      Button($r('app.string.home_pick_image'))
        .fontSize(13)
        .height(34)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .fontColor($r('sys.color.font_primary'))
        .onClick(() => {
          pick()
        })
      if (hasImage()) {
        Button($r('app.string.home_clear_image'))
          .fontSize(13)
          .height(34)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => {
            clear()
          })
      }
    }
    .width('100%')
    .margin({ top: 6 })
  }

  /** 提示文字 */
  @Builder
  tipText(label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor($r('sys.color.font_secondary'))
      .margin({ top: 8 })
  }

  /** Logo 分区 */
  @Builder
  logoSection() {
    Column() {
      this.groupHeader($r('app.string.home_logo_mode'), true)
      this.chipGroup([
        new HomeOption($r('app.string.home_logo_default'), 'default'),
        new HomeOption($r('app.string.home_logo_image'), 'image'),
        new HomeOption($r('app.string.home_logo_text'), 'text'),
        new HomeOption($r('app.string.home_logo_html'), 'html'),
        new HomeOption($r('app.string.home_logo_none'), 'none')
      ], (): string => appSettings.home_logo_mode, (v: string) => {
        appSettings.home_logo_mode = v
        this.changed()
      })

      if (appSettings.home_logo_mode === 'image') {
        this.imagePickRow((): void => {
          this.pickLogoImage()
        }, (): void => {
          appSettings.home_logo_image = ''
          this.changed()
        }, (): boolean => appSettings.home_logo_image !== '')
      } else if (appSettings.home_logo_mode === 'text') {
        TextInput({ text: this.logoText, placeholder: $r('app.string.home_logo_text_hint') })
          .width('100%')
          .fontSize(14)
          .margin({ top: 10 })
          .onChange((v: string) => {
            this.logoText = v
            appSettings.home_logo_text = v
            this.changed()
          })
      } else if (appSettings.home_logo_mode === 'html') {
        // 提示在前，操作行次之，编辑框占满其余空间
        this.tipText($r('app.string.home_html_tip'))
        Row({ space: 10 }) {
          Button($r('app.string.home_import_file'))
            .fontSize(13)
            .height(34)
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .fontColor($r('sys.color.font_primary'))
            .onClick(() => {
              this.importLogoHtml()
            })
          Button($r('app.string.home_apply'))
            .fontSize(13)
            .height(34)
            .padding({ left: 18, right: 18 })
            .backgroundColor(QhState.currentThemeColor)
            .fontColor(Color.White)
            .onClick(() => {
              this.applyLogoHtml()
            })
        }
        .width('100%')
        .margin({ top: 6 })
        TextArea({ text: this.logoHtml, placeholder: $r('app.string.home_logo_html_hint') })
          .width('100%')
          .constraintSize({ minHeight: 220 })
          .fontSize(13)
          .margin({ top: 6 })
          .onChange((v: string) => {
            this.logoHtml = v
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 搜索框分区 */
  @Builder
  searchSection() {
    Column() {
      this.groupHeader($r('app.string.home_search_style'), true)
      this.chipGroup([
        new HomeOption($r('app.string.home_style_rect'), 'rect'),
        new HomeOption($r('app.string.home_style_line'), 'line')
      ], (): string => appSettings.home_search_style, (v: string) => {
        appSettings.home_search_style = v
        this.changed()
      })

      this.toggleRow($r('app.string.home_show_search_area'),
        (): boolean => appSettings.home_show_search_area, (v: boolean) => {
          appSettings.home_show_search_area = v
          this.changed()
        })

      if (appSettings.home_search_style === 'rect') {
        this.chipGroup([
          new HomeOption($r('app.string.home_effect_normal'), 'normal'),
          new HomeOption($r('app.string.home_effect_transparent'), 'transparent'),
          new HomeOption($r('app.string.home_effect_blur'), 'blur')
        ], (): string => appSettings.home_search_effect, (v: string) => {
          appSettings.home_search_effect = v
          this.changed()
        })
        this.sliderRow($r('app.string.home_search_radius'),
          (): number => appSettings.home_search_radius, 0, 30, (v: number) => {
            appSettings.home_search_radius = v
            this.changed()
          })
        this.sliderRow($r('app.string.home_search_opacity'),
          (): number => appSettings.home_search_opacity, 0, 100, (v: number) => {
            appSettings.home_search_opacity = v
            this.changed()
          })
      }

      this.groupHeader($r('app.string.home_search_border_width'), false)
      this.sliderRow($r('app.string.home_search_border_width'),
        (): number => appSettings.home_search_border_width, 0, 4, (v: number) => {
          appSettings.home_search_border_width = v
          this.changed()
        })
      this.sliderRow($r('app.string.home_search_border_opacity'),
        (): number => appSettings.home_search_border_opacity, 0, 100, (v: number) => {
          appSettings.home_search_border_opacity = v
          this.changed()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 背景分区 */
  @Builder
  bgSection() {
    Column() {
      this.groupHeader($r('app.string.home_bg_theme'), true)
      this.chipGroup([
        new HomeOption($r('app.string.home_theme_system'), 'system'),
        new HomeOption($r('app.string.home_theme_light'), 'light'),
        new HomeOption($r('app.string.home_theme_dark'), 'dark')
      ], (): string => appSettings.home_bg_theme, (v: string) => {
        appSettings.home_bg_theme = v
        this.changed()
      })

      this.groupHeader($r('app.string.home_bg_image'), false)
      this.imagePickRow((): void => {
        this.pickBgImage()
      }, (): void => {
        appSettings.home_bg_image = ''
        this.changed()
      }, (): boolean => appSettings.home_bg_image !== '')

      if (appSettings.home_bg_image !== '') {
        this.sliderRow($r('app.string.home_bg_opacity'),
          (): number => appSettings.home_bg_opacity, 0, 100, (v: number) => {
            appSettings.home_bg_opacity = v
            this.changed()
          })
        this.sliderRow($r('app.string.home_bg_blur'),
          (): number => appSettings.home_bg_blur, 0, 40, (v: number) => {
            appSettings.home_bg_blur = v
            this.changed()
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 收藏分区 */
  @Builder
  favoritesSection() {
    Column() {
      this.groupHeader($r('app.string.home_quick_icon_style'), true)
      this.chipGroup([
        new HomeOption($r('app.string.home_icon_text'), 'text'),
        new HomeOption($r('app.string.home_icon_favicon'), 'icon')
      ], (): string => appSettings.home_quick_icon_style, (v: string) => {
        appSettings.home_quick_icon_style = v
        this.changed()
      })

      this.groupHeader($r('app.string.home_group_size'), false)
      this.sliderRow($r('app.string.home_quick_width'),
        (): number => appSettings.home_quick_width, 0, 72, (v: number) => {
          appSettings.home_quick_width = v
          this.changed()
        })
      this.sliderRow($r('app.string.home_quick_height'),
        (): number => appSettings.home_quick_height, 0, 72, (v: number) => {
          appSettings.home_quick_height = v
          this.changed()
        })
      this.sliderRow($r('app.string.home_quick_radius'),
        (): number => appSettings.home_quick_radius, 0, 36, (v: number) => {
          appSettings.home_quick_radius = v
          this.changed()
        })
      this.tipText($r('app.string.home_favorites_tip'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 高级分区 */
  @Builder
  advancedSection() {
    Column() {
      this.groupHeader($r('app.string.home_custom_css'), true)
      // 使用开关：关闭即不注入自定义 CSS（内容保留）
      this.toggleRow($r('app.string.home_use_custom_css'),
        (): boolean => appSettings.home_custom_css_enabled,
        (v: boolean) => {
          appSettings.home_custom_css_enabled = v
          this.changed()
        })
      // 提示在前，操作行次之，编辑框占满其余空间
      this.tipText($r('app.string.home_html_tip'))
      Row({ space: 10 }) {
        Button($r('app.string.home_import_file'))
          .fontSize(13)
          .height(34)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .fontColor($r('sys.color.font_primary'))
          .onClick(() => {
            this.importCustomCss()
          })
        Button($r('app.string.home_apply'))
          .fontSize(13)
          .height(34)
          .padding({ left: 18, right: 18 })
          .backgroundColor(QhState.currentThemeColor)
          .fontColor(Color.White)
          .onClick(() => {
            this.applyCustomCss()
          })
      }
      .width('100%')
      .margin({ top: 6 })
      TextArea({ text: this.customCss, placeholder: $r('app.string.home_custom_css_hint') })
        .width('100%')
        .constraintSize({ minHeight: 200 })
        .fontSize(13)
        .margin({ top: 6 })
        .onChange((v: string) => {
          this.customCss = v
        })

      this.groupHeader($r('app.string.home_reset'), false)
      Button($r('app.string.home_reset'))
        .fontSize(14)
        .height(38)
        .width('100%')
        .margin({ top: 10 })
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .fontColor(Color.Red)
        .onClick(() => {
          this.confirmReset()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 分区内容 */
  @Builder
  sectionContent() {
    if (this.activeTab === TAB_LOGO) {
      this.logoSection()
    } else if (this.activeTab === TAB_SEARCH) {
      this.searchSection()
    } else if (this.activeTab === TAB_BG) {
      this.bgSection()
    } else if (this.activeTab === TAB_FAV) {
      this.favoritesSection()
    } else {
      this.advancedSection()
    }
  }

  build() {
    NaviContainer({
      title: $r('app.string.home_customize_title'),
      // 全屏预览时标题栏一并隐藏，预览覆盖整个页面（含状态栏区域）
      hideTitleBar: this.previewFullscreen,
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onBackPressed: (): boolean => {
        // 全屏预览时返回先退出全屏
        if (this.previewFullscreen) {
          this.previewFullscreen = false
          return true
        }
        // 面板展开时返回先收起面板，预览最大化
        if (this.panelOpen) {
          this.panelOpen = false
          return true
        }
        return false
      }
    })
  }

  @Builder
  pageContent() {
    Column() {
      // 预览区：始终最大化，配置面板作为上层覆盖其上，不挤压预览布局
      Stack({ alignContent: Alignment.Bottom }) {
        Stack() {
          if (appSettings.isHomeHtmlMode()) {
            HomeHtmlView({ tab: this.previewTab })
          } else {
            HomepageView({ tab: this.previewTab })
          }
          // 拦截触摸，预览不可交互
          Column()
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.Block)
        }
        .width('100%')
        .height('100%')
        .borderRadius(this.previewFullscreen ? 0 : 20)
        .clip(true)

        // 向上展开的配置面板：覆盖在预览上层（同主页菜单展开效果），全屏预览时隐藏
        if (this.panelOpen && !this.previewFullscreen) {
          Scroll() {
            Column() {
              this.sectionContent()
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 10, bottom: 12 })
            .constraintSize({ maxWidth: 520 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height(this.panelExpanded ? '100%' : '52%')
          .align(Alignment.Top)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor($r('app.color.start_window_background'))
          .borderRadius({ topLeft: 20, topRight: 20 })
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.12)', offsetY: -4 })
          .transition(TransitionEffect.translate({ y: 420 })
            .animation({ duration: 250, curve: Curve.EaseOut }))
        }

        // 右下角全屏预览按钮：透明行右对齐定位，空白区触摸穿透
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
              .fontSize(20)
              .fontColor([Color.White])
              .rotate({ angle: this.previewFullscreen ? 90 : 0 })
          }
          .width(42)
          .height(42)
          .borderRadius(21)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.previewFullscreen ? QhState.currentThemeColor : 'rgba(0,0,0,0.45)')
          .shadow({ radius: 6, color: 'rgba(0,0,0,0.25)' })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
              this.previewFullscreen = !this.previewFullscreen
            })
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 14, bottom: 14 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .layoutWeight(1)
      .margin(this.previewFullscreen
        ? { left: 0, right: 0, top: 0, bottom: 0 }
        : { left: 16, right: 16, top: 10, bottom: 8 })

      // 分区 tab 栏（固定最底，避让底部安全区），全屏预览时隐藏
      if (!this.previewFullscreen) {
        Row() {
          ForEach(this.tabs, (t: HomeTabItem) => {
            Text(t.label)
              .fontSize(13)
              .fontWeight(this.activeTab === t.id ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.activeTab === t.id
                ? QhState.currentThemeColor
                : $r('sys.color.font_secondary'))
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(14)
              .backgroundColor(this.activeTab === t.id
                ? $r('sys.color.comp_background_tertiary')
                : Color.Transparent)
              .onClick(() => {
                this.pickTab(t.id)
              })
          }, (t: HomeTabItem) => t.id.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 + QhState.bottomRectHeight })
        .justifyContent(FlexAlign.Start)
        .backgroundColor($r('app.color.start_window_background'))
        .borderRadius({ topLeft: 20, topRight: 20 })
        .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetY: -2 })
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Builder
export function SettingsCustomBuilder() {
  HomeCustomizePage()
}
