
import AutoTable from '../AutoTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../app/Logger';
import TrackerStatInfo from '../../../entity/TrackerStatInfo';

const logger = createLogger('TrackerStatDao');

/** 单跟踪者记录的网站数上限 */
const MAX_SITES = 30;

/**
 * 跟踪者统计表（隐私报告）：按跟踪域名聚合拦截次数与出现网站
 */
@Table({ db: 'qinghong', name: 'tracker_stat' })
export class TrackerStatDao extends AutoTable<TrackerStatInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'tracker_stat');
  }

  protected getEntityClass(): new (...args: Object[]) => TrackerStatInfo {
    return TrackerStatInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: TrackerStatInfo): number {
    return item.id ?? 0
  }

  /** 全部统计（按拦截次数降序） */
  async listAll(): Promise<TrackerStatInfo[]> {
    return this.query(this.getPredicates().orderByDesc('hits'))
  }

  /** 记录一次跟踪命中：hits +1，网站去重追加（上限 MAX_SITES），更新时间 */
  async recordHit(host: string, company: string, category: string, siteHost: string): Promise<void> {
    const results = await this.query(this.getPredicates().equalTo('host', host))
    const now = new Date().getTime()
    if (results.length > 0) {
      const info: TrackerStatInfo = results[0]
      info.hits += 1
      info.lastSeen = now
      const sites: string[] = TrackerStatDao.parseSites(info.sites)
      if (siteHost !== '' && sites.indexOf(siteHost) < 0) {
        sites.push(siteHost)
        if (sites.length > MAX_SITES) {
          sites.shift()
        }
        info.sites = JSON.stringify(sites)
        info.siteCount = sites.length
      }
      await this.update(info)
      return
    }
    const info = new TrackerStatInfo(host, company, category)
    info.hits = 1
    info.lastSeen = now
    const sites: string[] = siteHost !== '' ? [siteHost] : []
    info.sites = JSON.stringify(sites)
    info.siteCount = sites.length
    await this.insert(info)
    logger.debug(`recordHit new: ${host} (${company})`)
  }

  /** 清空全部统计 */
  async removeAll(): Promise<number> {
    return this.deleteItem(this.getPredicates())
  }

  /** 解析 sites JSON（容错：异常返回空数组） */
  private static parseSites(text: string): string[] {
    if (text === '') {
      return []
    }
    try {
      const arr = JSON.parse(text) as string[]
      return arr
    } catch (e) {
      logger.error(`parseSites 失败: ${e}`)
      return []
    }
  }
}
