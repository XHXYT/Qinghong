import { Column } from "../utils/database/decorator/Decorators";

/**
 * 下载记录（@ObservedV2：列表行细粒度观察，属性级刷新不重建行组件）
 */
@ObservedV2
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
  @Trace
  @Column({
    name: 'file_name',
    type: 'TEXT',
    notNull: true
  })
  fileName: string;

  /**
   * 本地路径
   */
  @Trace
  @Column({
    name: 'path',
    type: 'TEXT',
    notNull: true
  })
  path: string;

  /**
   * 状态 downloading / paused / completed / failed
   */
  @Trace
  @Column({
    name: 'status',
    type: 'TEXT',
    notNull: true,
    defaultValue: 'downloading'
  })
  status: string = 'downloading';

  /**
   * 已接收字节数（暂停/失败续传点；HLS 为已完成分片字节累计）
   */
  @Trace
  @Column({
    name: 'received_size',
    type: 'INTEGER',
    notNull: true,
    defaultValue: '0'
  })
  receivedSize: number = 0;

  /**
   * 总字节数（-1 未知）
   */
  @Trace
  @Column({
    name: 'total_size',
    type: 'INTEGER',
    notNull: true,
    defaultValue: '-1'
  })
  totalSize: number = -1;

  /**
   * HLS 已完成分片数（暂停续传点；普通下载 0）
   */
  @Trace
  @Column({
    name: 'seg_index',
    type: 'INTEGER',
    notNull: true,
    defaultValue: '0'
  })
  segIndex: number = 0;

  /**
   * 是否 HLS(m3u8) 合并下载（暂停/失败续传走分片续传而非 Range 续传）
   */
  @Trace
  @Column({
    name: 'is_hls',
    type: 'BOOLEAN',
    notNull: true,
    defaultValue: '0'
  })
  isHls: boolean = false;

  /**
   * 来源页面地址（防盗链 Referer；重试/续传沿用）
   */
  @Column({
    name: 'referer',
    type: 'TEXT',
    notNull: true,
    defaultValue: ''
  })
  referer: string = '';

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
