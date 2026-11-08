
import AutoTable from '../AutoTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../Logger';
import ItpStatInfo from '../../../entity/ItpStatInfo';

const logger = createLogger('ItpStatDao');

/** 单跟踪者记录的网站数上限 */
const MAX_SITES = 30;

/**
 * 智能防跟踪（ITP）拦截统计表（隐私报告）：按被拦截跟踪域名聚合拦截次数与触发网站
 */
@Table({ db: 'qinghong', name: 'itp_stat' })
export class ItpStatDao extends AutoTable<ItpStatInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'itp_stat');
  }

  protected getEntityClass(): new (...args: Object[]) => ItpStatInfo {
    return ItpStatInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: ItpStatInfo): number {
    return item.id ?? 0
  }

  /** 全部统计（按拦截次数降序） */
  async listAll(): Promise<ItpStatInfo[]> {
    return this.query(this.getPredicates().orderByDesc('hits'))
  }

  /** 记录若干次拦截命中（hits += count），网站去重追加（上限 MAX_SITES），更新时间 */
  async recordHit(host: string, company: string, category: string, siteHost: string, count: number): Promise<void> {
    const results = await this.query(this.getPredicates().equalTo('host', host))
    const now = new Date().getTime()
    if (results.length > 0) {
      const info: ItpStatInfo = results[0]
      info.hits += count
      info.company = company
      info.category = category
      info.lastSeen = now
      const sites: string[] = ItpStatDao.parseSites(info.sites)
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
    const info = new ItpStatInfo(host, company, category)
    info.hits = count
    info.lastSeen = now
    const sites: string[] = siteHost !== '' ? [siteHost] : []
    info.sites = JSON.stringify(sites)
    info.siteCount = sites.length
    await this.insert(info)
    logger.debug(`recordHit new: ${host} (${company})`)
  }

  /** 删除指定域名的统计 */
  async removeHost(host: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('host', host))
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
