import { http } from '@kit.NetworkKit';
import { _QhState } from '../entryability/AppState';
import SearchHistoryInfo from '../common/entity/SearchHistoryInfo';
import { SearchHistoryDao } from '../common/utils/database/impl/SearchHistoryDao';
import { SearchEngine, SearchEngines, UrlUtils } from '../common/constants/SearchEngines';
import { BookmarkDao } from '../common/utils/database/impl/BookmarkDao';
import { HistoryDao } from '../common/utils/database/impl/HistoryDao';
import { appSettings } from '../common/entity/SettingsModel';
import { tabsVM } from './TabsViewModel';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('SearchViewModel')

/**
 * 联想条目类型
 */
export enum SuggestType {
  SEARCH_HISTORY = 0,
  BOOKMARK = 1,
  HISTORY = 2,
  NETWORK_SUGGEST = 3,
  TAB = 4,
  FAVORITES = 5,
}

/**
 * 联想条目
 */
@ObservedV2
export class SuggestItem {
  type: SuggestType
  /** 展示文本 */
  text: string
  /** 目标地址（书签/历史）或空（搜索类） */
  url: string
  /** 标签页建议对应的标签 id（非标签页建议为 -1） */
  tabId: number

  constructor(type: SuggestType, text: string, url: string = '', tabId: number = -1) {
    this.type = type
    this.text = text
    this.url = url
    this.tabId = tabId
  }
}

@ObservedV2
export class SearchViewModel {
  @Trace suggestions: SuggestItem[] = []
  @Trace inputText: string = ''

  private db: SearchHistoryDao | null = null
  private bookmarkDb: BookmarkDao | null = null
  private historyDb: HistoryDao | null = null
  private requestSeq: number = 0

  constructor() {
  }

  private getDB(): SearchHistoryDao {
    if (!this.db) {
      this.db = new SearchHistoryDao(_QhState.Context)
    }
    return this.db
  }

  private getBookmarkDB(): BookmarkDao {
    if (!this.bookmarkDb) {
      this.bookmarkDb = new BookmarkDao(_QhState.Context)
    }
    return this.bookmarkDb
  }

  private getHistoryDB(): HistoryDao {
    if (!this.historyDb) {
      this.historyDb = new HistoryDao(_QhState.Context)
    }
    return this.historyDb
  }

  /**
   * 更新联想列表（按设置的建议来源：收藏/书签/标签页/历史浏览/搜索引擎/搜索历史）
   */
  async updateSuggestions(input: string, incognito: boolean): Promise<void> {
    this.inputText = input
    const keyword = input.trim()
    const seq = ++this.requestSeq
    if (!keyword) {
      this.suggestions = []
      return
    }

    const result: SuggestItem[] = []
    const kw = keyword.toLowerCase()

    // 输入即 URL 时，直接给出导航项
    if (UrlUtils.isLikelyUrl(keyword)) {
      result.push(new SuggestItem(SuggestType.HISTORY, keyword, UrlUtils.normalizeUrl(keyword)))
    }

    // 搜索历史
    if (!incognito && appSettings.isSuggestSourceOn('search_history')) {
      try {
        const histories = await this.getDB().queryByKeywordLike(keyword, 3)
        for (const h of histories) {
          result.push(new SuggestItem(SuggestType.SEARCH_HISTORY, h.keyword))
        }
      } catch (e) {
        logger.error('updateSuggestions', `搜索历史查询失败: ${e}`)
      }
    }

    // 收藏（主页快捷图标）
    if (appSettings.isSuggestSourceOn('favorites')) {
      try {
        const favs = await this.getBookmarkDB().queryQuick()
        let count = 0
        for (const b of favs) {
          if (count >= 3) break
          if (b.title.toLowerCase().includes(kw) || b.url.toLowerCase().includes(kw)) {
            result.push(new SuggestItem(SuggestType.FAVORITES, b.title, b.url))
            count++
          }
        }
      } catch (e) {
        logger.error('updateSuggestions', `收藏查询失败: ${e}`)
      }
    }

    // 书签
    if (appSettings.isSuggestSourceOn('bookmarks')) {
      try {
        const marks = await this.getBookmarkDB().queryByKeywordLike(keyword, 3)
        for (const b of marks) {
          result.push(new SuggestItem(SuggestType.BOOKMARK, b.title, b.url))
        }
      } catch (e) {
        logger.error('updateSuggestions', `书签查询失败: ${e}`)
      }
    }

    // 标签页
    if (appSettings.isSuggestSourceOn('tabs')) {
      let count = 0
      for (const t of tabsVM.tabs) {
        if (count >= 3) break
        if (t.isHome) continue
        if (t.title.toLowerCase().includes(kw) || t.url.toLowerCase().includes(kw)) {
          result.push(new SuggestItem(SuggestType.TAB, t.title, t.url, t.id))
          count++
        }
      }
    }

    // 历史浏览
    if (!incognito && appSettings.isSuggestSourceOn('history')) {
      try {
        const hs = await this.getHistoryDB().queryByKeywordLike(keyword, 3)
        for (const h of hs) {
          result.push(new SuggestItem(SuggestType.HISTORY, h.title, h.url))
        }
      } catch (e) {
        logger.error('updateSuggestions', `历史浏览查询失败: ${e}`)
      }
    }

    // 联网联想（搜索引擎建议）
    if (appSettings.isSuggestSourceOn('engine')) {
      const engine = SearchEngines.getCurrentEngine()
      const suggests = await this.fetchSuggest(engine, keyword)
      for (const s of suggests) {
        result.push(new SuggestItem(SuggestType.NETWORK_SUGGEST, s))
      }
    }

    // 防止过期请求覆盖新输入
    if (seq !== this.requestSeq) return
    this.suggestions = result.slice(0, 12)
  }

