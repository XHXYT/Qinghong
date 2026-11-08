import { _QhState } from '../entryability/AppState';
import HistoryInfo from '../common/entity/HistoryInfo';
import { HistoryDao } from '../common/utils/database/impl/HistoryDao';
import { createLogger } from '../common/utils/app/Logger';

const logger = createLogger('HistoryViewModel')

@ObservedV2
export class HistoryViewModel {
  @Trace histories: HistoryInfo[] = []
  @Trace isLoading: boolean = false

  private db: HistoryDao | null = null

  constructor() {
  }

  private getDB(): HistoryDao {
    if (!this.db) {
      this.db = new HistoryDao(_QhState.Context)
    }
    return this.db
  }

  async loadAll(): Promise<void> {
    this.isLoading = true
    try {
      this.histories = await this.getDB().queryRecent()
    } catch (e) {
      logger.error('loadAll', `${e}`)
    }
    this.isLoading = false
  }

  /**
   * 记录一次访问（无痕由调用方过滤）
   */
  async addVisit(title: string, url: string): Promise<void> {
    if (!url) return
    try {
      await this.getDB().addVisit(title, url)
    } catch (e) {
      logger.error('addVisit', `${e}`)
    }
  }

  async deleteById(id: number): Promise<void> {
    await this.getDB().deleteById(id)
    await this.loadAll()
  }

  /** 批量删除（多选编辑栏） */
  async deleteByIds(ids: number[]): Promise<void> {
    if (ids.length === 0) {
      return
    }
    await this.getDB().deleteByIds(ids)
    await this.loadAll()
  }

  async deleteByUrl(url: string): Promise<void> {
    await this.getDB().deleteByUrl(url)
    await this.loadAll()
  }

  async clearAll(): Promise<void> {
    await this.getDB().clearAll()
    await this.loadAll()
  }
}

export const historyVM = new HistoryViewModel()
