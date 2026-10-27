import { Column } from "../utils/database/decorator/Decorators";

/**
 * 用户脚本（Userscript）
 */
export default class UserScriptInfo {
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
   * 脚本名称（@name）
   */
  @Column({
    name: 'name',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  name: string = '';

  /**
   * 版本（@version）
   */
  @Column({
    name: 'version',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  version: string = '';

  /**
   * 完整脚本源码（含 metadata 块）
   */
  @Column({
    name: 'code',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  code: string = '';

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
   * 运行时机：document-start / document-end / document-idle
   */
  @Column({
    name: 'run_at',
    type: 'TEXT',
    notNull: true,
    defaultValue: 'document-end'
  })
  runAt: string = 'document-end';

  /**
   * 生效域名规则（@match/@include，多行以 \n 分隔）
   */
  @Column({
    name: 'matches',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  matches: string = '';

  /**
   * 排除规则（@exclude/@exclude-match，多行以 \n 分隔）
   */
  @Column({
    name: 'excludes',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  excludes: string = '';

  /**
   * 更新地址（@updateURL/@downloadURL，空表示不支持订阅更新）
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
   * 最近更新时间（安装/编辑/重置时刷新）
   */
  @Column({
    name: 'update_time',
    type: 'INTEGER',
    notNull: true,
    defaultValue: 0
  })
  updateTime: number = 0;

  /**
   * 声明的 API（@grant，JSON 数组，宽松模式下仅记录不强制）
   */
  @Column({
    name: 'grants',
    type: 'TEXT',
    notNull: true,
    defaultValue: '[]'
  })
  grants: string = '[]';

  /**
   * 跨域白名单（@connect，JSON 数组，GM_xmlhttpRequest 校验）
   */
  @Column({
    name: 'connects',
    type: 'TEXT',
    notNull: true,
    defaultValue: '[]'
  })
  connects: string = '[]';

  /**
   * 依赖库（@require，JSON 数组 [{url, code}]，安装时下载）
   */
  @Column({
    name: 'requires',
    type: 'TEXT',
    notNull: true,
    defaultValue: '[]'
  })
  requires: string = '[]';

  /**
   * 资源（@resource，JSON 数组 [{name, mime, b64}]，安装时下载）
   */
  @Column({
    name: 'resources',
    type: 'TEXT',
    notNull: true,
    defaultValue: '[]'
  })
  resources: string = '[]';

  /**
   * 是否不在 iframe 中运行（@noframes）
   */
  @Column({
    name: 'noframes',
    type: 'BOOLEAN',
    notNull: true,
    defaultValue: false
  })
  noframes: boolean = false;
}
