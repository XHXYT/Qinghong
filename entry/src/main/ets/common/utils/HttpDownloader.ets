import { http, connection } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { createLogger } from './Logger';
import { ProxyUtils } from './ProxyUtils';
import { appSettings } from '../entity/SettingsModel';

const logger = createLogger('HttpDownloader')

/** 浏览器式 UA，降低 CDN 拒绝概率 */
const BROWSER_UA: string =
  'Mozilla/5.0 (Linux; Android 12) Mobile AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

/** 暂停/中止标记：置 aborted 后流式下载在下一个数据块处中止并抛 'aborted' */
export class AbortFlag {
  aborted: boolean = false
}

/** 流式下载选项 */
export class StreamOptions {
  /** 数据写入文件的起始偏移（断点续传 / 分片追加） */
  startOffset: number = 0
  /** 断点续传：startOffset > 0 时携带 Range 头，服务器忽略 Range 返回 200 时自动从头重写 */
  resume: boolean = false
  /** 来源页面地址（防盗链 Referer 校验；空 = 不携带） */
  referer: string = ''
  abort: AbortFlag | null = null
  /** 进度回调（全量累计接收字节 / 总字节，-1 未知） */
  onProgress: ((received: number, total: number) => void) | null = null
}

/**
 * HTTP 流式下载工具：
 * request 接口响应默认上限 5MB，大文件/媒体必须走 requestInStream 分块接收写盘。
 * request.downloadFile 的 filePath 仅支持应用沙箱路径（写公共下载目录会任务失败），
 * 故本工具统一流式写调用方指定路径（建议沙箱临时文件，完成后拷入公共目录）。
 */
export class HttpDownloader {

  static readonly UA: string = BROWSER_UA
  private static readonly MAX_REDIRECTS: number = 10

  /** URL 是否疑似 HLS 播放列表（.m3u8 后缀，兼容签名链接 query 中携带） */
  static looksLikeM3u8(url: string): boolean {
    const lower: string = url.toLowerCase()
    if (lower.split('?')[0].split('#')[0].endsWith('.m3u8')) {
      return true
    }
    return lower.includes('.m3u8')
  }

