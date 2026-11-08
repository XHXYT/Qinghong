import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { _QhState } from '../entryability/AppState';
import DownloadRecordInfo from '../common/entity/DownloadRecordInfo';
import { DownloadRecordDao } from '../common/utils/database/impl/DownloadRecordDao';
import { UrlUtils } from '../common/constants/SearchEngines';
import { createLogger } from '../common/utils/app/Logger';
import { toastUtil } from '../common/utils/ui/ToastUtils';
import { PublicDownloadDir } from '../common/utils/download/PublicDownloadDir';
import { DataBackupViewModel } from './DataBackupViewModel';
import { HttpDownloader, StreamOptions, AbortFlag } from '../common/utils/download/HttpDownloader';
import { HlsDownloader, HlsOptions } from '../common/utils/download/HlsDownloader';
import { DownloadNotifier } from '../common/utils/download/DownloadNotifier';
import { appSettings } from '../common/entity/SettingsModel';

const logger = createLogger('DownloadViewModel')

/** 直链下载连续无进展重试次数（有推进不计数，与 HLS 分片同策略） */
const DIRECT_RETRIES: number = 6
/** 直链下载总尝试上限（防病态循环） */
const MAX_DIRECT_ATTEMPTS: number = 50

/** 进行中的下载任务（abort 中止控制；key = 记录 path） */
class ActiveTask {
  readonly key: string
  readonly abort: AbortFlag = new AbortFlag()

  constructor(key: string) {
    this.key = key
  }
}

/** 待确认下载（接管下载事件后的确认弹窗数据；fileName 可编辑） */
@ObservedV2
export class PendingDownload {
  readonly url: string
  readonly referer: string
  readonly isHls: boolean
  @Trace fileName: string

