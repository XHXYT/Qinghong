import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { HttpDownloader, StreamOptions, AbortFlag } from './HttpDownloader';
import { createLogger } from './Logger';
import { appSettings } from '../entity/SettingsModel';

const logger = createLogger('HlsDownloader')

/** master 播放列表最大嵌套层数 */
const MAX_PLAYLIST_DEPTH: number = 5
/** 单个分片连续无进展的放弃阈值（有推进则不计数） */
const SEGMENT_RETRIES: number = 5
/** 单个分片总尝试次数上限（防病态循环） */
const MAX_SEGMENT_ATTEMPTS: number = 50
/** 乱序完成分片的缓冲字节上限（防大分片并发撑爆内存；到达后暂停发起新分片） */
const HLS_MAX_BUFFERED: number = 32 * 1024 * 1024

/** 分片并发下载数（设置项，1-8 钳制；代理掐连接环境下串行重试吞吐极低，并发分片成倍提速） */
function segmentConcurrency(): number {
  const v: number = Math.round(appSettings.download_concurrency)
  return v >= 1 && v <= 8 ? v : 4
}

/** HLS 下载选项（分片粒度断点续传 + 中止 + 进度回调） */
export class HlsOptions {
  /** 起始分片下标（续传点） */
  startSegIndex: number = 0
  /** 已写入字节数（续传截断与追加起点） */
  startOffset: number = 0
  /** 来源页面地址（防盗链 Referer 校验；列表/分片/密钥请求均携带） */
  referer: string = ''
  abort: AbortFlag | null = null
  /** 进度回调（已完成分片数 / 分片总数 / 已收字节（含缓冲在途，速度统计用） / 已写盘字节（续传锚点）） */
  onProgress: ((segDone: number, segTotal: number, receivedBytes: number, writtenBytes: number) => void) | null = null
}

/** HLS 分片：地址 + 加密信息（AES-128；keyUrl 空 = 不加密） */
class HlsSegment {
  readonly url: string
  readonly keyUrl: string
  readonly ivHex: string
  readonly seq: number

  constructor(url: string, keyUrl: string, ivHex: string, seq: number) {
    this.url = url
    this.keyUrl = keyUrl
    this.ivHex = ivHex
    this.seq = seq
  }
}

/**
 * HLS(m3u8) 下载器：
 * 拉取播放列表（master 先选第一个变体）→ 解析分片地址（相对/绝对）→
 * 并发下载全部分片、按序追加合并为单个媒体文件（MPEG-TS 直接拼接即可播放）；
 * 支持 AES-128 加密流（#EXT-X-KEY：下载密钥逐分片 AES-CBC 解密后合并，
 * IV 取 KEY 行 IV 属性，缺省用分片 media sequence 号的 128 位大端表示）。
 * 不支持：直播流（无 ENDLIST）、SAMPLE-AES。
 */
export class HlsDownloader {

  /**
   * 下载 m3u8 视频并合并为单个媒体文件写入 destPath
   * @param url 播放列表地址
   * @param destPath 目标文件路径（建议 .ts）
   * @param opts 下载选项（续传点 / 中止 / 进度回调）
   */
  static async downloadHls(url: string, destPath: string, opts: HlsOptions | null): Promise<void> {
    const o: HlsOptions = opts ?? new HlsOptions()
    // 1. 逐层解析 master 播放列表，取最终媒体播放列表内容
    let playlistUrl: string = url
    let text: string = await HttpDownloader.getString(playlistUrl, o.referer)
    for (let depth = 0; depth < MAX_PLAYLIST_DEPTH; depth++) {
      if (!text.trimStart().startsWith('#EXTM3U')) {
        throw new Error('not an HLS playlist')
      }
      if (text.includes('#EXT-X-STREAM-INF')) {
        // master 播放列表：取第一个变体子列表地址重新拉取
        const variant: string = HlsDownloader.lineAfter(text, '#EXT-X-STREAM-INF')
        if (variant === '') {
          throw new Error('master playlist without variant')
        }
        playlistUrl = HlsDownloader.resolveUrl(playlistUrl, variant)
        text = await HttpDownloader.getString(playlistUrl, o.referer)
      } else {
        break
      }
    }
    // 2. 从媒体播放列表内容提取分片并合并下载
    await HlsDownloader.downloadSegmentsFromText(text, playlistUrl, destPath, o)
  }

