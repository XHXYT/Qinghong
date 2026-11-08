import { webview } from '@kit.ArkWeb';
import { appSettings } from '../entity/SettingsModel';

/**
 * 智能防跟踪（ITP）豁免域名列表（WebviewController 静态 API，应用级、内核不持久化）：
 * 列表内域名绕过 ITP 处理（第三方请求仍可携带 Cookie）；
 * 与「站点设置-允许跨站跟踪」（站点维度关 ITP）互补，此处为域名维度全应用豁免。
 */
export class ItpBypassUtils {

  /** 引擎就绪标记（首个 Web attach 后置 true）：内核级静态 API 在引擎未就绪时调用有崩溃风险（同 setHttpDns 教训） */
  private static webReady: boolean = false

  /** 首个 Web 引擎就绪时调用（TabWeb onControllerAttached），重设内核豁免列表 */
  static onWebAttach(): void {
    if (ItpBypassUtils.webReady) {
      return
    }
    ItpBypassUtils.webReady = true
    ItpBypassUtils.apply()
  }

  /** 应用豁免列表（快照式：清空后整体重设，幂等；列表为空时仅清空） */
  static apply(): void {
    if (!ItpBypassUtils.webReady) {
      return
    }
    try {
      webview.WebviewController.clearIntelligentTrackingPreventionBypassingList()
      const hosts: string[] = appSettings.itp_bypass_hosts
      if (hosts.length > 0) {
        webview.WebviewController.addIntelligentTrackingPreventionBypassingList(hosts)
      }
    } catch (e) {
      console.error(`[ItpBypass] 设置豁免列表失败: ${e}`)
    }
  }

  /** 添加豁免域名（去重；规范化小写去 www. 前缀），持久化并应用 */
  static addHost(host: string): boolean {
    const normalized: string = ItpBypassUtils.normalize(host)
    if (normalized === '' || appSettings.itp_bypass_hosts.indexOf(normalized) >= 0) {
      return false
    }
    appSettings.itp_bypass_hosts.push(normalized)
    appSettings.save()
    ItpBypassUtils.apply()
    return true
  }

  /** 移除豁免域名，持久化并应用 */
  static removeHost(host: string): void {
    const idx: number = appSettings.itp_bypass_hosts.indexOf(host)
    if (idx < 0) {
      return
    }
    appSettings.itp_bypass_hosts.splice(idx, 1)
    appSettings.save()
    ItpBypassUtils.apply()
  }

  /** 域名规范化：小写、去协议/路径/端口/ www. 前缀 */
  private static normalize(host: string): string {
    let value: string = host.trim().toLowerCase()
    const scheme: number = value.indexOf('://')
    if (scheme >= 0) {
      value = value.substring(scheme + 3)
    }
    const slash: number = value.indexOf('/')
    if (slash >= 0) {
      value = value.substring(0, slash)
    }
    const colon: number = value.indexOf(':')
    if (colon >= 0) {
      value = value.substring(0, colon)
    }
    if (value.startsWith('www.')) {
      value = value.substring(4)
    }
    return value
  }
}
