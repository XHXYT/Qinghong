import { webview } from '@kit.ArkWeb';
import { connection } from '@kit.NetworkKit';
import { HostsDao } from '../common/utils/database/impl/HostsDao';
import HostsRuleInfo from '../common/entity/HostsRuleInfo';
import { _QhState } from '../entryability/AppState';
import { createLogger } from '../common/utils/app/Logger';

const logger = createLogger('HostsViewModel');

/**
 * Hosts 管理：RDB 规则增删改（每 host 支持多 IP，空格分隔）+
 * 双通道内核同步（connection.addCustomDnsRule 多 IP 数组 + webview.setHostIP 首个 IP 保底）
 */
export class HostsViewModel {

  private dao: HostsDao | null = null
  /** Web 引擎就绪标记（首个 Web attach 后置 true）：setHostIP 在引擎网络服务未就绪时调用，
   * 规则会被暂存引擎静态区，待 NetworkContext 注册时回放触发纯虚函数调用 SIGABRT，必须延迟 */
  private webReady: boolean = false
  /** netmanager 通道已应用（host → ip 串） */
  private netApplied: Map<string, string> = new Map()
  /** webview 通道已应用（host → ip 串），仅引擎就绪后 */
  private webApplied: Map<string, string> = new Map()

  private getDB(): HostsDao {
    if (this.dao === null) {
      this.dao = new HostsDao(_QhState.Context)
    }
    return this.dao
  }

  /** 首个 Web 引擎就绪时调用（TabWeb onControllerAttached）：启用 webview 通道并全量同步 */
  onWebAttach(): void {
    if (this.webReady) {
      return
    }
    this.webReady = true
    this.syncToWeb()
  }

  /** 全部规则（按域名排序） */
  async listAll(): Promise<HostsRuleInfo[]> {
    return this.getDB().listAll()
  }

  /** 查询单条规则（无则 null） */
  async getByHost(host: string): Promise<HostsRuleInfo | null> {
    return this.getDB().getByHost(host)
  }

  /**
   * 追加规则：host 已存在时合并 IP（去重），否则新建，并同步内核
   */
  async addRule(host: string, ipInput: string): Promise<void> {
    const existing: HostsRuleInfo | null = await this.getDB().getByHost(host)
    let merged: string[] = []
    if (existing !== null) {
      merged = HostsViewModel.splitIps(existing.ip)
    }
    for (const ip of HostsViewModel.splitIps(ipInput)) {
      if (merged.indexOf(ip) < 0) {
        merged.push(ip)
      }
    }
    await this.getDB().setRule(host, merged.join(' '))
    await this.syncToWeb()
  }

  /** 覆盖写入规则（有则改无则插）并同步内核 */
  async setRule(host: string, ip: string): Promise<void> {
    await this.getDB().setRule(host, ip)
    await this.syncToWeb()
  }

  /** 删除规则并同步内核 */
  async removeByHost(host: string): Promise<void> {
    await this.getDB().removeByHost(host)
    await this.syncToWeb()
  }

  /** 清空规则并同步内核 */
  async removeAll(): Promise<void> {
    await this.getDB().removeAll()
    await this.syncToWeb()
  }

  /**
   * 批量导入 hosts 格式文本：
   * - 每行「IP... 域名...」任意组合（一行内多 IP 或经典「单 IP 多域名」均支持，
   *   自动识别 token 是 IP 还是域名），# 后为注释
   * - 同 host 跨行合并 IP（去重）
   * - 返回导入条数（按去重后 host 计）
   */
  async importRules(text: string): Promise<number> {
    const lines: string[] = text.split('\n')
    const pending: Map<string, string[]> = new Map()
    for (const raw of lines) {
      let line: string = raw
      const hashIdx: number = line.indexOf('#')
      if (hashIdx >= 0) {
        line = line.substring(0, hashIdx)
      }
      line = line.trim()
      if (line === '') {
        continue
      }
      const parts: string[] = line.split(/\s+/)
      const ips: string[] = []
      const hosts: string[] = []
      let ok: boolean = true
      for (const p of parts) {
        if (HostsViewModel.isValidIp(p)) {
          ips.push(p)
        } else if (HostsViewModel.isValidHost(p)) {
          hosts.push(p)
        } else {
          ok = false
          break
        }
      }
      if (!ok || ips.length === 0 || hosts.length === 0) {
        continue
      }
      for (const host of hosts) {
        let merged: string[] = []
        const got: string[] | undefined = pending.get(host)
        if (got !== undefined) {
          merged = got
        }
        for (const ip of ips) {
          if (merged.indexOf(ip) < 0) {
            merged.push(ip)
          }
        }
        pending.set(host, merged)
      }
    }
    const entries: string[] = []
    pending.forEach((ips: string[], host: string): void => {
      entries.push(host)
    })
    for (const host of entries) {
      const ips: string[] | undefined = pending.get(host)
      let joined: string = ''
      if (ips !== undefined) {
        joined = ips.join(' ')
      }
      await this.getDB().setRule(host, joined)
    }
    await this.syncToWeb()
    return entries.length
  }