  /** 已有播放列表内容时直接解析分片并合并下载（省一次列表请求） */
  static async downloadSegmentsFromText(text: string, playlistUrl: string, destPath: string,
    opts: HlsOptions | null): Promise<void> {
    if (!text.trimStart().startsWith('#EXTM3U')) {
      throw new Error('not an HLS playlist')
    }
    // 直播流无 ENDLIST，分片持续增长无法下载完整
    if (!text.includes('#EXT-X-ENDLIST')) {
      throw new Error('live stream not supported')
    }
    const o: HlsOptions = opts ?? new HlsOptions()
    const segments: HlsSegment[] = HlsDownloader.parseMediaPlaylist(text, playlistUrl)
    if (segments.length === 0) {
      throw new Error('HLS playlist has no segments')
    }
    if (o.startSegIndex >= segments.length) {
      // 续传点越界（列表变化等）：视为已全部完成
      if (o.onProgress !== null) {
        o.onProgress(segments.length, segments.length, o.startOffset, o.startOffset)
      }
      return
    }
    // 3. 并发下载分片、按序追加合并为单文件（MPEG-TS 直接拼接即可播放）；
    //    乱序完成的分片缓冲在内存等待队首，字节回压约束缓冲上限防内存膨胀；
    //    续传时截断到已完成边界（中止分片可能残留越界数据），并从断点分片继续
    let openMode: number = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    if (o.startOffset > 0 && fileIo.accessSync(destPath)) {
      fileIo.truncateSync(destPath, o.startOffset)
      openMode = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE
    }
    const file: fileIo.File = fileIo.openSync(destPath, openMode)
    const tmpBase: string = `${destPath}.part`
    // 本次下载的并发数（启动时读一次设置，中途改配置不影响进行中任务）
    const conc: number = segmentConcurrency()
    const keyCache: Map<string, Uint8Array> = new Map<string, Uint8Array>()
    // 本地中止旗标：整体失败/暂停/退出时联动停掉所有在途分片请求
    const localAbort: AbortFlag = new AbortFlag()
    const segOpts: HlsOptions = new HlsOptions()
    segOpts.referer = o.referer
    segOpts.abort = localAbort
    let offset: number = o.startOffset
    let segDone: number = o.startSegIndex
    let appendIdx: number = o.startSegIndex
    let nextFetch: number = o.startSegIndex
    let bufferedBytes: number = 0
    let failed: Error | null = null
    let finished: boolean = false
    const pending: Map<number, Uint8Array> = new Map<number, Uint8Array>()
    const liveRecv: Map<number, number> = new Map<number, number>()
    const inFlight: Set<number> = new Set<number>()
    const tmpPool: string[] = []
    for (let w: number = 0; w < conc; w++) {
      tmpPool.push(`${tmpBase}${w}`)
    }

    // 进度双值上报：已收字节（含乱序缓冲与在途，速度平滑）+ 已写盘字节（续传锚点）。
    // 两者必须分离：落库 receivedSize 若含缓冲/在途会超前实际文件大小，
    // 重启续传校验（文件大小 ≥ 记录值）必然失败，断点被误判损坏清零重下
    const reportProgress = (): void => {
      if (finished || o.onProgress === null) {
        return
      }
      let live: number = 0
      liveRecv.forEach((v: number): void => {
        live += v
      })
      o.onProgress(segDone, segments.length, offset + bufferedBytes + live, offset)
    }

    const spawnFetch = (i: number): void => {
      inFlight.add(i)
      const tmp: string = tmpPool[tmpPool.length - 1]
      tmpPool.pop()
      HlsDownloader.fetchSegment(segments[i], tmp, keyCache, segOpts, (recv: number): void => {
        liveRecv.set(i, recv)
        reportProgress()
      })
        .then((plain: Uint8Array): void => {
          liveRecv.delete(i)
          inFlight.delete(i)
          tmpPool.push(tmp)
          pending.set(i, plain)
          bufferedBytes += plain.byteLength
          reportProgress()
        })
        .catch((e: BusinessError): void => {
          liveRecv.delete(i)
          inFlight.delete(i)
          tmpPool.push(tmp)
          if (failed === null) {
            const msg: string = e !== null && e !== undefined && e.message !== undefined && e.message !== ''
              ? `${e.code ?? ''}: ${e.message}` : `${e}`
            failed = new Error(msg)
          }
        })
    }

    try {
      while (appendIdx < segments.length) {
        if (failed !== null) {
          const err: Error = failed
          localAbort.aborted = true
          throw err
        }
        if (o.abort !== null && o.abort.aborted) {
          localAbort.aborted = true
          throw new Error('aborted')
        }
        // 发起新分片：并发连接数与乱序缓冲字节双重约束
        while (nextFetch < segments.length && inFlight.size < conc &&
          bufferedBytes < HLS_MAX_BUFFERED) {
          spawnFetch(nextFetch)
          nextFetch++
        }
        const head: Uint8Array | undefined = pending.get(appendIdx)
        if (head !== undefined) {
          // 队首分片就绪：按序追加写盘
          pending.delete(appendIdx)
          bufferedBytes -= head.byteLength
          const n: number = await fileIo.write(file.fd, head.buffer,
            { offset: offset, length: head.byteLength })
          offset += n
          appendIdx++
          segDone = appendIdx
          reportProgress()
          continue
        }
        await HlsDownloader.sleep(20)
      }
    } finally {
      // 退出联动：停掉所有在途分片请求并清理分片临时文件（成功时无在途，无副作用）
      finished = true
      localAbort.aborted = true
      fileIo.closeSync(file)
      for (let w: number = 0; w < conc; w++) {
        try {
          if (fileIo.accessSync(`${tmpBase}${w}`)) {
            fileIo.unlinkSync(`${tmpBase}${w}`)
          }
        } catch (e) {
          logger.debug(`清理分片临时文件失败: ${e}`)
        }
      }
    }
  }

