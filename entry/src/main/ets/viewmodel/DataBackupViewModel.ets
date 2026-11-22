import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { _QhState } from '../entryability/AppState';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import HistoryInfo from '../common/entity/HistoryInfo';
import SearchHistoryInfo from '../common/entity/SearchHistoryInfo';
import DownloadRecordInfo from '../common/entity/DownloadRecordInfo';
import SiteSettingInfo from '../common/entity/SiteSettingInfo';
import HostsRuleInfo from '../common/entity/HostsRuleInfo';
import UserScriptInfo from '../common/entity/UserScriptInfo';
import UserScriptValue from '../common/entity/UserScriptValue';
import ExtensionInfo from '../common/entity/ExtensionInfo';
import ExtensionValue from '../common/entity/ExtensionValue';
import { BookmarkDao } from '../common/utils/database/impl/BookmarkDao';
import { HistoryDao } from '../common/utils/database/impl/HistoryDao';
import { SearchHistoryDao } from '../common/utils/database/impl/SearchHistoryDao';
import { DownloadRecordDao } from '../common/utils/database/impl/DownloadRecordDao';
import { SiteSettingDao } from '../common/utils/database/impl/SiteSettingDao';
import { HostsDao } from '../common/utils/database/impl/HostsDao';
import { UserScriptDao } from '../common/utils/database/impl/UserScriptDao';
import { UserScriptValueDao } from '../common/utils/database/impl/UserScriptValueDao';
import { ExtensionDao } from '../common/utils/database/impl/ExtensionDao';
import { ExtensionValueDao } from '../common/utils/database/impl/ExtensionValueDao';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { UserScriptEngine } from '../common/utils/userscript/UserScriptEngine';
import { adBlockSubsStore, AdBlockSubscription } from '../common/utils/adblock/AdBlockSubs';
import { extensionVM } from './ExtensionViewModel';
import { scriptVM } from './ScriptViewModel';
import { tabsVM } from './TabsViewModel';
import { AppConstants } from '../common/constants/AppConstants';
import { HomeImageUtil } from '../common/utils/home/HomeImageUtil';
import { createLogger } from '../common/utils/app/Logger';
import { PublicDownloadDir } from '../common/utils/download/PublicDownloadDir';

const logger = createLogger('DataBackup')

/** Via 安卓版导出内 script 元数据（settings.txt 的 {"script":{...}} 行） */
class ViaScriptMeta {
  url: string = ''
  enabled: boolean = true
}

/** Via 安卓版导出内会话标签（tabs.txt 单行） */
class ViaTabEntry {
  title: string = ''
  url: string = ''
  updated: number = 0
}

/**
 * 数据备份/导入：书签 HTML（Netscape 格式）与全量数据 JSON
 */
export class DataBackupViewModel {

  private bookmarkDb: BookmarkDao | null = null
  private historyDb: HistoryDao | null = null
  private searchHistoryDb: SearchHistoryDao | null = null
  private downloadDb: DownloadRecordDao | null = null
  private siteSettingDb: SiteSettingDao | null = null
  private hostsDb: HostsDao | null = null
  private userScriptDb: UserScriptDao | null = null
  private userScriptValueDb: UserScriptValueDao | null = null
  private extensionDb: ExtensionDao | null = null
  private extensionValueDb: ExtensionValueDao | null = null

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

  private getSearchHistoryDB(): SearchHistoryDao {
    if (this.searchHistoryDb === null) {
      this.searchHistoryDb = new SearchHistoryDao(_QhState.Context)
    }
    return this.searchHistoryDb
  }

  private getDownloadDB(): DownloadRecordDao {
    if (this.downloadDb === null) {
      this.downloadDb = new DownloadRecordDao(_QhState.Context)
    }
    return this.downloadDb
  }

  private getSiteSettingDB(): SiteSettingDao {
    if (this.siteSettingDb === null) {
      this.siteSettingDb = new SiteSettingDao(_QhState.Context)
    }
    return this.siteSettingDb
  }

  private getHostsDB(): HostsDao {
    if (this.hostsDb === null) {
      this.hostsDb = new HostsDao(_QhState.Context)
    }
    return this.hostsDb
  }

  private getUserScriptDB(): UserScriptDao {
    if (this.userScriptDb === null) {
      this.userScriptDb = new UserScriptDao(_QhState.Context)
    }
    return this.userScriptDb
  }

