
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import UserScriptInfo from '../../../entity/UserScriptInfo';

/**
 * 用户脚本表
 */
@Table({ db: 'qinghong', name: 'user_script' })
export class UserScriptDao extends AutoTable<UserScriptInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'user_script');
  }

  protected getEntityClass(): new (...args: Object[]) => UserScriptInfo {
    return UserScriptInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: UserScriptInfo): ValueType {
    return item.id
  }

  /**
   * 查询全部脚本，按创建时间倒序
   */
  async queryAll(): Promise<UserScriptInfo[]> {
    return this.query(this.getPredicates().orderByDesc('create_time'))
  }

  /**
   * 按名称查询（同名脚本覆盖安装）
   */
  async queryByName(name: string): Promise<UserScriptInfo | null> {
    const results = await this.query(this.getPredicates().equalTo('name', name))
    return results.length > 0 ? results[0] : null
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }
}
