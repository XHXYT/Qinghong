import { fileIo } from '@kit.CoreFileKit';
import { _QhState } from '../entryability/AppState';
import OfflinePageInfo from '../common/entity/OfflinePageInfo';
import { OfflinePageDao } from '../common/utils/database/impl/OfflinePageDao';
import { createLogger } from '../common/utils/app/Logger';
import { toastUtil } from '../common/utils/ui/ToastUtils';

const logger = createLogger('OfflinePageViewModel')

@ObservedV2
export class OfflinePageViewModel {
  @Trace records: OfflinePageInfo[] = []

  private db: OfflinePageDao | null = null

  constructor() {
  }

  private getDB(): OfflinePageDao {
    if (!this.db) {
      this.db = new OfflinePageDao(_QhState.Context)
    }
    return this.db
  }

  async loadAll(): Promise<void> {
    try {
      this.records = await this.getDB().queryAll()
    } catch (e) {
      logger.error('loadAll', `${e}`)
    }
  }

  /**
   * 保存离线页面记录（离线档文件写入公共目录成功后调用）
   */
  async saveRecord(url: string, name: string, path: string): Promise<void> {
    try {
      await this.getDB().insert(new OfflinePageInfo(name, url, path))
      await this.loadAll()
      toastUtil.showToast({ message: $r('app.string.offline_saved') })
    } catch (e) {
      logger.error('saveRecord', `${e}`)
      toastUtil.showToast({ message: $r('app.string.offline_save_failed') })
    }
  }

  /**
   * 删除记录并清理离线档文件（文件不存在忽略）
   */
  async deleteRecord(id: number, path: string): Promise<void> {
    try {
      if (path !== '' && fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (e) {
      logger.error('deleteRecord', `${e}`)
    }
    await this.getDB().deleteById(id)
    await this.loadAll()
  }
}

export const offlinePageVM = new OfflinePageViewModel()
