import { request } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { _QhState } from '../entryability/AppState';
import DownloadRecordInfo from '../common/entity/DownloadRecordInfo';
import { DownloadRecordDao } from '../common/utils/database/impl/DownloadRecordDao';
import { AppConstants } from '../common/constants/AppConstants';
import { UrlUtils } from '../common/constants/SearchEngines';
import { createLogger } from '../common/utils/Logger';
import { toastUtil } from '../common/utils/ToastUtils';

const logger = createLogger('DownloadViewModel')

@ObservedV2
export class DownloadViewModel {
  @Trace records: DownloadRecordInfo[] = []
  @Trace isLoading: boolean = false

  private db: DownloadRecordDao | null = null

  constructor() {
  }

  private getDB(): DownloadRecordDao {
    if (!this.db) {
      this.db = new DownloadRecordDao(_QhState.Context)
    }
    return this.db
  }

  /**
   * 下载目录（确保存在）
   */
  private ensureDownloadDir(): string {
    const dir = `${_QhState.Context.filesDir}/${AppConstants.DOWNLOAD_DIR}`
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true)
    }
    return dir
  }

  async loadAll(): Promise<void> {
    this.isLoading = true
    try {
      this.records = await this.getDB().queryAll()
    } catch (e) {
      logger.error('loadAll', `${e}`)
    }
    this.isLoading = false
  }

  /**
   * 发起下载并落库
   */
  async download(url: string): Promise<void> {
    if (!url) return
    try {
      const dir = this.ensureDownloadDir()
      let fileName = UrlUtils.fileNameOf(url)
      if (!fileName) {
        fileName = `download_${new Date().getTime()}`
      }
      const dest = `${dir}/${fileName}`
      const record = new DownloadRecordInfo(url, fileName, dest, 'downloading')
      await this.getDB().saveOrUpdate(record)
      await this.loadAll()

      const task = await request.downloadFile(_QhState.Context, { url: url, filePath: dest })
      task.on('complete', async () => {
        await this.updateStatusByPath(dest, 'completed')
        toastUtil.showToast({ message: $r('app.string.download_completed') })
      })
      task.on('remove', async () => {
        await this.updateStatusByPath(dest, 'failed')
      })
      task.on('fail', async (err: number) => {
        logger.error('download', `下载失败 code=${err}`)
        await this.updateStatusByPath(dest, 'failed')
        toastUtil.showToast({ message: $r('app.string.download_failed') })
      })
      toastUtil.showToast({ message: $r('app.string.download_started') })
    } catch (e) {
      logger.error('download', `${e}`)
      toastUtil.showToast({ message: $r('app.string.download_failed') })
    }
  }

  private async updateStatusByPath(path: string, status: string): Promise<void> {
    try {
      const existing = await this.getDB().queryByPath(path)
      if (existing && existing.id !== null) {
        await this.getDB().updateStatus(existing.id, status)
      }
      await this.loadAll()
    } catch (e) {
      logger.error('updateStatusByPath', `${e}`)
    }
  }

  async deleteRecord(id: number): Promise<void> {
    await this.getDB().deleteById(id)
    await this.loadAll()
  }

  async clearAll(): Promise<void> {
    await this.getDB().clearAll()
    await this.loadAll()
  }
}

export const downloadVM = new DownloadViewModel()
