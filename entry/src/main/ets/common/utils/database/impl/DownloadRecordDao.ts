
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../app/Logger';
import DownloadRecordInfo from '../../../entity/DownloadRecordInfo';

const logger = createLogger('DownloadRecordDao');

/**
 * 下载记录表
 */
@Table({ db: 'qinghong', name: 'download_record' })
export class DownloadRecordDao extends AutoTable<DownloadRecordInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'download_record');
  }

  protected getEntityClass(): new (...args: Object[]) => DownloadRecordInfo {
    return DownloadRecordInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: DownloadRecordInfo): ValueType {
    return item.id
  }

  /**
   * 查询全部下载记录，按时间倒序
   */
  async queryAll(): Promise<DownloadRecordInfo[]> {
    return this.query(this.getPredicates().orderByDesc('create_time'))
  }

  /**
   * 按路径查询
   */
  async queryByPath(path: string): Promise<DownloadRecordInfo | null> {
    const results = await this.query(this.getPredicates().equalTo('path', path))
    return results.length > 0 ? results[0] : null
  }

  /**
   * 保存或更新记录
   */
  async saveOrUpdate(record: DownloadRecordInfo): Promise<number> {
    const existing = await this.queryByPath(record.path)
    if (existing) {
      existing.status = record.status
      existing.fileName = record.fileName
      existing.url = record.url
      return this.update(existing)
    }
    return this.insert(record)
  }

  async updateStatus(id: number, status: string): Promise<number> {
    const results = await this.query(this.getPredicates().equalTo('id', id))
    if (results.length === 0) return -1
    const info = results[0]
    info.status = status
    return this.update(info)
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }

  async clearAll(): Promise<void> {
    await this.clearTable()
  }
}
