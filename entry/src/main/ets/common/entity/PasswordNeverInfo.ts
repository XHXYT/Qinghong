import { Column } from "../utils/database/decorator/Decorators";

/**
 * 不保存密码的网站（密码管理器例外列表）
 */
export default class PasswordNeverInfo {
  @Column({
    name: 'host',
    type: 'TEXT',
    isPrimaryKey: true
  })
  host: string = '';

  constructor(host: string = '') {
    this.host = host;
  }
}
