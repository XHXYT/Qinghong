import { Column } from "../utils/database/decorator/Decorators";

/**
 * 扩展存储键值（chrome.storage.local 持久化）
 */
export default class ExtensionValue {
  /**
   * 记录ID，新增时设置为 null 可实现自增
   */
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 扩展ID
   */
  @Column({
    name: 'ext_id',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  extId: string = '';

  /**
   * 键名
   */
  @Column({
    name: 'key',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  key: string = '';

  /**
   * 值（JSON 原文）
   */
  @Column({
    name: 'value',
    type: 'TEXT',
    notNull: true,
    defaultValue: 'null'
  })
  value: string = 'null';
}
