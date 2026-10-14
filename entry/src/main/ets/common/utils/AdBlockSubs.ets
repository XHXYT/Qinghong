import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { _QhState } from '../../entryability/AppState';
import { preferenceUtil } from './persistence/PreferenceUtil';
import { AppConstants } from '../constants/AppConstants';
import { createLogger } from './Logger';

const logger = createLogger('AdBlockSubs')

/**
 * 规则订阅条目
 */
@ObservedV2
export class AdBlockSubscription {
  @Trace url: string = ''
  @Trace name: string = ''
  @Trace enabled: boolean = true
  /** 规则条数 */
  @Trace ruleCount: number = 0
  /** 上次更新时间（ms），0 表示未更新 */
  @Trace lastUpdated: number = 0
  /** 是否正在下载/更新规则 */
  @Trace updating: boolean = false
  /** 名称跟随规则 Title（首次下载成功后自动命名，用后即失效） */
  @Trace autoName: boolean = false

  constructor(url: string, name: string, enabled: boolean, ruleCount: number, lastUpdated: number,
    autoName: boolean = false) {
    this.url = url
    this.name = name
    this.enabled = enabled
    this.ruleCount = ruleCount
    this.lastUpdated = lastUpdated
    this.autoName = autoName
  }
}

/** 首选项 JSON 持久化原始结构 */
interface SubRaw {
  url: string
  name: string
  enabled: boolean
  ruleCount: number
  lastUpdated: number
  autoName?: boolean
}

/**
 * 规则订阅仓库：订阅元数据存首选项 JSON，
 * 已下载的规则文件存沙箱 filesDir/adblock/subscriptions/<url哈希>.txt
 */
@ObservedV2
export class AdBlockSubsStore {

  /** 订阅列表 */
  @Trace subs: AdBlockSubscription[] = []
  /** 自动更新间隔：manual / 12h / daily / weekly / monthly */
  @Trace interval: string = 'daily'
  /** 上次自动全部更新时间（ms），0 表示尚未自动更新 */
  @Trace lastAutoUpdate: number = 0

  /** 规则变化回调（下载/更新成功后触发，引擎注册用于重载规则） */
  onRulesChanged: (() => void) | null = null

  /** 批量更新中：延迟到批量结束再通知，避免逐条重载引擎 */
  private bulk: boolean = false
  private bulkDirty: boolean = false

  private loaded: boolean = false

  /** 订阅规则文件目录 */
  subsDir(): string {
    return `${_QhState.Context.filesDir}/adblock/subscriptions`
  }

  /** 订阅规则文件路径 */
  rulesPath(sub: AdBlockSubscription): string {
    return `${this.subsDir()}/${AdBlockSubsStore.urlHash(sub.url)}.txt`
  }

  /** 读取指定订阅已下载的规则文本 */
  readRules(sub: AdBlockSubscription): string {
    try {
      const path: string = this.rulesPath(sub)
      if (fileIo.accessSync(path)) {
        return fileIo.readTextSync(path)
      }
    } catch (e) {
      logger.error(`readRules 失败: ${e}`)
    }
    return ''
  }

  /**
   * 启动时加载订阅数据
   */
  async load(): Promise<void> {
    if (this.loaded) {
      return
    }
    try {
      const raw: string = await preferenceUtil.get<string>(AppConstants.KEY_AD_BLOCK_SUBS, '')
      if (raw !== '') {
        const arr: SubRaw[] = JSON.parse(raw) as SubRaw[]
        if (arr) {
          for (const r of arr) {
            this.subs.push(new AdBlockSubscription(r.url, r.name, r.enabled, r.ruleCount, r.lastUpdated,
              r.autoName === true))
          }
        }
      }
      this.interval = await preferenceUtil.get<string>(AppConstants.KEY_AD_BLOCK_SUBS_INTERVAL, 'daily')
      this.lastAutoUpdate = await preferenceUtil.get<number>(AppConstants.KEY_AD_BLOCK_SUBS_AUTO_TIME, 0)
      this.loaded = true
    } catch (e) {
      logger.error(`load 失败: ${e}`)
    }
  }

  private persist(): void {
    const arr: SubRaw[] = []
    for (const s of this.subs) {
      arr.push({
        url: s.url, name: s.name, enabled: s.enabled, ruleCount: s.ruleCount,
        lastUpdated: s.lastUpdated, autoName: s.autoName
      })
    }
    preferenceUtil.put(AppConstants.KEY_AD_BLOCK_SUBS, JSON.stringify(arr)).catch((): void => {
    })
  }

