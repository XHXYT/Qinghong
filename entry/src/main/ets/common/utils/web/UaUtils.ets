import { webview } from '@kit.ArkWeb';
import { appSettings } from '../../entity/SettingsModel';
import { tabsVM } from '../../../viewmodel/TabsViewModel';
import { QhState } from '../../../entryability/AppState';
import { createLogger } from '../app/Logger';

const logger = createLogger('UaUtils');

/**
 * 预置浏览器标识
 */
export class UserAgentPreset {
  readonly id: string
  readonly nameRes: ResourceStr
  readonly ua: string

  constructor(id: string, nameRes: ResourceStr, ua: string) {
    this.id = id
    this.nameRes = nameRes
    this.ua = ua
  }
}

/**
 * 浏览器标识工具：预置列表、解析、简化、应用
 * 应用链路（域名级能力可用时，API 20+）：
 * - 全局 UA → setAppCustomUserAgent（内核应用级）
 * - 站点 UA → setUserAgentForHosts（内核域名级，宿主列表由 provider 异步构建）
 * - 商店桌面 UA → setUserAgentForHosts（onWebAttach 时注册，含 CWS/Edge 商店宿主）
 * - 实例级 setCustomUserAgent 全部退役（导航栈内同步设置会触发内核重入断言 SIGTRAP 崩溃）
 * 能力不可用时自动回退旧路径（实例级逐标签应用）
 */
export class UaUtils {

  /** 系统默认 UA（首次 Web 附加时捕获，须在任何内核级 UA 设置之前，用于还原与简化） */
  static defaultUa: string = ''

  /** 域名级 UA 能力是否可用（首次内核调用失败即置 false，永久回退实例级旧路径） */
  private static hostUaAvailable: boolean = true

  /** 已注册过域名映射的 UA 串（用于清除失效映射：不在最新分组里的旧 UA 重设空列表） */
  private static registeredHostUas: Set<string> = new Set()

  /** Chrome Web Store 站点（移动 UA 会被商店判定为移动端跳转应用下载引导页） */
  static readonly CWS_HOSTS: string[] = ['chromewebstore.google.com', 'chrome.google.com']

  /** Edge Add-ons 站点（需带 Edg 后缀的 UA，否则详情页提示「与你的浏览器不兼容」） */
  static readonly EDGE_STORE_HOSTS: string[] = ['microsoftedge.microsoft.com']

  /** CWS 站点桌面 UA（Windows Chrome，与内核 M114 对齐；实例级应用于商店标签） */
  static readonly STORE_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.5735.196 Safari/537.36'

  /** Edge 商店桌面 UA（Chrome UA + Edg 后缀，模拟桌面 Edge；实例级应用于商店标签） */
  static readonly EDGE_STORE_UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.1823.82 Safari/537.36 Edg/114.0.1823.82'

  /** 域名级 UA 宿主映射构建器（由 SiteSettingsViewModel 注入，避免循环依赖；返回 UA 串 → host 列表） */
  static hostUaMapProvider: (() => Promise<Map<string, string[]>>) | null = null

