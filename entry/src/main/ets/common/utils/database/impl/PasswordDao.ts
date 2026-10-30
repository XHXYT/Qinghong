
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../Logger';
import PasswordInfo from '../../../entity/PasswordInfo';
import { PwdCrypto } from '../../PwdCrypto';
import rdb from '@ohos.data.relationalStore';

const logger = createLogger('PasswordDao');

/**
 * 保存的网站登录密码表
 * 独立库 qinghong_pwd.db：S4 安全级别 + RDB 文件级加密；
 * password 列为 HUKS AES-256-GCM 密文（enc1: + base64(nonce+密文+tag)），
 * 读取时解密；历史明文行读取时原样返回，下次写入时自动转为密文
 */
@Table({ db: 'qinghong_pwd', name: 'password' })
export class PasswordDao extends AutoTable<PasswordInfo> {

  constructor(context: Context) {
    super(context, 'qinghong_pwd', 'password', rdb.SecurityLevel.S4, true);
  }

  protected getEntityClass(): new (...args: Object[]) => PasswordInfo {
    return PasswordInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: PasswordInfo): ValueType {
    return item.id
  }

  /** 单条解密（失败返回原文兜底，避免单行异常拖垮整表） */
  private async decryptItem(info: PasswordInfo): Promise<PasswordInfo> {
    if (!PwdCrypto.isEncrypted(info.password)) {
      return info
    }
    try {
      info.password = await PwdCrypto.decrypt(info.password)
    } catch (e) {
      logger.error(`decrypt password failed, host: ${info.host}, err: ${e}`)
    }
    return info
  }

  /**
   * 按 host + username 精确查找（仅表单登录凭据，用于 upsert 与更新提示），密码已解密
   */
  async findByAccount(host: string, username: string): Promise<PasswordInfo | null> {
    const results = await this.query(this.getPredicates()
      .equalTo('auth_type', 'form')
      .equalTo('host', host)
      .equalTo('username', username)
      .limitAs(1))
    return results.length > 0 ? await this.decryptItem(results[0]) : null
  }

  /**
   * 查询某网站最近更新的表单登录凭据（自动填充用），密码已解密
   */
  async findLatestByHost(host: string): Promise<PasswordInfo | null> {
    const results = await this.query(this.getPredicates()
      .equalTo('auth_type', 'form')
      .equalTo('host', host)
      .orderByDesc('updated_at')
      .limitAs(1))
    return results.length > 0 ? await this.decryptItem(results[0]) : null
  }

  /**
   * 按 host + realm 查找 HTTP Basic 认证凭据，密码已解密
   */
  async findBasic(host: string, realm: string): Promise<PasswordInfo | null> {
    const results = await this.query(this.getPredicates()
      .equalTo('auth_type', 'basic')
      .equalTo('host', host)
      .equalTo('realm', realm)
      .limitAs(1))
    return results.length > 0 ? await this.decryptItem(results[0]) : null
  }

  /**
   * 新增或更新 HTTP Basic 认证凭据（host + realm 唯一），入库前加密
   */
  async upsertBasic(host: string, realm: string, username: string, password: string): Promise<void> {
    const existing = await this.findBasic(host, realm)
    if (existing !== null) {
      if (existing.username === username && existing.password === password) {
        return
      }
      existing.username = username
      existing.password = await PwdCrypto.encrypt(password)
      existing.updatedAt = new Date().getTime()
      await this.update(existing)
      logger.debug(`upsertBasic updated: ${host} realm=${realm}`)
      return
    }
    const info = new PasswordInfo(host, username, await PwdCrypto.encrypt(password))
    info.realm = realm
    info.authType = 'basic'
    await this.insert(info)
    logger.debug(`upsertBasic inserted: ${host} realm=${realm}`)
  }

  async listAll(): Promise<PasswordInfo[]> {
    const results = await this.query(this.getPredicates().orderByDesc('updated_at'))
    const list: PasswordInfo[] = []
    for (const info of results) {
      list.push(await this.decryptItem(info))
    }
    return list
  }

  /**
   * 新增或更新（host + username 唯一），入库前加密
   */
  async upsert(host: string, username: string, password: string): Promise<void> {
    const existing = await this.findByAccount(host, username)
    if (existing !== null) {
      if (existing.password === password) {
        return
      }
      existing.password = await PwdCrypto.encrypt(password)
      existing.updatedAt = new Date().getTime()
      await this.update(existing)
      logger.debug(`upsert updated: ${host}`)
      return
    }
    const info = new PasswordInfo(host, username, await PwdCrypto.encrypt(password))
    await this.insert(info)
    logger.debug(`upsert inserted: ${host}`)
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }
}