  /**
   * 下载单个分片（明文/加密自适应 + 分片内断点续传 + 自适应重试），返回明文字节
   * @param onRecv 分片累计已收字节回调（进度上报用）
   */
  private static async fetchSegment(seg: HlsSegment, tmpPath: string, keyCache: Map<string, Uint8Array>,
    o: HlsOptions, onRecv: (received: number) => void): Promise<Uint8Array> {
    let lastError: string = 'download failed'
    // 分片内断点：截断重试只补缺失尾部（代理掐断多发生在响应尾段，整片重下成功率极低）
    let segRecv: number = 0
    // 自适应重试：只要每次尝试有推进（断点前移）就不消耗放弃预算，
    // 连续无进展才计数（SEGMENT_RETRIES 次后放弃）；attempts 上限防病态循环
    let noProgress: number = 0
    let attempts: number = 0
    while (noProgress < SEGMENT_RETRIES && attempts < MAX_SEGMENT_ATTEMPTS) {
      attempts++
      if (o.abort !== null && o.abort.aborted) {
        throw new Error('aborted')
      }
      const attemptStart: number = segRecv
      try {
        let plain: Uint8Array
        if (seg.keyUrl === '') {
          // 明文分片：落临时文件读回（重试可从断点续传）
          const so: StreamOptions = new StreamOptions()
          so.startOffset = segRecv
          so.resume = segRecv > 0
          so.referer = o.referer
          so.abort = o.abort
          so.onProgress = (received: number, total: number): void => {
            segRecv = received
            onRecv(received)
          }
          await HttpDownloader.downloadToFile(seg.url, tmpPath, so)
          plain = HlsDownloader.readAllBytes(tmpPath)
        } else {
          // 加密分片：密文落临时文件 → 读入解密（密文字节数≈明文）
          const key: Uint8Array = await HlsDownloader.fetchKey(seg.keyUrl, keyCache, o.referer)
          const iv: Uint8Array = HlsDownloader.ivOf(seg)
          const co: StreamOptions = new StreamOptions()
          co.startOffset = segRecv
          co.resume = segRecv > 0
          co.referer = o.referer
          co.abort = o.abort
          co.onProgress = (received: number, total: number): void => {
            segRecv = received
            onRecv(received)
          }
          await HttpDownloader.downloadToFile(seg.url, tmpPath, co)
          const cipherData: Uint8Array = HlsDownloader.readAllBytes(tmpPath)
          if (cipherData.byteLength % 16 !== 0 || cipherData.byteLength === 0) {
            // 长度非 16 对齐：多半是截断的响应或 200 错误页，解密前直接判失败
            logger.warn(`cipher data invalid: len=${cipherData.byteLength} head=${HlsDownloader.headText(cipherData)}`)
            throw new Error(`cipher data misaligned (${cipherData.byteLength} bytes)`)
          }
          plain = await HlsDownloader.aesCbcDecrypt(key, iv, cipherData)
        }
        return plain
      } catch (e) {
        // 中止立即退出，不参与重试
        if (o.abort !== null && o.abort.aborted) {
          throw new Error('aborted')
        }
        // requestInStream 的网络异常以非 Error 对象抛出（直接字符串化是 [object Object]），取 BusinessError 信息
        const be: BusinessError = e as BusinessError
        lastError = be !== null && be !== undefined && be.message !== undefined && be.message !== ''
          ? `${be.code ?? ''}: ${be.message}` : `${e}`
        // 有推进（断点前移）不计数：掐连接的网络下每次续传只送 8~32KB，
        // 数次数放弃会差几百字节前功尽弃（实锤：5 次推进到只差 561 字节时耗尽预算）
        if (segRecv > attemptStart) {
          noProgress = 0
        } else {
          noProgress++
        }
        logger.warn(`segment failed (attempt ${attempts}, no-progress ${noProgress}/${SEGMENT_RETRIES}): ` +
          `${seg.url} ${lastError}`)
        // 指数退避按无进展次数escalate（0.5/1/2/4s 封顶）：有推进时快速重试只补小尾巴，
        // 连续无进展（网络断了/节点失效）逐步拉长间隔，跨过网络切换抖动窗口
        await HlsDownloader.sleep(Math.min(4000, 500 * Math.pow(2, noProgress)))
      }
    }
    throw new Error(`segment download failed: ${lastError}`)
  }