  private getUserScriptValueDB(): UserScriptValueDao {
    if (this.userScriptValueDb === null) {
      this.userScriptValueDb = new UserScriptValueDao(_QhState.Context)
    }
    return this.userScriptValueDb
  }

  private getExtensionDB(): ExtensionDao {
    if (this.extensionDb === null) {
      this.extensionDb = new ExtensionDao(_QhState.Context)
    }
    return this.extensionDb
  }

  private getExtensionValueDB(): ExtensionValueDao {
    if (this.extensionValueDb === null) {
      this.extensionValueDb = new ExtensionValueDao(_QhState.Context)
    }
    return this.extensionValueDb
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
   * 导出数据 JSON，返回 JSON 文本；按勾选项导出对应数据段：
   * 0 书签 / 1 历史 / 2 设置（应用设置+界面设置） / 3 搜索历史 / 4 下载记录 /
   * 5 站点设置 / 6 hosts / 7 广告拦截规则订阅 / 8 用户脚本 / 9 扩展
   */
  async exportDataJson(sel: boolean[]): Promise<string> {
    const payload: Record<string, Object> = {
      'app': 'qinghong',
      'version': 2,
      'export_time': new Date().getTime()
    }
    if (sel[0]) {
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
    if (sel[1]) {
      const all: HistoryInfo[] = await this.getHistoryDB().queryAll()
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
    if (sel[2]) {
      payload['settings'] = appSettings.toSyncData()
      payload['ui_settings'] = UISettings.toSyncData()
    }
    if (sel[3]) {
      const all: SearchHistoryInfo[] = await this.getSearchHistoryDB().queryAll()
      const arr: Record<string, Object>[] = []
      for (const s of all) {
        arr.push({
          'keyword': s.keyword,
          'visit_time': s.visitTime
        })
      }
      payload['search_history'] = arr
    }
    if (sel[4]) {
      const all: DownloadRecordInfo[] = await this.getDownloadDB().queryAll()
      const arr: Record<string, Object>[] = []
      for (const d of all) {
        arr.push({
          'url': d.url,
          'file_name': d.fileName,
          'path': d.path,
          'status': d.status,
          'received_size': d.receivedSize,
          'total_size': d.totalSize,
          'seg_index': d.segIndex,
          'is_hls': d.isHls,
          'referer': d.referer,
          'create_time': d.createTime
        })
      }
      payload['download_records'] = arr
    }
    if (sel[5]) {
      const all: SiteSettingInfo[] = await this.getSiteSettingDB().listAll()
      const arr: Record<string, Object>[] = []
      for (const s of all) {
        arr.push({
          'site': s.site,
          'key': s.key,
          'value': s.value
        })
      }
      payload['site_settings'] = arr
    }
    if (sel[6]) {
      const all: HostsRuleInfo[] = await this.getHostsDB().listAll()
      const arr: Record<string, Object>[] = []
      for (const r of all) {
        arr.push({
          'host': r.host,
          'ip': r.ip
        })
      }
      payload['hosts'] = arr
    }
    if (sel[7]) {
      await adBlockSubsStore.load()
      const subsArr: Record<string, Object>[] = []
      for (const s of adBlockSubsStore.subs) {
        subsArr.push({
          'url': s.url,
          'name': s.name,
          'enabled': s.enabled,
          'rule_count': s.ruleCount,
          'last_updated': s.lastUpdated
        })
      }
      const block: Record<string, Object> = {
        'interval': adBlockSubsStore.interval,
        'subs': subsArr
      }
      payload['ad_block'] = block
    }
    if (sel[8]) {
      const all: UserScriptInfo[] = await this.getUserScriptDB().queryAll()
      const arr: Record<string, Object>[] = []
      for (const s of all) {
        const valuesArr: Record<string, Object>[] = []
        const rows: UserScriptValue[] = await this.getUserScriptValueDB().queryByScript(s.id ?? -1)
        for (const v of rows) {
          valuesArr.push({
            'key': v.key,
            'value': v.value
          })
        }
        arr.push({
          'name': s.name,
          'version': s.version,
          'code': s.code,
          'enabled': s.enabled,
          'run_at': s.runAt,
          'matches': s.matches,
          'excludes': s.excludes,
          'update_url': s.updateUrl,
          'create_time': s.createTime,
          'update_time': s.updateTime,
          'grants': s.grants,
          'connects': s.connects,
          'requires': s.requires,
          'resources': s.resources,
          'noframes': s.noframes,
          'values': valuesArr
        })
      }
      payload['user_scripts'] = arr
    }
    if (sel[9]) {
      const all: ExtensionInfo[] = await this.getExtensionDB().queryAll()
      const arr: Record<string, Object>[] = []
      for (const e of all) {
        const valuesArr: Record<string, Object>[] = []
        const rows: ExtensionValue[] = await this.getExtensionValueDB().queryByExt(e.extId)
        for (const v of rows) {
          valuesArr.push({
            'key': v.key,
            'value': v.value
          })
        }
        arr.push({
          'ext_id': e.extId,
          'name': e.name,
          'version': e.version,
          'description': e.description,
          'manifest_version': e.manifestVersion,
          'enabled': e.enabled,
          'path': e.path,
          'manifest': e.manifest,
          'update_url': e.updateUrl,
          'create_time': e.createTime,
          'update_time': e.updateTime,
          'values': valuesArr
        })
      }
      payload['extensions'] = arr
    }
    return JSON.stringify(payload)
  }

  /**
   * 导出备份 zip 并写入 Download/<包名>/backup/qinghong_backup.zip：
   * backup.json（数据段按勾选项）+ home_media/（设置勾选时随行壁纸与 logo）+
   * extensions/<extId>/（扩展勾选时扩展解包文件）
   */
  async exportBackup(sel: boolean[]): Promise<void> {
    const filesDir: string = _QhState.Context.filesDir
    const cacheDir: string = _QhState.Context.cacheDir
    const stamp: number = new Date().getTime()
    const staging: string = `${cacheDir}/qinghong_export_${stamp}`
    const tmpZip: string = `${cacheDir}/qinghong_export_${stamp}.zip`
    try {
      const json: string = await this.exportDataJson(sel)
      DataBackupViewModel.removeDirQuiet(staging)
      DataBackupViewModel.ensureDir(staging)
      DataBackupViewModel.writeTextSync(`${staging}/backup.json`, json)
      if (sel[2] && fileIo.accessSync(`${filesDir}/home_media`)) {
        DataBackupViewModel.copyDir(`${filesDir}/home_media`, `${staging}/home_media`)
      }
      if (sel[9]) {
        const all: ExtensionInfo[] = await this.getExtensionDB().queryAll()
        for (const e of all) {
          const src: string = `${filesDir}/extensions/${e.extId}`
          if (fileIo.accessSync(src)) {
            DataBackupViewModel.copyDir(src, `${staging}/extensions/${e.extId}`)
          }
        }
      }
      await zlib.compressFile(staging, tmpZip, {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      })
      const bytes: Uint8Array = DataBackupViewModel.readBytesSync(tmpZip)
      const dir: string = await PublicDownloadDir.ensureDir('backup')
      PublicDownloadDir.writeBytes(dir, 'qinghong_backup.zip', bytes)
    } finally {
      DataBackupViewModel.removeDirQuiet(staging)
      DataBackupViewModel.unlinkQuiet(tmpZip)
    }
  }

  /**
   * 从 URI（文件选择器返回的 JSON/ZIP 备份）导入数据，返回是否成功；
   * 按文件头自动识别：PK 开头走 zip（backup.json + 文件目录），否则按纯 JSON 解析
   */
  async importDataFromUri(uri: string): Promise<boolean> {
    const bytes: Uint8Array = await DataBackupViewModel.readBytesFromUri(uri)
    if (bytes.length >= 2 && bytes[0] === 0x50 && bytes[1] === 0x4B) {
      return await this.importZipFromBytes(bytes)
    }
    return this.importDataFromContent(buffer.from(bytes.buffer).toString('utf-8'), null)
  }

  /** 解压 zip 备份到缓存目录，定位 backup.json（根目录或一级子目录）后按数据段恢复 */
  private async importZipFromBytes(bytes: Uint8Array): Promise<boolean> {
    const cacheDir: string = _QhState.Context.cacheDir
    const stamp: number = new Date().getTime()
    const tmpZip: string = `${cacheDir}/qinghong_import_${stamp}.zip`
    const tmpDir: string = `${cacheDir}/qinghong_import_${stamp}`
    try {
      const buf: ArrayBuffer = new ArrayBuffer(bytes.byteLength)
      new Uint8Array(buf).set(bytes)
      const file: fileIo.File = fileIo.openSync(tmpZip,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, buf)
      } finally {
        fileIo.closeSync(file)
      }
      DataBackupViewModel.removeDirQuiet(tmpDir)
      DataBackupViewModel.ensureDir(tmpDir)
      await zlib.decompressFile(tmpZip, tmpDir)
      let base: string = tmpDir
      if (!fileIo.accessSync(`${tmpDir}/backup.json`)) {
        // 压缩目录时 zip 内可能带一层目录名
        const names: string[] = fileIo.listFileSync(tmpDir)
        let found: boolean = false
        for (const name of names) {
          const candidate: string = `${tmpDir}/${name}`
          if (fileIo.accessSync(`${candidate}/backup.json`)) {
            base = candidate
            found = true
            break
          }
        }
        if (!found) {
          // 非 Qinghong 备份：尝试识别 Via 安卓版导出（settings.txt + bookmarks.html 等）
          const viaBase: string | null = DataBackupViewModel.findViaBase(tmpDir)
          if (viaBase !== null) {
            return await this.importViaFromBase(viaBase)
          }
          logger.error('importZip', '备份 zip 中未找到 backup.json')
          return false
        }
      }
      const content: string = DataBackupViewModel.readTextSync(`${base}/backup.json`)
      return await this.importDataFromContent(content, base)
    } finally {
      DataBackupViewModel.unlinkQuiet(tmpZip)
      DataBackupViewModel.removeDirQuiet(tmpDir)
    }
  }

  /**
   * 导入 Via 安卓版导出目录：
   * bookmarks.html 书签（Netscape 格式，复用现有解析器）/ favorites.txt 主页收藏（转快速访问书签）
   * / history.txt 历史 / settings.txt 内 filters 广告规则订阅 + script 元数据 / script-*.txt 用户脚本
   * / tabs.txt 会话标签（按更新时间取前若干，容量上限内）/ bg.jpg 主页背景
   */
  private async importViaFromBase(base: string): Promise<boolean> {
    try {
      let imported: number = 0
      // 书签
      const bmPath: string = `${base}/bookmarks.html`
      if (DataBackupViewModel.exists(bmPath)) {
        imported += await this.importBookmarksFromContent(DataBackupViewModel.readTextSync(bmPath))
      }
      // 主页收藏 → 快速访问书签
      const favPath: string = `${base}/favorites.txt`
      if (DataBackupViewModel.exists(favPath)) {
        const lines: string[] = DataBackupViewModel.readTextSync(favPath).split('\n')
        for (const line of lines) {
          const rec: Record<string, Object> | null = DataBackupViewModel.parseJsonLine(line)
          if (rec === null) {
            continue
          }
          const url: string = (rec['url'] as string) ?? ''
          if (url === '') {
            continue
          }
          const title: string = (rec['title'] as string) ?? url
          const info: BookmarkInfo = new BookmarkInfo(title, url, true)
          info.folder = ''
          info.createTime = new Date().getTime() - imported
          await this.upsertImported(info)
          imported++
        }
      }
      // 历史（updated_at 秒级时间戳）
      const hisPath: string = `${base}/history.txt`
      if (DataBackupViewModel.exists(hisPath)) {
        const lines: string[] = DataBackupViewModel.readTextSync(hisPath).split('\n')
        for (const line of lines) {
          const rec: Record<string, Object> | null = DataBackupViewModel.parseJsonLine(line)
          if (rec === null) {
            continue
          }
          const url: string = (rec['url'] as string) ?? ''
          if (url === '') {
            continue
          }
          const title: string = (rec['title'] as string) ?? url
          let stamp: number = (rec['updated_at'] as number) ?? 0
          if (stamp > 0 && stamp < 1e12) {
            stamp *= 1000
          }
          await this.getHistoryDB().addVisit(title, url, stamp > 0 ? stamp : new Date().getTime())
        }
      }
      // settings.txt：filters 规则订阅 + script 元数据（按文件名索引）
      const scriptMeta: Record<string, ViaScriptMeta> = {}
      const setPath: string = `${base}/settings.txt`
      if (DataBackupViewModel.exists(setPath)) {
        const lines: string[] = DataBackupViewModel.readTextSync(setPath).split('\n')
        let subsLoaded: boolean = false
        for (const line of lines) {
          const rec: Record<string, Object> | null = DataBackupViewModel.parseJsonLine(line)
          if (rec === null) {
            continue
          }
          const filters: Object | undefined = rec['filters']
          if (filters !== undefined) {
            const f: Record<string, Object> = filters as Record<string, Object>
            const url: string = (f['url'] as string) ?? ''
            if (url === '') {
              continue
            }
            if (!subsLoaded) {
              await adBlockSubsStore.load()
              subsLoaded = true
            }
            adBlockSubsStore.add(url)
            const sub: AdBlockSubscription | null = DataBackupViewModel.findAdSub(url)
            if (sub !== null) {
              const title: string = (f['title'] as string) ?? ''
              if (title !== '') {
                adBlockSubsStore.edit(sub, title, url, false)
              }
              adBlockSubsStore.toggle(sub, (f['enabled'] as boolean) ?? true)
            }
            continue
          }
          const script: Object | undefined = rec['script']
          if (script !== undefined) {
            const s: Record<string, Object> = script as Record<string, Object>
            const path: string = (s['path'] as string) ?? ''
            if (path === '') {
              continue
            }
            const meta: ViaScriptMeta = new ViaScriptMeta()
            meta.url = (s['url'] as string) ?? ''
            meta.enabled = (s['enabled'] as boolean) ?? true
            scriptMeta[path] = meta
          }
        }
      }
      // 用户脚本：目录内全部 script-*.txt（含 settings.txt 未登记的本地脚本），按 settings 元数据带更新源/开关
      const names: string[] = fileIo.listFileSync(base)
      let scriptsImported: number = 0
      for (const name of names) {
        if (!name.startsWith('script-') || !name.endsWith('.txt')) {
          continue
        }
        const code: string = DataBackupViewModel.readTextSync(`${base}/${name}`)
        if (code.indexOf('==UserScript==') < 0) {
          logger.warn('importVia', `跳过非用户脚本文件: ${name}`)
          continue
        }
        const meta: ViaScriptMeta | undefined = scriptMeta[name]
        await scriptVM.addFromCode(code, meta === undefined ? '' : meta.url)
        scriptsImported++
        // Via 中已停用的脚本还原停用状态
        if (meta !== undefined && !meta.enabled) {
          const parsedName: string = UserScriptEngine.parseMeta(code).name
          const saved: UserScriptInfo | null = await this.getUserScriptDB().queryByName(parsedName)
          if (saved !== null) {
            saved.enabled = false
            await this.getUserScriptDB().update(saved)
          }
        }
      }
      if (scriptsImported > 0) {
        await scriptVM.loadAll()
      }
      // 会话标签：按更新时间降序去重（含当前已开标签），导入至剩余标签容量上限
      const tabsPath: string = `${base}/tabs.txt`
      if (DataBackupViewModel.exists(tabsPath)) {
        const entries: ViaTabEntry[] = []
        const tabLines: string[] = DataBackupViewModel.readTextSync(tabsPath).split('\n')
        for (const line of tabLines) {
          const rec: Record<string, Object> | null = DataBackupViewModel.parseJsonLine(line)
          if (rec === null) {
            continue
          }
          const url: string = (rec['url'] as string) ?? ''
          if (url === '' || url.startsWith('about:')) {
            continue
          }
          const e: ViaTabEntry = new ViaTabEntry()
          e.title = (rec['title'] as string) ?? url
          e.url = url
          e.updated = (rec['updated_at'] as number) ?? 0
          entries.push(e)
        }
        entries.sort((a: ViaTabEntry, b: ViaTabEntry): number => b.updated - a.updated)
        const seen: Set<string> = new Set<string>()
        for (const t of tabsVM.tabs) {
          seen.add(t.url)
        }
        const capacity: number = AppConstants.MAX_TABS - tabsVM.tabs.length
        const origActive: number = tabsVM.activeTabId
        let restored: number = 0
        for (const e of entries) {
          if (restored >= capacity) {
            break
          }
          if (seen.has(e.url)) {
            continue
          }
          seen.add(e.url)
          tabsVM.newTab(e.url, false, false, true)
          restored++
        }
        if (restored > 0) {
          tabsVM.switchTab(origActive)
        }
        logger.info('importVia', `会话标签导入 ${restored} 个`)
      }
      // 主页背景：bg.jpg 转存 home_media/bg.png 并设为背景
      const bgPath: string = `${base}/bg.jpg`
      if (DataBackupViewModel.exists(bgPath)) {
        const dir: string = HomeImageUtil.ensureDir(`${_QhState.Context.filesDir}/home_media`)
        if (await HomeImageUtil.savePicked(bgPath, `${dir}/bg.png`, 2560, 100)) {
          appSettings.home_bg_image = `${dir}/bg.png`
          appSettings.save()
        } else {
          logger.warn('importVia', 'bg.jpg 转存失败，跳过主页背景')
        }
      }
      logger.info('importVia', `Via 导出导入完成：${imported} 条书签/收藏，${scriptsImported} 个脚本`)
      return true
    } catch (e) {
      logger.error('importVia', `${e}`)
      return false
    }
  }

  /** Via 导出目录特征：settings.txt + （bookmarks.html / favorites.txt / history.txt）任一 */
  private static isViaExportDir(dir: string): boolean {
    return DataBackupViewModel.exists(`${dir}/settings.txt`)
      && (DataBackupViewModel.exists(`${dir}/bookmarks.html`)
        || DataBackupViewModel.exists(`${dir}/favorites.txt`)
        || DataBackupViewModel.exists(`${dir}/history.txt`))
  }

  /** 根目录或一级子目录中定位 Via 导出目录，未找到返回 null */
  private static findViaBase(root: string): string | null {
    if (DataBackupViewModel.isViaExportDir(root)) {
      return root
    }
    const names: string[] = fileIo.listFileSync(root)
    for (const name of names) {
      const candidate: string = `${root}/${name}`
      if (DataBackupViewModel.exists(`${candidate}/settings.txt`)
        && DataBackupViewModel.isViaExportDir(candidate)) {
        return candidate
      }
    }
    return null
  }

  /** 文件/目录是否存在（不抛异常） */
  private static exists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (e) {
      return false
    }
  }

  /** 解析单行 JSON（空行/坏行返回 null），Via 导出的 txt 均为按行 JSON */
  private static parseJsonLine(line: string): Record<string, Object> | null {
    const t: string = line.trim()
    if (t === '') {
      return null
    }
    try {
      return JSON.parse(t) as Record<string, Object>
    } catch (e) {
      return null
    }
  }

  /**
   * 解析 JSON 备份并恢复（书签/历史/设置/搜索历史/下载记录/站点设置/hosts/规则订阅/用户脚本/扩展），返回是否成功；
   * 按备份内实际存在的数据段恢复，兼容旧版（version 1/2 纯 JSON）备份；
   * @param fileBase zip 备份解压后的基准目录（含 backup.json 及随行文件），纯 JSON 备份传 null
   */
  async importDataFromContent(content: string, fileBase: string | null): Promise<boolean> {
    if (!content) {
      return false
    }
    try {
      const raw: Record<string, Object> = JSON.parse(content) as Record<string, Object>
      if ((raw['app'] as string) !== 'qinghong') {
        return false
      }
      const filesDir: string = _QhState.Context.filesDir
      // 随行文件：设置段携带的主页壁纸/logo（home_bg_image/home_logo_image 指向的路径与本机沙箱一致，先落盘再恢复设置）
      if (fileBase !== null && fileIo.accessSync(`${fileBase}/home_media`)) {
        DataBackupViewModel.copyDir(`${fileBase}/home_media`, `${filesDir}/home_media`)
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
          await this.getHistoryDB().addVisit(title, url,
            (rec['visit_time'] as number) ?? new Date().getTime())
        }
      }
      const settings = raw['settings']
      if (settings !== undefined && settings !== null) {
        appSettings.applySyncData(settings as Record<string, Object>)
        appSettings.save()
      }
      const uiSettings = raw['ui_settings']
      if (uiSettings !== undefined && uiSettings !== null) {
        UISettings.applySyncData(uiSettings as Record<string, Object>)
        UISettings.save()
      }
      const searchHistory = raw['search_history']
      if (searchHistory !== undefined && searchHistory !== null) {
        const arr: Object[] = searchHistory as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const keyword: string = (rec['keyword'] as string) ?? ''
          if (keyword === '') {
            continue
          }
          await this.getSearchHistoryDB().saveOrUpdate(keyword,
            (rec['visit_time'] as number) ?? new Date().getTime())
        }
      }
      const downloads = raw['download_records']
      if (downloads !== undefined && downloads !== null) {
        const arr: Object[] = downloads as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const path: string = (rec['path'] as string) ?? ''
          if (path === '') {
            continue
          }
          // 本地已有同路径记录则保留本地状态（避免覆盖进行中的下载进度）
          if (await this.getDownloadDB().queryByPath(path) !== null) {
            continue
          }
          const info: DownloadRecordInfo = new DownloadRecordInfo(
            (rec['url'] as string) ?? '',
            (rec['file_name'] as string) ?? '',
            path,
            (rec['status'] as string) ?? 'completed',
            (rec['create_time'] as number) ?? new Date().getTime())
          info.receivedSize = (rec['received_size'] as number) ?? 0
          info.totalSize = (rec['total_size'] as number) ?? -1
          info.segIndex = (rec['seg_index'] as number) ?? 0
          info.isHls = (rec['is_hls'] as boolean) ?? false
          info.referer = (rec['referer'] as string) ?? ''
          await this.getDownloadDB().insert(info)
        }
      }
      const siteSettings = raw['site_settings']
      if (siteSettings !== undefined && siteSettings !== null) {
        const arr: Object[] = siteSettings as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const site: string = (rec['site'] as string) ?? ''
          const key: string = (rec['key'] as string) ?? ''
          const value: string = (rec['value'] as string) ?? ''
          if (site === '' || key === '') {
            continue
          }
          await this.getSiteSettingDB().setOverride(site, key, value)
        }
      }
      const hosts = raw['hosts']
      if (hosts !== undefined && hosts !== null) {
        const arr: Object[] = hosts as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const host: string = (rec['host'] as string) ?? ''
          const ip: string = (rec['ip'] as string) ?? ''
          if (host === '' || ip === '') {
            continue
          }
          await this.getHostsDB().setRule(host, ip)
        }
      }
      const adBlock = raw['ad_block']
      if (adBlock !== undefined && adBlock !== null) {
        await DataBackupViewModel.importAdBlock(adBlock as Record<string, Object>)
      }
      const userScripts = raw['user_scripts']
      if (userScripts !== undefined && userScripts !== null) {
        const arr: Object[] = userScripts as Object[]
        for (const item of arr) {
          const rec: Record<string, Object> = item as Record<string, Object>
          const name: string = (rec['name'] as string) ?? ''
          if (name === '') {
            continue
          }
          const existing: UserScriptInfo | null = await this.getUserScriptDB().queryByName(name)
          const info: UserScriptInfo = existing ?? new UserScriptInfo()
          info.name = name
          info.version = (rec['version'] as string) ?? ''
          info.code = (rec['code'] as string) ?? ''
          info.enabled = (rec['enabled'] as boolean) ?? true
          info.runAt = (rec['run_at'] as string) ?? 'document-end'
          info.matches = (rec['matches'] as string) ?? ''
          info.excludes = (rec['excludes'] as string) ?? ''
          info.updateUrl = (rec['update_url'] as string) ?? ''
          info.createTime = (rec['create_time'] as number) ?? 0
          info.updateTime = (rec['update_time'] as number) ?? 0
          info.grants = (rec['grants'] as string) ?? '[]'
          info.connects = (rec['connects'] as string) ?? '[]'
          info.requires = (rec['requires'] as string) ?? '[]'
          info.resources = (rec['resources'] as string) ?? '[]'
          info.noframes = (rec['noframes'] as boolean) ?? false
          if (existing === null) {
            await this.getUserScriptDB().insert(info)
          } else {
            await this.getUserScriptDB().update(info)
          }
          // GM 存储键值：insert 不回填 id，重查取新 id 后恢复
          const saved: UserScriptInfo | null = await this.getUserScriptDB().queryByName(name)
          if (saved !== null && saved.id !== null) {
            const values: Object | null = rec['values'] ?? null
            if (values !== null) {
              for (const v of values as Object[]) {
                const vrec: Record<string, Object> = v as Record<string, Object>
                const key: string = (vrec['key'] as string) ?? ''
                if (key === '') {
                  continue
                }
                await this.getUserScriptValueDB().upsert(saved.id, key,
                  (vrec['value'] as string) ?? 'null')
              }
            }
          }
        }
        await scriptVM.loadAll()
      }
      const extensions = raw['extensions']
      if (extensions !== undefined && extensions !== null && fileBase !== null) {
        await this.importExtensions(extensions as Object[], fileBase)
      }
      logger.info('importData', '数据导入完成')
      return true
    } catch (e) {
      logger.error('importData', `${e}`)
      return false
    }
  }

  /** 恢复扩展：解压目录内 extensions/<extId> 解包文件 + 元数据 + chrome.storage 键值，完成后刷新扩展运行时缓存 */
  private async importExtensions(arr: Object[], fileBase: string): Promise<void> {
    const filesDir: string = _QhState.Context.filesDir
    for (const item of arr) {
      const rec: Record<string, Object> = item as Record<string, Object>
      const extId: string = (rec['ext_id'] as string) ?? ''
      if (extId === '') {
        continue
      }
      const srcDir: string = `${fileBase}/extensions/${extId}`
      if (!fileIo.accessSync(`${srcDir}/manifest.json`)) {
        logger.warn('importExtensions', `备份中缺少扩展 ${extId} 的解包文件，跳过`)
        continue
      }
      const destDir: string = `${filesDir}/extensions/${extId}`
      DataBackupViewModel.removeDirQuiet(destDir)
      DataBackupViewModel.copyDir(srcDir, destDir)
      const existing: ExtensionInfo | null = await this.getExtensionDB().queryByExtId(extId)
      const info: ExtensionInfo = existing ?? new ExtensionInfo()
      info.extId = extId
      info.name = (rec['name'] as string) ?? ''
      info.version = (rec['version'] as string) ?? ''
      info.description = (rec['description'] as string) ?? ''
      info.manifestVersion = (rec['manifest_version'] as number) ?? 3
      info.enabled = (rec['enabled'] as boolean) ?? true
      info.path = (rec['path'] as string) ?? `extensions/${extId}`
      info.manifest = (rec['manifest'] as string) ?? '{}'
      info.updateUrl = (rec['update_url'] as string) ?? ''
      if (existing === null) {
        info.createTime = (rec['create_time'] as number) ?? new Date().getTime()
        await this.getExtensionDB().insert(info)
      } else {
        info.updateTime = (rec['update_time'] as number) ?? new Date().getTime()
        await this.getExtensionDB().update(info)
      }
      const values: Object | null = rec['values'] ?? null
      if (values !== null) {
        for (const v of values as Object[]) {
          const vrec: Record<string, Object> = v as Record<string, Object>
          const key: string = (vrec['key'] as string) ?? ''
          if (key === '') {
            continue
          }
          await this.getExtensionValueDB().upsert(extId, key, (vrec['value'] as string) ?? 'null')
        }
      }
    }
    await extensionVM.refreshAfterRestore()
  }

  /** 恢复广告拦截规则订阅（已存在的更新名称与开关，新订阅添加并后台下载规则） */
  private static async importAdBlock(block: Record<string, Object>): Promise<void> {
    await adBlockSubsStore.load()
    const interval: string = (block['interval'] as string) ?? ''
    if (interval !== '') {
      adBlockSubsStore.setInterval(interval)
    }
    const subsObj: Object | null = block['subs'] ?? null
    if (subsObj === null) {
      return
    }
    const arr: Object[] = subsObj as Object[]
    for (const item of arr) {
      const rec: Record<string, Object> = item as Record<string, Object>
      const url: string = (rec['url'] as string) ?? ''
      if (url === '') {
        continue
      }
      adBlockSubsStore.add(url)
      const sub: AdBlockSubscription | null = DataBackupViewModel.findAdSub(url)
      if (sub === null) {
        continue
      }
      const name: string = (rec['name'] as string) ?? ''
      if (name !== '') {
        adBlockSubsStore.edit(sub, name, url, false)
      }
      adBlockSubsStore.toggle(sub, (rec['enabled'] as boolean) ?? true)
    }
  }

  private static findAdSub(url: string): AdBlockSubscription | null {
    for (const s of adBlockSubsStore.subs) {
      if (s.url === url) {
        return s
      }
    }
    return null
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

  static async readBytesFromUri(uri: string): Promise<Uint8Array> {
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
      return new Uint8Array(buf)
    } finally {
      fileIo.closeSync(file)
    }
  }

  private static ensureDir(path: string): void {
    if (!fileIo.accessSync(path)) {
      fileIo.mkdirSync(path, true)
    }
  }

  private static removeDirQuiet(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.rmdirSync(path)
      }
    } catch (e) {
      logger.error(`removeDirQuiet 失败: ${e}`)
    }
  }

  private static unlinkQuiet(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (e) {
      logger.error(`unlinkQuiet 失败: ${e}`)
    }
  }

  private static writeTextSync(path: string, text: string): void {
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, text)
    } finally {
      fileIo.closeSync(file)
    }
  }

  private static readTextSync(path: string): string {
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
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

  private static readBytesSync(path: string): Uint8Array {
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
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
      return new Uint8Array(buf)
    } finally {
      fileIo.closeSync(file)
    }
  }

  /** 递归复制目录（覆盖已有同名文件/目录） */
  private static copyDir(src: string, dest: string): void {
    DataBackupViewModel.ensureDir(dest)
    const names: string[] = fileIo.listFileSync(src)
    for (const name of names) {
      const s: string = `${src}/${name}`
      const d: string = `${dest}/${name}`
      if (fileIo.statSync(s).isDirectory()) {
        DataBackupViewModel.copyDir(s, d)
      } else {
        fileIo.copyFileSync(s, d)
      }
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