  /**
   * 保存搜索历史（无痕由调用方过滤）
   */
  async saveSearch(keyword: string, incognito: boolean): Promise<void> {
    const kw = keyword.trim()
    if (!kw || incognito) return
    try {
      await this.getDB().saveOrUpdate(kw)
    } catch (e) {
      logger.error('saveSearch', `${e}`)
    }
  }

  /**
   * 清空联想
   */
  clear(): void {
    this.requestSeq++
    this.suggestions = []
    this.inputText = ''
  }

  /**
   * 联网获取搜索联想
   */
  private async fetchSuggest(engine: SearchEngine, keyword: string): Promise<string[]> {
    const url = SearchEngines.buildSuggestUrl(engine, keyword)
    if (!url) return []
    return new Promise<string[]>((resolve: (value: string[]) => void) => {
      const httpReq = http.createHttp()
      httpReq.request(url, {
        connectTimeout: 3000,
        readTimeout: 3000,
        usingCache: false
      }).then((resp: http.HttpResponse) => {
        const out: string[] = []
        if (resp.responseCode === 200 && typeof resp.result === 'string') {
          try {
            const data = JSON.parse(resp.result) as Object[]
            if (data && data.length > 1) {
              const list = data[1] as Object[]
              if (list) {
                for (const item of list) {
                  if (typeof item === 'string') {
                    out.push(item)
                  }
                }
              }
            }
          } catch (e) {
            logger.warn('fetchSuggest', `联想解析失败: ${e}`)
          }
        }
        resolve(out.slice(0, 6))
      }).catch((e: Object) => {
        logger.warn('fetchSuggest', `联想请求失败: ${e}`)
        resolve([])
      }).finally(() => {
        httpReq.destroy()
      })
    })
  }
}

/**
 * 搜索历史页面辅助 VM（管理搜索历史列表）
 */
@ObservedV2
export class SearchHistoryViewModel {
  @Trace items: SearchHistoryInfo[] = []
  @Trace isLoading: boolean = false

  private db: SearchHistoryDao | null = null

  private getDB(): SearchHistoryDao {
    if (!this.db) {
      this.db = new SearchHistoryDao(_QhState.Context)
    }
    return this.db
  }

  async loadAll(): Promise<void> {
    this.isLoading = true
    try {
      this.items = await this.getDB().queryRecent(500)
    } catch (e) {
      logger.error('loadAll', `${e}`)
    }
    this.isLoading = false
  }

  async deleteById(id: number): Promise<void> {
    await this.getDB().deleteById(id)
    await this.loadAll()
  }

  async clearAll(): Promise<void> {
    await this.getDB().clearAll()
    await this.loadAll()
  }
}

export const searchVM = new SearchViewModel()
export const searchHistoryVM = new SearchHistoryViewModel()
