import { connection, http } from '@kit.NetworkKit';
import { SiteSettingsViewModel } from '../../../viewmodel/SiteSettingsViewModel';

/** 诊断段状态：检测中/正常/失败 */
export enum SegmentState {
  CHECKING = 0,
  OK = 1,
  FAIL = 2
}

/** 三段连通性诊断结果（每段完成即回调，渐进填充覆盖层） */
export class DiagnoseResult {
  device: SegmentState = SegmentState.CHECKING
  network: SegmentState = SegmentState.CHECKING
  site: SegmentState = SegmentState.CHECKING
  /** 三段均出结果（或短路结束） */
  done: boolean = false
}

/**
 * 网页加载卡住时的分段连通性诊断（浏览器 → 网络 → 网站）：
 * 段1 浏览器（设备）：connection 有无默认网络且具备 INTERNET 能力；
 * 段2 网络（互联网）：系统 NET_CAPABILITY_VALIDATED 快速路径（零流量），未验证则 HTTP 探测兜底；
 * 段3 网站（目标站）：按目标 URL 的 scheme+host 直接探测。
 * 任一段失败即短路结束（后续段无意义），探测均 4 秒超时。
 */
export class NetDiagnose {

  /** 顺序执行三段检测，每段完成经 onUpdate 回调一次 */
  static async run(targetUrl: string, onUpdate: (r: DiagnoseResult) => void): Promise<void> {
    const result: DiagnoseResult = new DiagnoseResult()
    // 段1：设备网络（同步能力查询，即时出结果）
    result.device = NetDiagnose.checkDevice() ? SegmentState.OK : SegmentState.FAIL
    onUpdate(result)
    if (result.device === SegmentState.FAIL) {
      result.done = true
      onUpdate(result)
      return
    }
    // 段2：互联网连通
    const netOk: boolean = await NetDiagnose.checkNetwork()
    result.network = netOk ? SegmentState.OK : SegmentState.FAIL
    onUpdate(result)
    if (!netOk) {
      result.done = true
      onUpdate(result)
      return
    }
    // 段3：目标站点
    const siteOk: boolean = await NetDiagnose.checkSite(targetUrl)
    result.site = siteOk ? SegmentState.OK : SegmentState.FAIL
    result.done = true
    onUpdate(result)
  }

  /** 段1：设备是否存在默认网络且具备 INTERNET 能力 */
  private static checkDevice(): boolean {
    try {
      if (!connection.hasDefaultNetSync()) {
        return false
      }
      const net: connection.NetHandle = connection.getDefaultNetSync()
      const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(net)
      const capList: Array<connection.NetCap> | undefined = caps.networkCap
      return capList !== undefined && capList.includes(connection.NetCap.NET_CAPABILITY_INTERNET)
    } catch (e) {
      return false
    }
  }

  /** 段2：互联网是否可达（系统已验证直接通过，否则探测兜底确认） */
  private static async checkNetwork(): Promise<boolean> {
    try {
      const net: connection.NetHandle = connection.getDefaultNetSync()
      const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(net)
      const capList: Array<connection.NetCap> | undefined = caps.networkCap
      if (capList !== undefined && capList.includes(connection.NetCap.NET_CAPABILITY_VALIDATED)) {
        return true
      }
    } catch (e) {
      // 能力查询失败，走探测兜底
    }
    return NetDiagnose.probe('http://www.baidu.com', 4000)
  }

  /** 段3：目标站点是否可达（按目标 URL 的 scheme + host 探测） */
  private static async checkSite(targetUrl: string): Promise<boolean> {
    const host: string = SiteSettingsViewModel.hostOf(targetUrl)
    if (host === '') {
      return false
    }
    const idx: number = targetUrl.indexOf('://')
    const scheme: string = idx > 0 ? targetUrl.substring(0, idx) : 'https'
    return NetDiagnose.probe(`${scheme}://${host}/`, 4000)
  }

  /** HTTP 探测：收到任意响应（含 3xx/4xx/5xx）即视为可达，仅网络层异常（超时/DNS/拒绝）判失败 */
  private static async probe(url: string, timeoutMs: number): Promise<boolean> {
    const client: http.HttpRequest = http.createHttp()
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING
      }
      await client.request(url, options)
      return true
    } catch (e) {
      return false
    } finally {
      client.destroy()
    }
  }
}
