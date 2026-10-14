import { webview } from '@kit.ArkWeb';
import { appSettings } from '../entity/SettingsModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';

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
 */
export class UaUtils {

  /** 系统默认 UA（首次 Web 附加时捕获，用于还原与简化） */
  static defaultUa: string = ''

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
      'Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko'),
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

  /** 解析 id → UA 字符串（'' 表示未找到） */
  static resolveUa(id: string): string {
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

  /** 当前生效的 UA 字符串（含简化处理） */
  static effectiveUa(): string {
    let ua: string = UaUtils.resolveUa(appSettings.ua_mode)
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

  /** 应用 UA 到指定 Web 控制器（首次调用时捕获系统默认 UA） */
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

  /** 应用 UA 到所有已创建的 Web 控制器 */
  static applyToAll(): void {
    for (const tab of tabsVM.tabs) {
      const c = tab.controller
      if (c) {
        UaUtils.applyTo(c)
      }
    }
  }
}