  /** 设置自动更新间隔 */
  setInterval(v: string): void {
    this.interval = v
    preferenceUtil.put(AppConstants.KEY_AD_BLOCK_SUBS_INTERVAL, v).catch((): void => {
    })
  }

  /** 是否到达自动更新时间 */
  isAutoUpdateDue(): boolean {
    const ms: number = AdBlockSubsStore.intervalMs(this.interval)
    if (ms <= 0) {
      return false
    }
    return Date.now() - this.lastAutoUpdate >= ms
  }

  /**
   * 添加订阅：先入列表展示，再后台下载规则（成功后经 onRulesChanged 通知引擎）
   * @return false 表示该订阅已存在
   */
  add(url: string): boolean {
    for (const s of this.subs) {
      if (s.url === url) {
        return false
      }
    }
    const sub: AdBlockSubscription =
      new AdBlockSubscription(url, AdBlockSubsStore.nameFromUrl(url), true, 0, 0, true)
    this.subs.push(sub)
    this.persist()
    this.update(sub).then((): void => {
    })
    return true
  }

  /**
   * 下载/更新单个订阅的规则文件，成功返回 true
   */
  async update(sub: AdBlockSubscription): Promise<boolean> {
    if (sub.updating) {
      return false
    }
    sub.updating = true
    const text: string | null = await this.downloadWithRetry(sub.url)
    sub.updating = false
    if (text === null || !this.writeRules(sub, text)) {
      return false
    }
    // 首次下载：名称跟随规则里的 Title 字段（一次性）
    if (sub.autoName) {
      const title: string = AdBlockSubsStore.titleFromRules(text)
      if (title !== '') {
        sub.name = title
        sub.autoName = false
      }
    }
    sub.ruleCount = AdBlockSubsStore.countRules(text)
    sub.lastUpdated = Date.now()
    this.persist()
    this.notifyRulesChanged()
    return true
  }

  /** 通知规则变化（批量更新时延迟到批量结束统一通知一次） */
  private notifyRulesChanged(): void {
    if (this.bulk) {
      this.bulkDirty = true
      return
    }
    if (this.onRulesChanged !== null) {
      this.onRulesChanged()
    }
  }

  /**
   * 更新全部启用中的订阅
   * @param auto 是否自动更新（记录 lastAutoUpdate）
   * @return 成功更新的订阅数
   */
  async updateAll(auto: boolean): Promise<number> {
    let updated: number = 0
    const targets: AdBlockSubscription[] = []
    for (const s of this.subs) {
      if (s.enabled) {
        targets.push(s)
      }
    }
    this.bulk = true
    for (const s of targets) {
      if (await this.update(s)) {
        updated++
      }
    }
    this.bulk = false
    if (this.bulkDirty) {
      this.bulkDirty = false
      this.notifyRulesChanged()
    }
    if (auto) {
      this.lastAutoUpdate = Date.now()
      preferenceUtil.put(AppConstants.KEY_AD_BLOCK_SUBS_AUTO_TIME, this.lastAutoUpdate).catch((): void => {
      })
    }
    return updated
  }

