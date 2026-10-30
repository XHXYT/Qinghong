import { _QhState } from '../entryability/AppState';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import { BookmarkDao } from '../common/utils/database/impl/BookmarkDao';
import { homeHtmlRefresh } from '../common/utils/HomeHtmlRefresh';
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
    // 书签/主页收藏变化后通知挂载中的 HTML 主页重推配置（原生主页经 @Trace 自动刷新）
    homeHtmlRefresh.request()
  }

  async addBookmark(title: string, url: string, isQuick: boolean = false): Promise<void> {
    if (!url) return
    await this.getDB().saveOrUpdate(new BookmarkInfo(title || url, url, isQuick))
    await this.loadAll()
  }

  /** 添加书签（可指定文件夹、主页收藏与自定义图标路径） */
  async addBookmarkWithMeta(title: string, url: string, folder: string, isQuick: boolean,
    icon: string = ''): Promise<void> {
    if (!url) return
    const info: BookmarkInfo = new BookmarkInfo(title || url, url, isQuick)
    info.folder = folder
    info.icon = icon
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

  /** 同步判断是否已是主页收藏（基于内存列表，供菜单高亮等响应式读取） */
  hasQuick(url: string): boolean {
    return this.quickLinks.some((b: BookmarkInfo) => b.url === url)
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
    await this.updateBookmarkWithMeta(id, title, url, '', false, '', true)
  }

  /** 编辑书签（标题/地址/文件夹/主页收藏/图标；地址变化时删旧建新；skipUnset=true 时 folder/quick/icon 不变） */
  async updateBookmarkWithMeta(id: number, title: string, url: string, folder: string,
    isQuick: boolean, icon: string, skipUnset: boolean = false): Promise<void> {
    const list: BookmarkInfo[] = await this.getDB().queryAll()
    for (const b of list) {
      if (b.id === id) {
        if (url === b.url) {
          b.title = title
          if (!skipUnset) {
            b.folder = folder
            b.isQuick = isQuick
            if (icon !== '') {
              b.icon = icon
            }
          }
          await this.getDB().update(b)
        } else {
          const nb: BookmarkInfo = new BookmarkInfo(title, url, skipUnset ? b.isQuick : isQuick)
          nb.folder = skipUnset ? b.folder : folder
          nb.icon = skipUnset ? b.icon : (icon !== '' ? icon : b.icon)
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

  /** 拖拽排序：按槽位重写 orderIndex（槽位与文件夹顺序值同一数值空间） */
  async reorderBookmarksWithSlots(ordered: BookmarkInfo[], slots: number[]): Promise<void> {
    if (ordered.length === 0 || ordered.length !== slots.length) {
      return
    }
    for (let i: number = 0; i < ordered.length; i++) {
      const b: BookmarkInfo = ordered[i]
      b.orderIndex = slots[i]
      if (b.id !== null) {
        await this.getDB().update(b)
      }
    }
    await this.loadAll()
  }

  /** 删除文件夹内全部书签（含子文件夹归属的） */
  async deleteFolderContents(folder: string): Promise<void> {
    if (folder === '') {
      return
    }
    const list: BookmarkInfo[] = await this.getDB().queryAll()
    for (const b of list) {
      if ((b.folder === folder || b.folder.startsWith(`${folder}/`)) && b.id !== null) {
        await this.getDB().deleteById(b.id)
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