  /** GET 文本内容（播放列表等小资源），自动跟随重定向 */
  static async getString(url: string, referer: string = ''): Promise<string> {
    let current: string = url
    for (let i = 0; i <= HttpDownloader.MAX_REDIRECTS; i++) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          readTimeout: 30000,
          connectTimeout: 20000,
          expectDataType: http.HttpDataType.STRING,
          header: HttpDownloader.buildHeader(referer)
        }
        HttpDownloader.applyProxy(current, options)
        const resp: http.HttpResponse = await req.request(current, options)
        if (resp.responseCode >= 200 && resp.responseCode < 300) {
          return typeof resp.result === 'string' ? resp.result : ''
        }
        if (resp.responseCode >= 300 && resp.responseCode < 400) {
          const location: string = HttpDownloader.headerOf(resp.header, 'location')
          if (location !== '') {
            current = location
            continue
          }
        }
        throw new Error(`HTTP ${resp.responseCode}`)
      } finally {
        req.destroy()
      }
    }
    throw new Error('too many redirects')
  }

  /** GET 二进制内容（HLS 密钥等小资源），自动跟随重定向 */
  static async getArrayBuffer(url: string, referer: string = ''): Promise<Uint8Array> {
    let current: string = url
    for (let i = 0; i <= HttpDownloader.MAX_REDIRECTS; i++) {
      const req: http.HttpRequest = http.createHttp()
      try {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          readTimeout: 30000,
          connectTimeout: 20000,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          header: HttpDownloader.buildHeader(referer)
        }
        HttpDownloader.applyProxy(current, options)
        const resp: http.HttpResponse = await req.request(current, options)
        if (resp.responseCode >= 200 && resp.responseCode < 300) {
          if (resp.result instanceof ArrayBuffer) {
            return new Uint8Array(resp.result)
          }
          throw new Error('unexpected response type')
        }
        if (resp.responseCode >= 300 && resp.responseCode < 400) {
          const location: string = HttpDownloader.headerOf(resp.header, 'location')
          if (location !== '') {
            current = location
            continue
          }
        }
        throw new Error(`HTTP ${resp.responseCode}`)
      } finally {
        req.destroy()
      }
    }
    throw new Error('too many redirects')
  }

  /**
   * 流式下载 url 到文件：
   * - 默认覆盖写；opts.startOffset > 0 且目标已存在时先截断到 startOffset 再续写
   *   （中止时可能有越界残留数据）
   */
  static async downloadToFile(url: string, destPath: string, opts: StreamOptions | null): Promise<void> {
    const o: StreamOptions = opts ?? new StreamOptions()
    let mode: number = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    if (o.startOffset > 0 && fileIo.accessSync(destPath)) {
      fileIo.truncateSync(destPath, o.startOffset)
      mode = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE
    }
    const file: fileIo.File = fileIo.openSync(destPath, mode)
    try {
      await HttpDownloader.copyStreamTo(url, file.fd, o)
    } finally {
      fileIo.closeSync(file)
    }
  }

  /**
   * 流式下载 url 并从 opts.startOffset 起写入已打开的文件 fd
   * （普通下载、断点续传与 HLS 分片合并共用）；自动跟随重定向，返回本次写入的字节数
   */
  static copyStreamTo(url: string, fd: number, opts: StreamOptions | null): Promise<number> {
    const o: StreamOptions = opts ?? new StreamOptions()
    return new Promise<number>((resolve: (n: number) => void, reject: (e: Error) => void) => {
      HttpDownloader.streamOnce(url, fd, o, 0, resolve, reject)
    })
  }

  /** 单次流式请求；3xx 时销毁当前请求并递归跟随 location */
  private static streamOnce(url: string, fd: number, o: StreamOptions, redirects: number,
    resolve: (n: number) => void, reject: (e: Error) => void): void {
    if (redirects > HttpDownloader.MAX_REDIRECTS) {
      reject(new Error('too many redirects'))
      return
    }
    if (o.abort !== null && o.abort.aborted) {
      reject(new Error('aborted'))
      return
    }
    const req: http.HttpRequest = http.createHttp()
    let location: string = ''
    let code: number = -1
    let codeKnown: boolean = false
    let ended: boolean = false
    let settled: boolean = false
    let writeOffset: number = o.startOffset
    let base: number = o.startOffset
    let total: number = -1
    let written: number = 0
    let writeChain: Promise<void> = Promise.resolve()
    let lastDataAt: number = Date.now()
    let watchdogId: number = -1

    const stopWatchdog = (): void => {
      if (watchdogId >= 0) {
        clearInterval(watchdogId)
        watchdogId = -1
      }
    }

    const finish = (err?: Error): void => {
      if (settled) {
        return
      }
      settled = true
      stopWatchdog()
      writeChain
        .catch((): void => {
        })
        .then((): void => {
          HttpDownloader.destroyRequest(req)
          if (err !== undefined) {
            reject(err)
          } else if (total > 0 && base + written < total) {
            // 连接提前断开时 dataEnd 仍触发：响应体不完整视为失败，交由上层重试
            reject(new Error(`truncated response (${base + written}/${total})`))
          } else {
            resolve(written)
          }
        })
    }

    // 响应码与数据接收都完成才能得出结论（promise 与流事件时序不固定）
    const trySettle = (): void => {
      if (settled || !codeKnown || !ended) {
        return
      }
      if (code >= 200 && code < 300) {
        finish()
        return
      }
      if (code >= 300 && code < 400 && location !== '') {
        settled = true
        stopWatchdog()
        writeChain
          .catch((): void => {
          })
          .then((): void => {
            HttpDownloader.destroyRequest(req)
            HttpDownloader.streamOnce(location, fd, o, redirects + 1, resolve, reject)
          })
        return
      }
      finish(new Error(`HTTP ${code}`))
    }

    req.on('headersReceive', (header: Object): void => {
      location = HttpDownloader.headerOf(header, 'location')
      if (location !== '') {
        // 重定向响应：不改动续传状态
        return
      }
      const contentRange: string = HttpDownloader.headerOf(header, 'content-range')
      const lenStr: string = HttpDownloader.headerOf(header, 'content-length')
      const len: number = lenStr !== '' && !Number.isNaN(Number(lenStr)) ? Number(lenStr) : -1
      if (o.resume && o.startOffset > 0) {
        if (contentRange !== '') {
          // 206：bytes x-y/total
          const slash: number = contentRange.indexOf('/')
          const tStr: string = slash >= 0 ? contentRange.substring(slash + 1) : ''
          total = tStr !== '' && !Number.isNaN(Number(tStr)) ? Number(tStr) : -1
        } else {
          // 服务器忽略 Range 返回 200 全量：从头重写
          writeOffset = 0
          base = 0
          total = len
        }
      } else {
        total = len
      }
    })
    req.on('dataReceive', (data: ArrayBuffer): void => {
      lastDataAt = Date.now()
      if (o.abort !== null && o.abort.aborted) {
        finish(new Error('aborted'))
        return
      }
      if (settled || (codeKnown && code >= 300)) {
        // 重定向响应体不落盘
        return
      }
      const chunk: ArrayBuffer = data
      writeChain = writeChain
        .then((): Promise<number> => {
          if (settled) {
            return Promise.resolve(0)
          }
          return fileIo.write(fd, chunk, { offset: writeOffset, length: chunk.byteLength })
        })
        .then((n: number): void => {
          writeOffset += n
          written += n
          if (o.onProgress !== null) {
            o.onProgress(base + written, total)
          }
        })
        .catch((e: Object): void => {
          finish(new Error(HttpDownloader.errText(e)))
        })
    })
    req.on('dataEnd', (): void => {
      ended = true
      trySettle()
    })
    // 看门狗：连接静默挂死（代理节点失效不发 FIN）时 readTimeout 要等满 10 分钟，
    // 这里 20 秒收不到任何数据即判定死连接，快速失败交由上层重试
    watchdogId = setInterval((): void => {
      if (settled) {
        return
      }
      // 暂停请求在挂死连接（无数据流动、dataReceive 不触发）下也要及时生效
      if (o.abort !== null && o.abort.aborted) {
        finish(new Error('aborted'))
        return
      }
      if (Date.now() - lastDataAt > 20000) {
        finish(new Error('stalled: no data for 20s'))
      }
    }, 5000)
    const header: Record<string, string> = HttpDownloader.buildHeader(o.referer)
    // 下载取原始字节：禁用压缩与缓存，保证 Content-Length 与落盘字节数一致可校验
    header['accept-encoding'] = 'identity'
    if (o.resume && o.startOffset > 0) {
      header['range'] = `bytes=${o.startOffset}-`
    }
    const reqOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      // readTimeout 为请求总时长（含传输），大文件需更长超时
      readTimeout: 600000,
      connectTimeout: 20000,
      usingCache: false,
      header: header
    }
    HttpDownloader.applyProxy(url, reqOptions)
    req.requestInStream(url, reqOptions)
      .then((c: number): void => {
        code = c
        codeKnown = true
        trySettle()
      })
      .catch((e: Object): void => {
        finish(new Error(HttpDownloader.errText(e)))
      })
  }

  /** SDK 异常转可读文本（BusinessError 直接字符串化是 [object Object]，取 code/message） */
  private static errText(e: Object): string {
    const be: BusinessError = e as BusinessError
    if (be !== null && be !== undefined && be.message !== undefined && be.message !== '') {
      const c: string = be.code !== undefined ? `${be.code}: ` : ''
      return `${c}${be.message}`
    }
    return `${e}`
  }

  /** 构造请求头：浏览器 UA + 可选 Referer（防盗链校验） */
  private static buildHeader(referer: string): Record<string, string> {
    const header: Record<string, string> = { 'user-agent': BROWSER_UA }
    if (referer !== '') {
      header['referer'] = referer
    }
    return header
  }

  /**
   * 命中应用代理分流时注入自定义代理（下载与内核同套「走代理」规则，按 URL 域名匹配）：
   * http 代理走 usingProxy；socks 代理走 usingSocks5Proxy（优先级高于 usingProxy，http 层强制直连）；
   * 未命中分流不动配置（维持系统默认代理行为）。
   */
  private static applyProxy(url: string, options: http.HttpRequestOptions): void {
    if (!ProxyUtils.shouldProxyUrl(url)) {
      return
    }
    const host: string = appSettings.proxy_host.trim()
    const port: number = appSettings.proxy_port
    if (appSettings.proxy_type === 'socks') {
      const s: connection.Socks5Proxy = { host: host, port: port }
      options.usingSocks5Proxy = s
      options.usingProxy = false
    } else {
      const p: connection.HttpProxy = { host: host, port: port, exclusionList: [] }
      options.usingProxy = p
    }
  }

  /** 从响应头对象取指定头域值（头域名大小写不敏感），不存在返回 '' */
  private static headerOf(header: Object, name: string): string {
    try {
      const h: Record<string, string> = header as Record<string, string>
      const lower: string = name.toLowerCase()
      const keys: string[] = Object.keys(h)
      for (const k of keys) {
        if (k.toLowerCase() === lower) {
          return h[k]
        }
      }
    } catch (e) {
      logger.debug(`headerOf failed: ${e}`)
    }
    return ''
  }

  private static destroyRequest(req: http.HttpRequest): void {
    try {
      req.off('headersReceive')
      req.off('dataReceive')
      req.off('dataEnd')
      req.destroy()
    } catch (e) {
      logger.debug(`destroy request failed: ${e}`)
    }
  }
}
