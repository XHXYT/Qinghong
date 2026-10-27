import { Column } from "../utils/database/decorator/Decorators";

/**
 * 书签
 */
export default class BookmarkInfo {
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
   * 标题
   */
  @Column({
    name: 'title',
    type: 'TEXT',
    notNull: true
  })
  title: string;

  /**
   * 地址
   */
  @Column({
    name: 'url',
    type: 'TEXT',
    notNull: true,
    unique: true
  })
  url: string;

  /**
   * 排序序号
   */
  @Column({
    name: 'order_index',
    type: 'INTEGER',
    notNull: true,
    defaultValue: 0
  })
  orderIndex: number = 0;

  /**
   * 是否为主页快捷图标
   */
  @Column({
    name: 'is_quick',
    type: 'BOOLEAN',
    notNull: true,
    defaultValue: 0
  })
  isQuick: boolean = false;

  /**
   * 所在文件夹（'' = 根目录）
   */
  @Column({
    name: 'folder',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  folder: string = '';

  /**
   * 自定义图标文件路径（'' = 未自定义，显示 favicon 或首字头像）
   */
  @Column({
    name: 'icon',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  icon: string = '';

  /**
   * 创建时间
   */
  @Column({
    name: 'create_time',
    type: 'INTEGER',
    notNull: true
  })
  createTime: number;

  constructor(title: string, url: string, isQuick: boolean = false,
    orderIndex: number = 0, createTime: number = new Date().getTime()) {
    this.title = title;
    this.url = url;
    this.isQuick = isQuick;
    this.orderIndex = orderIndex;
    this.createTime = createTime;
  }
}
