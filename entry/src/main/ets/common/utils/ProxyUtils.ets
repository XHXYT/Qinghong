import { webview } from '@kit.ArkWeb';
import { appSettings } from '../entity/SettingsModel';
import SiteSettingInfo from '../entity/SiteSettingInfo';
import { SiteSettingDao } from './database/impl/SiteSettingDao';
import { _QhState } from '../../entryability/AppState';

/** 站点级"走代理"覆盖 key（site_setting 表） */
export const SITE_PROXY_KEY: string = 'site_proxy';

/**
 * 代理分流：ArkWeb 仅支持全应用全局代理（ProxyController，无 per-Web setProxy）。
 * 走代理范围由「网站设定 · 走代理」决定（默认 + 站点例外）：
 * 默认开 = 所有网站走代理，例外（off）站点直连；
 * 默认关 = 仅例外（on）站点走代理（enableReverseBypass 反转旁路语义），其余直连。
 * 路由由内核按请求域名匹配 bypass 规则，多标签并发互不影响。
 * 仅支持单一代理服务器（所有分流站点共用）。
 */
export class ProxyUtils {

  /** 引擎就绪标记（首个 Web attach 后置 true）：与 setHttpDns 同理，内核网络配置在引擎未就绪时调用有崩溃风险 */
  private static webReady: boolean = false
  /** 本次会话已应用过代理覆盖（撤销仅在曾应用过时执行，避免无谓内核调用） */
  private static applied: boolean = false
  private static dao: SiteSettingDao | null = null

  private static getDB(): SiteSettingDao {
    if (ProxyUtils.dao === null) {
      ProxyUtils.dao = new SiteSettingDao(_QhState.Context)
    }
    return ProxyUtils.dao
  }

  /** 首个 Web 引擎就绪时调用（TabWeb onControllerAttached），落地代理配置 */
  static onWebAttach(): void {
    if (ProxyUtils.webReady) {
      return
    }
    ProxyUtils.webReady = true
    ProxyUtils.apply()
  }

  /** 代理配置是否有效（启用 + 主机非空 + 端口合法） */
  static valid(): boolean {
    return appSettings.proxy_enabled
      && appSettings.proxy_host.trim() !== ''
      && Number.isInteger(appSettings.proxy_port)
      && appSettings.proxy_port >= 1
      && appSettings.proxy_port <= 65535
  }

  /** 「走代理」全局默认档（site_defaults JSON，'on'=默认全部走代理；解析失败回退 'off'） */
  static proxyDefault(): string {
    if (appSettings.site_defaults === '') {
      return 'off'
    }
    try {
      const raw: Record<string, Object> = JSON.parse(appSettings.site_defaults) as Record<string, Object>
      const v: Object | undefined = raw[SITE_PROXY_KEY]
      if (v !== undefined && typeof v === 'string' && v === 'on') {
        return 'on'
      }
    } catch (e) {
      // 解析失败视为默认关闭
    }
    return 'off'
  }

  /**
   * 全量重算并应用代理配置（启动/代理设置/走代理默认或例外变更时调用）。
   * 默认开：所有请求经过代理，例外（off）站点直连；
   * 默认关：仅例外（on）站点经过代理（reverse bypass），无例外站点时撤销覆盖。
   * 配置无效时撤销覆盖，恢复系统代理。
   */
  static async apply(): Promise<void> {
    if (!ProxyUtils.webReady) {
      return
    }
    if (!ProxyUtils.valid()) {
      ProxyUtils.remove()
      return
    }
    const rows: SiteSettingInfo[] = await ProxyUtils.getDB().listByKey(SITE_PROXY_KEY)
    const config: webview.ProxyConfig = new webview.ProxyConfig()
    config.insertProxyRule(`${appSettings.proxy_type}://${appSettings.proxy_host.trim()}:${appSettings.proxy_port}`)
    if (ProxyUtils.proxyDefault() === 'on') {
      // 默认走代理：例外（off）站点加入旁路规则直连
      for (const r of rows) {
        if (r.value === 'off' && r.site !== '') {
          config.insertBypassRule(r.site)
        }
      }
    } else {
      // 默认直连：仅例外（on）站点走代理
      const sites: string[] = []
      for (const r of rows) {
        if (r.value === 'on' && r.site !== '') {
          sites.push(r.site)
        }
      }
      if (sites.length === 0) {
        ProxyUtils.remove()
        return
      }
      config.enableReverseBypass(true)
      for (const s of sites) {
        config.insertBypassRule(s)
      }
    }
    try {
      webview.ProxyController.applyProxyOverride(config, (): void => {
      })
      ProxyUtils.applied = true
    } catch (e) {
      console.error(`[ProxyUtils] applyProxyOverride 失败: ${e}`)
    }
  }

  /** 撤销代理覆盖（仅曾应用过才执行） */
  static remove(): void {
    if (!ProxyUtils.applied) {
      return
    }
    try {
      webview.ProxyController.removeProxyOverride((): void => {
      })
      ProxyUtils.applied = false
    } catch (e) {
      console.error(`[ProxyUtils] removeProxyOverride 失败: ${e}`)
    }
  }
}
