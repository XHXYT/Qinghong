import { Column } from "../utils/database/decorator/Decorators";

/**
 * 用户脚本 GM 存储键值（GM_setValue/GM_getValue 持久化）
 */
export default class UserScriptValue {
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
   * 所属脚本ID
   */
  @Column({
    name: 'script_id',
    type: 'INTEGER',
    notNull: true,
    defaultValue: 0
  })
  scriptId: number = 0;

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
   * 值（JSON 原文，JS 任意可序列化值）
   */
  @Column({
    name: 'value',
    type: 'TEXT',
    notNull: true,
    defaultValue: 'null'
  })
  value: string = 'null';
}
