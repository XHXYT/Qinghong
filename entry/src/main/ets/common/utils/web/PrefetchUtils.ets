import { webview } from '@kit.ArkWeb'
import { appSettings } from '../../entity/SettingsModel'
import { SearchEngines, UrlUtils } from '../../constants/SearchEngines'
import { createLogger } from '../app/Logger'

const logger = createLogger('PrefetchUtils')

/**
 * 地址栏回车目标预热（ArkWeb C3）
 * - 输入即 URL：prefetchPage 整页预取（引擎缓存约 5 分钟，回车直达秒开）
 * - 合成搜索 URL：prepareForPageLoad 预连接（DNS/TCP/TLS 握手，不耗流量）
 * - 无痕标签 / 「预加载网页」关闭时不做任何预热（隐私优先）
 */
export class PrefetchUtils {
  private static warmTimer: number = -1
  private static lastUrl: string = ''
  private static lastWarmAt: number = 0

  /** 输入停顿 300ms 后按“回车目标”预热（controller 为 null 或未挂载时仅预连接） */
  static scheduleWarm(input: string, incognito: boolean, controller: webview.WebviewController | null): void {
    PrefetchUtils.cancel()
    if (incognito || !appSettings.web_prefetch) {
      return
    }
    const keyword = input.trim()
    if (!keyword) {
      return
    }
    const isUrl: boolean = UrlUtils.isLikelyUrl(keyword)
    const url: string = isUrl ? UrlUtils.normalizeUrl(keyword)
      : SearchEngines.buildSearchUrl(SearchEngines.getCurrentEngine(), keyword)
    if (!url) {
      return
    }
    // 同 URL 60s 内不重复预热（prefetchPage 自带 500ms 节流与缓存）
    if (url === PrefetchUtils.lastUrl && Date.now() - PrefetchUtils.lastWarmAt < 60000) {
      return
    }
    PrefetchUtils.warmTimer = setTimeout((): void => {
      PrefetchUtils.warmTimer = -1
      PrefetchUtils.warm(url, isUrl, controller)
    }, 300)
  }

  private static warm(url: string, full: boolean, controller: webview.WebviewController | null): void {
    PrefetchUtils.lastUrl = url
    PrefetchUtils.lastWarmAt = Date.now()
    if (full) {
      // 输入即 URL：整页预取；无控制器或失败时退回预连接
      try {
        if (controller !== null) {
          controller.prefetchPage(url)
          return
        }
      } catch (e) {
        logger.warn('warm', `prefetchPage 失败，回退预连接: ${e}`)
      }
    }
    try {
      webview.WebviewController.prepareForPageLoad(url, true, 1)
    } catch (e) {
      logger.warn('warm', `预连接失败: ${e}`)
    }
  }

  /** 取消待执行预热（联想清空/导航时） */
  static cancel(): void {
    if (PrefetchUtils.warmTimer >= 0) {
      clearTimeout(PrefetchUtils.warmTimer)
      PrefetchUtils.warmTimer = -1
    }
  }
}