  static readonly PRESETS: UserAgentPreset[] = [
    new UserAgentPreset('default', $r('app.string.ua_default'),
      'Mozilla/5.0 (Linux; Android 13; V2190A Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/97.0.4692.98 Mobile Safari/537.36 T7/13.34 SearchCraft/3.10.2'),
    new UserAgentPreset('android_phone', $r('app.string.ua_android_phone'),
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'),
    new UserAgentPreset('android_tablet', $r('app.string.ua_android_tablet'),
      'Mozilla/5.0 (Linux; Android 13; SM-T870) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'),
    new UserAgentPreset('windows_chrome', $r('app.string.ua_windows_chrome'),
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'),
    new UserAgentPreset('windows_ie', $r('app.string.ua_windows_ie'),
      'Mozilla/5.0 (Windows NT; WOW64; Trident/7.0; rv:11.0) like Gecko'),
    new UserAgentPreset('macos', $r('app.string.ua_macos'),
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'),
    new UserAgentPreset('iphone', $r('app.string.ua_iphone'),
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'),
    new UserAgentPreset('ipad', $r('app.string.ua_ipad'),
      'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'),
    new UserAgentPreset('symbian', $r('app.string.ua_symbian'),
      'Mozilla/5.0 (SymbianOS/9.4; Series60/5.0 NokiaN97-1/20.0.019; Profile/MIDP-2.1 Configuration/CLDC-1.1) AppleWebKit/525 (KHTML, like Gecko) BrowserNG/7.1.4')
  ]

  /** 预置项显示名（同时查找自定义 UA 名称，找不到回退「自定义」） */
  static presetName(id: string): ResourceStr {
    for (const p of UaUtils.PRESETS) {
      if (p.id === id) {
        return p.nameRes
      }
    }
    for (const c of appSettings.custom_uas) {
      if (c.id === id) {
        return c.name
      }
    }
    return $r('app.string.ua_custom')
  }

  /** 宽屏形态（宽度断点 > 1 或自由窗口）：「默认」档在此形态下自动改用桌面标识 */
  static wideForm(): boolean {
    return QhState.widthBp > 1 || QhState.windowMode
  }

  /** 解析 id → UA 字符串（'' 表示未找到；「默认」档自动跟随设备形态：宽屏用桌面标识，窄屏用移动标识） */
  static resolveUa(id: string): string {
    if (id === 'default' && UaUtils.wideForm()) {
      const wide: string = UaUtils.lookupUa('windows_chrome')
      if (wide !== '') {
        return wide
      }
    }
    return UaUtils.lookupUa(id)
  }

  /** 按预置/自定义列表解析 id → UA 字符串（不做形态特判） */
  private static lookupUa(id: string): string {
    for (const p of UaUtils.PRESETS) {
      if (p.id === id) {
        return p.ua
      }
    }
    for (const c of appSettings.custom_uas) {
      if (c.id === id) {
        return c.ua
      }
    }
    return ''
  }

  /** 简化 UA：移除设备及次要版本信息 */
  static simplify(ua: string): string {
    if (ua === '') {
      return ''
    }
    let r: string = ua
    // 移除设备型号/构建号：(Linux; Android 13; V2190A Build/xxx; wv) → (Linux; Android 13)
    r = r.replace(/(Android\s+\d+)(?:\.\d+)?\s*;[^)]*\)/g, '$1)')
    // 版本号仅保留主版本：131.0.0.0 → 131、537.36 → 537
    r = r.replace(/(\d+)(?:\.\d+)+/g, '$1')
    return r
  }

  /** 当前生效的 UA 字符串（含简化处理；电脑模式开启时改用电脑模式标识） */
  static effectiveUa(): string {
    let ua: string = appSettings.desktop_mode
      ? UaUtils.desktopUa()
      : UaUtils.resolveUa(appSettings.ua_mode)
    if (ua === '') {
      ua = UaUtils.defaultUa
    }
    if (appSettings.ua_simplify && ua !== '') {
      ua = UaUtils.simplify(ua)
    }
    return ua
  }

  /** 电脑模式下的 UA（'custom' 表示跟随主列表选择） */
  static desktopUa(): string {
    if (appSettings.ua_desktop === 'custom') {
      return UaUtils.resolveUa(appSettings.ua_mode)
    }
    return UaUtils.resolveUa(appSettings.ua_desktop)
  }

  /** 站点设置全局默认「电脑模式」是否开启（站点设置默认值，区别于应用级电脑模式开关） */
  private static siteDesktopDefaultOn(): boolean {
    if (appSettings.site_defaults === '') {
      return false
    }
    try {
      const raw: Record<string, Object> = JSON.parse(appSettings.site_defaults) as Record<string, Object>
      const v: Object | undefined = raw['site_desktop']
      return v !== undefined && v === 'on'
    } catch (e) {
      return false
    }
  }

  /** 应用级 UA：全局设置 + 站点默认电脑模式（域名级架构下所有未覆盖站点统一走此 UA） */
  private static appUa(): string {
    if (!appSettings.desktop_mode && UaUtils.siteDesktopDefaultOn()) {
      return UaUtils.desktopUa()
    }
    return UaUtils.effectiveUa()
  }

  /** 域名级 UA 能力是否可用（TabWeb 据此决定是否走实例级旧路径） */
  static hostUaMode(): boolean {
    return UaUtils.hostUaAvailable
  }

  /** Web 附加入口：首次捕获系统默认 UA（须早于任何内核级 UA 设置）→ 同步应用级 UA → 商店域名级注册 */
  static onWebAttach(controller: webview.WebviewController): void {
    if (UaUtils.defaultUa === '') {
      try {
        UaUtils.defaultUa = controller.getUserAgent()
      } catch (e) {
        return
      }
    }
    UaUtils.syncAppUa()
    UaUtils.applyStoreHostUa()
    logger.info('UaApply', `onWebAttach syncAppUa: wideForm=${UaUtils.wideForm()}`)
  }

  /** 应用级 UA 同步（setAppCustomUserAgent；能力不可用回退实例级旧路径） */
  static syncAppUa(): void {
    if (UaUtils.hostUaAvailable) {
      const ua: string = UaUtils.appUa()
      if (ua === '') {
        return
      }
      try {
        webview.WebviewController.setAppCustomUserAgent(ua)
        logger.info('UaApply', `setAppCustomUserAgent: ${ua.substring(0, 60)}`)
        return
      } catch (e) {
        // 801 能力不支持等 → 永久回退实例级路径
        UaUtils.hostUaAvailable = false
      }
    }
    for (const tab of tabsVM.tabs) {
      const c = tab.controller
      if (c) {
        UaUtils.applyTo(c)
      }
    }
  }

  /** 域名级 UA 注册：按 UA 串分组设置宿主列表；不再使用的旧 UA 重设空列表清除映射 */
  static applyHostUaMap(groups: Map<string, string[]>): void {
    if (!UaUtils.hostUaAvailable) {
      return
    }
    const seen: Set<string> = new Set()
    groups.forEach((hosts: string[], ua: string): void => {
      seen.add(ua)
      try {
        webview.WebviewController.setUserAgentForHosts(ua, hosts)
        UaUtils.registeredHostUas.add(ua)
      } catch (e) {
      }
    })
    const stale: string[] = []
    UaUtils.registeredHostUas.forEach((ua: string): void => {
      if (!seen.has(ua)) {
        stale.push(ua)
      }
    })
    for (const ua of stale) {
      try {
        webview.WebviewController.setUserAgentForHosts(ua, [])
        UaUtils.registeredHostUas.delete(ua)
      } catch (e) {
      }
    }
  }

  /** 应用 UA 到指定 Web 控制器（旧路径：实例级 setCustomUserAgent，仅能力回退时使用） */
  static applyTo(controller: webview.WebviewController): void {
    if (UaUtils.defaultUa === '') {
      try {
        UaUtils.defaultUa = controller.getUserAgent()
      } catch (e) {
        return
      }
    }
    const ua: string = UaUtils.effectiveUa()
    if (ua === '') {
      return
    }
    try {
      controller.setCustomUserAgent(ua)
    } catch (e) {
    }
  }

  /** 全局 UA 变更统一入口：应用级重设 + 域名映射重建（能力回退时退化为实例级遍历） */
  static applyToAll(): void {
    UaUtils.syncAppUa()
    const provider = UaUtils.hostUaMapProvider
    if (provider !== null) {
      provider().then((groups: Map<string, string[]>): void => {
        UaUtils.applyHostUaMap(groups)
      }).catch((): void => {
      })
    }
  }

  /** 商店桌面 UA 域名级注册（CWS/Edge 商店站点；不入 registeredHostUas，站点分组重建不清除商店映射） */
  private static applyStoreHostUa(): void {
    if (!UaUtils.hostUaAvailable) {
      return
    }
    try {
      webview.WebviewController.setUserAgentForHosts(UaUtils.STORE_UA, UaUtils.CWS_HOSTS)
      webview.WebviewController.setUserAgentForHosts(UaUtils.EDGE_STORE_UA, UaUtils.EDGE_STORE_HOSTS)
    } catch (e) {
    }
  }
}
