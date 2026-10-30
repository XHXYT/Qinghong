import { Column } from "../utils/database/decorator/Decorators";

/**
 * 保存的网站登录密码（密码管理器）
 */
export default class PasswordInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 网站 host（如 example.com）
   */
  @Column({
    name: 'host',
    type: 'TEXT',
    notNull: true
  })
  host: string;

  /**
   * 用户名（可为空串）
   */
  @Column({
    name: 'username',
    type: 'TEXT',
    notNull: true
  })
  username: string;

  /**
   * 密码
   */
  @Column({
    name: 'password',
    type: 'TEXT',
    notNull: true
  })
  password: string;

  /**
   * HTTP 认证 realm（仅 authType='basic' 时有意义，表单登录为 ''）
   */
  @Column({
    name: 'realm',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  realm: string;

  /**
   * 凭据类型：'form' 网页表单登录 | 'basic' HTTP Basic 认证
   */
  @Column({
    name: 'auth_type',
    type: 'TEXT',
    notNull: true,
    defaultValue: 'form'
  })
  authType: string;

  /**
   * 最近更新时间
   */
  @Column({
    name: 'updated_at',
    type: 'INTEGER',
    notNull: true
  })
  updatedAt: number;

  constructor(host: string = '', username: string = '', password: string = '',
    updatedAt: number = new Date().getTime()) {
    this.host = host;
    this.username = username;
    this.password = password;
    this.realm = '';
    this.authType = 'form';
    this.updatedAt = updatedAt;
  }
}
