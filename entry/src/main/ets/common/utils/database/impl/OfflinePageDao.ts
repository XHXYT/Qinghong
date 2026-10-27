
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import OfflinePageInfo from '../../../entity/OfflinePageInfo';

/**
 * 离线页面记录表
 */
@Table({ db: 'qinghong', name: 'offline_page' })
export class OfflinePageDao extends AutoTable<OfflinePageInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'offline_page');
  }

  protected getEntityClass(): new (...args: Object[]) => OfflinePageInfo {
    return OfflinePageInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: OfflinePageInfo): ValueType {
    return item.id
  }

  /**
   * 查询全部离线页面，按时间倒序
   */
  async queryAll(): Promise<OfflinePageInfo[]> {
    return this.query(this.getPredicates().orderByDesc('create_time'))
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }
}
