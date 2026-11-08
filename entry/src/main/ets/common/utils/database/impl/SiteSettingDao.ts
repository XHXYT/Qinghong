
import AutoTable from '../AutoTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../app/Logger';
import SiteSettingInfo from '../../../entity/SiteSettingInfo';

const logger = createLogger('SiteSettingDao');

/**
 * 站点设置表：统一一张宽表存所有设置项的每站点覆盖值，
 * key 是数据不是 schema，新增设置项零迁移
 */
@Table({ db: 'qinghong', name: 'site_setting' })
export class SiteSettingDao extends AutoTable<SiteSettingInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'site_setting');
  }

  protected getEntityClass(): new (...args: Object[]) => SiteSettingInfo {
    return SiteSettingInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: SiteSettingInfo): number {
    return item.id ?? 0
  }

  /**
   * 查询单个覆盖值（无覆盖返回 null）
   */
  async getOverride(site: string, key: string): Promise<string | null> {
    const results = await this.query(this.getPredicates().equalTo('site', site).equalTo('key', key))
    return results.length > 0 ? results[0].value : null
  }

  /**
   * 某设置项的全部例外站点
   */
  async listByKey(key: string): Promise<SiteSettingInfo[]> {
    return this.query(this.getPredicates().equalTo('key', key).orderByAsc('site'))
  }

  /**
   * 某站点的全部覆盖项
   */
  async listBySite(site: string): Promise<SiteSettingInfo[]> {
    return this.query(this.getPredicates().equalTo('site', site).orderByAsc('key'))
  }

  /**
   * 所有有设置覆盖的站点（去重）
   */
  async listSites(): Promise<string[]> {
    const all = await this.query(this.getPredicates().orderByAsc('site'))
    const sites: string[] = []
    for (const r of all) {
      if (sites.length === 0 || sites[sites.length - 1] !== r.site) {
        sites.push(r.site)
      }
    }
    return sites
  }

  /**
   * 写入覆盖值（有则改无则插）
   */
  async setOverride(site: string, key: string, value: string): Promise<void> {
    const results = await this.query(this.getPredicates().equalTo('site', site).equalTo('key', key))
    if (results.length > 0) {
      const info: SiteSettingInfo = results[0]
      info.value = value
      await this.update(info)
      return
    }
    await this.insert(new SiteSettingInfo(site, key, value))
  }

  /**
   * 删除单条覆盖
   */
  async removeOverride(site: string, key: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('site', site).equalTo('key', key))
  }

  /**
   * 删除站点全部覆盖
   */
  async removeSite(site: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('site', site))
  }

  /**
   * 删除某设置项的全部覆盖
   */
  async removeByKey(key: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('key', key))
  }
}
