
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import ExtensionValue from '../../../entity/ExtensionValue';

/**
 * 扩展存储键值表（chrome.storage.local）
 */
@Table({ db: 'qinghong', name: 'extension_value' })
export class ExtensionValueDao extends AutoTable<ExtensionValue> {

  constructor(context: Context) {
    super(context, 'qinghong', 'extension_value');
  }

  protected getEntityClass(): new (...args: Object[]) => ExtensionValue {
    return ExtensionValue;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: ExtensionValue): ValueType {
    return item.id
  }

  /**
   * 查询某扩展全部键值
   */
  async queryByExt(extId: string): Promise<ExtensionValue[]> {
    return this.query(this.getPredicates().equalTo('ext_id', extId))
  }

  /**
   * 写入键值（存在即更新）
   */
  async upsert(extId: string, key: string, value: string): Promise<void> {
    const rows: ExtensionValue[] = await this.query(
      this.getPredicates().equalTo('ext_id', extId).equalTo('key', key))
    if (rows.length > 0 && rows[0].id !== null) {
      rows[0].value = value
      await this.update(rows[0])
      return
    }
    const row: ExtensionValue = new ExtensionValue()
    row.extId = extId
    row.key = key
    row.value = value
    await this.insert(row)
  }

  /**
   * 删除某扩展的某个键
   */
  async deleteByKey(extId: string, key: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('ext_id', extId).equalTo('key', key))
  }

  /**
   * 清空某扩展全部键值
   */
  async clearByExt(extId: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('ext_id', extId))
  }
}
