import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { bundleManager } from '@kit.AbilityKit';
import { _QhState } from '../entryability/AppState';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import HistoryInfo from '../common/entity/HistoryInfo';
import { BookmarkDao } from '../common/utils/database/impl/BookmarkDao';
import { HistoryDao } from '../common/utils/database/impl/HistoryDao';
import { appSettings } from '../common/entity/SettingsModel';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('DataBackup')

/**
 * 数据备份/导入：书签 HTML（Netscape 格式）与全量数据 JSON
 */
export class DataBackupViewModel {

  private bookmarkDb: BookmarkDao | null = null
  private historyDb: HistoryDao | null = null

  private getBookmarkDB(): BookmarkDao {
    if (this.bookmarkDb === null) {
      this.bookmarkDb = new BookmarkDao(_QhState.Context)
    }
    return this.bookmarkDb
  }

  private getHistoryDB(): HistoryDao {
    if (this.historyDb === null) {
      this.historyDb = new HistoryDao(_QhState.Context)
    }
    return this.historyDb
  }

  /**
   * 导出书签为 Netscape HTML 书签文件（Chrome/Firefox 通用格式）；无书签返回空串
   */
  async exportBookmarksHtml(): Promise<string> {
    const all: BookmarkInfo[] = await this.getBookmarkDB().queryAll()
    if (all.length === 0) {
      return ''
    }
    const lines: string[] = [
      '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
      '<!-- This is an automatically generated file. It will be read and overwritten. DO NOT EDIT! -->',
      '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
      '<TITLE>Bookmarks</TITLE>',
      '<H1>Bookmarks</H1>',
      '<DL><p>'
    ]
    for (const b of all) {
      lines.push(`    <DT><A HREF="${DataBackupViewModel.escapeHtml(b.url)}" ` +
        `ADD_DATE="${Math.floor(b.createTime / 1000)}">${DataBackupViewModel.escapeHtml(b.title)}</A>`)
    }
    lines.push('</DL><p>')
    return lines.join('\n')
  }

  /**
   * 从 URI（文件选择器返回的书签 HTML）导入书签，返回导入条数
   */
  async importBookmarksFromUri(uri: string): Promise<number> {
    return this.importBookmarksFromContent(await DataBackupViewModel.readTextFromUri(uri))
  }

