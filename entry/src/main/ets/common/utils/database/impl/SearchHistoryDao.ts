
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../app/Logger';
import SearchHistoryInfo from '../../../entity/SearchHistoryInfo';

const logger = createLogger('SearchHistoryDao');

/**
 * 搜索历史表
 */
@Table({ db: 'qinghong', name: 'search_history' })
export class SearchHistoryDao extends AutoTable<SearchHistoryInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'search_history');
  }

  protected getEntityClass(): new (...args: Object[]) => SearchHistoryInfo {
    return SearchHistoryInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: SearchHistoryInfo): ValueType {
    return item.id
  }

  /**
   * 保存或更新搜索词
   * @param visitTime 搜索时间（默认当前时间；导入备份时传入原时间以保真）
   */
  async saveOrUpdate(keyword: string, visitTime: number = new Date().getTime()): Promise<number> {
    const results = await this.query(this.getPredicates().equalTo('keyword', keyword))
    if (results.length > 0) {
      const info = results[0]
      info.visitTime = visitTime
      return this.update(info)
    }
    return this.insert(new SearchHistoryInfo(keyword, visitTime))
  }

  /**
   * 查询最近 N 条搜索历史
   */
  async queryRecent(limit: number = 10): Promise<SearchHistoryInfo[]> {
    return this.query(this.getPredicates().orderByDesc('visit_time').limitAs(limit))
  }

  /**
   * 全量搜索历史（按时间倒序；导出备份用）
   */
  async queryAll(): Promise<SearchHistoryInfo[]> {
    return this.query(this.getPredicates().orderByDesc('visit_time'))
  }

  /**
   * 前缀/模糊匹配搜索历史
   */
  async queryByKeywordLike(keyword: string, limit: number = 5): Promise<SearchHistoryInfo[]> {
    if (!keyword) return []
    return this.query(this.getPredicates()
      .like('keyword', `%${keyword}%`)
      .orderByDesc('visit_time')
      .limitAs(limit))
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }

  async clearAll(): Promise<void> {
    await this.clearTable()
  }
}
