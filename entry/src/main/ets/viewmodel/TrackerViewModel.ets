import { buffer } from '@kit.ArkTS';
import { TrackerStatDao } from '../common/utils/database/impl/TrackerStatDao';
import { ItpStatDao } from '../common/utils/database/impl/ItpStatDao';
import TrackerStatInfo from '../common/entity/TrackerStatInfo';
import ItpStatInfo from '../common/entity/ItpStatInfo';
import { _QhState } from '../entryability/AppState';
import { createLogger } from '../common/utils/app/Logger';

const logger = createLogger('TrackerViewModel');

/** ITP 拦截缓冲防抖落库间隔（毫秒） */
const ITP_FLUSH_DEBOUNCE = 3000;

/** 跟踪者数据库条目（rawfile/tracker_db.json 解析结果） */
interface TrackerDbEntry {
  company: string
  category: string
}

/** 跟踪者数据库原始 JSON 结构 */
interface TrackerDbRaw {
  domains: Record<string, TrackerDbEntry>
}

/** ITP 拦截内存缓冲条目（防抖落库前按 域名|网站 聚合） */
interface ItpBufferEntry {
  trackerHost: string
  siteHost: string
  count: number
}

/**
 * 隐私报告（跟踪者视角）：
 * - 内置跟踪者数据库（域名 → 公司 + 类别），rawfile 一次性加载
 * - onAdsBlocked 上报的被拦截 URL 经域名后缀匹配归类，按跟踪域名聚合落库
 * - onIntelligentTrackingPreventionResult 上报的 ITP 拦截经内存缓冲防抖落库（itp_stat 表）
 * - 无痕标签不记录（网站列表会暴露浏览历史）
 */
export class TrackerViewModel {

  private dao: TrackerStatDao | null = null
  private itpDao: ItpStatDao | null = null

  /** ITP 拦截缓冲（键：trackerHost|siteHost）与防抖落库定时器 */
  private itpBuffer: Map<string, ItpBufferEntry> = new Map()
  private itpFlushTimer: number = -1

  /** 跟踪者数据库（跟踪域名 → 公司/类别），首次使用时从 rawfile 加载 */
  private db: Map<string, TrackerDbEntry> | null = null
  private dbLoading: Promise<void> | null = null

  private getDB(): TrackerStatDao {
    if (this.dao === null) {
      this.dao = new TrackerStatDao(_QhState.Context)
    }
    return this.dao
  }

  private getItpDB(): ItpStatDao {
    if (this.itpDao === null) {
      this.itpDao = new ItpStatDao(_QhState.Context)
    }
    return this.itpDao
  }

  /** 确保跟踪者数据库已加载（单飞） */
  private ensureDb(): Promise<void> {
    if (this.db !== null) {
      return Promise.resolve()
    }
    if (this.dbLoading !== null) {
      return this.dbLoading
    }
    this.dbLoading = new Promise<void>((resolve: () => void) => {
      this.db = TrackerViewModel.loadDb()
      resolve()
    })
    return this.dbLoading
  }

  /** 读取 rawfile 跟踪者数据库（同步读；失败时置空 Map，隐私报告退化为无记录） */
  private static loadDb(): Map<string, TrackerDbEntry> {
    const map = new Map<string, TrackerDbEntry>()
    try {
      const data: Uint8Array = _QhState.Context.resourceManager.getRawFileContentSync('tracker_db.json')
      const text: string = buffer.from(data).toString('utf-8')
      const raw = JSON.parse(text) as TrackerDbRaw
      const domains: Record<string, TrackerDbEntry> = raw.domains
      const keys = Object.keys(domains)
      for (const key of keys) {
        const entry: TrackerDbEntry = domains[key]
        map.set(key, entry)
      }
      logger.debug(`loadDb: ${map.size} domains`)
    } catch (e) {
      logger.error(`loadDb 失败: ${e}`)
    }
    return map
  }

  /**
   * 域名后缀匹配：从完整 host 逐级去掉最左侧标签查询数据库
   * （a.b.doubleclick.net → b.doubleclick.net → doubleclick.net）
   */
  private matchDomain(host: string): TrackerDbEntry | null {
    if (this.db === null) {
      return null
    }
    let current: string = host
    while (current !== '') {
      const hit: TrackerDbEntry | undefined = this.db.get(current)
      if (hit !== undefined) {
        return hit
      }
      const dot: number = current.indexOf('.')
      if (dot < 0 || dot === current.length - 1) {
        return null
      }
      current = current.substring(dot + 1)
    }
    return null
  }

