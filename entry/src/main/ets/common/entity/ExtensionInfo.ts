import { Column } from "../utils/database/decorator/Decorators";

/**
 * 浏览器扩展（Chrome Extension 兼容层）
 */
export default class ExtensionInfo {
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
   * 扩展ID（32 位十六进制，chrome.runtime.id）
   */
  @Column({
    name: 'ext_id',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  extId: string = '';

  /**
   * 名称（__MSG_ 已在安装时解析）
   */
  @Column({
    name: 'name',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  name: string = '';

  /**
   * 版本
   */
  @Column({
    name: 'version',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  version: string = '';

  /**
   * 描述（__MSG_ 已在安装时解析）
   */
  @Column({
    name: 'description',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  description: string = '';

  /**
   * manifest 版本（2/3）
   */
  @Column({
    name: 'manifest_version',
    type: 'INTEGER',
    notNull: true,
    defaultValue: 3
  })
  manifestVersion: number = 3;

  /**
   * 是否启用
   */
  @Column({
    name: 'enabled',
    type: 'BOOLEAN',
    notNull: true,
    defaultValue: true
  })
  enabled: boolean = true;

  /**
   * 是否固定到工具栏（PC 浏览器 pin 语义）
   */
  @Column({
    name: 'pinned',
    type: 'BOOLEAN',
    notNull: true,
    defaultValue: false
  })
  pinned: boolean = false;

  /**
   * 解包目录（相对应用沙箱，如 extensions/<extId>）
   */
  @Column({
    name: 'path',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  path: string = '';

  /**
   * manifest.json 完整原文（chrome.runtime.getManifest 返回）
   */
  @Column({
    name: 'manifest',
    type: 'TEXT',
    notNull: true,
    defaultValue: '{}'
  })
  manifest: string = '{}';

  /**
   * 安装来源（crx 直链/商店页 URL，空表示本地导入）
   */
  @Column({
    name: 'update_url',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  updateUrl: string = '';

  /**
   * 创建时间
   */
  @Column({
    name: 'create_time',
    type: 'INTEGER',
    notNull: true,
    defaultValue: 0
  })
  createTime: number = 0;

  /**
   * 最近更新时间
   */
  @Column({
    name: 'update_time',
    type: 'INTEGER',
    notNull: true,
    defaultValue: 0
  })
  updateTime: number = 0;
}
