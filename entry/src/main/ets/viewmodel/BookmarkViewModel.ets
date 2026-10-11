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

  async isBookmarked(url: string): Promise<boolean> {
    return await this.getDB().queryByUrl(url) !== null
  }

  async deleteBookmark(id: number): Promise<void> {
    await this.getDB().deleteById(id)
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
