
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import UserScriptValue from '../../../entity/UserScriptValue';

/**
 * 用户脚本 GM 存储键值表
 */
@Table({ db: 'qinghong', name: 'user_script_value' })
export class UserScriptValueDao extends AutoTable<UserScriptValue> {

  constructor(context: Context) {
    super(context, 'qinghong', 'user_script_value');
  }

  protected getEntityClass(): new (...args: Object[]) => UserScriptValue {
    return UserScriptValue;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: UserScriptValue): ValueType {
    return item.id
  }

  /**
   * 查询某脚本全部键值
   */
  async queryByScript(scriptId: number): Promise<UserScriptValue[]> {
    return this.query(this.getPredicates().equalTo('script_id', scriptId))
  }

  /**
   * 查询全部键值（启动时载入内存缓存）
   */
  async queryAllRows(): Promise<UserScriptValue[]> {
    return this.query(this.getPredicates())
  }

  /**
   * 写入键值（存在即更新）
   */
  async upsert(scriptId: number, key: string, value: string): Promise<void> {
    const rows: UserScriptValue[] = await this.query(
      this.getPredicates().equalTo('script_id', scriptId).equalTo('key', key))
    if (rows.length > 0 && rows[0].id !== null) {
      rows[0].value = value
      await this.update(rows[0])
      return
    }
    const row: UserScriptValue = new UserScriptValue()
    row.scriptId = scriptId
    row.key = key
    row.value = value
    await this.insert(row)
  }

  /**
   * 删除某脚本的某个键
   */
  async deleteByKey(scriptId: number, key: string): Promise<void> {
    await this.deleteItem(this.getPredicates().equalTo('script_id', scriptId).equalTo('key', key))
  }

  /**
   * 删除某脚本全部键值（脚本删除时清理）
   */
  async deleteByScript(scriptId: number): Promise<void> {
    await this.deleteItem(this.getPredicates().equalTo('script_id', scriptId))
  }
}