  /**
   * 解析媒体播放列表为分片列表：
   * 逐行维护 EXT-X-KEY 加密状态（METHOD=NONE 清除、AES-128 设置、其余抛错），
   * EXT-X-MAP 初始化段插到队首；分片 media sequence 号自 EXT-X-MEDIA-SEQUENCE 起递增
   */
  private static parseMediaPlaylist(text: string, playlistUrl: string): HlsSegment[] {
    const lines: string[] = text.split('\n')
    const segments: HlsSegment[] = []
    let mediaSequence: number = 0
    let seqSeen: boolean = false
    let keyUrl: string = ''
    let ivHex: string = ''
    let initSegment: string = ''
    let segIndex: number = 0
    for (const raw of lines) {
      const line: string = raw.trim()
      if (line === '') {
        continue
      }
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
        const v: string = HlsDownloader.attrValue(line, '#EXT-X-MEDIA-SEQUENCE')
        const n: number = Number(v)
        if (!Number.isNaN(n)) {
          mediaSequence = n
          seqSeen = true
        }
        continue
      }
      if (line.startsWith('#EXT-X-KEY')) {
        const method: string = HlsDownloader.attrValue(line, 'METHOD')
        if (method === 'NONE') {
          keyUrl = ''
          ivHex = ''
          continue
        }
        if (method !== 'AES-128') {
          // SAMPLE-AES 等其他加密方式不支持
          throw new Error('encrypted HLS not supported')
        }
        const uri: string = HlsDownloader.attrValue(line, 'URI')
        if (uri === '') {
          throw new Error('encrypted HLS key without URI')
        }
        keyUrl = HlsDownloader.resolveUrl(playlistUrl, uri)
        ivHex = HlsDownloader.attrValue(line, 'IV')
        continue
      }
      if (line.startsWith('#EXT-X-MAP')) {
        const uri: string = HlsDownloader.attrValue(line, 'URI')
        if (uri !== '') {
          initSegment = HlsDownloader.resolveUrl(playlistUrl, uri)
        }
        continue
      }
      if (line.startsWith('#')) {
        continue
      }
      // 分片行（KEY 状态作用到本分片）
      const segSeq: number = seqSeen ? mediaSequence + segIndex : segIndex
      segments.push(new HlsSegment(HlsDownloader.resolveUrl(playlistUrl, line), keyUrl, ivHex, segSeq))
      segIndex++
    }
    if (initSegment !== '') {
      segments.unshift(new HlsSegment(initSegment, '', '', 0))
    }
    return segments
  }

  /** 取密钥（缓存去重；支持 http(s) 与 data:base64 URI） */
  private static async fetchKey(keyUrl: string, cache: Map<string, Uint8Array>,
    referer: string): Promise<Uint8Array> {
    const hit: Uint8Array | undefined = cache.get(keyUrl)
    if (hit !== undefined) {
      return hit
    }
    let key: Uint8Array
    if (keyUrl.startsWith('data:')) {
      key = HlsDownloader.decodeDataUri(keyUrl)
    } else {
      key = await HttpDownloader.getArrayBuffer(keyUrl, referer)
    }
    if (key.byteLength !== 16) {
      throw new Error('invalid HLS key length')
    }
    cache.set(keyUrl, key)
    return key
  }

  /** data:[<mediatype>][;base64],<data> 形式密钥（base64 解码为 16 字节） */
  private static decodeDataUri(uri: string): Uint8Array {
    const commaIdx: number = uri.indexOf(',')
    if (commaIdx < 0 || !uri.substring(0, commaIdx).includes('base64')) {
      throw new Error('unsupported HLS key data URI')
    }
    const helper: util.Base64Helper = new util.Base64Helper()
    return helper.decodeSync(uri.substring(commaIdx + 1))
  }

  /** 分片 IV：KEY 行 IV 属性（hex），缺省用 media sequence 号的 128 位大端表示 */
  private static ivOf(seg: HlsSegment): Uint8Array {
    if (seg.ivHex !== '') {
      return HlsDownloader.hexToBytes(seg.ivHex)
    }
    const iv: Uint8Array = new Uint8Array(16)
    let s: number = seg.seq
    for (let i = 15; i >= 0 && s > 0; i--) {
      iv[i] = s % 256
      s = Math.floor(s / 256)
    }
    return iv
  }

  /** hex 字符串（可带 0x/0X 前缀）转字节数组 */
  private static hexToBytes(hex: string): Uint8Array {
    let h: string = hex.trim()
    if (h.startsWith('0x') || h.startsWith('0X')) {
      h = h.substring(2)
    }
    if (h.length % 2 !== 0) {
      throw new Error('invalid IV hex')
    }
    const out: Uint8Array = new Uint8Array(h.length / 2)
    for (let i = 0; i < out.length; i++) {
      const v: number = parseInt(h.substring(i * 2, i * 2 + 2), 16)
      if (Number.isNaN(v)) {
        throw new Error('invalid IV hex')
      }
      out[i] = v
    }
    return out
  }

  /** AES-128-CBC(PKCS7) 解密单个分片 */
  private static async aesCbcDecrypt(key: Uint8Array, iv: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    const keyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128')
    const keyBlob: cryptoFramework.DataBlob = { data: key }
    const symKey: cryptoFramework.SymKey = await keyGen.convertKey(keyBlob)
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7')
    const ivBlob: cryptoFramework.DataBlob = { data: iv }
    const params: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: ivBlob
    }
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params)
    const input: cryptoFramework.DataBlob = { data }
    const mid: cryptoFramework.DataBlob = await cipher.update(input)
    const tail: cryptoFramework.DataBlob | null = await cipher.doFinal(null)
    if (tail === null || tail.data.byteLength === 0) {
      return mid.data
    }
    // 拼接 update 与 doFinal 输出
    const out: Uint8Array = new Uint8Array(mid.data.byteLength + tail.data.byteLength)
    out.set(mid.data, 0)
    out.set(tail.data, mid.data.byteLength)
    return out
  }

  /** 读小文件全部字节（加密分片密文，单分片常见 1~10MB） */
  private static readAllBytes(path: string): Uint8Array {
    const stat: fileIo.Stat = fileIo.statSync(path)
    const buf: ArrayBuffer = new ArrayBuffer(stat.size)
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    try {
      fileIo.readSync(file.fd, buf)
    } finally {
      fileIo.closeSync(file)
    }
    return new Uint8Array(buf)
  }

  /** 取字节数组前 32 字节的可读文本（用于错误页/截断内容的日志辨识） */
  private static headText(data: Uint8Array): string {
    let out: string = ''
    const n: number = Math.min(32, data.byteLength)
    for (let i = 0; i < n; i++) {
      const b: number = data[i]
      out += b >= 32 && b < 127 ? String.fromCharCode(b) : '.'
    }
    return out
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout(resolve, ms)
    })
  }

  /** 取 tag 行之后第一个非空非注释行（master 变体地址） */
  private static lineAfter(text: string, tag: string): string {
    const lines: string[] = text.split('\n')
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith(tag)) {
        for (let j = i + 1; j < lines.length; j++) {
          const line: string = lines[j].trim()
          if (line !== '' && !line.startsWith('#')) {
            return line
          }
        }
      }
    }
    return ''
  }

  /**
   * 提取标签行属性值：
   * - 形如 `#EXT-X-KEY:METHOD=AES-128,URI="..."` 的 `属性=` 项（不带引号或带引号）
   * - 形如 `#EXT-X-MEDIA-SEQUENCE:123` 的标签直取值（attr 为标签名时）
   */
  private static attrValue(line: string, attr: string): string {
    const marker: string = `${attr}=`
    const idx: number = line.indexOf(marker)
    if (idx >= 0) {
      const rest: string = line.substring(idx + marker.length)
      if (rest.startsWith('"')) {
        const end: number = rest.indexOf('"', 1)
        if (end > 1) {
          return rest.substring(1, end)
        }
        return ''
      }
      const comma: number = rest.indexOf(',')
      return comma >= 0 ? rest.substring(0, comma) : rest
    }
    // 标签名直取值（TAG:VALUE）
    const tagIdx: number = line.indexOf(`${attr}:`)
    if (tagIdx >= 0) {
      const rest: string = line.substring(tagIdx + attr.length + 1)
      const comma: number = rest.indexOf(',')
      return (comma >= 0 ? rest.substring(0, comma) : rest).trim()
    }
    return ''
  }

  /** 相对/绝对/协议相对分片地址 → 基于播放列表地址的绝对地址 */
  static resolveUrl(playlistUrl: string, line: string): string {
    if (line.startsWith('http://') || line.startsWith('https://')) {
      return line
    }
    const schemeEnd: number = playlistUrl.indexOf('://')
    if (schemeEnd < 0) {
      return line
    }
    if (line.startsWith('//')) {
      return playlistUrl.substring(0, schemeEnd) + ':' + line
    }
    if (line.startsWith('/')) {
      // origin + 绝对路径
      const pathStart: number = playlistUrl.indexOf('/', schemeEnd + 3)
      const origin: string = pathStart < 0 ? playlistUrl : playlistUrl.substring(0, pathStart)
      return origin + line
    }
    // 相对播放列表所在目录
    const slash: number = playlistUrl.lastIndexOf('/')
    return playlistUrl.substring(0, slash + 1) + line
  }
}
