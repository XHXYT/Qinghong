import { Column } from "../utils/database/decorator/Decorators";

/**
 * 浏览历史
 */
export default class HistoryInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 页面标题
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
   * 最近访问时间
   */
  @Column({
    name: 'visit_time',
    type: 'INTEGER',
    notNull: true
  })
  visitTime: number;

  constructor(title: string, url: string, visitTime: number = new Date().getTime()) {
    this.title = title;
    this.url = url;
    this.visitTime = visitTime;
  }
}