  /** 删除订阅及其规则文件 */
  remove(sub: AdBlockSubscription): void {
    const idx: number = this.subs.indexOf(sub)
    if (idx < 0) {
      return
    }
    this.subs.splice(idx, 1)
    try {
      const path: string = `${this.subsDir()}/${AdBlockSubsStore.urlHash(sub.url)}.txt`
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (e) {
      logger.error(`remove 删除规则文件失败: ${e}`)
    }
    this.persist()
  }

  /** 切换订阅启用状态 */
  toggle(sub: AdBlockSubscription, on: boolean): void {
    sub.enabled = on
    this.persist()
  }

  /**
   * 编辑订阅名称/链接，返回 false 表示新链接与其他订阅冲突
   * 链接变化时已下载的规则文件迁移到新链接对应的哈希文件名
   * @param autoName true 表示名称留空、跟随规则 Title（下载成功后自动命名）
   */
  edit(sub: AdBlockSubscription, name: string, url: string, autoName: boolean): boolean {
    if (url !== sub.url) {
      for (const s of this.subs) {
        if (s !== sub && s.url === url) {
          return false
        }
      }
      const text: string = this.readRules(sub)
      try {
        const oldPath: string = `${this.subsDir()}/${AdBlockSubsStore.urlHash(sub.url)}.txt`
        if (fileIo.accessSync(oldPath)) {
          fileIo.unlinkSync(oldPath)
        }
      } catch (e) {
        logger.error(`edit 删除旧规则文件失败: ${e}`)
      }
      sub.url = url
      if (text !== '') {
        this.writeRules(sub, text)
      }
    }
    sub.name = name
    sub.autoName = autoName
    this.persist()
    return true
  }

  /**
   * 从已下载的规则文件读取 Title 字段重命名订阅
   * @return false 表示规则文件不存在或未找到 Title
   */
  renameFromRule(sub: AdBlockSubscription): boolean {
    const text: string = this.readRules(sub)
    if (text === '') {
      return false
    }
    const title: string = AdBlockSubsStore.titleFromRules(text)
    if (title === '') {
      return false
    }
    sub.name = title
    sub.autoName = false
    this.persist()
    return true
  }

  private writeRules(sub: AdBlockSubscription, text: string): boolean {
    try {
      const dir: string = this.subsDir()
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true)
      }
      const path: string = `${dir}/${AdBlockSubsStore.urlHash(sub.url)}.txt`
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, text)
      } finally {
        fileIo.closeSync(file)
      }
      return true
    } catch (e) {
      logger.error(`writeRules 失败: ${e}`)
      return false
    }
  }

  private async download(url: string): Promise<string | null> {
    return new Promise<string | null>((resolve: (v: string | null) => void) => {
      const req: http.HttpRequest = http.createHttp()
      req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 90000,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 15; PCAM00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*'
        }
      })
        .then((resp: http.HttpResponse) => {
          if (resp.responseCode >= 200 && resp.responseCode < 300
            && typeof resp.result === 'string' && resp.result !== '') {
            resolve(resp.result)
          } else {
            logger.warn(`download 响应异常: ${url} -> ${resp.responseCode}, result: ${typeof resp.result}`)
            resolve(null)
          }
        })
        .catch((e: BusinessError) => {
          logger.warn(`download 失败: ${url}, ${e.message}`)
          resolve(null)
        })
        .finally(() => {
          req.destroy()
        })
    })
  }

  /** 下载（失败自动重试一次） */
  private async downloadWithRetry(url: string): Promise<string | null> {
    let text: string | null = await this.download(url)
    if (text === null) {
      text = await this.download(url)
    }
    return text
  }

  /** URL → 稳定文件名（djb2 哈希十六进制） */
  private static urlHash(url: string): string {
    let h: number = 5381
    for (let i = 0; i < url.length; i++) {
      h = ((h << 5) + h + url.charCodeAt(i)) | 0
    }
    return (h >>> 0).toString(16)
  }

  /** 从 URL 提取订阅名（最后一段去扩展名，如 cjx-annoyance.txt → cjx-annoyance） */
  static nameFromUrl(url: string): string {
    const noQuery: string = url.split('?')[0]
    const seg: string = noQuery.substring(noQuery.lastIndexOf('/') + 1)
    if (seg !== '') {
      const dot: number = seg.lastIndexOf('.')
      return dot > 0 ? seg.substring(0, dot) : seg
    }
    const rest: string = noQuery.replace(/^https?:\/\//, '')
    return rest.substring(0, rest.indexOf('/')) || rest
  }

  /** 统计规则条数（非注释、非空行） */
  static countRules(text: string): number {
    let n: number = 0
    const lines: string[] = text.split('\n')
    for (let line of lines) {
      line = line.trim()
      if (line.length === 0) {
        continue
      }
      const first: string = line[0]
      if (first === '!' || first === '[') {
        continue
      }
      n++
    }
    return n
  }

  /** 从规则文件头部元数据注释中提取 Title 字段（如 `! Title: EasyList`），未找到返回 '' */
  static titleFromRules(text: string): string {
    const lines: string[] = text.split('\n')
    for (let line of lines) {
      line = line.trim()
      if (line.length === 0) {
        continue
      }
      const first: string = line[0]
      // 只在头部注释/元数据区查找，遇到首条规则即止
      if (first !== '!' && first !== '[') {
        break
      }
      if (first !== '!') {
        continue
      }
      const meta: string = line.substring(1).trim()
      if (meta.startsWith('Title:')) {
        const title: string = meta.substring('Title:'.length).trim()
        if (title !== '') {
          return title
        }
      }
    }
    return ''
  }

  /** 间隔标识 → 毫秒（manual 为 0） */
  static intervalMs(v: string): number {
    switch (v) {
      case '12h':
        return 12 * 3600 * 1000
      case 'weekly':
        return 7 * 24 * 3600 * 1000
      case 'monthly':
        return 30 * 24 * 3600 * 1000
      case 'daily':
        return 24 * 3600 * 1000
      default:
        return 0
    }
  }
}

export const adBlockSubsStore: AdBlockSubsStore = new AdBlockSubsStore()
