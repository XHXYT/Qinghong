import { webview } from '@kit.ArkWeb';
import { appSettings } from '../entity/SettingsModel';

/**
 * Web 高级安全模式（API 26+，WebviewController.enableAdvancedSecurityMode，全局静态）。
 * 目前用于「禁止 WebRTC 非代理 UDP」：阻止 WebRTC 通过非代理 UDP 绕过代理隧道、
 * 暴露用户真实物理 IP；禁用后 WebRTC 流量强制走 TCP 代理，视频通话等实时通信可能无法建立。
 */
export class AdvancedSecurityUtils {

  /** 引擎就绪标记（首个 Web attach 后置 true）：内核级静态 API 在引擎未就绪时调用有崩溃风险（同 setHttpDns 教训） */
  private static webReady: boolean = false

  /** 首个 Web 引擎就绪时调用（TabWeb onControllerAttached），落地安全配置 */
  static onWebAttach(): void {
    if (AdvancedSecurityUtils.webReady) {
      return
    }
    AdvancedSecurityUtils.webReady = true
    AdvancedSecurityUtils.apply()
  }

  /** 应用高级安全配置（禁止/恢复 WebRTC 非代理 UDP；未指定字段保持默认 false） */
  static apply(): void {
    if (!AdvancedSecurityUtils.webReady) {
      return
    }
    try {
      webview.WebviewController.enableAdvancedSecurityMode({
        disableNonProxyUDP: appSettings.disable_webrtc_udp
      })
    } catch (e) {
      console.error(`[AdvancedSecurity] enableAdvancedSecurityMode 失败: ${e}`)
    }
  }
}
