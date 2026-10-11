import { http } from '@kit.NetworkKit';
import { _QhState } from '../entryability/AppState';
import SearchHistoryInfo from '../common/entity/SearchHistoryInfo';
import { SearchHistoryDao } from '../common/utils/database/impl/SearchHistoryDao';
import { SearchEngine, SearchEngines, UrlUtils } from '../common/constants/SearchEngines';
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

  constructor(type: SuggestType, text: string, url: string = '') {
    this.type = type
    this.text = text
    this.url = url
  }
}

@ObservedV2
export class SearchViewModel {
  @Trace suggestions: SuggestItem[] = []
  @Trace inputText: string = ''

  private db: SearchHistoryDao | null = null
  private requestSeq: number = 0

  constructor() {
  }

  private getDB(): SearchHistoryDao {
    if (!this.db) {
      this.db = new SearchHistoryDao(_QhState.Context)
    }
    return this.db
  }

  /**
   * 更新联想列表（本地历史 + 书签 + 浏览历史 + 联网联想）
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

    // 输入即 URL 时，直接给出导航项
    if (UrlUtils.isLikelyUrl(keyword)) {
      result.push(new SuggestItem(SuggestType.HISTORY, keyword, UrlUtils.normalizeUrl(keyword)))
    }

    // 搜索历史
    if (!incognito) {
      try {
        const histories = await this.getDB().queryByKeywordLike(keyword, 3)
        for (const h of histories) {
          result.push(new SuggestItem(SuggestType.SEARCH_HISTORY, h.keyword))
        }
      } catch (e) {
        logger.error('updateSuggestions', `搜索历史查询失败: ${e}`)
      }
    }

    // 联网联想（搜索建议）
    const engine = SearchEngines.getCurrentEngine()
    const suggests = await this.fetchSuggest(engine, keyword)
    for (const s of suggests) {
      result.push(new SuggestItem(SuggestType.NETWORK_SUGGEST, s))
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
