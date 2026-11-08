
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../app/Logger';
import PasswordNeverInfo from '../../../entity/PasswordNeverInfo';
import rdb from '@ohos.data.relationalStore';

const logger = createLogger('PasswordNeverDao');

/**
 * 不保存密码的网站表（密码管理器例外列表）
 * 与密码表同库 qinghong_pwd.db：S4 安全级别 + RDB 文件级加密
 */
@Table({ db: 'qinghong_pwd', name: 'password_never' })
export class PasswordNeverDao extends AutoTable<PasswordNeverInfo> {

  constructor(context: Context) {
    super(context, 'qinghong_pwd', 'password_never', rdb.SecurityLevel.S4, true);
  }

  protected getEntityClass(): new (...args: Object[]) => PasswordNeverInfo {
    return PasswordNeverInfo;
  }

  getColumnId(): string {
    return "host"
  }

  getEntityId(item: PasswordNeverInfo): ValueType {
    return item.host
  }

  async has(host: string): Promise<boolean> {
    const results = await this.query(this.getPredicates().equalTo('host', host).limitAs(1))
    return results.length > 0
  }

  async listAll(): Promise<string[]> {
    const results = await this.query(this.getPredicates().orderByAsc('host'))
    return results.map((item: PasswordNeverInfo): string => item.host)
  }

  async add(host: string): Promise<void> {
    if (await this.has(host)) {
      return
    }
    await this.insert(new PasswordNeverInfo(host))
    logger.debug(`add never-save: ${host}`)
  }

  async remove(host: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('host', host))
  }
}
