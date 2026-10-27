import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { _QhState } from '../entryability/AppState';

const SHORTCUT_UA: string = 'Mozilla/5.0 (Linux; Android 14) Mobile Safari/537.36'

/** https://host[:port]/path → https://host[:port] */
function originOf(url: string): string {
  const idx: number = url.indexOf('://')
  if (idx < 0) {
    return ''
  }
  const rest: string = url.substring(idx + 3)
  const slash: number = rest.indexOf('/')
  return slash < 0 ? url : url.substring(0, idx + 3 + slash)
}

/** 相对 href → 绝对地址（其余格式放弃） */
function absoluteUrl(href: string, origin: string): string {
  if (href === '') {
    return ''
  }
  if (href.startsWith('http://') || href.startsWith('https://')) {
    return href
  }
  if (href.startsWith('//')) {
    return `https:${href}`
  }
  if (href.startsWith('/')) {
    return `${origin}${href}`
  }
  if (href.startsWith('./')) {
    return `${origin}/${href.substring(2)}`
  }
  return `${origin}/${href}`
}

/** 解析 HTML 内 link 图标候选（apple-touch-icon 优先） */
function parseIconLinks(html: string, origin: string): string[] {
  const apple: string[] = []
  const icons: string[] = []
  const tags: string[] | null = html.match(/<link[^>]+>/gi)
  if (tags === null) {
    return []
  }
  for (const tag of tags) {
    const relM: RegExpMatchArray | null = tag.match(/rel\s*=\s*["'][^"']*["']/i)
    if (relM === null || !/icon/i.test(relM[0])) {
      continue
    }
    const hrefM: RegExpMatchArray | null = tag.match(/href\s*=\s*["']([^"']+)["']/i)
    if (hrefM === null) {
      continue
    }
    const abs: string = absoluteUrl(hrefM[1], origin)
    if (abs === '') {
      continue
    }
    if (/apple-touch-icon/i.test(relM[0])) {
      apple.push(abs)
    } else {
      icons.push(abs)
    }
  }
  const out: string[] = []
  for (const a of apple) {
    out.push(a)
  }
  for (const i of icons) {
    out.push(i)
  }
  return out
}

/**
 * 解码任意格式图标（ICO/WEBP/BMP/JPEG/SVG）→ PixelMap → 重编码 PNG 写盘；
 * 尺寸过小（<24px）的图标放弃
 */
async function normalizeIcon(buf: ArrayBuffer, savePath: string): Promise<boolean> {
  let source: image.ImageSource | null = null
  let pixelMap: image.PixelMap | null = null
  let packer: image.ImagePacker | null = null
  try {
    source = image.createImageSource(buf)
    pixelMap = await source.createPixelMap()
    const info: image.ImageInfo = await pixelMap.getImageInfo()
    if (info.size.width < 24 || info.size.height < 24) {
      return false
    }
    packer = image.createImagePacker()
    const pngBuf: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 })
    const bytes: Uint8Array = new Uint8Array(pngBuf)
    const file: fileIo.File = fileIo.openSync(savePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
    fileIo.closeSync(file)
    return true
  } catch (e) {
    return false
  } finally {
    if (packer !== null) {
      packer.release()
    }
    if (pixelMap !== null) {
      pixelMap.release()
    }
    if (source !== null) {
      source.release()
    }
  }
}

/** 下载图标候选：校验大小上下限后经 ImageKit 解码重编码为 PNG 写入沙箱 */
async function downloadIcon(url: string, savePath: string): Promise<boolean> {
  const client: http.HttpRequest = http.createHttp()
  try {
    const headers: Record<string, string> = { 'User-Agent': SHORTCUT_UA }
    const resp: http.HttpResponse = await client.request(url, {
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false,
      connectTimeout: 5000,
      readTimeout: 5000,
      header: headers
    })
    const result: string | Object | ArrayBuffer | undefined = resp.result
    if (!(result instanceof ArrayBuffer)) {
      return false
    }
    if (result.byteLength < 64 || result.byteLength > 200 * 1024) {
      return false
    }
    return await normalizeIcon(result, savePath)
  } catch (e) {
    return false
  } finally {
    client.destroy()
  }
}

/**
 * 尝试抓取网站自身图标：
 * 站点 HTML link 解析（apple-touch-icon 优先）+ /favicon.ico 兜底；
 * 候选经 ImageKit 解码（支持 ICO/WEBP/BMP）重编码为 PNG，跳过过小图标
 */
async function fetchSiteIcon(pageUrl: string, savePath: string): Promise<boolean> {
  const origin: string = originOf(pageUrl)
  if (origin === '') {
    return false
  }
  const candidates: string[] = []
  let html: string = ''
  const client: http.HttpRequest = http.createHttp()
  try {
    const headers: Record<string, string> = { 'User-Agent': SHORTCUT_UA }
    const resp: http.HttpResponse = await client.request(origin, {
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: 5000,
      readTimeout: 8000,
      header: headers
    })
    if (typeof resp.result === 'string') {
      html = resp.result
    }
  } catch (e) {
    html = ''
  } finally {
    client.destroy()
  }
  if (html !== '') {
    const links: string[] = parseIconLinks(html, origin)
    for (const l of links) {
      if (candidates.indexOf(l) < 0) {
        candidates.push(l)
      }
    }
  }
  const fallback: string = `${origin}/favicon.ico`
  if (candidates.indexOf(fallback) < 0) {
    candidates.push(fallback)
  }
  let count: number = 0
  for (const c of candidates) {
    if (count >= 5) {
      break
    }
    count++
    if (await downloadIcon(c, savePath)) {
      return true
    }
  }
  return false
}