  /**
   * 解析 Netscape 书签 HTML 并导入（按 URL 去重），返回导入条数
   */
  async importBookmarksFromContent(content: string): Promise<number> {
    if (!content) {
      return 0
    }
    const re = /<A\s[^>]*HREF="([^"]*)"[^>]*>([\s\S]*?)<\/A>/gi
    let count: number = 0
    let match: RegExpExecArray | null = re.exec(content)
    while (match !== null) {
      const url: string = DataBackupViewModel.decodeEntities(match[1]).trim()
      const title: string = DataBackupViewModel.decodeEntities(match[2]).trim()
      if (url !== '') {
        await this.getBookmarkDB().saveOrUpdate(new BookmarkInfo(title || url, url))
        count++
      }
      match = re.exec(content)
    }
    return count
  }

  /**
   * 导出全量数据 JSON（书签/历史/设置），返回 JSON 文本
   */
  async exportDataJson(exportBookmarks: boolean, exportHistory: boolean,
    exportSettings: boolean): Promise<string> {
    const payload: Record<string, Object> = {
      'app': 'qinghong',
      'version': 1,
      'export_time': new Date().getTime()
    }
    if (exportBookmarks) {
      const all: BookmarkInfo[] = await this.getBookmarkDB().queryAll()
      const arr: Record<string, Object>[] = []
      for (const b of all) {
        arr.push({
          'title': b.title,
          'url': b.url,
          'is_quick': b.isQuick,
          'create_time': b.createTime
        })
      }
      payload['bookmarks'] = arr
    }
    if (exportHistory) {
      const all: HistoryInfo[] = await this.getHistoryDB().queryRecent(1000)
      const arr: Record<string, Object>[] = []
      for (const h of all) {
        arr.push({
          'title': h.title,
          'url': h.url,
          'visit_time': h.visitTime
        })
      }
      payload['history'] = arr
    }
    if (exportSettings) {
      payload['settings'] = appSettings.toSyncData()
    }
    return JSON.stringify(payload)
  }

  /**
   * 从 URI（文件选择器返回的 JSON 备份）导入数据，返回是否成功
   */
  async importDataFromUri(uri: string): Promise<boolean> {
    return this.importDataFromContent(await DataBackupViewModel.readTextFromUri(uri))
  }

  /**
   * 解析 JSON 备份并恢复（书签/历史/设置），返回是否成功
   */
  async importDataFromContent(content: string): Promise<boolean> {
    if (!content) {
      return false
    }
    try {
      const raw: Record<string, Object> = JSON.parse(content) as Record<string, Object>
      if ((raw['app'] as string) !== 'qinghong') {
        return false
      }
      const bookmarks = raw['bookmarks']
      if (bookmarks !== undefined && bookmarks !== null) {
        const arr: Object[] = bookmarks as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const url: string = (rec['url'] as string) ?? ''
          if (url === '') {
            continue
          }
          const title: string = (rec['title'] as string) ?? url
          const info: BookmarkInfo = new BookmarkInfo(title, url, (rec['is_quick'] as boolean) ?? false)
          info.createTime = (rec['create_time'] as number) ?? new Date().getTime()
          await this.getBookmarkDB().saveOrUpdate(info)
        }
      }
      const history = raw['history']
      if (history !== undefined && history !== null) {
        const arr: Object[] = history as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const url: string = (rec['url'] as string) ?? ''
          if (url === '') {
            continue
          }
          const title: string = (rec['title'] as string) ?? url
          await this.getHistoryDB().addVisit(title, url)
        }
      }
      const settings = raw['settings']
      if (settings !== undefined && settings !== null) {
        appSettings.applySyncData(settings as Record<string, Object>)
        appSettings.save()
      }
      logger.info('importData', '数据导入完成')
      return true
    } catch (e) {
      logger.error('importData', `${e}`)
      return false
    }
  }

  /** 备份文件目录：公共下载目录 Download/<本应用包名>/backup（真实路径） */
  static getBackupDir(): string {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
    const uri: string = `file://docs/storage/Users/currentUser/Download/${info.name}/backup`
    return new fileUri.FileUri(uri).path
  }

  /** 直接在备份目录写文本（目录不存在则创建） */
  private static writeTextDirect(dir: string, fileName: string, text: string): void {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true)
    }
    const file: fileIo.File = fileIo.openSync(`${dir}/${fileName}`,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, text)
    } finally {
      fileIo.closeSync(file)
    }
  }

  /**
   * 将文本写入公共下载目录 Download/<本应用包名>/backup/<fileName>。
   * 包名目录未创建（首次导出无访问权限）时，先走系统 DOWNLOAD 保存流程：
   * 无界面，由系统自动创建 Download/<包名> 并授予访问权限，随后重试直接写入。
   */
  static async writeBackupFile(fileName: string, text: string): Promise<void> {
    const dir: string = DataBackupViewModel.getBackupDir()
    try {
      DataBackupViewModel.writeTextDirect(dir, fileName, text)
      return
    } catch (e) {
      logger.info('writeBackupFile', '直接写入失败，走 DOWNLOAD 系统授权流程')
    }
    const svPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(_QhState.Context)
    const options: picker.DocumentSaveOptions = {
      pickerMode: picker.DocumentPickerMode.DOWNLOAD
    }
    const uris: string[] = await svPicker.save(options)
    if (uris.length === 0) {
      throw new Error('DOWNLOAD 保存流程未返回文件 URI')
    }
    // 系统会预创建空文件，删除后写入正式备份文件
    try {
      fileIo.unlinkSync(new fileUri.FileUri(uris[0]).path)
    } catch (e) {
      logger.error('writeBackupFile', `删除预创建文件失败: ${e}`)
    }
    DataBackupViewModel.writeTextDirect(dir, fileName, text)
  }

  static async readTextFromUri(uri: string): Promise<string> {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd)
      const buf: ArrayBuffer = new ArrayBuffer(stat.size)
      let total: number = 0
      while (total < stat.size) {
        const n: number = fileIo.readSync(file.fd, buf, { offset: total })
        if (n <= 0) {
          break
        }
        total += n
      }
      return buffer.from(buf).toString('utf-8')
    } finally {
      fileIo.closeSync(file)
    }
  }

  private static escapeHtml(v: string): string {
    return v.replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  }

  private static decodeEntities(v: string): string {
    return v.replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&#39;/g, '\'')
      .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  }
}

export const dataBackupVM = new DataBackupViewModel()