  /** 从 URL 提取小写 host（去端口，去 www. 前缀） */
  static hostOf(url: string): string {
    const rest: string = url.indexOf('://') >= 0 ? url.substring(url.indexOf('://') + 3) : url
    let host: string = rest.split('/')[0]
    const port: number = host.indexOf(':')
    if (port >= 0) {
      host = host.substring(0, port)
    }
    host = host.toLowerCase()
    if (host.startsWith('www.')) {
      host = host.substring(4)
    }
    return host
  }

  /**
   * 记录一批被拦截请求（onAdsBlocked 上报）：
   * 逐 URL 匹配跟踪者数据库，命中则聚合落库；pageUrl 为当前页面（记录出现网站）
   */
  async recordBlocked(pageUrl: string, urls: string[]): Promise<void> {
    await this.ensureDb()
    if (this.db === null || this.db.size === 0) {
      return
    }
    const siteHost: string = TrackerViewModel.hostOf(pageUrl)
    const counted: Map<string, TrackerDbEntry> = new Map()
    for (const url of urls) {
      const host: string = TrackerViewModel.hostOf(url)
      if (host === '') {
        continue
      }
      const entry: TrackerDbEntry | null = this.matchDomain(host)
      if (entry === null) {
        continue
      }
      const known: TrackerDbEntry | undefined = counted.get(host)
      if (known !== undefined) {
        continue
      }
      counted.set(host, entry)
      await this.getDB().recordHit(host, entry.company, entry.category, siteHost)
    }
  }

  /** 全部跟踪者统计（按拦截次数降序） */
  async listAll(): Promise<TrackerStatInfo[]> {
    return this.getDB().listAll()
  }

  /** 清空全部统计 */
  async removeAll(): Promise<void> {
    await this.getDB().removeAll()
  }

  /**
   * 记录一次 ITP 拦截（onIntelligentTrackingPreventionResult 上报）：
   * 内存按 域名|网站 聚合计数，防抖落库（回调高频触发时避免逐条写库）
   */
  recordItpBlocked(siteHost: string, trackerHost: string): void {
    if (trackerHost === '') {
      return
    }
    const key: string = `${trackerHost}|${siteHost}`
    const entry: ItpBufferEntry | undefined = this.itpBuffer.get(key)
    if (entry !== undefined) {
      entry.count += 1
    } else {
      this.itpBuffer.set(key, { trackerHost: trackerHost, siteHost: siteHost, count: 1 })
    }
    if (this.itpFlushTimer >= 0) {
      return
    }
    this.itpFlushTimer = setTimeout(() => {
      this.itpFlushTimer = -1
      this.flushItpBuffer()
    }, ITP_FLUSH_DEBOUNCE)
  }

  /** 缓冲批量落库：tracker_db 命中取公司/类别，未命中以域名本身为公司、类别跨站追踪 */
  private flushItpBuffer(): void {
    if (this.itpBuffer.size === 0) {
      return
    }
    const entries: ItpBufferEntry[] = Array.from(this.itpBuffer.values())
    this.itpBuffer.clear()
    this.ensureDb().then((): void => {
      for (const entry of entries) {
        const match: TrackerDbEntry | null = this.matchDomain(entry.trackerHost)
        const company: string = match !== null ? match.company : entry.trackerHost
        const category: string = match !== null ? match.category : 'track'
        this.getItpDB().recordHit(entry.trackerHost, company, category, entry.siteHost, entry.count)
          .catch((e: Object): void => {
            logger.error(`ITP 统计落库失败: ${e}`)
          })
      }
    })
  }

  /** 全部 ITP 拦截统计（按拦截次数降序） */
  async listItpAll(): Promise<ItpStatInfo[]> {
    return this.getItpDB().listAll()
  }

  /** 清空全部 ITP 拦截统计 */
  async removeItpAll(): Promise<void> {
    await this.getItpDB().removeAll()
  }
}

export const trackerVM: TrackerViewModel = new TrackerViewModel()
