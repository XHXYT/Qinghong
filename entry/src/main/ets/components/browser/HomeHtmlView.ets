import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { QhState, _QhState } from '../../entryability/AppState';
import { TabInfo } from '../../viewmodel/TabsViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { appSettings } from '../../common/entity/SettingsModel';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';
import { SearchToolbarEngines } from '../../common/constants/SearchEngines';
import { ResourceUtils } from '../../common/utils/app/ResourceUtil';
import { homeHtmlRefresh } from '../../common/utils/home/HomeHtmlRefresh';
import { homeBg } from '../../common/utils/home/HomeBg';
import { toastUtil } from '../../common/utils/ui/ToastUtils';
import { createLogger } from '../../common/utils/app/Logger';
import { hitokoto } from '../../common/utils/home/Hitokoto';
import { searchVM, SuggestItem, SuggestType } from '../../viewmodel/SearchViewModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';

const logger = createLogger('HomeHtmlView')

/** 快捷图标下发项 */
class HomeQuickItem {
  title: string = ''
  url: string = ''
  icon: string = ''
}

/** 搜索引擎下拉项 */
class HomeEngineEntry {
  id: string = ''
  name: string = ''
}

/** 下发到 HTML 主页的完整配置 */
class HomeHtmlConfig {
  theme: string = 'system'
  /** 主页背景偏暗（背景图采样/背景主题综合判定）：页面文字取浅色 */
  bgDark: boolean = false
  bgImage: string = ''
  bgOpacity: number = 100
  bgBlur: number = 0
  showSearchArea: boolean = true
  logoMode: string = 'default'
  logoImage: string = ''
  logoText: string = ''
  logoHtml: string = ''
  searchRadius: number = 23
  searchOpacity: number = 100
  searchBorderWidth: number = 0
  searchBorderOpacity: number = 100
  searchStyle: string = 'rect'
  searchEffect: string = 'blur'
  searchBlur: number = 16
  searchOffset: number = 0
  searchHeight: number = 46
  quickWidth: number = 0
  quickHeight: number = 0
  quickRadius: number = 24
  quickIconStyle: string = 'text'
  accent: string = ''
  items: HomeQuickItem[] = []
  engines: HomeEngineEntry[] = []
  engineId: string = ''
  incognito: boolean = false
  incognitoText: string = ''
  hint: string = ''
  appName: string = ''
  customCss: string = ''
}

/** 下发到 HTML 主页的联想条目 */
class HomeSuggestEntry {
  type: string = ''
  text: string = ''
  url: string = ''
}

/** 原生侧 ↔ HTML 主页桥 */
class HomeHtmlBridge {
  /** 联想输入回调（宿主异步拉取联想并 runJavaScript 回推 HTML 渲染） */
  suggestHandler: (text: string) => void = (): void => {
  }
  /** 联想条目点击回调（宿主按索引分发跳转） */
  pickHandler: (index: number) => void = (): void => {
  }

  /** HTML 搜索框输入：请求联想 */
  suggest(text: string): void {
    this.suggestHandler(text)
  }

  /** HTML 联想条目点击：按索引分发 */
  openSuggest(index: number): void {
    this.pickHandler(index)
  }

  openUrl(url: string): void {
    // 走地址栏同款「URL 直达 / 搜索词转引擎」逻辑：搜索词直接 navigate 会被内核
    // 当作主机名做 punycode 编码（http://xn--...），URL 本身不受影响
    browserVM.submitAddress(url)
  }

  /** HTML 主页引擎下拉切换当前搜索引擎 */
  setEngine(id: string): void {
    appSettings.search_engine_id = id
  }

