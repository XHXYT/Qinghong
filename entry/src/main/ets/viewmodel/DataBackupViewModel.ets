import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { _QhState } from '../entryability/AppState';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import HistoryInfo from '../common/entity/HistoryInfo';
import { BookmarkDao } from '../common/utils/database/impl/BookmarkDao';
import { HistoryDao } from '../common/utils/database/impl/HistoryDao';
import { appSettings } from '../common/entity/SettingsModel';
import { createLogger } from '../common/utils/app/Logger';
import { PublicDownloadDir } from '../common/utils/download/PublicDownloadDir';

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
   * 导出书签为 Netscape HTML 书签文件（Chrome/Firefox 通用格式，含文件夹层级）；无书签返回空串
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
    DataBackupViewModel.writeFolderHtml(lines, '', '    ', all)
    lines.push('</DL><p>')
    return lines.join('\n')
  }

  /** 递归写出文件夹层级（先本层书签，再按出现序子文件夹） */
  private static writeFolderHtml(lines: string[], folder: string, indent: string, all: BookmarkInfo[]): void {
    for (const b of all) {
      if (b.folder === folder) {
        lines.push(`${indent}<DT><A HREF="${DataBackupViewModel.escapeHtml(b.url)}" ` +
          `ADD_DATE="${Math.floor(b.createTime / 1000)}">${DataBackupViewModel.escapeHtml(b.title)}</A>`)
      }
    }
    const emitted: string[] = []
    for (const b of all) {
      if (b.folder !== '' && !emitted.includes(b.folder)
        && DataBackupViewModel.parentPathOf(b.folder) === folder) {
        emitted.push(b.folder)
        lines.push(`${indent}<DT><H3>${DataBackupViewModel.escapeHtml(
          DataBackupViewModel.lastSegmentOf(b.folder))}</H3>`)
        lines.push(`${indent}<DL><p>`)
        DataBackupViewModel.writeFolderHtml(lines, b.folder, `${indent}    `, all)
        lines.push(`${indent}</DL><p>`)
      }
    }
  }

  /** 父级路径（'' = 根） */
  private static parentPathOf(path: string): string {
    const idx: number = path.lastIndexOf('/')
    return idx < 0 ? '' : path.substring(0, idx)
  }

  /** 末级名称 */
  private static lastSegmentOf(path: string): string {
    const idx: number = path.lastIndexOf('/')
    return idx < 0 ? path : path.substring(idx + 1)
  }

  /**
   * 从 URI（文件选择器返回的书签 HTML）导入书签，返回导入条数
   */
  async importBookmarksFromUri(uri: string): Promise<number> {
    return this.importBookmarksFromContent(await DataBackupViewModel.readTextFromUri(uri))
  }

  /**
   * 按 URL 去重插入/更新，并强制覆盖 createTime 与 folder
   * （导入场景需覆盖已有行的时间戳/文件夹以还原文件内的顺序与层级）
   */
  private async upsertImported(info: BookmarkInfo): Promise<void> {
    const existing: BookmarkInfo | null = await this.getBookmarkDB().queryByUrl(info.url)
    if (existing !== null) {
      existing.title = info.title
      existing.isQuick = info.isQuick || existing.isQuick
      existing.folder = info.folder
      existing.createTime = info.createTime
      await this.getBookmarkDB().update(existing)
    } else {
      await this.getBookmarkDB().insert(info)
    }
  }

  /**
   * 解析 Netscape 书签 HTML 并导入（按 URL 去重，保留文件夹层级），返回导入条数
   */
  async importBookmarksFromContent(content: string): Promise<number> {
    if (!content) {
      return 0
    }
    // 按出现顺序扫描：H3 文件夹名 / DL 开闭 / 书签 A 标签
    const tokenizer: RegExp = /(?:<DT>\s*)?<H3[^>]*>([\s\S]*?)<\/H3\s*>|<DL[^>]*>|<\/DL\s*>|<A\s[^>]*HREF="([^"]*)"[^>]*>([\s\S]*?)<\/A\s*>/gi
    const stack: string[] = []
    let pendingFolder: string | null = null
    let count: number = 0
    // 展示按 create_time 倒序：按文档顺序递减时间戳，保证文件内顺序与展示顺序一致
    const baseTime: number = new Date().getTime()
    let match: RegExpExecArray | null = tokenizer.exec(content)
    while (match !== null) {
      if (match[1] !== undefined) {
        pendingFolder = DataBackupViewModel.decodeEntities(match[1]).trim()
      } else if (match[2] !== undefined) {
        const url: string = DataBackupViewModel.decodeEntities(match[2]).trim()
        if (url !== '') {
          const title: string = DataBackupViewModel.decodeEntities(match[3]).trim()
          const info: BookmarkInfo = new BookmarkInfo(title || url, url)
          info.folder = stack.filter((s: string): boolean => s !== '').join('/')
          info.createTime = baseTime - count
          await this.upsertImported(info)
          count++
        }
      } else if (match[0].substring(0, 3).toUpperCase() === '<DL') {
        // 进入新层级：有前置 H3 则为文件夹层，否则沿用父级路径
        stack.push(pendingFolder ?? '')
        pendingFolder = null
      } else if (stack.length > 0) {
        stack.pop()
      }
      match = tokenizer.exec(content)
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
          'folder': b.folder,
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
        const baseTime: number = new Date().getTime()
        let idx: number = 0
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const url: string = (rec['url'] as string) ?? ''
          if (url === '') {
            continue
          }
          const title: string = (rec['title'] as string) ?? url
          const info: BookmarkInfo = new BookmarkInfo(title, url, (rec['is_quick'] as boolean) ?? false)
          info.folder = (rec['folder'] as string) ?? ''
          info.createTime = (rec['create_time'] as number) ?? (baseTime - idx)
          await this.upsertImported(info)
          idx++
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

  /**
   * 将文本写入公共下载目录 Download/<本应用包名>/backup/<fileName>（授权由 PublicDownloadDir 统一处理）
   */
  static async writeBackupFile(fileName: string, text: string): Promise<void> {
    const dir: string = await PublicDownloadDir.ensureDir('backup')
    PublicDownloadDir.writeText(dir, fileName, text)
  }

  /**
   * 将 PDF 二进制写入公共下载目录 Download/<本应用包名>/PDF/<fileName>，返回文件真实路径
   * （授权由 PublicDownloadDir 统一处理）
   */
  static async writePdfFile(fileName: string, data: Uint8Array): Promise<string> {
    const dir: string = await PublicDownloadDir.ensureDir('PDF')
    PublicDownloadDir.writeBytes(dir, fileName, data)
    return `${dir}/${fileName}`
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