/**
 * favicon 缓存：
 * 1. 网页加载（Web onFaviconReceived）自动按 host 存 PNG；
 * 2. 无缓存时按页面 URL 懒加载（书签列表进入时逐条补抓）；
 * 均存于 cacheDir/favicon，version 自增驱动 UI 重新读取
 */
@ObservedV2
export class FaviconCache {

  /** url → host（端口冒号转下划线，去 userinfo） */
  static hostOf(url: string): string {
    const idx: number = url.indexOf('://')
    if (idx < 0) {
      return ''
    }
    const rest: string = url.substring(idx + 3)
    const slash: number = rest.indexOf('/')
    let host: string = slash < 0 ? rest : rest.substring(0, slash)
    const at: number = host.indexOf('@')
    if (at >= 0) {
      host = host.substring(at + 1)
    }
    return host.replace(':', '_')
  }

  private dir: string = ''
  private scanned: boolean = false
  private cached: Set<string> = new Set<string>()
  /** 抓取中的 host，防重复请求 */
  private pending: Set<string> = new Set<string>()
  /** 缓存写入计数：读取方（build 内 has()）依赖此属性，自增后触发刷新 */
  @Trace version: number = 0

  private ensureDir(): string {
    if (this.dir === '') {
      this.dir = `${_QhState.Context.cacheDir}/favicon`
      if (!fileIo.accessSync(this.dir)) {
        fileIo.mkdirSync(this.dir)
      }
    }
    if (!this.scanned) {
      // 回填历史缓存（应用重启后内存 set 为空但文件仍在）
      this.scanned = true
      try {
        const names: string[] = fileIo.listFileSync(this.dir)
        for (const name of names) {
          if (name.endsWith('.png')) {
            this.cached.add(name.substring(0, name.length - 4))
          }
        }
      } catch (e) {
        console.error(`[FaviconCache] 缓存目录扫描失败: ${e}`)
      }
    }
    return this.dir
  }

  pathOf(host: string): string {
    return `${this.ensureDir()}/${host}.png`
  }

  /** 是否已有缓存图标（依赖 version，供 build 内调用以驱动刷新） */
  has(host: string): boolean {
    if (host === '') {
      return false
    }
    this.ensureDir()
    const v: number = this.version
    return this.cached.has(host)
  }

  /** 保存页面加载回调的 favicon（重复 host 跳过） */
  saveFromPixelMap(host: string, favicon: image.PixelMap): void {
    if (host === '' || this.cached.has(host)) {
      return
    }
    const savePath: string = this.pathOf(host)
    let packer: image.ImagePacker | null = null
    try {
      packer = image.createImagePacker()
      packer.packToData(favicon, { format: 'image/png', quality: 100 })
        .then((buf: ArrayBuffer): void => {
          if (packer !== null) {
            packer.release()
          }
          const bytes: Uint8Array = new Uint8Array(buf)
          const file: fileIo.File = fileIo.openSync(savePath,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
          fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
          fileIo.closeSync(file)
          this.cached.add(host)
          this.version++
          console.info(`[FaviconCache] 已缓存 favicon host=${host} size=${bytes.byteLength}`)
        })
        .catch((error: BusinessError): void => {
          if (packer !== null) {
            packer.release()
          }
          console.error(`[FaviconCache] favicon 编码失败 host=${host}: ${error.code} ${error.message}`)
        })
    } catch (e) {
      if (packer !== null) {
        packer.release()
      }
      console.error(`[FaviconCache] favicon 保存异常 host=${host}: ${e}`)
    }
  }

  /**
   * 懒加载：无缓存时按页面 URL 抓取站点图标并缓存（书签列表进入时逐条调用）；
   * 同 host 并发去重；成功后 version 自增驱动列表刷新
   */
  async fetchAsync(pageUrl: string): Promise<boolean> {
    const host: string = FaviconCache.hostOf(pageUrl)
    if (host === '' || this.has(host) || this.pending.has(host)) {
      return host !== '' && this.cached.has(host)
    }
    this.pending.add(host)
    try {
      const ok: boolean = await fetchSiteIcon(pageUrl, this.pathOf(host))
      if (ok) {
        this.cached.add(host)
        this.version++
        console.info(`[FaviconCache] 懒加载成功 host=${host}`)
      }
      return ok
    } finally {
      this.pending.delete(host)
    }
  }

  /** 清空全部 favicon 缓存（主页定制「清除图标」；书签页图标会按需重新抓取） */
  clearAll(): void {
    this.ensureDir()
    try {
      const names: string[] = fileIo.listFileSync(this.dir)
      for (const name of names) {
        fileIo.unlinkSync(`${this.dir}/${name}`)
      }
      this.cached.clear()
      this.pending.clear()
      this.version++
    } catch (e) {
      console.error(`[FaviconCache] 清空缓存失败: ${e}`)
    }
  }

  /** 复制缓存图标到目标路径（桌面快捷方式复用，应用重启后仍可用） */
  copyTo(host: string, savePath: string): boolean {
    if (host === '') {
      return false
    }
    try {
      const src: string = this.pathOf(host)
      if (!fileIo.accessSync(src)) {
        return false
      }
      fileIo.copyFileSync(src, savePath)
      return true
    } catch (e) {
      return false
    }
  }
}

export const faviconCache: FaviconCache = new FaviconCache()