  /** HTML 长按快捷图标：确认移除快捷（保留书签） */
  removeQuick(url: string, title: string): void {
    toastUtil.showAlertDialog({
      title: title,
      message: url,
      buttons: [
        {
          value: $r('app.string.remove_quick'),
          action: (): void => {
            bookmarkVM.setQuick(url, false)
            homeHtmlRefresh.request()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'removeQuickHtml')
  }
}

/** HTML 主页刷新注册表（外部单例无法 @Monitor，用回调驱动重推配置） */

/**
 * 本地 HTML 主页（Logo HTML 模式 / 自定义 CSS 非空时启用）
 */
@ComponentV2
export struct HomeHtmlView {
  @Require @Param tab: TabInfo

  controller: webview.WebviewController = new webview.WebviewController()
  bridge: HomeHtmlBridge = new HomeHtmlBridge()
  private pageReady: boolean = false
  /** HTML 搜索联想快照（点击按索引分发，原生不重复渲染 HTML 侧列表） */
  private suggestList: SuggestItem[] = []
  /** HTML 联想请求序号（本地过期守卫） */
  private suggestSeq: number = 0
  /** document start 预载配置：首帧即按最终样式渲染，省掉 onPageEnd 后 runJavaScript 二次重绘 */
  private docStartScript: string = ''
  private pushFn: () => void = (): void => {
    this.pushConfig()
  }

  aboutToAppear(): void {
    // 桥回调接线：HTML 输入联想 / 联想条目点击分发
    this.bridge.suggestHandler = (text: string): void => {
      this.handleSuggest(text)
    }
    this.bridge.pickHandler = (index: number): void => {
      this.pickSuggest(index)
    }
    // 快照挂载时刻配置，注入到文档开始：页面内联脚本首帧同步渲染最终样式
    this.docStartScript = `window.__QH_CFG__ = ${JSON.stringify(this.buildConfig())};`
    // 书签异步加载完成后再推一次配置，避免首次推送时快捷图标（quickLinks）尚未就绪
    bookmarkVM.loadAll().then((): void => {
      this.ensureFavicons()
      this.pushConfig()
    })
    homeHtmlRefresh.register(this.pushFn)
    try {
      _QhState.window.on('keyboardHeightChange', this.kbListener)
    } catch (error) {
    }
  }

  aboutToDisappear(): void {
    homeHtmlRefresh.unregister(this.pushFn)
    try {
      _QhState.window.off('keyboardHeightChange', this.kbListener)
    } catch (error) {
    }
  }

  /** 键盘高度变化（px→vp）：推给页面按聚焦元素整体上移避让 */
  private kbListener: (px: number) => void = (px: number): void => {
    if (!this.pageReady) {
      return
    }
    const vp: number = QhState.windowWidth > 0 && _QhState.windowWidth_px > 0
      ? px / (_QhState.windowWidth_px / QhState.windowWidth)
      : 0
    try {
      this.controller.runJavaScript(`window.qhKbAvoid && window.qhKbAvoid(${vp})`)
        .catch((): void => {
        })
    } catch (error) {
    }
  }

  /** 联想类型 → HTML 图标名（与 HTML 侧 SG_ICONS 键一致） */
  private suggestTypeName(t: SuggestType): string {
    if (t === SuggestType.BOOKMARK) {
      return 'bookmark'
    }
    if (t === SuggestType.HISTORY) {
      return 'history'
    }
    if (t === SuggestType.TAB) {
      return 'tab'
    }
    if (t === SuggestType.FAVORITES) {
      return 'star'
    }
    if (t === SuggestType.NETWORK_SUGGEST) {
      return 'lightbulb'
    }
    return 'search'
  }

  /** HTML 搜索框输入：纯计算联想（不写共享状态，避免联动原生面板），过期守卫后回推 HTML 渲染 */
  private handleSuggest(text: string): void {
    const seq: number = ++this.suggestSeq
    searchVM.computeSuggestions(text, this.tab.isIncognito).then((list: SuggestItem[]) => {
      // 过期守卫：期间有新输入则丢弃本次结果
      if (seq !== this.suggestSeq) {
        return
      }
      this.suggestList = list.slice(0, 12)
      const entries: HomeSuggestEntry[] = []
      for (const it of this.suggestList) {
        const en: HomeSuggestEntry = new HomeSuggestEntry()
        en.type = this.suggestTypeName(it.type)
        en.text = it.text
        en.url = it.url
        entries.push(en)
      }
      if (!this.pageReady) {
        return
      }
      try {
        this.controller.runJavaScript(`window.renderSuggests(${JSON.stringify(entries)})`)
          .catch((): void => {
          })
      } catch (error) {
      }
    })
  }

  /** HTML 联想条目点击：标签切换 / URL 直达 / 搜索词提交 */
  private pickSuggest(index: number): void {
    if (index < 0 || index >= this.suggestList.length) {
      return
    }
    const item: SuggestItem = this.suggestList[index]
    this.suggestSeq++
    this.suggestList = []
    if (item.type === SuggestType.TAB && item.tabId >= 0) {
      tabsVM.switchTab(item.tabId)
      return
    }
    if (item.url !== '') {
      browserVM.openUrl(item.url)
      return
    }
    browserVM.submitAddress(item.text)
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

  private buildConfig(): HomeHtmlConfig {
    const cfg: HomeHtmlConfig = new HomeHtmlConfig()
    cfg.theme = appSettings.home_bg_theme
    cfg.bgDark = homeBg.dark
    cfg.bgImage = appSettings.home_bg_image
    cfg.bgOpacity = appSettings.home_bg_opacity
    cfg.bgBlur = appSettings.home_bg_blur
    cfg.showSearchArea = appSettings.home_show_search_area
    cfg.logoMode = appSettings.home_logo_mode
    cfg.logoImage = appSettings.home_logo_image
    cfg.logoText = appSettings.home_logo_text
    cfg.logoHtml = appSettings.home_logo_html
    cfg.searchRadius = appSettings.home_search_radius
    cfg.searchOpacity = appSettings.home_search_opacity
    cfg.searchBorderWidth = appSettings.home_search_border_width
    cfg.searchBorderOpacity = appSettings.home_search_border_opacity
    cfg.searchStyle = appSettings.home_search_style
    cfg.searchEffect = appSettings.home_search_effect
    cfg.searchBlur = appSettings.home_search_blur
    cfg.searchOffset = appSettings.home_search_offset
    cfg.searchHeight = appSettings.home_search_height
    cfg.quickWidth = appSettings.home_quick_width
    cfg.quickHeight = appSettings.home_quick_height
    cfg.quickRadius = appSettings.home_quick_radius
    cfg.quickIconStyle = appSettings.home_quick_icon_style
    cfg.accent = ResourceUtils.parseColor(QhState.currentThemeColor)
    for (const e of SearchToolbarEngines.enabledEngines()) {
      const en: HomeEngineEntry = new HomeEngineEntry()
      en.id = e.id
      en.name = e.name
      cfg.engines.push(en)
    }
    cfg.engineId = appSettings.search_engine_id
    for (const b of bookmarkVM.quickLinks) {
      const it: HomeQuickItem = new HomeQuickItem()
      it.title = b.title
      it.url = b.url
      if (appSettings.home_quick_icon_style === 'icon') {
        const host: string = FaviconCache.hostOf(b.url)
        if (faviconCache.has(host)) {
          it.icon = faviconCache.pathOf(host)
        }
      }
      cfg.items.push(it)
    }
    cfg.incognito = this.tab.isIncognito
    cfg.incognitoText = ResourceUtils.getString($r('app.string.incognito_hint'))
    cfg.hint = hitokoto.quote !== '' ? hitokoto.quote : ResourceUtils.getString($r('app.string.search_hint'))
    cfg.appName = ResourceUtils.getString($r('app.string.app_name'))
    cfg.customCss = appSettings.customCssEnabled() ? appSettings.home_custom_css : ''
    return cfg
  }

  private pushConfig(): void {
    if (!this.pageReady) {
      return
    }
    try {
      const json: string = JSON.stringify(this.buildConfig())
      this.controller.runJavaScript(`window.renderHome(${json})`)
        .catch((error: BusinessError): void => {
          logger.error(`renderHome failed: ${error.code} ${error.message}`)
        })
    } catch (error) {
      const err = error as BusinessError
      logger.error(`pushConfig failed: ${err.code} ${err.message}`)
    }
  }

  build() {
    Web({ src: 'resource://rawfile/homepage.html', controller: this.controller })
      .width('100%')
      .height('100%')
      // 键盘悬浮覆盖网页：主页背景与内容不被输入法顶起/压缩
      .keyboardAvoidMode(WebKeyboardAvoidMode.OVERLAYS_CONTENT)
      .javaScriptProxy({
        object: this.bridge,
        name: 'qhBridge',
        methodList: ['openUrl', 'setEngine', 'removeQuick', 'suggest', 'openSuggest'],
        controller: this.controller
      })
      .fileAccess(true)
      .javaScriptOnDocumentStart([{ script: this.docStartScript, scriptRules: ['resource://'] }])
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .onPageEnd(() => {
        this.pageReady = true
        this.pushConfig()
      })
  }
}
