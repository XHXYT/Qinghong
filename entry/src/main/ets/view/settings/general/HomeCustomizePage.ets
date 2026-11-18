import { NaviContainer } from '../../../components/NaviContainer';
import { QhState, _QhState } from '../../../entryability/AppState';
import { appSettings, UISettings, CssTheme } from '../../../common/entity/SettingsModel';
import { TabInfo } from '../../../viewmodel/TabsViewModel';
import { HomepageView, HomeBgLayer } from '../../../components/browser/HomepageView';
import { HomeHtmlView } from '../../../components/browser/HomeHtmlView';
import { HomeImmersive } from '../../../common/utils/home/HomeImmersive';
import { homeBg } from '../../../common/utils/home/HomeBg';
import { homeHtmlRefresh } from '../../../common/utils/home/HomeHtmlRefresh';
import { HomeImageUtil } from '../../../common/utils/home/HomeImageUtil';
import { toastUtil } from '../../../common/utils/ui/ToastUtils';
import { createLogger } from '../../../common/utils/app/Logger';
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
  /** 根栈全屏预览实例（分栏下点全屏按钮推入根栈，进入即全屏、退出即 pop） */
  @Local fullPreviewInstance: boolean = false
  @Local logoText: string = appSettings.home_logo_text
  @Local logoHtml: string = appSettings.home_logo_html
  @Local customCss: string = appSettings.home_custom_css
  /** 当前选中（工作区绑定）的 CSS 主题名，'' = 未选中；点应用时编辑框内容回写该主题 */
  @Local selectedCssTheme: string = ''
  /** 已保存 CSS 主题列表（跟随 appSettings.home_custom_css_themes 变化） */
  @Computed
  get cssThemeList(): CssTheme[] {
    return appSettings.cssThemes()
  }

  /** 预览用假标签（非无痕主页态） */
  private previewTab: TabInfo = new TabInfo(-100)

  private readonly tabs: HomeTabItem[] = [
    new HomeTabItem($r('app.string.home_tab_logo'), TAB_LOGO),
    new HomeTabItem($r('app.string.home_tab_search'), TAB_SEARCH),
    new HomeTabItem($r('app.string.home_tab_background'), TAB_BG),
    new HomeTabItem($r('app.string.home_tab_favorites'), TAB_FAV),
    new HomeTabItem($r('app.string.home_tab_advanced'), TAB_ADV)
  ]

  /** 编辑后通知 HTML 主页刷新（原生主页靠 @Trace 自动刷新），并重估背景明暗（黑/白字依据） */
  private changed(): void {
    homeBg.refresh()
    homeHtmlRefresh.request()
  }

  /** 主页沉浸态（与 Index 判定一致，供全屏预览还原真实主页布局） */
  private homeImmersive(): boolean {
    return HomeImmersive.active()
  }

  /** HTML 主页沉浸：真实主页网页全屏铺底、操作栏浮于其上 */
  private htmlHomeFull(): boolean {
    return this.homeImmersive() && appSettings.isHomeHtmlMode()
  }

  /** 全屏预览内容顶部内缩：HTML 沉浸网页全屏不内缩，其余按实测顶栏总高避让 */
  private previewInsetTop(): number {
    return this.htmlHomeFull() ? 0 : QhState.homeTopBarHeight
  }

  /** 真实主页底栏+小白条合计占位：实测底栏总高（栏在上布局无底栏，补小白条避让） */
  private previewBarBottom(): number {
    const navAvoid: number = UISettings.app_layout === 'top' ? QhState.bottomRectHeight : 0
    return QhState.homeBottomBarHeight + navAvoid
  }

  /** 全屏预览内容底部内缩：HTML 沉浸网页全屏不内缩 */
  private previewInsetBottom(): number {
    return this.htmlHomeFull() ? 0 : this.previewBarBottom()
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

  /** 应用编辑框中的自定义 CSS：绑定主题（显式选中或按旧生效内容自动匹配）后把编辑框内容回写进该主题，再生效 */
  private applyCustomCss(): void {
    if (this.customCss.trim() === '') {
      this.selectedCssTheme = ''
    } else {
      /* 无显式选中（重进页面）时，当前高亮主题来自旧生效内容匹配——自动绑定为工作主题 */
      if (this.selectedCssTheme === '') {
        const old: string = appSettings.home_custom_css
        if (old.trim() !== '') {
          const cur: CssTheme[] = appSettings.cssThemes()
          for (let i = 0; i < cur.length; i++) {
            if (cur[i].css === old) {
              this.selectedCssTheme = cur[i].name
              break
            }
          }
        }
      }
      if (this.selectedCssTheme !== '') {
        const themes: CssTheme[] = appSettings.cssThemes()
        for (let i = 0; i < themes.length; i++) {
          if (themes[i].name === this.selectedCssTheme) {
            if (themes[i].css !== this.customCss) {
              themes[i].css = this.customCss
              appSettings.putCssThemes(themes)
            }
            break
          }
        }
      }
    }
    appSettings.home_custom_css = this.customCss
    this.changed()
  }

  /** 当前选中主题下标：优先按显式选中态（点应用会回写该主题），无选中时按生效内容回退（重进页面恢复高亮），-1 = 无匹配 */
  private activeCssTheme(): number {
    const themes: CssTheme[] = this.cssThemeList
    if (this.selectedCssTheme !== '') {
      for (let i = 0; i < themes.length; i++) {
        if (themes[i].name === this.selectedCssTheme) {
          return i
        }
      }
      return -1
    }
    const cur: string = appSettings.home_custom_css
    if (cur.trim() === '') {
      return -1
    }
    for (let i = 0; i < themes.length; i++) {
      if (themes[i].css === cur) {
        return i
      }
    }
    return -1
  }

  /** 主题自动命名：本地化「主题 %d」（资源读取失败回退英文） */
  private cssThemeName(n: number): string {
    const ctx = this.getUIContext().getHostContext()
    if (ctx) {
      try {
        return ctx.resourceManager.getStringByNameSync('home_css_theme_name', n)
      } catch (error) {
        logger.error(`cssThemeName n=${n} failed: ${JSON.stringify(error)}`)
      }
    }
    return `Theme ${n}`
  }

  /** 保存编辑框当前 CSS 为主题（自动取最小未占用编号，上限 6 套） */
  private saveCssTheme(): void {
    if (this.customCss.trim() === '') {
      toastUtil.showToast({ message: $r('app.string.home_css_theme_empty') })
      return
    }
    const themes: CssTheme[] = appSettings.cssThemes()
    if (themes.length >= 6) {
      toastUtil.showToast({ message: $r('app.string.home_css_theme_full') })
      return
    }
    const used: string[] = []
    for (const t of themes) {
      used.push(t.name)
    }
    let name: string = ''
    for (let n = 1; n <= 6; n++) {
      const candidate: string = this.cssThemeName(n)
      if (!used.includes(candidate)) {
        name = candidate
        break
      }
    }
    if (name === '') {
      name = this.cssThemeName(themes.length + 1)
    }
    themes.push(new CssTheme(name, this.customCss))
    appSettings.putCssThemes(themes)
    this.selectedCssTheme = name
  }

  /** 应用已保存的 CSS 主题：填入编辑框并立即生效，同时设为选中（后续点应用回写该主题） */
  private applyCssTheme(idx: number): void {
    const themes: CssTheme[] = this.cssThemeList
    if (idx < 0 || idx >= themes.length) {
      return
    }
    this.customCss = themes[idx].css
    this.selectedCssTheme = themes[idx].name
    appSettings.home_custom_css = themes[idx].css
    appSettings.home_custom_css_enabled = true
    this.changed()
  }

  /** 删除已保存的 CSS 主题（长按芯片触发，二次确认；按名称定位防错删） */
  private confirmDeleteCssTheme(idx: number): void {
    const themes: CssTheme[] = this.cssThemeList
    if (idx < 0 || idx >= themes.length) {
      return
    }
    const name: string = themes[idx].name
    toastUtil.showAlertDialog({
      title: name,
      message: $r('app.string.home_css_theme_delete_message'),
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            const latest: CssTheme[] = appSettings.cssThemes()
            let target: number = -1
            for (let i = 0; i < latest.length; i++) {
              if (latest[i].name === name) {
                target = i
                break
              }
            }
            if (target >= 0) {
              const deleted: string = latest[target].name
              latest.splice(target, 1)
              appSettings.putCssThemes(latest)
              if (this.selectedCssTheme === deleted) {
                this.selectedCssTheme = ''
              }
            }
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'cssThemeDelete')
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
            this.selectedCssTheme = ''
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
        if (appSettings.home_search_effect === 'blur') {
          this.sliderRow($r('app.string.home_search_blur'),
            (): number => appSettings.home_search_blur, 0, 30, (v: number) => {
              appSettings.home_search_blur = v
              this.changed()
            })
        }
      }

      this.sliderRow($r('app.string.home_search_height'),
        (): number => appSettings.home_search_height, 36, 60, (v: number) => {
          appSettings.home_search_height = v
          this.changed()
        })
      this.sliderRow($r('app.string.home_search_offset'),
        (): number => appSettings.home_search_offset, -200, 200, (v: number) => {
          appSettings.home_search_offset = v
          this.changed()
        })

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

  /** 已保存 CSS 主题芯片组（点击载入并选中、长按删除；选中主题高亮，点应用回写该主题） */
  @Builder
  cssThemeChips() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.cssThemeList, (t: CssTheme, idx: number) => {
        Text(t.name)
          .fontSize(13)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(this.activeCssTheme() === idx
            ? QhState.currentThemeColor
            : $r('sys.color.comp_background_tertiary'))
          .fontColor(this.activeCssTheme() === idx ? Color.White : $r('sys.color.font_primary'))
          .margin({ right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.applyCssTheme(idx)
          })
          .gesture(LongPressGesture()
            .onAction(() => {
              this.confirmDeleteCssTheme(idx)
            }))
      }, (t: CssTheme) => t.name)
      if (this.cssThemeList.length === 0) {
        Text($r('app.string.home_css_theme_none'))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
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
      // CSS 主题：保存编辑框内容为新主题（上限 6 套）并选中；点击芯片载入并选中，点应用回写选中主题
      this.groupHeader($r('app.string.home_css_themes'), false)
      this.tipText($r('app.string.home_css_theme_hint'))
      this.cssThemeChips()
      Button($r('app.string.home_css_theme_save'))
        .fontSize(13)
        .height(34)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .fontColor($r('sys.color.font_primary'))
        .margin({ top: 6 })
        .onClick(() => {
          this.saveCssTheme()
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
        // 根栈全屏预览实例：路由参数 'full' 标记，进入即全屏
        if (ctx.pathInfo.param === 'full') {
          this.fullPreviewInstance = true
          this.previewFullscreen = true
        }
      },
      onBackPressed: (): boolean => {
        // 全屏预览时返回先退出全屏
        if (this.previewFullscreen) {
          if (this.fullPreviewInstance) {
            QhState.pageStack.pop(true)
          } else {
            this.previewFullscreen = false
          }
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
          // 原生沉浸全屏预览：背景层铺满整窗（延伸至状态栏与底栏区域，同 Index）
          if (this.previewFullscreen && !appSettings.isHomeHtmlMode() && this.homeImmersive()) {
            HomeBgLayer()
          }
          // 预览内容：全屏时按真实主页内缩避让栏区域（HTML 沉浸网页全屏、不内缩）
          Column() {
            if (appSettings.isHomeHtmlMode()) {
              HomeHtmlView({ tab: this.previewTab })
            } else {
              HomepageView({ tab: this.previewTab, immersive: this.previewFullscreen && this.homeImmersive() })
            }
          }
          .width('100%')
          .height('100%')
          .padding({
            top: this.previewFullscreen ? this.previewInsetTop() : 0,
            bottom: this.previewFullscreen ? this.previewInsetBottom() : 0
          })

          // 全屏预览顶栏占位示意：真实主页该区域被顶栏（标签栏/操作栏/地址栏）遮挡
          if (this.previewFullscreen && QhState.homeTopBarHeight > 0) {
            Column()
              .width('100%')
              .height(QhState.homeTopBarHeight)
              .backgroundColor('rgba(0,0,0,0.30)')
              .position({ x: 0, y: 0 })
          }
          // 全屏预览底栏占位示意：真实主页该区域被底栏/小白条遮挡
          if (this.previewFullscreen && this.previewBarBottom() > 0) {
            Column()
              .width('100%')
              .height(this.previewBarBottom())
              .backgroundColor('rgba(0,0,0,0.30)')
              .position({ x: 0, y: '100%' })
              .markAnchor({ y: '100%' })
          }

          // 拦截触摸，预览不可交互
          Column()
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.Block)
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_color_accent'))
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
            // 根栈全屏预览实例：按钮即退出（pop 根栈回编辑现场）
            if (this.fullPreviewInstance) {
              QhState.pageStack.pop(true)
              return
            }
            // 分栏（设置页在子栈）：推全屏预览实例到根栈，覆盖整个窗口（含设置页标题栏）
            if (QhState.widthBp > 1) {
              QhState.pageStack.pushPathByName('settings_custom', 'full', true)
              return
            }
            // 单栏：本地切换全屏预览
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
