import { Column } from "../utils/database/decorator/Decorators";

/**
 * 搜索历史
 */
export default class SearchHistoryInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 搜索词
   */
  @Column({
    name: 'keyword',
    type: 'TEXT',
    notNull: true
  })
  keyword: string;

  /**
   * 搜索时间
   */
  @Column({
    name: 'visit_time',
    type: 'INTEGER',
    notNull: true
  })
  visitTime: number;

  constructor(keyword: string, visitTime: number = new Date().getTime()) {
    this.keyword = keyword;
    this.visitTime = visitTime;
  }
}
