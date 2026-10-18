import { _QhState } from '../entryability/AppState';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import { BookmarkDao } from '../common/utils/database/impl/BookmarkDao';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('BookmarkViewModel')

@ObservedV2
export class BookmarkViewModel {
  @Trace bookmarks: BookmarkInfo[] = []
  @Trace quickLinks: BookmarkInfo[] = []
  @Trace isLoading: boolean = false

  private db: BookmarkDao | null = null

  constructor() {
  }

  private getDB(): BookmarkDao {
    if (!this.db) {
      this.db = new BookmarkDao(_QhState.Context)
    }
    return this.db
  }

  async loadAll(): Promise<void> {
    this.isLoading = true
    try {
      this.bookmarks = await this.getDB().queryAll()
      this.quickLinks = await this.getDB().queryQuick()
    } catch (e) {
      logger.error('loadAll', `${e}`)
    }
    this.isLoading = false
  }

  async addBookmark(title: string, url: string, isQuick: boolean = false): Promise<void> {
    if (!url) return
    await this.getDB().saveOrUpdate(new BookmarkInfo(title || url, url, isQuick))
    await this.loadAll()
  }

  /** 添加书签（可指定文件夹与主页收藏） */
  async addBookmarkWithMeta(title: string, url: string, folder: string, isQuick: boolean): Promise<void> {
    if (!url) return
    const info: BookmarkInfo = new BookmarkInfo(title || url, url, isQuick)
    info.folder = folder
    await this.getDB().saveOrUpdate(info)
    await this.loadAll()
  }

  async isBookmarked(url: string): Promise<boolean> {
    return await this.getDB().queryByUrl(url) !== null
  }

  /** 同步判断是否已收藏（基于内存列表，供菜单高亮等响应式读取） */
  hasBookmark(url: string): boolean {
    return this.bookmarks.some((b: BookmarkInfo) => b.url === url)
  }

  /** 同步按地址查找书签（基于内存列表） */
  findByUrl(url: string): BookmarkInfo | null {
    for (const b of this.bookmarks) {
      if (b.url === url) {
        return b
      }
    }
    return null
  }

  async deleteBookmark(id: number): Promise<void> {
    await this.getDB().deleteById(id)
    await this.loadAll()
  }

  /** 编辑书签（标题/地址；地址变化时删旧建新并保留文件夹与快捷） */
  async updateBookmark(id: number, title: string, url: string): Promise<void> {
    const list: BookmarkInfo[] = await this.getDB().queryAll()
    for (const b of list) {
      if (b.id === id) {
        if (url === b.url) {
          b.title = title
          await this.getDB().update(b)
        } else {
          const nb: BookmarkInfo = new BookmarkInfo(title, url, b.isQuick)
          nb.folder = b.folder
          await this.getDB().deleteById(id)
          await this.getDB().saveOrUpdate(nb)
        }
        break
      }
    }
    await this.loadAll()
  }

  /** 批量移动书签到指定文件夹 */
  async moveBookmarksTo(ids: number[], folder: string): Promise<void> {
    if (ids.length === 0) {
      return
    }
    const idSet: Set<number> = new Set<number>(ids)
    const list: BookmarkInfo[] = await this.getDB().queryAll()
    for (const b of list) {
      if (b.id !== null && idSet.has(b.id)) {
        b.folder = folder
        await this.getDB().update(b)
      }
    }
    await this.loadAll()
  }

  /** 文件夹路径整体改写（重命名/移动/删除文件夹时同步书签归属，dst='' 表示移回根目录） */
  async moveFolderPrefix(src: string, dst: string): Promise<void> {
    if (src === '') {
      return
    }
    const list: BookmarkInfo[] = await this.getDB().queryAll()
    for (const b of list) {
      if (b.folder === src || b.folder.startsWith(`${src}/`)) {
        b.folder = b.folder === src ? dst : `${dst}${b.folder.substring(src.length)}`
        await this.getDB().update(b)
      }
    }
    await this.loadAll()
  }

  async deleteByUrl(url: string): Promise<void> {
    await this.getDB().deleteByUrl(url)
    await this.loadAll()
  }

  async setQuick(url: string, quick: boolean): Promise<void> {
    await this.getDB().setQuick(url, quick)
    await this.loadAll()
  }
}

export const bookmarkVM = new BookmarkViewModel()
