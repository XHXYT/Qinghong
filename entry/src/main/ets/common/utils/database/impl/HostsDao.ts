
import AutoTable from '../AutoTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../Logger';
import HostsRuleInfo from '../../../entity/HostsRuleInfo';

const logger = createLogger('HostsDao');

/**
 * Hosts 规则表：为指定域名指定解析 IP（host 唯一）
 */
@Table({ db: 'qinghong', name: 'hosts_rule' })
export class HostsDao extends AutoTable<HostsRuleInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'hosts_rule');
  }

  protected getEntityClass(): new (...args: Object[]) => HostsRuleInfo {
    return HostsRuleInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: HostsRuleInfo): number {
    return item.id ?? 0
  }

  /**
   * 全部规则（按域名排序）
   */
  async listAll(): Promise<HostsRuleInfo[]> {
    return this.query(this.getPredicates().orderByAsc('host'))
  }

  /**
   * 查询域名规则（无则 null）
   */
  async getByHost(host: string): Promise<HostsRuleInfo | null> {
    const results = await this.query(this.getPredicates().equalTo('host', host))
    return results.length > 0 ? results[0] : null
  }

  /**
   * 写入规则（有则改无则插）
   */
  async setRule(host: string, ip: string): Promise<void> {
    const results = await this.query(this.getPredicates().equalTo('host', host))
    if (results.length > 0) {
      const info: HostsRuleInfo = results[0]
      info.ip = ip
      await this.update(info)
      return
    }
    await this.insert(new HostsRuleInfo(host, ip))
  }

  /**
   * 删除单条规则
   */
  async removeByHost(host: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('host', host))
  }

  /**
   * 清空全部规则
   */
  async removeAll(): Promise<number> {
    return this.deleteItem(this.getPredicates())
  }
}
