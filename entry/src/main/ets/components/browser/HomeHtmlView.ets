import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { QhState } from '../../entryability/AppState';
import { TabInfo } from '../../viewmodel/TabsViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { appSettings } from '../../common/entity/SettingsModel';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';
import { SearchToolbarEngines } from '../../common/constants/SearchEngines';
import { ResourceUtils } from '../../common/utils/ResourceUtil';
import { homeHtmlRefresh } from '../../common/utils/HomeHtmlRefresh';
import { toastUtil } from '../../common/utils/ToastUtils';
import { createLogger } from '../../common/utils/Logger';
import { hitokoto } from '../../common/utils/Hitokoto';

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

/** 原生侧 ↔ HTML 主页桥 */
class HomeHtmlBridge {
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
  /** document start 预载配置：首帧即按最终样式渲染，省掉 onPageEnd 后 runJavaScript 二次重绘 */
  private docStartScript: string = ''
  private pushFn: () => void = (): void => {
    this.pushConfig()
  }

  aboutToAppear(): void {
    // 快照挂载时刻配置，注入到文档开始：页面内联脚本首帧同步渲染最终样式
    this.docStartScript = `window.__QH_CFG__ = ${JSON.stringify(this.buildConfig())};`
    // 书签异步加载完成后再推一次配置，避免首次推送时快捷图标（quickLinks）尚未就绪
    bookmarkVM.loadAll().then((): void => {
      this.ensureFavicons()
      this.pushConfig()
    })
    homeHtmlRefresh.register(this.pushFn)
  }

  aboutToDisappear(): void {
    homeHtmlRefresh.unregister(this.pushFn)
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
        methodList: ['openUrl', 'setEngine', 'removeQuick'],
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