  /**
   * 内核同步（增量），双通道独立跟踪：
   * - netmanager 通道（connection.addCustomDnsRule，多 IP 数组）：与 Web 引擎无关，启动即应用
   * - webview 通道（setHostIP 首个 IP）：仅引擎就绪后应用（onWebAttach），避免 NetworkContext 注册期崩溃
   */
  async syncToWeb(): Promise<void> {
    const rules: HostsRuleInfo[] = await this.getDB().listAll()
    const seen: Map<string, string> = new Map()
    // netmanager 通道
    for (const r of rules) {
      seen.set(r.host, r.ip)
      const ips: string[] = HostsViewModel.splitIps(r.ip)
      if (ips.length === 0) {
        continue
      }
      if (this.netApplied.get(r.host) === r.ip) {
        continue
      }
      try {
        // 先移除旧规则再重加，规避内核合并语义不明导致的陈旧 IP 残留
        await connection.removeCustomDnsRule(r.host)
      } catch (e) {
        // 无旧规则时可能报错，忽略
      }
      try {
        await connection.addCustomDnsRule(r.host, ips)
      } catch (e) {
        logger.error(`addCustomDnsRule 失败 (${r.host}): ${e}`)
      }
      this.netApplied.set(r.host, r.ip)
    }
    const netStale: string[] = []
    this.netApplied.forEach((ip: string, host: string): void => {
      if (seen.get(host) !== ip) {
        netStale.push(host)
      }
    })
    for (const host of netStale) {
      try {
        await connection.removeCustomDnsRule(host)
      } catch (e) {
        logger.error(`removeCustomDnsRule 失败 (${host}): ${e}`)
      }
      this.netApplied.delete(host)
    }
    // webview 通道（仅引擎就绪后）
    if (this.webReady) {
      for (const r of rules) {
        if (this.webApplied.get(r.host) === r.ip) {
          continue
        }
        const ips: string[] = HostsViewModel.splitIps(r.ip)
        if (ips.length > 0) {
          try {
            webview.WebviewController.setHostIP(r.host, ips[0], 86400)
          } catch (e) {
            logger.error(`setHostIP 失败 (${r.host}): ${e}`)
          }
        }
        this.webApplied.set(r.host, r.ip)
      }
      const webStale: string[] = []
      this.webApplied.forEach((ip: string, host: string): void => {
        if (seen.get(host) !== ip) {
          webStale.push(host)
        }
      })
      for (const host of webStale) {
        try {
          webview.WebviewController.clearHostIP(host)
        } catch (e) {
          logger.error(`clearHostIP 失败 (${host}): ${e}`)
        }
        this.webApplied.delete(host)
      }
    }
  }

  /** 拆分 IP 串（空格/制表分隔），去空去重 */
  static splitIps(v: string): string[] {
    const result: string[] = []
    if (v === '') {
      return result
    }
    const parts: string[] = v.split(/\s+/)
    for (const p of parts) {
      if (p !== '' && result.indexOf(p) < 0) {
        result.push(p)
      }
    }
    return result
  }

  /** IP 列表校验：至少一个且全部合法 */
  static isValidIpList(v: string): boolean {
    const ips: string[] = HostsViewModel.splitIps(v)
    if (ips.length === 0) {
      return false
    }
    for (const ip of ips) {
      if (!HostsViewModel.isValidIp(ip)) {
        return false
      }
    }
    return true
  }

  /** 域名校验：小写字母数字连字符标签 + 至少一个点 */
  static isValidHost(v: string): boolean {
    return /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/.test(v)
  }

  /** IP 校验：IPv4（点分十进制，0-255）或 IPv6（宽松：冒号分隔十六进制） */
  static isValidIp(v: string): boolean {
    if (v === '') {
      return false
    }
    // IPv4
    if (v.indexOf(':') < 0) {
      const segs: string[] = v.split('.')
      if (segs.length !== 4) {
        return false
      }
      for (const s of segs) {
        if (!/^\d{1,3}$/.test(s)) {
          return false
        }
        const n: number = Number(s)
        if (n > 255) {
          return false
        }
      }
      return true
    }
    // IPv6（宽松校验：仅十六进制与冒号，允许 :: 压缩）
    return /^[0-9a-fA-F:]{2,45}$/.test(v) && v.indexOf(':') !== v.lastIndexOf(':')
  }
}

export const hostsVM: HostsViewModel = new HostsViewModel()
