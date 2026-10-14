import { Column } from "../utils/database/decorator/Decorators";

/**
 * 站点设置覆盖（site + key 唯一，value 为档位标识）
 */
export default class SiteSettingInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 站点域名（如 example.com）
   */
  @Column({
    name: 'site',
    type: 'TEXT',
    notNull: true
  })
  site: string;

  /**
   * 设置项标识（如 site_image）
   */
  @Column({
    name: 'key',
    type: 'TEXT',
    notNull: true
  })
  key: string;

  /**
   * 档位标识（如 block）
   */
  @Column({
    name: 'value',
    type: 'TEXT',
    notNull: true
  })
  value: string;

  constructor(site: string = '', key: string = '', value: string = '') {
    this.site = site;
    this.key = key;
    this.value = value;
  }
}
