import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 设备 API 能力判定（compatibleSdkVersion 23 起，API 26+ 特性按项判定，低版本设备降级）：
 * 仅收敛「运行时调用不存在会抛错 / 静默失效」的跨版本差异，判定结果随设备固定不缓存失效问题
 */
export class ApiCompat {

  /** 原生 http SOCKS5 代理（connection.Socks5Proxy / HttpRequestOptions.usingSocks5Proxy，API 26+）：
   *  低版本设备原生 http 请求（下载等）不支持 SOCKS5，仅内核网页代理可用 */
  static socks5HttpProxy(): boolean {
    return deviceInfo.sdkApiVersion >= 26
  }

  /** Web 高级安全模式（WebviewController.enableAdvancedSecurityMode，API 26+）：
   *  低版本设备无此接口，对应设置项隐藏、配置调用跳过 */
  static advancedSecurityMode(): boolean {
    return deviceInfo.sdkApiVersion >= 26
  }
}
