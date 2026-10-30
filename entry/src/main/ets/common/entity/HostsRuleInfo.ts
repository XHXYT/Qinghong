import { Column } from "../utils/database/decorator/Decorators";

/**
 * Hosts 规则：为指定域名指定解析 IP（host 唯一，类似系统 hosts）
 */
export default class HostsRuleInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 域名（如 example.com）
   */
  @Column({
    name: 'host',
    type: 'TEXT',
    notNull: true
  })
  host: string;

  /**
   * 解析 IP（IPv4 或 IPv6）
   */
  @Column({
    name: 'ip',
    type: 'TEXT',
    notNull: true
  })
  ip: string;

  constructor(host: string = '', ip: string = '') {
    this.host = host;
    this.ip = ip;
  }
}