  constructor(url: string, referer: string, isHls: boolean, fileName: string) {
    this.url = url
    this.referer = referer
    this.isHls = isHls
    this.fileName = fileName
  }
}

  @ObservedV2
  export class DownloadViewModel {
  @Trace records: DownloadRecordInfo[] = []
  @Trace isLoading: boolean = false
  /** 待确认下载（非 null 时浏览器根页弹确认卡片，确认/取消后清空） */
  @Trace pending: PendingDownload | null = null
  /** path → 进度百分比（-1 = 总大小未知；HLS 为分片粒度百分比） */
  @Trace progressOf: Map<string, number> = new Map<string, number>()
  /** path → 实时下载速度（字节/秒，EMA 平滑） */
  @Trace speedOf: Map<string, number> = new Map<string, number>()
  /** path → HLS 总大小估算（字节；已完成分片平均大小 × 总分片数，每完成一个分片校正一次） */
  @Trace estimatedTotalOf: Map<string, number> = new Map<string, number>()
  /** path → 显示用已收字节（HLS 含乱序缓冲与在途，实时增长；落库续传锚点仍用 record.receivedSize） */
  @Trace displayRecvOf: Map<string, number> = new Map<string, number>()
  /** path → 上次估算时的已完成分片数（只在分片边界重算估算，避免片内抖动） */
  private lastSegDoneOf: Map<string, number> = new Map<string, number>()

  private db: DownloadRecordDao | null = null
  private activeTasks: Map<string, ActiveTask> = new Map<string, ActiveTask>()
  private uiTickOf: Map<string, number> = new Map<string, number>()
  private dbTickOf: Map<string, number> = new Map<string, number>()
  private lastRecvOf: Map<string, number> = new Map<string, number>()
  private lastTsOf: Map<string, number> = new Map<string, number>()

  constructor() {
  }

  /** 字节数可读化（0 → 0B；负数 → 空串） */
  static formatSize(n: number): string {
    if (n < 0) {
      return ''
    }
    if (n < 1024) {
      return `${n}B`
    }
    if (n < 1024 * 1024) {
      return `${(n / 1024).toFixed(1)}KB`
    }
    if (n < 1024 * 1024 * 1024) {
      return `${(n / 1024 / 1024).toFixed(1)}MB`
    }
    return `${(n / 1024 / 1024 / 1024).toFixed(2)}GB`
  }

  private static unknownSizeText: string = ''

  /** 「未知大小」文案（资源读取一次后缓存，subtitleOf 高频调用） */
  private static unknownSize(): string {
    if (DownloadViewModel.unknownSizeText === '') {
      DownloadViewModel.unknownSizeText =
        _QhState.Context.resourceManager.getStringSync($r('app.string.unknown_size').id)
    }
    return DownloadViewModel.unknownSizeText
  }

  /** 列表/通知共用的副标题：已下载/总大小 · 速度（总大小未知但有实际落盘数据时只显示已下载字节） */
  static subtitleOf(received: number, total: number, speed: number, downloading: boolean): string {
    const rs: string = DownloadViewModel.formatSize(received)
    let out: string
    if (total > 0) {
      out = `${rs}/${DownloadViewModel.formatSize(total)}`
    } else if (received > 0) {
      // 有实际数据：直接显示落盘字节数，不挂「未知大小」
      out = rs
    } else {
      out = `${rs}/${DownloadViewModel.unknownSize()}`
    }
    if (downloading && speed > 0) {
      out = `${out} · ${DownloadViewModel.formatSize(speed)}/s`
    }
    return out
  }

  private getDB(): DownloadRecordDao {
    if (!this.db) {
      this.db = new DownloadRecordDao(_QhState.Context)
    }
    return this.db
  }

  /**
   * 加载全部记录：就地把 DB 行同步进已有实例（@ObservedV2 属性级刷新），
   * 不整表换实例——列表行按稳定 key 复用，避免整行重建
   */
  async loadAll(): Promise<void> {
    this.isLoading = true
    try {
      const rows: DownloadRecordInfo[] = await this.getDB().queryAll()
      const keyOf = (r: DownloadRecordInfo): string => r.id !== null ? `${r.id}` : r.path
      const oldMap: Map<string, DownloadRecordInfo> = new Map<string, DownloadRecordInfo>()
      for (const r of this.records) {
        oldMap.set(keyOf(r), r)
      }
      const next: DownloadRecordInfo[] = []
      for (const row of rows) {
        const old: DownloadRecordInfo | undefined = oldMap.get(keyOf(row))
        if (old !== undefined && old !== row) {
          old.url = row.url
          old.fileName = row.fileName
          old.path = row.path
          old.status = row.status
          old.receivedSize = row.receivedSize
          old.totalSize = row.totalSize
          old.segIndex = row.segIndex
          old.isHls = row.isHls
          old.referer = row.referer
          old.createTime = row.createTime
          next.push(old)
        } else {
          next.push(row)
        }
      }
      this.records = next
    } catch (e) {
      logger.error('loadAll', `${e}`)
    }
    this.isLoading = false
  }

  /**
   * 发起下载（先弹确认）：接管下载事件后计算默认文件名与类型，
   * 用户在确认弹窗中可改名，确认后 startDownload 走原下载管线：
   * - m3u8 播放列表 → 解析分片顺序合并为单个 .ts；其余链接流式直下
   * - request.downloadFile 的 filePath 仅支持应用沙箱路径（写公共目录任务必失败），
   *   故统一流式下载到沙箱临时文件，完成后拷入公共下载目录 Download/<包名>/Download
   */
  download(url: string, referer: string = ''): void {
    if (!url) {
      return
    }
    const isHls: boolean = HttpDownloader.looksLikeM3u8(url)
    let fileName: string = UrlUtils.fileNameOf(url)
    if (isHls) {
      fileName = DownloadViewModel.hlsFileName(fileName)
    } else if (!fileName) {
      fileName = `download_${new Date().getTime()}`
    }
    this.pending = new PendingDownload(url, referer, isHls, fileName)
  }

  /** 确认下载：清洗（可能已编辑的）文件名后开始任务 */
  confirmDownload(fileName: string): void {
    const p: PendingDownload | null = this.pending
    if (p === null) {
      return
    }
    this.pending = null
    this.startDownload(p.url, p.referer, DownloadViewModel.sanitizeFileName(fileName), p.isHls)
  }

  /** 取消待确认下载 */
  cancelDownload(): void {
    this.pending = null
  }

  /** 文件名清洗：去路径分隔符与文件系统非法字符，空回退默认名 */
  private static sanitizeFileName(name: string): string {
    const n: string = name.trim().replace(/[/\\:*?"<>|]/g, '')
    if (n !== '') {
      return n
    }
    return `download_${new Date().getTime()}`
  }

  /** 异常转可读文本（Error 取 message，BusinessError 取 code/message，防 [object Object]） */
  private static errMessage(e: Object): string {
    const be: BusinessError = e as BusinessError
    if (be !== null && be !== undefined && be.message !== undefined && be.message !== '') {
      const c: string = be.code !== undefined ? `${be.code}: ` : ''
      return `${c}${be.message}`
    }
    return `${e}`
  }

  /** 确认后开始下载并落库 */
  private async startDownload(url: string, referer: string, fileName: string, isHls: boolean): Promise<void> {
    let dest: string = ''
    try {
      const dir: string = await PublicDownloadDir.ensureDir('Download')
      dest = `${dir}/${fileName}`
      if (this.activeTasks.has(dest)) {
        return
      }
      const record: DownloadRecordInfo = new DownloadRecordInfo(url, fileName, dest, 'downloading')
      record.isHls = isHls
      record.referer = referer
      await this.getDB().saveOrUpdate(record)
      await this.loadAll()
      toastUtil.showToast({ message: $r('app.string.download_started') })
      this.runTask(dest, url, isHls, false)
    } catch (e) {
      logger.error('download', `${e}`)
      toastUtil.showToast({ message: $r('app.string.download_failed') })
    }
  }

  /** 暂停下载：活动任务经看门狗 5 秒内响应中止并落库 paused；遗留 downloading 记录（无活动任务）直接置 paused */
  async pause(record: DownloadRecordInfo): Promise<void> {
    const task: ActiveTask | undefined = this.activeTasks.get(record.path)
    if (task !== undefined) {
      task.abort.aborted = true
      return
    }
    if (record.status === 'downloading') {
      record.status = 'paused'
      await this.getDB().update(record)
      await this.loadAll()
    }
  }

  /** 应用重启后遗留的 downloading 记录（无对应活动任务）统一置为 paused，供继续/重试 */
  async syncStale(): Promise<void> {
    let changed: boolean = false
    for (const r of this.records) {
      if (r.status === 'downloading' && !this.activeTasks.has(r.path)) {
        r.status = 'paused'
        await this.getDB().update(r)
        changed = true
      }
    }
    if (changed) {
      await this.loadAll()
    }
  }

  /** 继续暂停任务 / 重试失败或中断任务（receivedSize > 0 即断点续传，临时文件丢失则自动重下） */
  async retry(record: DownloadRecordInfo): Promise<void> {
    if (this.activeTasks.has(record.path)) {
      return
    }
    const resume: boolean = record.receivedSize > 0 && record.status !== 'completed'
    try {
      if (!resume) {
        record.receivedSize = 0
        record.segIndex = 0
        record.totalSize = -1
      }
      record.status = 'downloading'
      if (record.id !== null) {
        await this.getDB().update(record)
      }
      await this.loadAll()
      this.runTask(record.path, record.url, record.isHls, resume)
    } catch (e) {
      logger.error('retry', `${e}`)
    }
  }

  /** 批量：重试所有失败任务 */
  async retryAllFailed(): Promise<void> {
    const failed: DownloadRecordInfo[] =
      this.records.filter((r: DownloadRecordInfo): boolean => r.status === 'failed')
    for (const r of failed) {
      await this.retry(r)
    }
  }

  /** 批量：暂停所有下载中任务 */
  async pauseAll(): Promise<void> {
    const downloading: DownloadRecordInfo[] =
      this.records.filter((r: DownloadRecordInfo): boolean => r.status === 'downloading')
    for (const r of downloading) {
      await this.pause(r)
    }
  }

  /** 批量：继续所有暂停任务 */
  async resumeAll(): Promise<void> {
    const paused: DownloadRecordInfo[] =
      this.records.filter((r: DownloadRecordInfo): boolean => r.status === 'paused')
    for (const r of paused) {
      await this.retry(r)
    }
  }

  /** 单个下载任务执行（download/retry 共用）；resume = 断点续传 */
  private async runTask(dest: string, url: string, isHls: boolean, resume: boolean): Promise<void> {
    // 同时任务数限流：超过上限排队等待；等待期间用户暂停/删除会改变记录状态，唤醒后复查退出
    const limit: number = Math.round(appSettings.download_task_limit)
    const maxTasks: number = limit >= 1 && limit <= 4 ? limit : 3
    while (this.activeTasks.size >= maxTasks) {
      await DownloadViewModel.sleep(400)
      const queued: DownloadRecordInfo | null = await this.getDB().queryByPath(dest)
      if (queued === null || queued.status !== 'downloading') {
        return
      }
    }
    const task: ActiveTask = new ActiveTask(dest)
    this.activeTasks.set(dest, task)
    const notifId: number = DownloadViewModel.notifIdOf(dest)
    let record: DownloadRecordInfo | null = null
    let tmpPath: string = ''
    let finalDest: string = dest
    try {
      await DownloadNotifier.prepare()
      // 优先复用列表中的实例（@ObservedV2：后续属性变更直接细粒度刷新 UI），查不到再查库
      const inList: DownloadRecordInfo | undefined =
        this.records.find((r: DownloadRecordInfo): boolean => r.path === dest)
      record = inList !== undefined ? inList : await this.getDB().queryByPath(dest)
      if (record === null) {
        throw new Error('download record missing')
      }
      const rec: DownloadRecordInfo = record
      if (!resume) {
        rec.receivedSize = 0
        rec.segIndex = 0
        rec.totalSize = -1
        rec.status = 'downloading'
        await this.getDB().update(rec)
      }
      this.progressOf.set(finalDest, 0)
      // 沙箱临时文件（流式写盘；命名稳定以便暂停后续传复用），完成后拷入公共下载目录
      const tmpDir: string = `${_QhState.Context.cacheDir}/download_tmp`
      if (!fileIo.accessSync(tmpDir)) {
        fileIo.mkdirSync(tmpDir, true)
      }
      tmpPath = `${tmpDir}/${rec.fileName}`
      // 续传前提：临时文件存在且不小于已记录字节数（缓存被清/文件损坏则放弃断点从头下）
      if (rec.receivedSize > 0 && (!fileIo.accessSync(tmpPath) || fileIo.statSync(tmpPath).size < rec.receivedSize)) {
        rec.receivedSize = 0
        rec.segIndex = 0
        await this.getDB().update(rec)
      }
      // 速度统计重置（receivedSize/totalSize 已是 @Trace，直接随进度刷新）
      this.speedOf.set(finalDest, 0)
      this.lastRecvOf.delete(finalDest)
      this.lastTsOf.delete(finalDest)
      if (isHls) {
        const opts: HlsOptions = new HlsOptions()
        opts.startSegIndex = rec.segIndex
        opts.startOffset = rec.receivedSize
        opts.referer = rec.referer
        opts.abort = task.abort
        opts.onProgress = (segDone: number, segTotal: number, received: number, written: number): void => {
          this.onTaskProgress(rec, segDone / segTotal * 100, received, -1, segDone, segTotal, written)
        }
        await HlsDownloader.downloadHls(url, tmpPath, opts)
      } else {
        // 直链下载自适应重试：掐连接网络下响应体常在尾部被截断（truncated），
        // 有推进就断点续传重试、连续无进展才计数放弃（与 HLS 分片同策略）
        let recv: number = rec.receivedSize
        let noProgress: number = 0
        let attempts: number = 0
        let done: boolean = false
        while (!done && noProgress < DIRECT_RETRIES && attempts < MAX_DIRECT_ATTEMPTS) {
          attempts++
          if (task.abort.aborted) {
            throw new Error('aborted')
          }
          const attemptStart: number = recv
          const opts: StreamOptions = new StreamOptions()
          opts.startOffset = recv
          opts.resume = recv > 0
          opts.referer = rec.referer
          opts.abort = task.abort
          opts.onProgress = (received: number, total: number): void => {
            recv = received
            const percent: number = total > 0 ? received / total * 100 : -1
            this.onTaskProgress(rec, percent, received, total, 0, 0, received)
          }
          try {
            await HttpDownloader.downloadToFile(url, tmpPath, opts)
            done = true
          } catch (e) {
            // 中止立即退出，不参与重试
            if (task.abort.aborted) {
              throw new Error('aborted')
            }
            if (recv > attemptStart) {
              noProgress = 0
            } else {
              noProgress++
            }
            logger.warn(`direct download retry (attempt ${attempts}, no-progress ` +
              `${noProgress}/${DIRECT_RETRIES}): ${url} ${DownloadViewModel.errMessage(e)}`)
            await DownloadViewModel.sleep(Math.min(4000, 500 * Math.pow(2, noProgress)))
          }
        }
        if (!done) {
          throw new Error('direct download failed')
        }
        // 无 .m3u8 后缀但内容实为播放列表：转 HLS 分片合并（文件名与记录同步更新）
        if (!resume && DownloadViewModel.fileStartsWith(tmpPath, '#EXTM3U')) {
          const text: string = fileIo.readTextSync(tmpPath)
          const dir: string = finalDest.substring(0, finalDest.lastIndexOf('/'))
          const newFileName: string = DownloadViewModel.hlsFileName(rec.fileName)
          finalDest = `${dir}/${newFileName}`
          rec.fileName = newFileName
          rec.path = finalDest
          rec.isHls = true
          rec.receivedSize = 0
          rec.segIndex = 0
          rec.totalSize = -1
          await this.getDB().update(rec)
          this.progressOf.delete(dest)
          this.displayRecvOf.delete(dest)
          this.progressOf.set(finalDest, 0)
          const hlsOpts: HlsOptions = new HlsOptions()
          hlsOpts.referer = rec.referer
          hlsOpts.abort = task.abort
          hlsOpts.onProgress = (segDone: number, segTotal: number, received: number, written: number): void => {
            this.onTaskProgress(rec, segDone / segTotal * 100, received, -1, segDone, segTotal, written)
          }
          await HlsDownloader.downloadSegmentsFromText(text, url, tmpPath, hlsOpts)
        }
      }
      fileIo.copyFileSync(tmpPath, finalDest)
      DownloadViewModel.removeTmp(tmpPath)
      rec.status = 'completed'
      if (rec.totalSize > 0) {
        rec.receivedSize = rec.totalSize
      } else {
        // 总大小未知（HLS 分片合并）：完成后以实际落盘文件大小为准，列表不再显示「未知大小」
        const size: number = fileIo.statSync(finalDest).size
        rec.totalSize = size
        rec.receivedSize = size
      }
      await this.getDB().update(rec)
      this.progressOf.set(finalDest, 100)
      this.displayRecvOf.delete(finalDest)
      await this.loadAll()
      DownloadNotifier.cancel(notifId)
      toastUtil.showToast({ message: $r('app.string.download_completed') })
    } catch (e) {
      const err: string = `${e}`
      logger.error('runTask', err)
      if (record !== null) {
        const rec: DownloadRecordInfo = record
        if (task.abort.aborted) {
          // 暂停：保留临时文件供续传
          rec.status = 'paused'
          await this.getDB().update(rec)
          await this.loadAll()
          this.displayRecvOf.delete(rec.path)
          DownloadNotifier.cancel(notifId)
        } else {
          rec.status = 'failed'
          await this.getDB().update(rec)
          await this.loadAll()
          this.displayRecvOf.delete(rec.path)
          // 保留临时文件：失败后重试可断点续传，避免大文件反复重下
          // 失败通知留存（覆盖同 id 进度通知），不随进度通知一起消失
          DownloadNotifier.publishFailed(notifId, rec.fileName)
          toastUtil.showToast({
            message: err.includes('encrypted')
              ? $r('app.string.hls_encrypted_unsupported') : $r('app.string.download_failed')
          })
        }
      }
    } finally {
      this.activeTasks.delete(dest)
    }
  }

  /** 进度上报：内存进度+速度（UI 400ms 节流）+ 落库与通知（1s 节流）；
   * written = 已写盘字节（落库续传锚点，必须 ≤ 实际文件大小），received = 含缓冲在途（速度统计用） */
  private onTaskProgress(record: DownloadRecordInfo, percent: number, received: number,
    total: number, segDone: number, segTotal: number, written: number): void {
    const now: number = Date.now()
    record.receivedSize = written
    record.totalSize = total
    record.segIndex = segDone
    // HLS 总大小估算：只在分片完成边界重算（已完成分片平均大小 × 总分片数），片内保持稳定
    if (total <= 0 && segTotal > 0 && segDone > 0) {
      const lastSeg: number = this.lastSegDoneOf.get(record.path) ?? -1
      if (segDone !== lastSeg) {
        this.lastSegDoneOf.set(record.path, segDone)
        const est: number = Math.round(written / segDone) * segTotal
        this.estimatedTotalOf.set(record.path, Math.max(est, written))
      }
    }
    const displayTotal: number = this.displayTotalOf(record)
    const lastUi: number = this.uiTickOf.get(record.path) ?? 0
    if (now - lastUi >= 400) {
      this.uiTickOf.set(record.path, now)
      this.progressOf.set(record.path, percent)
      // 显示用已收字节（含在途，实时增长；落库 receivedSize 仍为落盘锚点 written）
      this.displayRecvOf.set(record.path, received)
      // 速度：区间字节数/耗时，EMA 平滑；首帧记录基准（此前基准从未落 Map，dt 恒 0 导致速度永远不显示）
      const prevRecv: number | undefined = this.lastRecvOf.get(record.path)
      const prevTs: number | undefined = this.lastTsOf.get(record.path)
      if (prevRecv !== undefined && prevTs !== undefined) {
        const dt: number = (now - prevTs) / 1000
        if (dt >= 0.2) {
          const inst: number = Math.max(0, (received - prevRecv) / dt)
          const old: number = this.speedOf.get(record.path) ?? 0
          this.speedOf.set(record.path, old > 0 ? old * 0.6 + inst * 0.4 : inst)
          this.lastRecvOf.set(record.path, received)
          this.lastTsOf.set(record.path, now)
        }
      } else {
        this.lastRecvOf.set(record.path, received)
        this.lastTsOf.set(record.path, now)
      }
    }
    const lastDb: number = this.dbTickOf.get(record.path) ?? 0
    if (now - lastDb >= 1000) {
      this.dbTickOf.set(record.path, now)
      this.getDB().update(record).catch((): void => {
      })
      const speed: number = this.speedOf.get(record.path) ?? 0
      const subtitle: string = DownloadViewModel.subtitleOf(received, displayTotal, speed, true)
      DownloadNotifier.publishProgress(DownloadViewModel.notifIdOf(record.path), record.fileName, percent, subtitle)
    }
  }

  /** 显示用总大小：记录值优先，未知（HLS）回退估算值（无估算返回 -1） */
  displayTotalOf(record: DownloadRecordInfo): number {
    if (record.totalSize > 0) {
      return record.totalSize
    }
    return this.estimatedTotalOf.get(record.path) ?? -1
  }

  /** HLS 合并产物文件名：原名去后缀 + .ts（无原名则 video_时间戳.ts） */
  private static hlsFileName(name: string): string {
    const base: string = name !== ''
      ? name.replace(/\.[^./\\]*$/, '') : `video_${new Date().getTime()}`
    return `${base}.ts`
  }

  /** 通知 id：下载路径哈希派生（同一任务进度更新覆盖同一条通知） */
  private static notifIdOf(path: string): number {
    let h: number = 0
    for (let i = 0; i < path.length; i++) {
      h = (h * 31 + path.charCodeAt(i)) % 1000000
    }
    return h
  }

  /** 读文件头部判断是否以指定前缀开头（下载内容嗅探） */
  private static fileStartsWith(path: string, prefix: string): boolean {
    try {
      return fileIo.readTextSync(path, { offset: 0, length: prefix.length + 8 })
        .trimStart().startsWith(prefix)
    } catch (e) {
      return false
    }
  }

  private static removeTmp(path: string): void {
    if (path === '') {
      return
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (e) {
      logger.debug(`清理临时文件失败: ${e}`)
    }
  }

  async deleteRecord(id: number): Promise<void> {
    const rec: DownloadRecordInfo | undefined =
      this.records.find((r: DownloadRecordInfo): boolean => r.id === id)
    if (rec !== undefined) {
      const task: ActiveTask | undefined = this.activeTasks.get(rec.path)
      if (task !== undefined) {
        task.abort.aborted = true
      }
      this.progressOf.delete(rec.path)
      this.speedOf.delete(rec.path)
      this.lastRecvOf.delete(rec.path)
      this.lastTsOf.delete(rec.path)
      this.uiTickOf.delete(rec.path)
      this.dbTickOf.delete(rec.path)
      this.estimatedTotalOf.delete(rec.path)
      this.lastSegDoneOf.delete(rec.path)
    }
    await this.getDB().deleteById(id)
    await this.loadAll()
  }

  /**
   * 保存网页 HTML 到下载目录并落库（工具栏「保存网页」）：
   * 文件名取页面标题（非法字符替换），写入后直接标记 completed
   */
  async saveLocalHtml(srcUrl: string, pageTitle: string, html: string): Promise<void> {
    try {
      const dir = await PublicDownloadDir.ensureDir('Download')
      const safeName: string = pageTitle.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim()
        .substring(0, 50)
      const fileName = `${safeName !== '' ? safeName : 'page'}_${new Date().getTime()}.html`
      const dest = `${dir}/${fileName}`
      PublicDownloadDir.writeText(dir, fileName, html)
      await this.getDB().saveOrUpdate(new DownloadRecordInfo(srcUrl, fileName, dest, 'completed'))
      await this.loadAll()
      toastUtil.showToast({ message: $r('app.string.page_saved') })
    } catch (e) {
      logger.error('saveLocalHtml', `${e}`)
      toastUtil.showToast({ message: $r('app.string.page_save_failed') })
    }
  }

  /**
   * 保存网页 PDF 到公共下载目录 Download/<包名>/PDF 并落库（菜单「打印PDF」）：
   * createPdf 生成的数据流写入 .pdf，文件名取页面标题，写入后直接标记 completed
   */
  async saveLocalPdf(srcUrl: string, pageTitle: string, data: Uint8Array): Promise<void> {
    try {
      const safeName: string = pageTitle.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim()
        .substring(0, 50)
      const fileName = `${safeName !== '' ? safeName : 'page'}_${new Date().getTime()}.pdf`
      const dest: string = await DataBackupViewModel.writePdfFile(fileName, data)
      await this.getDB().saveOrUpdate(new DownloadRecordInfo(srcUrl, fileName, dest, 'completed'))
      await this.loadAll()
      toastUtil.showToast({ message: $r('app.string.pdf_saved') })
    } catch (e) {
      logger.error('saveLocalPdf', `${e}`)
      toastUtil.showToast({ message: $r('app.string.pdf_save_failed') })
    }
  }

  async clearAll(): Promise<void> {
    this.activeTasks.forEach((task: ActiveTask): void => {
      task.abort.aborted = true
    })
    this.progressOf.clear()
    this.speedOf.clear()
    this.lastRecvOf.clear()
    this.lastTsOf.clear()
    this.estimatedTotalOf.clear()
    this.lastSegDoneOf.clear()
    await this.getDB().clearAll()
    await this.loadAll()
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout((): void => {
        resolve()
      }, ms)
    })
  }
}

export const downloadVM = new DownloadViewModel()
