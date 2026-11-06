
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import ExtensionInfo from '../../../entity/ExtensionInfo';

/**
 * 浏览器扩展表
 */
@Table({ db: 'qinghong', name: 'extension' })
export class ExtensionDao extends AutoTable<ExtensionInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'extension');
  }

  protected getEntityClass(): new (...args: Object[]) => ExtensionInfo {
    return ExtensionInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: ExtensionInfo): ValueType {
    return item.id
  }

  /**
   * 查询全部扩展，按创建时间倒序
   */
  async queryAll(): Promise<ExtensionInfo[]> {
    return this.query(this.getPredicates().orderByDesc('create_time'))
  }

  /**
   * 按扩展ID查询（同 ID 覆盖安装）
   */
  async queryByExtId(extId: string): Promise<ExtensionInfo | null> {
    const results = await this.query(this.getPredicates().equalTo('ext_id', extId))
    return results.length > 0 ? results[0] : null
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }
}
