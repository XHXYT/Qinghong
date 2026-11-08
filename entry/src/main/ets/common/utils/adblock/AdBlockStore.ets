import { preferenceUtil } from '../persistence/PreferenceUtil';
import { AppConstants } from '../../constants/AppConstants';

/**
 * 广告拦截统计（设备本地数据，不参与同步）
 */
@ObservedV2
export class AdBlockStore {

  /** 累计拦截条数 */
  @Trace count: number = 0
  /** 累计节省流量（字节） */
  @Trace bytes: number = 0

  private loaded: boolean = false
  private flushTimer: number = -1

  /**
   * 启动时加载历史统计（累加到内存计数上，避免加载前拦截的请求丢失）
   */
  async load(): Promise<void> {
    if (this.loaded) {
      return
    }
    try {
      const c: number = await preferenceUtil.get<number>(AppConstants.KEY_AD_BLOCK_COUNT, 0)
      this.count += c ?? 0
      const b: number = await preferenceUtil.get<number>(AppConstants.KEY_AD_BLOCK_BYTES, 0)
      this.bytes += b ?? 0
      this.loaded = true
    } catch (e) {
      console.error(`[AdBlockStore] 加载拦截统计失败: ${e}`)
    }
  }

  /**
   * 累加拦截统计：n 条、bytes 字节（拦截引擎高频调用，防抖落盘）
   */
  add(n: number, bytes: number): void {
    this.count += n
    this.bytes += bytes
    if (this.flushTimer >= 0) {
      return
    }
    this.flushTimer = setTimeout((): void => {
      this.flushTimer = -1
      this.flush()
    }, 2000)
  }

  private flush(): void {
    preferenceUtil.put(AppConstants.KEY_AD_BLOCK_COUNT, this.count).catch((): void => {
    })
    preferenceUtil.put(AppConstants.KEY_AD_BLOCK_BYTES, this.bytes).catch((): void => {
    })
  }

  /** 清零 */
  async reset(): Promise<void> {
    this.count = 0
    this.bytes = 0
    try {
      await preferenceUtil.put(AppConstants.KEY_AD_BLOCK_COUNT, 0)
      await preferenceUtil.put(AppConstants.KEY_AD_BLOCK_BYTES, 0)
    } catch (e) {
      console.error(`[AdBlockStore] 重置拦截统计失败: ${e}`)
    }
  }

  /** 流量大小格式化：B / KB / MB / GB */
  static formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`
    }
    const kb: number = bytes / 1024
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`
    }
    const mb: number = kb / 1024
    if (mb < 1024) {
      return `${mb.toFixed(1)} MB`
    }
    return `${(mb / 1024).toFixed(2)} GB`
  }
}

export const adBlockStore: AdBlockStore = new AdBlockStore()
