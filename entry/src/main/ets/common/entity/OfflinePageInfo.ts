import { Column } from "../utils/database/decorator/Decorators";

/**
 * 离线页面记录（离线网页存档索引）
 */
export default class OfflinePageInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 显示名称（保存时用户输入）
   */
  @Column({
    name: 'name',
    type: 'TEXT',
    notNull: true
  })
  name: string;

  /**
   * 原页面地址
   */
  @Column({
    name: 'url',
    type: 'TEXT',
    notNull: true
  })
  url: string;

  /**
   * 离线档文件路径（公共 Download/包名/Offline）
   */
  @Column({
    name: 'path',
    type: 'TEXT',
    notNull: true
  })
  path: string;

  /**
   * 创建时间
   */
  @Column({
    name: 'create_time',
    type: 'INTEGER',
    notNull: true
  })
  createTime: number;

  constructor(name: string, url: string, path: string,
    createTime: number = new Date().getTime()) {
    this.name = name;
    this.url = url;
    this.path = path;
    this.createTime = createTime;
  }
}
