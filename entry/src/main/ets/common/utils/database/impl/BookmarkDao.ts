
import AutoTable from '../AutoTable';
import { ValueType } from '../AbsTable';
import { Table } from '../decorator/Decorators';
import { Context } from '@kit.AbilityKit';
import { createLogger } from '../../Logger';
import BookmarkInfo from '../../../entity/BookmarkInfo';

const logger = createLogger('BookmarkDao');

/**
 * 书签表
 */
@Table({ db: 'qinghong', name: 'bookmark' })
export class BookmarkDao extends AutoTable<BookmarkInfo> {

  constructor(context: Context) {
    super(context, 'qinghong', 'bookmark');
  }

  protected getEntityClass(): new (...args: Object[]) => BookmarkInfo {
    return BookmarkInfo;
  }

  getColumnId(): string {
    return "id"
  }

  getEntityId(item: BookmarkInfo): ValueType {
    return item.id
  }

  /**
   * 查询全部书签，按排序号升序、创建时间倒序
   */
  async queryAll(): Promise<BookmarkInfo[]> {
    return this.query(this.getPredicates().orderByAsc('order_index').orderByDesc('create_time'))
  }

  /**
   * 查询主页快捷图标
   */
  async queryQuick(): Promise<BookmarkInfo[]> {
    return this.query(this.getPredicates().equalTo('is_quick', true)
      .orderByAsc('order_index').orderByDesc('create_time'))
  }

  /**
   * 按 URL 查询
   */
  async queryByUrl(url: string): Promise<BookmarkInfo | null> {
    const results = await this.query(this.getPredicates().equalTo('url', url))
    return results.length > 0 ? results[0] : null
  }

  /**
   * 保存或更新（按 URL 去重；icon 非空时覆盖，空值保留原自定义图标）
   */
  async saveOrUpdate(bookmark: BookmarkInfo): Promise<number> {
    const existing = await this.queryByUrl(bookmark.url)
    if (existing) {
      existing.title = bookmark.title
      existing.isQuick = bookmark.isQuick || existing.isQuick
      existing.orderIndex = bookmark.orderIndex
      existing.folder = bookmark.folder
      if (bookmark.icon !== '') {
        existing.icon = bookmark.icon
      }
      return this.update(existing)
    }
    return this.insert(bookmark)
  }

  /**
   * 模糊搜索书签（标题或 URL）
   */
  async queryByKeywordLike(keyword: string, limit: number = 5): Promise<BookmarkInfo[]> {
    if (!keyword) return []
    return this.query(this.getPredicates()
      .like('title', `%${keyword}%`)
      .or()
      .like('url', `%${keyword}%`)
      .orderByDesc('create_time')
      .limitAs(limit))
  }

  async deleteById(id: number): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('id', id))
  }

  async deleteByUrl(url: string): Promise<number> {
    return this.deleteItem(this.getPredicates().equalTo('url', url))
  }

  /**
   * 设置/取消主页快捷图标
   */
  async setQuick(url: string, quick: boolean): Promise<number> {
    const existing = await this.queryByUrl(url)
    if (!existing) return -1
    existing.isQuick = quick
    return this.update(existing)
  }
}
