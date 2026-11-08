
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../app/Logger';
import HistoryInfo from '../../../entity/HistoryInfo';

const logger = createLogger('HistoryDao');

/**
 * 浏览历史表
 */
@Table({ db: 'qinghong', name: 'history' })
export class HistoryDao extends AutoTable<HistoryInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'history');
  }

  protected getEntityClass(): new (...args: Object[]) => HistoryInfo {
    return HistoryInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: HistoryInfo): ValueType {
    return item.id
  }

  /**
   * 记录一次访问（按 URL 去重，更新时间与标题）
   */
  async addVisit(title: string, url: string): Promise<number> {
    const results = await this.query(this.getPredicates().equalTo('url', url))
    if (results.length > 0) {
      const info = results[0]
      info.title = title || info.title
      info.visitTime = new Date().getTime()
      return this.update(info)
    }
    return this.insert(new HistoryInfo(title, url))
  }

  /**
   * 查询全部历史，按访问时间倒序（限制条数防止过大）
   */
  async queryRecent(limit: number = 500): Promise<HistoryInfo[]> {
    return this.query(this.getPredicates().orderByDesc('visit_time').limitAs(limit))
  }

  /**
   * 模糊搜索历史（标题或 URL）
   */
  async queryByKeywordLike(keyword: string, limit: number = 5): Promise<HistoryInfo[]> {
    if (!keyword) return []
    return this.query(this.getPredicates()
      .like('title', `%${keyword}%`)
      .or()
      .like('url', `%${keyword}%`)
      .orderByDesc('visit_time')
      .limitAs(limit))
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }

  /** 批量删除（多选编辑栏） */
  async deleteByIds(ids: number[]): Promise<number> {
    if (ids.length === 0) {
      return 0
    }
    return this.deleteItem(this.getPredicates().in('id', ids))
  }

  async deleteByUrl(url: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('url', url))
  }

  async clearAll(): Promise<void> {
    await this.clearTable()
  }
}
