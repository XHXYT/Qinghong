import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { createLogger } from '../app/Logger';

const logger = createLogger('ExtRes')

/**
 * 扩展资源主机：
 * 主 URL 形式为自定义协议 qinghong-extension://<extId>/<path>
 * （EntryAbility customizeSchemes 注册：standard+secure+CORS+fetch+CSP bypass，
 *   origin 语义对齐 chrome-extension://，IndexedDB/localStorage 可用，页面 CSP 不拦截扩展资源）；
 * https://<extId>.extension.qinghong.local/<path> 虚拟域与 chrome-extension:// 前缀
 * 同样拦截作兼容兜底。
 */
export const EXT_RES_HOST: string = 'extension.qinghong.local'

/** 扩展自定义协议名（customizeSchemes 注册） */
export const EXT_SCHEME: string = 'qinghong-extension'

/** 扩展自定义协议 URL 前缀 */
export const EXT_SCHEME_PREFIX: string = `${EXT_SCHEME}://`

/** MIME 映射项（textual = 文本类需显式编码） */
class ExtMimeEntry {
  readonly mime: string
  readonly textual: boolean

  constructor(mime: string, textual: boolean) {
    this.mime = mime
    this.textual = textual
  }
}

/**
 * 扩展资源服务：onInterceptRequest 拦截 qinghong-extension:// / chrome-extension:// 与虚拟域请求，
 * 从应用沙箱解包目录读取文件构造 WebResourceResponse
 */
export class ExtensionResources {
  private static readonly CRX_PREFIX: string = 'chrome-extension://'
  private static readonly VHOST_SUFFIX: string = `.${EXT_RES_HOST}`
  private static readonly VHOST_LEGACY_PREFIX: string = `https://${EXT_RES_HOST}/`
  /** 虚拟域直接回 WebResourceResponse，不受 runJavaScript 注入限制；AdGuard background.js 8.7MB */
  private static readonly MAX_FILE_BYTES: number = 64 * 1024 * 1024

  private static readonly MIME: Record<string, ExtMimeEntry> = {
    'html': new ExtMimeEntry('text/html', true),
    'htm': new ExtMimeEntry('text/html', true),
    'css': new ExtMimeEntry('text/css', true),
    'js': new ExtMimeEntry('application/javascript', true),
    'mjs': new ExtMimeEntry('application/javascript', true),
    'json': new ExtMimeEntry('application/json', true),
    'txt': new ExtMimeEntry('text/plain', true),
    'xml': new ExtMimeEntry('application/xml', true),
    'csv': new ExtMimeEntry('text/csv', true),
    'map': new ExtMimeEntry('application/json', true),
    'png': new ExtMimeEntry('image/png', false),
    'jpg': new ExtMimeEntry('image/jpeg', false),
    'jpeg': new ExtMimeEntry('image/jpeg', false),
    'gif': new ExtMimeEntry('image/gif', false),
    'svg': new ExtMimeEntry('image/svg+xml', true),
    'webp': new ExtMimeEntry('image/webp', false),
    'ico': new ExtMimeEntry('image/x-icon', false),
    'bmp': new ExtMimeEntry('image/bmp', false),
    'woff': new ExtMimeEntry('font/woff', false),
    'woff2': new ExtMimeEntry('font/woff2', false),
    'ttf': new ExtMimeEntry('font/ttf', false),
    'otf': new ExtMimeEntry('font/otf', false),
    'eot': new ExtMimeEntry('application/vnd.ms-fontobject', false),
    'pdf': new ExtMimeEntry('application/pdf', false),
    'mp3': new ExtMimeEntry('audio/mpeg', false),
    'mp4': new ExtMimeEntry('video/mp4', false),
    'webm': new ExtMimeEntry('video/webm', false),
    'ogg': new ExtMimeEntry('audio/ogg', false),
    'oga': new ExtMimeEntry('audio/ogg', false),
    'opus': new ExtMimeEntry('audio/ogg', false),
    'wav': new ExtMimeEntry('audio/wav', false),
    'flac': new ExtMimeEntry('audio/flac', false),
    'avif': new ExtMimeEntry('image/avif', false),
    'webmanifest': new ExtMimeEntry('application/manifest+json', true),
    'xhtml': new ExtMimeEntry('application/xhtml+xml', true),
    'vtt': new ExtMimeEntry('text/vtt', true),
    'wasm': new ExtMimeEntry('application/wasm', false)
  }

