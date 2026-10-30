import { Column } from "../utils/database/decorator/Decorators";

/**
 * 跟踪者统计（隐私报告）：按跟踪域名聚合被拦截的跟踪请求数与出现的网站
 */
export default class TrackerStatInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 跟踪域名（数据库键，如 doubleclick.net）
   */
  @Column({
    name: 'host',
    type: 'TEXT',
    notNull: true
  })
  host: string;

  /**
   * 跟踪者公司（如 Google）
   */
  @Column({
    name: 'company',
    type: 'TEXT',
    notNull: true
  })
  company: string;

  /**
   * 类别：ads 广告投放 / analytics 统计分析 / track 跨站追踪 / social 社交插件 / fingerprint 指纹识别
   */
  @Column({
    name: 'category',
    type: 'TEXT',
    notNull: true
  })
  category: string;

  /**
   * 累计拦截次数
   */
  @Column({
    name: 'hits',
    type: 'INTEGER',
    notNull: true,
    defaultValue: '0'
  })
  hits: number;

  /**
   * 出现过的网站数（去重）
   */
  @Column({
    name: 'site_count',
    type: 'INTEGER',
    notNull: true,
    defaultValue: '0'
  })
  siteCount: number;

  /**
   * 出现过的网站列表（JSON 数组，上限 30 个）
   */
  @Column({
    name: 'sites',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  sites: string;

  /**
   * 最近一次出现时间（毫秒时间戳）
   */
  @Column({
    name: 'last_seen',
    type: 'INTEGER',
    notNull: true,
    defaultValue: '0'
  })
  lastSeen: number;

  constructor(host: string = '', company: string = '', category: string = '') {
    this.host = host;
    this.company = company;
    this.category = category;
    this.hits = 0;
    this.siteCount = 0;
    this.sites = '[]';
    this.lastSeen = 0;
  }
}
