import { Column } from "../utils/database/decorator/Decorators";

/**
 * 下载记录
 */
export default class DownloadRecordInfo {
  @Column({
    name: 'id',
    type: 'INTEGER',
    isPrimaryKey: true,
    autoIncrement: true
  })
  id: number | null = null;

  /**
   * 下载地址
   */
  @Column({
    name: 'url',
    type: 'TEXT',
    notNull: true
  })
  url: string;

  /**
   * 文件名
   */
  @Column({
    name: 'file_name',
    type: 'TEXT',
    notNull: true
  })
  fileName: string;

  /**
   * 本地路径
   */
  @Column({
    name: 'path',
    type: 'TEXT',
    notNull: true
  })
  path: string;

  /**
   * 状态 downloading / completed / failed
   */
  @Column({
    name: 'status',
    type: 'TEXT',
    notNull: true,
    defaultValue: 'downloading'
  })
  status: string = 'downloading';

  /**
   * 创建时间
   */
  @Column({
    name: 'create_time',
    type: 'INTEGER',
    notNull: true
  })
  createTime: number;

  constructor(url: string, fileName: string, path: string, status: string = 'downloading',
    createTime: number = new Date().getTime()) {
    this.url = url;
    this.fileName = fileName;
    this.path = path;
    this.status = status;
    this.createTime = createTime;
  }
}