  /** background 宿主虚拟页路径（bg Web 主文档；无实体文件，respond 兜底合成最小 HTML，
   *  https 虚拟域 origin 使 IndexedDB/localStorage 可用——about:blank 的 opaque origin 下 IDB 被拒） */
  static readonly BG_PAGE_PATH: string = '__bg__.html'

  /** 扩展资源虚拟 URL（getURL / popup 主文档地址）：qinghong-extension://<extId>/<path> */
  static extUrl(extId: string, path: string): string {
    const clean: string = path.replace(/^\/+/, '')
    return `${EXT_SCHEME_PREFIX}${extId}/${clean}`
  }

  /** 请求是否指向扩展资源（onInterceptRequest 首行守卫，须轻量：仅前缀/包含判断） */
  static isExtRequest(url: string): boolean {
    return url.startsWith(EXT_SCHEME_PREFIX)
      || url.startsWith(ExtensionResources.CRX_PREFIX)
      || url.includes(`${ExtensionResources.VHOST_SUFFIX}/`)
      || url.startsWith(ExtensionResources.VHOST_LEGACY_PREFIX)
  }

  /**
   * 构造拦截响应：解析 extId/path → 读沙箱文件 → WebResourceResponse；
   * 非扩展请求返回 null（按原方式加载）；文件缺失/非法路径返回 404 响应
   * @param url 请求 URL（<extId>.<host>/<path> 子域虚拟域 / chrome-extension:// / 旧路径格式）
   * @param extRootDir 扩展解包根目录（<filesDir>/extensions）
   */
  static respond(url: string, extRootDir: string): WebResourceResponse | null {
    if (url.startsWith(EXT_SCHEME_PREFIX)) {
      return ExtensionResources.respondRest(url.substring(EXT_SCHEME_PREFIX.length), extRootDir)
    }
    if (url.startsWith(ExtensionResources.CRX_PREFIX)) {
      return ExtensionResources.respondRest(url.substring(ExtensionResources.CRX_PREFIX.length), extRootDir)
    }
    if (!url.startsWith('https://')) {
      return null
    }
    const noScheme: string = url.substring('https://'.length)
    const slash: number = noScheme.indexOf('/')
    const authority: string = slash < 0 ? noScheme : noScheme.substring(0, slash)
    const restPath: string = slash < 0 ? '' : noScheme.substring(slash + 1)
    // 子域虚拟主机（现网格式）：<extId>.<host>/<path>，每扩展独立 origin
    if (authority.endsWith(ExtensionResources.VHOST_SUFFIX)) {
      const extId: string = authority.substring(0, authority.length - ExtensionResources.VHOST_SUFFIX.length)
      if (!/^[a-p0-9]{32}$/.test(extId)) {
        return null
      }
      return ExtensionResources.respondRest(`${extId}/${restPath}`, extRootDir)
    }
    // 旧路径格式：<host>/<extId>/<path>
    if (authority === EXT_RES_HOST) {
      return ExtensionResources.respondRest(restPath, extRootDir)
    }
    return null
  }

  /** rest（<extId>/<path>）→ 读沙箱文件 → WebResourceResponse */
  private static respondRest(rest: string, extRootDir: string): WebResourceResponse | null {
    const slash: number = rest.indexOf('/')
    if (slash <= 0) {
      return null
    }
    const extId: string = rest.substring(0, slash)
    let path: string = rest.substring(slash + 1).split('?')[0].split('#')[0]
    if (!/^[a-p0-9]{32}$/.test(extId)) {
      return null
    }
    if (path === '') {
      path = 'index.html'
    }
    // 路径清洗：禁目录穿越
    if (path.includes('..') || path.includes('\\') || path.startsWith('/')) {
      return ExtensionResources.errorResponse(404, 'Not Found')
    }
    const entry: ExtMimeEntry | undefined = ExtensionResources.mimeOf(path)
    if (entry === undefined) {
      return ExtensionResources.errorResponse(403, 'Forbidden')
    }
    const data: ArrayBuffer | null = ExtensionResources.readFile(`${extRootDir}/${extId}/${path}`)
    if (data === null) {
      if (path === ExtensionResources.BG_PAGE_PATH) {
        return ExtensionResources.bgPageResponse()
      }
      return ExtensionResources.errorResponse(404, 'Not Found')
    }
    const response = new WebResourceResponse()
    response.setResponseCode(200)
    response.setReasonMessage('OK')
    response.setResponseMimeType(entry.mime)
    if (entry.textual) {
      response.setResponseEncoding('utf-8')
    }
    response.setResponseHeader(ExtensionResources.corsHeaders())
    if (entry.mime === 'text/html') {
      const html: string = ExtensionResources.decodeUtf8(data)
      if (html !== '' && !/<meta[^>]{0,300}viewport/i.test(html)) {
        response.setResponseData(ExtensionResources.patchViewport(html))
        return response
      }
    }
    response.setResponseData(data)
    return response
  }

