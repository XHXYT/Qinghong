import { webview } from '@kit.ArkWeb';
import { appSettings } from '../../entity/SettingsModel';

/**
 * DoH 服务商预置项
 */
export class DohProvider {
  readonly id: string
  readonly nameRes: ResourceStr
  readonly url: string

  constructor(id: string, nameRes: ResourceStr, url: string) {
    this.id = id
    this.nameRes = nameRes
    this.url = url
  }
}

/**
 * DNS 工具：DoH 加密解析（加速 & 防污染）+ 预解析加速（自动预连接）
 * 均为内核静态配置，启动时与开关变化时应用
 */
export class DnsUtils {

  /** 引擎就绪标记（首个 Web attach 后置 true）：setHttpDns 在引擎/网络服务未就绪时调用会原生空指针崩溃（SIGSEGV），必须延迟 */
  private static webReady: boolean = false
  /** DoH 配置待应用脏标记 */
  private static dohDirty: boolean = true
  /** 本次会话已成功调用过 setHttpDns（撤销 OFF 仅在曾应用过时才执行，避免无谓的内核调用） */
  private static dohSet: boolean = false

  /** DoH 服务商预置列表 */
  static readonly DOH_PROVIDERS: DohProvider[] = [
    new DohProvider('alidns', $r('app.string.dns_provider_alidns'), 'https://dns.alidns.com/dns-query'),
    new DohProvider('dnspod', $r('app.string.dns_provider_dnspod'), 'https://doh.pub/dns-query'),
    new DohProvider('google', $r('app.string.dns_provider_google'), 'https://dns.google/dns-query'),
    new DohProvider('cloudflare', $r('app.string.dns_provider_cloudflare'), 'https://cloudflare-dns.com/dns-query'),
    new DohProvider('qihoo360', $r('app.string.dns_provider_360'), 'https://doh.360.cn/dns-query')
  ]

  /** 服务商显示名（未知名回退自定义） */
  static providerName(id: string): ResourceStr {
    for (const p of DnsUtils.DOH_PROVIDERS) {
      if (p.id === id) {
        return p.nameRes
      }
    }
    return $r('app.string.dns_provider_custom')
  }

  /** 服务商 DoH 地址（'' 表示自定义或未知） */
  static providerUrl(id: string): string {
    for (const p of DnsUtils.DOH_PROVIDERS) {
      if (p.id === id) {
        return p.url
      }
    }
    return ''
  }

  /** 当前生效的 DoH 地址（自定义优先校验 https 前缀） */
  static dohUrl(): string {
    if (appSettings.dns_doh_provider === 'custom') {
      const u: string = appSettings.dns_doh_custom.trim()
      return u.startsWith('https://') ? u : ''
    }
    return DnsUtils.providerUrl(appSettings.dns_doh_provider)
  }

  /** 首个 Web 引擎就绪时调用（TabWeb onControllerAttached），落地挂起的 DoH 配置 */
  static onWebAttach(): void {
    DnsUtils.webReady = true
    if (DnsUtils.dohDirty) {
      DnsUtils.applyDoh()
    }
  }

  /** 应用 DoH 配置（引擎未就绪时挂起等待首个 Web attach；AUTO 模式解析失败自动回退系统 DNS） */
  static applyDoh(): void {
    DnsUtils.dohDirty = true
    if (!DnsUtils.webReady) {
      return
    }
    try {
      if (appSettings.dns_doh_enabled) {
        const url: string = DnsUtils.dohUrl()
        if (url !== '') {
          webview.WebviewController.setHttpDns(webview.SecureDnsMode.AUTO, url)
          DnsUtils.dohSet = true
        }
      } else {
        DnsUtils.disableDoh()
      }
      DnsUtils.dohDirty = false
    } catch (e) {
      DnsUtils.dohDirty = false
      console.error(`[DnsUtils] setHttpDns 失败: ${e}`)
    }
  }

  /** 撤销 DoH（仅曾应用过才调用；'' 不被接受时用占位 URL 重试，OFF 模式下配置被忽略） */
  private static disableDoh(): void {
    if (!DnsUtils.dohSet) {
      return
    }
    try {
      webview.WebviewController.setHttpDns(webview.SecureDnsMode.OFF, '')
      DnsUtils.dohSet = false
    } catch (e) {
      try {
        webview.WebviewController.setHttpDns(webview.SecureDnsMode.OFF, 'https://dns.alidns.com/dns-query')
        DnsUtils.dohSet = false
      } catch (e2) {
        console.error(`[DnsUtils] 撤销 DoH 失败: ${e2}`)
      }
    }
  }

  /** 预解析加速：自动预连接上个生命周期高频访问的 URL */
  static applyPreconnect(): void {
    try {
      webview.WebviewController.setAutoPreconnect(appSettings.dns_preconnect_enabled)
    } catch (e) {
      console.error(`[DnsUtils] setAutoPreconnect 失败: ${e}`)
    }
  }

  /** 启动时统一应用 */
  static applyAll(): void {
    DnsUtils.applyDoh()
    DnsUtils.applyPreconnect()
  }
}