  /** html 缺 viewport meta 时补齐（扩展页多为桌面布局，980px 默认视口下手机端左右大留白） */
  private static patchViewport(html: string): string {
    const meta: string = '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
    const headStart: number = html.search(/<head[^>]*>/i)
    if (headStart >= 0) {
      const headTagEnd: number = html.indexOf('>', headStart)
      if (headTagEnd >= 0) {
        const at: number = headTagEnd + 1
        return html.substring(0, at) + meta + html.substring(at)
      }
    }
    return meta + html
  }

  private static decodeUtf8(data: ArrayBuffer): string {
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
      return decoder.decodeToString(new Uint8Array(data))
    } catch (e) {
      logger.warn(`decodeUtf8: ${e}`)
      return ''
    }
  }

  /** bg 宿主虚拟页兜底响应（无实体文件）：返回最小 HTML，建立 https origin 供 IDB/localStorage 使用 */
  private static bgPageResponse(): WebResourceResponse {
    const response = new WebResourceResponse()
    response.setResponseCode(200)
    response.setReasonMessage('OK')
    response.setResponseMimeType('text/html')
    response.setResponseEncoding('utf-8')
    response.setResponseHeader(ExtensionResources.corsHeaders())
    response.setResponseData('<!DOCTYPE html><html><head><meta charset="utf-8"><title>bg</title></head><body></body></html>')
    return response
  }

  private static errorResponse(code: number, reason: string): WebResourceResponse {
    const response = new WebResourceResponse()
    response.setResponseCode(code)
    response.setReasonMessage(reason)
    response.setResponseMimeType('text/plain')
    response.setResponseEncoding('utf-8')
    response.setResponseHeader(ExtensionResources.corsHeaders())
    response.setResponseData('')
    return response
  }

  /** 跨源头：扩展资源被页面脚本 fetch/getURL 引用时放行（bg 宿主 origin 为 null，
      fetch 带 content-type 触发预检，须放行请求头，真机实证 filters_i18n.json 预检被拒） */
  private static corsHeaders(): Array<Header> {
    return [
      { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' },
      { headerKey: 'Access-Control-Allow-Methods', headerValue: 'GET, HEAD, OPTIONS' },
      { headerKey: 'Access-Control-Allow-Headers', headerValue: '*' }
    ]
  }

  private static mimeOf(path: string): ExtMimeEntry | undefined {
    const dot: number = path.lastIndexOf('.')
    const ext: string = dot < 0 ? '' : path.substring(dot + 1).toLowerCase()
    return ExtensionResources.MIME[ext]
  }

  /** 同步读文件（缺失/超限返回 null） */
  private static readFile(path: string): ArrayBuffer | null {
    try {
      if (!fileIo.accessSync(path)) {
        return null
      }
      const src: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
      try {
        const stat: fileIo.Stat = fileIo.statSync(src.fd)
        if (stat.size <= 0 || stat.size > ExtensionResources.MAX_FILE_BYTES) {
          return null
        }
        const buf: ArrayBuffer = new ArrayBuffer(stat.size)
        fileIo.readSync(src.fd, buf)
        return buf
      } finally {
        fileIo.closeSync(src)
      }
    } catch (e) {
      logger.warn(`readFile ${path}: ${e}`)
      return null
    }
  }
}
