import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { _QhState } from '../entryability/AppState';
import { createLogger } from '../common/utils/app/Logger';
import { appSettings } from '../common/entity/SettingsModel';
import { UserScriptEngine, ScriptMeta } from '../common/utils/userscript/UserScriptEngine';
import { GmRuntime, GmMenuCommand, GmXhrRaw, GmXhrAbortRaw, GmValueRaw, GmDeleteValueRaw } from '../common/utils/userscript/GmRuntime';
import { UserScriptDao } from '../common/utils/database/impl/UserScriptDao';
import { UserScriptValueDao } from '../common/utils/database/impl/UserScriptValueDao';
import UserScriptInfo from '../common/entity/UserScriptInfo';
import UserScriptValue from '../common/entity/UserScriptValue';
import { tabsVM, TabInfo } from './TabsViewModel';

const logger = createLogger('ScriptVM')

/** @require 依赖库存储结构（JSON 序列化进 user_script.requires 列） */
class GmDepRaw {
  url: string = ''
  code: string = ''
}

/** @resource 资源存储结构（JSON 序列化进 user_script.resources 列） */
class GmResRaw {
  name: string = ''
  mime: string = ''
  b64: string = ''
}

/** XHR 响应头字符串（JSON 形式，脚本侧可解析） */
function headersToJson(header: Object): string {
  try {
    return JSON.stringify(header)
  } catch (e) {
    return '{}'
  }
}

/** 从 URL 提取 host（用于 @connect 校验） */
function hostOf(url: string): string {
  const m: RegExpMatchArray | null = url.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/:?#]+)/)
  return m !== null && m.length > 1 ? m[1] : ''
}

/**
 * 用户脚本仓库 + GM_* 完整引擎：
 * - 脚本/依赖/资源存 qinghong.db user_script 表，GM 值存 user_script_value 表；
 * - document-start 经 javaScriptOnDocumentStart 注入，document-end/idle 在 onPageEnd 注入；
 * - GM API 经 window.__qhNative.gmRequest 桥接原生（值持久化、跨域请求、菜单命令等）。
 */
@ObservedV2
export class ScriptViewModel {
  @Trace scripts: UserScriptInfo[] = []

  /** GM 值版本号（值变更时 +1，触发 document-start 注入项重新烘焙） */
  @Trace valuesVersion: number = 0

  /** 当前各标签已注册的脚本菜单命令（浏览器菜单展示） */
  @Trace menuCommands: GmMenuCommand[] = []

  private db: UserScriptDao | null = null
  private valueDb: UserScriptValueDao | null = null

  /** GM 值内存缓存：scriptId → (key → JSON 原文) */
  private valuesCache: Map<number, Map<string, string>> = new Map()

  /** 进行中的 GM_xmlhttpRequest 请求（abort 支持） */
  private xhrTasks: Map<number, http.HttpRequest> = new Map()

  private getDB(): UserScriptDao {
    if (!this.db) {
      this.db = new UserScriptDao(_QhState.Context)
    }
    return this.db
  }

  private getValueDB(): UserScriptValueDao {
    if (!this.valueDb) {
      this.valueDb = new UserScriptValueDao(_QhState.Context)
    }
    return this.valueDb
  }

  /** 启动时加载全部脚本与 GM 值 */
  async loadAll(): Promise<void> {
    try {
      this.scripts = await this.getDB().queryAll()
      await this.loadValues()
    } catch (e) {
      logger.error(`loadAll: ${e}`)
    }
  }

  /** GM 值全量载入内存缓存 */
  private async loadValues(): Promise<void> {
    try {
      const rows: UserScriptValue[] = await this.getValueDB().queryAllRows()
      this.valuesCache = new Map()
      for (const row of rows) {
        let m: Map<string, string> | undefined = this.valuesCache.get(row.scriptId)
        if (m === undefined) {
          m = new Map()
          this.valuesCache.set(row.scriptId, m)
        }
        m.set(row.key, row.value)
      }
      this.valuesVersion++
    } catch (e) {
      logger.error(`loadValues: ${e}`)
    }
  }

  /**
   * 从源码安装脚本（解析 metadata；同名覆盖，用于「下载/导入/更新」复用）
   * @returns null=代码无效；true=新增；false=覆盖已有同名脚本
   */
  async addFromCode(code: string, updateUrl: string = ''): Promise<boolean | null> {
    if (code.trim() === '') {
      return null
    }
    const meta: ScriptMeta = UserScriptEngine.parseMeta(code)
    const name: string = meta.name !== '' ? meta.name : 'New Userscript'
    const existing: UserScriptInfo | null = await this.getDB().queryByName(name)
    if (existing !== null) {
      ScriptViewModel.fillMeta(existing, code, meta, updateUrl !== '' ? updateUrl : existing.updateUrl)
      await this.refreshDeps(existing, meta)
      await this.getDB().update(existing)
      await this.loadAll()
      return false
    }
    const info: UserScriptInfo = new UserScriptInfo()
    info.name = name
    info.createTime = Date.now()
    ScriptViewModel.fillMeta(info, code, meta, updateUrl)
    await this.refreshDeps(info, meta)
    await this.getDB().insert(info)
    await this.loadAll()
    return true
  }

  /** metadata 字段写入实体 */
  private static fillMeta(info: UserScriptInfo, code: string, meta: ScriptMeta, updateUrl: string): void {
    info.code = code
    info.name = meta.name !== '' ? meta.name : info.name
    info.version = meta.version
    info.runAt = meta.runAt
    info.matches = meta.matches.join('\n')
    info.excludes = meta.excludes.join('\n')
    info.updateUrl = updateUrl
    info.grants = JSON.stringify(meta.grants)
    info.connects = JSON.stringify(meta.connects)
    info.noframes = meta.noframes
    info.updateTime = Date.now()
  }

  /** 下载 @require 依赖与 @resource 资源（失败跳过该项，不阻塞安装） */
  private async refreshDeps(info: UserScriptInfo, meta: ScriptMeta): Promise<void> {
    const deps: GmDepRaw[] = []
    for (const url of meta.requires) {
      const code: string | null = await this.download(url)
      if (code !== null) {
        const d: GmDepRaw = new GmDepRaw()
        d.url = url
        d.code = code
        deps.push(d)
      } else {
        logger.warn(`@require 下载失败: ${url}`)
      }
    }
    info.requires = JSON.stringify(deps)
    const res: GmResRaw[] = []
    for (const r of meta.resources) {
      const fetched: GmResRaw | null = await this.fetchResource(r.name, r.url)
      if (fetched !== null) {
        res.push(fetched)
      } else {
        logger.warn(`@resource 下载失败: ${r.name} ${r.url}`)
      }
    }
    info.resources = JSON.stringify(res)
  }

  /** 下载资源并转 base64（≤2MB） */
  private async fetchResource(name: string, url: string): Promise<GmResRaw | null> {
    const req: http.HttpRequest = http.createHttp()
    try {
      const resp: http.HttpResponse = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 20000,
        usingCache: false,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })
      if (resp.responseCode < 200 || resp.responseCode >= 300
        || resp.result === null || resp.result === undefined
        || !(resp.result instanceof ArrayBuffer)) {
        logger.warn(`fetchResource 响应异常: ${url} -> ${resp.responseCode}`)
        return null
      }
      const bytes: Uint8Array = new Uint8Array(resp.result)
      if (bytes.byteLength <= 0 || bytes.byteLength > 2 * 1024 * 1024) {
        logger.warn(`fetchResource 超限: ${url}`)
        return null
      }
      const out: GmResRaw = new GmResRaw()
      out.name = name
      out.mime = ScriptViewModel.mimeOf(url)
      out.b64 = new util.Base64Helper().encodeToStringSync(bytes)
      return out
    } catch (e) {
      logger.warn(`fetchResource 失败: ${url}, ${e}`)
      return null
    } finally {
      req.destroy()
    }
  }

  /** 按 URL 扩展名猜测资源 MIME */
  private static mimeOf(url: string): string {
    const lower: string = url.split('?')[0].toLowerCase()
    if (lower.endsWith('.png')) {
      return 'image/png'
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg'
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif'
    }
    if (lower.endsWith('.svg')) {
      return 'image/svg+xml'
    }
    if (lower.endsWith('.css')) {
      return 'text/css'
    }
    if (lower.endsWith('.js')) {
      return 'application/javascript'
    }
    if (lower.endsWith('.json')) {
      return 'application/json'
    }
    if (lower.endsWith('.woff2')) {
      return 'font/woff2'
    }
    if (lower.endsWith('.ttf')) {
      return 'font/ttf'
    }
    return 'application/octet-stream'
  }

  /** 编辑保存：重新解析 metadata + 重下依赖 */
  async saveFromEdit(info: UserScriptInfo, code: string): Promise<void> {
    const meta: ScriptMeta = UserScriptEngine.parseMeta(code)
    ScriptViewModel.fillMeta(info, code, meta, info.updateUrl)
    await this.refreshDeps(info, meta)
    await this.getDB().update(info)
    await this.loadAll()
  }

  /** 启用/禁用 */
  async toggle(info: UserScriptInfo, enabled: boolean): Promise<void> {
    info.enabled = enabled
    await this.getDB().update(info)
    await this.loadAll()
  }

  /** 修改运行时机（就地更新 + 持久化，不重查询避免页面引用失效） */
  async updateRuntime(info: UserScriptInfo, runAt: string): Promise<void> {
    info.runAt = runAt
    await this.getDB().update(info)
  }

  /** 修改匹配/排除规则（换行分隔存储） */
  async updatePatterns(info: UserScriptInfo, matches: string, excludes: string): Promise<void> {
    info.matches = matches
    info.excludes = excludes
    await this.getDB().update(info)
  }

  /** 重置：从下载链接重新下载覆盖（含依赖/资源重下）；无链接返回 false */
  async resetFromUrl(info: UserScriptInfo): Promise<boolean> {
    if (info.updateUrl === '') {
      return false
    }
    const text: string | null = await this.download(info.updateUrl)
    if (text === null) {
      return false
    }
    const meta: ScriptMeta = UserScriptEngine.parseMeta(text)
    ScriptViewModel.fillMeta(info, text, meta, info.updateUrl)
    await this.refreshDeps(info, meta)
    await this.getDB().update(info)
    await this.loadAll()
    return true
  }

  /** 脚本大小文本（UTF-8 字节数，KB 保留 1 位小数） */
  static sizeText(code: string): string {
    let bytes: number = 0
    for (let i = 0; i < code.length; i++) {
      const c: number = code.charCodeAt(i)
      if (c < 0x80) {
        bytes++
      } else if (c < 0x800) {
        bytes += 2
      } else {
        bytes += 3
      }
    }
    return `${(bytes / 1024).toFixed(1)} KB`
  }

  /** 时间戳格式化（yyyy-MM-dd HH:mm） */
  static formatStamp(t: number): string {
    if (t <= 0) {
      return '-'
    }
    const d: Date = new Date(t)
    const p = (n: number): string => `${n}`.padStart(2, '0')
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
  }

  /** 删除（连带 GM 值与菜单命令） */
  async deleteScript(info: UserScriptInfo): Promise<void> {
    if (info.id !== null) {
      await this.getDB().deleteById(info.id)
      await this.getValueDB().deleteByScript(info.id)
    }
    const sid: number = info.id === null ? -1 : info.id
    this.menuCommands = this.menuCommands.filter((c: GmMenuCommand): boolean => c.scriptId !== sid)
    await this.loadAll()
  }

  /** 从链接下载安装（下载的脚本记录来源便于后续更新） */
  async downloadFromUrl(url: string): Promise<boolean> {
    const text: string | null = await this.download(url)
    if (text === null) {
      return false
    }
    const result: boolean | null = await this.addFromCode(text, url)
    return result !== null
  }

  /** 从本地文件导入（≤2MB 文本） */
  async importFromUri(uri: string): Promise<boolean> {
    try {
      const src: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat: fileIo.Stat = fileIo.statSync(src.fd)
      if (stat.size <= 0 || stat.size > 2 * 1024 * 1024) {
        fileIo.closeSync(src)
        return false
      }
      const buf: ArrayBuffer = new ArrayBuffer(stat.size)
      fileIo.readSync(src.fd, buf)
      fileIo.closeSync(src)
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
      const text: string = decoder.decodeToString(new Uint8Array(buf))
      const result: boolean | null = await this.addFromCode(text)
      return result !== null
    } catch (e) {
      logger.error(`importFromUri: ${e}`)
      return false
    }
  }

  /**
   * 批量更新：重新下载所有带来源链接的脚本（直接覆盖，含依赖重下）
   * @returns 更新成功的数量
   */
  async updateAll(): Promise<number> {
    let ok: number = 0
    const targets: UserScriptInfo[] = []
    for (const s of this.scripts) {
      if (s.updateUrl !== '') {
        targets.push(s)
      }
    }
    for (const s of targets) {
      const text: string | null = await this.download(s.updateUrl)
      if (text !== null) {
        const meta: ScriptMeta = UserScriptEngine.parseMeta(text)
        ScriptViewModel.fillMeta(s, text, meta, s.updateUrl)
        await this.refreshDeps(s, meta)
        await this.getDB().update(s)
        ok++
      }
    }
    if (ok > 0) {
      await this.loadAll()
    }
    return ok
  }

  /** 是否存在可更新的脚本（带来源链接） */
  hasUpdatable(): boolean {
    for (const s of this.scripts) {
      if (s.updateUrl !== '') {
        return true
      }
    }
    return false
  }

  /** 下载文本（失败自动重试一次） */
  private async download(url: string): Promise<string | null> {
    let text: string | null = await this.downloadOnce(url)
    if (text === null) {
      text = await this.downloadOnce(url)
    }
    return text
  }

  private downloadOnce(url: string): Promise<string | null> {
    return new Promise<string | null>((resolve: (v: string | null) => void) => {
      const req: http.HttpRequest = http.createHttp()
      req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingCache: false,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'Accept': '*/*'
        }
      })
        .then((resp: http.HttpResponse) => {
          if (resp.responseCode >= 200 && resp.responseCode < 300
            && typeof resp.result === 'string' && resp.result !== '') {
            if (resp.result.length > 2 * 1024 * 1024) {
              logger.warn(`download 超过 2MB 上限: ${url}`)
              resolve(null)
              return
            }
            resolve(resp.result)
          } else {
            logger.warn(`download 响应异常: ${url} -> ${resp.responseCode}`)
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

  // ==================== GM 存储值 ====================

  /** 值烘焙为 JSON 对象字面量（同步读取用） */
  private buildValuesJson(scriptId: number): string {
    const m: Map<string, string> | undefined = this.valuesCache.get(scriptId)
    if (m === undefined || m.size === 0) {
      return '{}'
    }
    let s: string = '{'
    let first: boolean = true
    m.forEach((raw: string, key: string): void => {
      if (!first) {
        s += ','
      }
      s += JSON.stringify(key) + ':' + raw
      first = false
    })
    return s + '}'
  }

  /** GM_setValue：更新缓存 + 持久化 + 广播其它标签（originTabId 除外） */
  gmSetValue(scriptId: number, key: string, valueRaw: string, originTabId: number): void {
    let m: Map<string, string> | undefined = this.valuesCache.get(scriptId)
    if (m === undefined) {
      m = new Map()
      this.valuesCache.set(scriptId, m)
    }
    const oldRaw: string | undefined = m.get(key)
    m.set(key, valueRaw)
    this.valuesVersion++
    this.getValueDB().upsert(scriptId, key, valueRaw).catch((e: BusinessError): void => {
      logger.error(`gmSetValue 持久化失败: ${e.message}`)
    })
    const oldJs: string = oldRaw === undefined ? 'undefined' : oldRaw
    this.broadcastValueChange(scriptId, key, oldJs, valueRaw, originTabId)
  }

  /** GM_deleteValue */
  gmDeleteValue(scriptId: number, key: string, originTabId: number): void {
    const m: Map<string, string> | undefined = this.valuesCache.get(scriptId)
    const oldRaw: string | undefined = m === undefined ? undefined : m.get(key)
    if (m !== undefined) {
      m.delete(key)
    }
    this.valuesVersion++
    this.getValueDB().deleteByKey(scriptId, key).catch((e: BusinessError): void => {
      logger.error(`gmDeleteValue 失败: ${e.message}`)
    })
    const oldJs: string = oldRaw === undefined ? 'undefined' : oldRaw
    this.broadcastValueChange(scriptId, key, oldJs, 'undefined', originTabId)
  }

  /** 值变更广播到其它标签页（页面内监听器同步触发） */
  private broadcastValueChange(scriptId: number, key: string, oldJs: string, newJs: string,
    originTabId: number): void {
    const js: string = `window.__qhGmCore && window.__qhGmCore.notifyValueChange(${scriptId},`
      + ` ${JSON.stringify(key)}, ${oldJs}, ${newJs}, true);`
    for (const t of tabsVM.tabs) {
      if (t.id === originTabId || t.isHome) {
        continue
      }
      const c = t.controller
      if (c !== null) {
        c.runJavaScript(js).catch((): void => {
        })
      }
    }
  }

  // ==================== GM_xmlhttpRequest ====================

  /** 跨域请求：@connect 校验后原生 http 执行，结果回调页面 */
  gmXhr(json: string, tab: TabInfo): void {
    const raw: GmXhrRaw = JSON.parse(json) as GmXhrRaw
    if (typeof raw.url !== 'string' || raw.url === '') {
      this.fireXhr(tab, raw.id, false, JSON.stringify({ error: 'no url' }))
      return
    }
    // @connect 白名单校验（未声明则放行）
    const script: UserScriptInfo | null = this.findScript(raw.scriptId)
    if (script !== null) {
      const connects: string[] = JSON.parse(script.connects) as string[]
      if (connects.length > 0) {
        const host: string = hostOf(raw.url)
        let allowed: boolean = false
        for (const p of connects) {
          if (UserScriptEngine.connectMatch(p, host)) {
            allowed = true
            break
          }
        }
        if (!allowed) {
          logger.warn(`gmXhr 被 @connect 拦截: ${raw.url}`)
          this.fireXhr(tab, raw.id, false, JSON.stringify({ error: 'not allowed by @connect' }))
          return
        }
      }
    }
    const method: http.RequestMethod = ScriptViewModel.xhrMethod(raw.method)
    const req: http.HttpRequest = http.createHttp()
    this.xhrTasks.set(raw.id, req)
    req.request(raw.url, {
      method: method,
      header: raw.headers,
      extraData: raw.data !== '' ? raw.data : undefined,
      connectTimeout: 15000,
      readTimeout: raw.timeout > 0 ? raw.timeout : 30000,
      usingCache: false,
      expectDataType: http.HttpDataType.STRING
    })
      .then((resp: http.HttpResponse) => {
        this.xhrTasks.delete(raw.id)
        req.destroy()
        const text: string = typeof resp.result === 'string' ? resp.result : ''
        if (text.length > 10 * 1024 * 1024) {
          this.fireXhr(tab, raw.id, false, JSON.stringify({ error: 'response too large' }))
          return
        }
        const payload: Record<string, Object> = {
          'finalUrl': raw.url,
          'readyState': 4,
          'status': resp.responseCode,
          'statusText': '',
          'responseHeaders': headersToJson(resp.header),
          'response': text,
          'responseText': text
        }
        this.fireXhr(tab, raw.id, true, JSON.stringify(payload))
      })
      .catch((e: BusinessError) => {
        this.xhrTasks.delete(raw.id)
        req.destroy()
        if (e.code === 2300028) {
          this.fireXhr(tab, raw.id, false, JSON.stringify({ __timeout: true }))
          return
        }
        logger.warn(`gmXhr 失败: ${raw.url}, ${e.message}`)
        this.fireXhr(tab, raw.id, false, JSON.stringify({ error: 'network', message: e.message }))
      })
  }

  /** 中止进行中的 GM 请求 */
  gmXhrAbort(json: string): void {
    const raw: GmXhrAbortRaw = JSON.parse(json) as GmXhrAbortRaw
    const task: http.HttpRequest | undefined = this.xhrTasks.get(raw.id)
    if (task !== undefined) {
      this.xhrTasks.delete(raw.id)
      try {
        task.destroy()
      } catch (e) {
        logger.warn(`gmXhrAbort: ${e}`)
      }
    }
  }

  /** 回调派发到发起请求的标签页 */
  private fireXhr(tab: TabInfo, id: number, ok: boolean, payloadStr: string): void {
    const c = tab.controller
    if (c === null) {
      return
    }
    const js: string = `window.__qhGmCore && window.__qhGmCore.fireXhr(${id}, ${ok},`
      + ` ${JSON.stringify(payloadStr)});`
    c.runJavaScript(js).catch((): void => {
    })
  }

  private static xhrMethod(m: string): http.RequestMethod {
    if (m === 'POST') {
      return http.RequestMethod.POST
    }
    if (m === 'PUT') {
      return http.RequestMethod.PUT
    }
    if (m === 'DELETE') {
      return http.RequestMethod.DELETE
    }
    if (m === 'HEAD') {
      return http.RequestMethod.HEAD
    }
    if (m === 'OPTIONS') {
      return http.RequestMethod.OPTIONS
    }
    return http.RequestMethod.GET
  }

  private findScript(scriptId: number): UserScriptInfo | null {
    for (const s of this.scripts) {
      if (s.id === scriptId) {
        return s
      }
    }
    return null
  }

  // ==================== GM 菜单命令 ====================

  /** 脚本注册菜单命令 */
  gmRegisterMenu(tabId: number, scriptId: number, menuId: number, name: string): void {
    const cmd: GmMenuCommand = new GmMenuCommand()
    cmd.tabId = tabId
    cmd.scriptId = scriptId
    cmd.menuId = menuId
    cmd.name = name
    this.menuCommands = this.menuCommands.concat([cmd])
  }

  /** 脚本注销菜单命令（按页面内菜单 id，全标签匹配） */
  gmUnregisterMenu(menuId: number): void {
    this.menuCommands = this.menuCommands.filter((c: GmMenuCommand): boolean => c.menuId !== menuId)
  }

  /** 导航开始时清空该标签的菜单命令（页面重载后由脚本重新注册） */
  clearMenuCommands(tabId: number): void {
    this.menuCommands = this.menuCommands.filter((c: GmMenuCommand): boolean => c.tabId !== tabId)
  }

  /** 当前激活标签的菜单命令（浏览器菜单展示用） */
  activeTabMenuCommands(): GmMenuCommand[] {
    const id: number = tabsVM.activeTabId
    return this.menuCommands.filter((c: GmMenuCommand): boolean => c.tabId === id)
  }

  /** 派发菜单命令执行 */
  dispatchMenuCommand(cmd: GmMenuCommand): void {
    for (const t of tabsVM.tabs) {
      if (t.id === cmd.tabId) {
        const c = t.controller
        if (c !== null) {
          const js: string = `window.__qhGmCore && window.__qhGmCore.fireMenu(${cmd.scriptId}, ${cmd.menuId});`
          c.runJavaScript(js).catch((): void => {
          })
        }
        return
      }
    }
  }

  // ==================== 注入代码生成 ====================

  /**
   * document-start 注入项：每个启用的 doc-start 脚本一个 ScriptItem，
   * scriptRules 复用 @match 规则（* 通配语义兼容）做 URL 预过滤；
   * 首项携带 GM core（幂等安装）
   */
  docStartScriptItems(): ScriptItem[] {
    // 读取 valuesVersion 建立依赖：GM 值变更后重新烘焙
    const version: number = this.valuesVersion
    const items: ScriptItem[] = []
    // 调试悬浮窗：总开关无关始终注入（排查「脚本未注入」）
    if (appSettings.userscript_debug) {
      items.push({
        script: GmRuntime.buildHudJs(),
        scriptRules: ['*']
      })
    }
    if (!appSettings.userscript_enabled) {
      return items
    }
    let first: boolean = true
    for (const s of this.scripts) {
      if (!s.enabled || s.runAt !== 'document-start' || s.id === null) {
        continue
      }
      const rules: string[] = UserScriptEngine.splitLines(s.matches)
      let code: string = first ? GmRuntime.buildCoreJs() : ''
      code += this.buildScriptCode(s)
      items.push({
        script: code,
        scriptRules: rules.length > 0 ? rules : ['*']
      })
      first = false
    }
    return items
  }

  /**
   * document-end/idle 注入代码：native 侧按 URL 匹配后拼接（onPageEnd 时 runJavaScript 执行）
   */
  onPageEndCode(url: string): string {
    const version: number = this.valuesVersion
    let code: string = ''
    // 调试悬浮窗：总开关无关始终注入
    if (appSettings.userscript_debug) {
      code += GmRuntime.buildHudJs() + '\n'
    }
    if (!appSettings.userscript_enabled) {
      return code
    }
    let first: boolean = true
    for (const s of this.scripts) {
      if (!s.enabled || s.runAt === 'document-start' || s.id === null) {
        continue
      }
      if (UserScriptEngine.matchUrl(url, s.matches, s.excludes)) {
        if (first) {
          code += GmRuntime.buildCoreJs()
          first = false
        }
        code += this.buildScriptCode(s) + '\n'
      }
    }
    return code
  }

  /** 单脚本注入代码：GM 沙箱（预烘焙值/资源/GM_info + @require 库 + 用户代码） */
  private buildScriptCode(s: UserScriptInfo): string {
    const sid: number = s.id === null ? -1 : s.id
    const valuesJson: string = this.buildValuesJson(sid)
    const resourcesJson: string = ScriptViewModel.resourcesMapJson(s.resources)
    const infoJson: string = ScriptViewModel.buildInfoJson(s)
    const requiresCode: string = ScriptViewModel.requiresCodeOf(s.requires)
    return GmRuntime.buildSandbox(sid, s, valuesJson, resourcesJson, infoJson, requiresCode)
  }

  /** 资源数组 JSON → 页面映射 JSON（{"name":{"mime","b64"}}） */
  private static resourcesMapJson(stored: string): string {
    if (stored === '' || stored === '[]') {
      return '{}'
    }
    try {
      const raw: GmResRaw[] = JSON.parse(stored) as GmResRaw[]
      if (!(raw instanceof Array)) {
        return '{}'
      }
      const map: Record<string, Object> = {}
      for (const r of raw) {
        if (typeof r.name === 'string' && typeof r.b64 === 'string') {
          const baked: Record<string, string> = {
            'mime': typeof r.mime === 'string' ? r.mime : 'application/octet-stream',
            'b64': r.b64
          }
          map[r.name] = baked as Object
        }
      }
      return JSON.stringify(map)
    } catch (e) {
      logger.warn(`resourcesMapJson 解析失败: ${e}`)
      return '{}'
    }
  }

  /** @require 库代码按序拼接 */
  private static requiresCodeOf(stored: string): string {
    if (stored === '' || stored === '[]') {
      return ''
    }
    try {
      const raw: GmDepRaw[] = JSON.parse(stored) as GmDepRaw[]
      if (!(raw instanceof Array)) {
        return ''
      }
      let code: string = ''
      for (const d of raw) {
        if (typeof d.code === 'string' && d.code !== '') {
          code += d.code + '\n;\n'
        }
      }
      return code
    } catch (e) {
      logger.warn(`requiresCodeOf 解析失败: ${e}`)
      return ''
    }
  }

  /** GM_info JSON */
  private static buildInfoJson(s: UserScriptInfo): string {
    const meta: ScriptMeta = UserScriptEngine.parseMeta(s.code)
    return '{"script":{"name":' + JSON.stringify(s.name)
      + ',"namespace":' + JSON.stringify(meta.namespace)
      + ',"version":' + JSON.stringify(s.version)
      + ',"description":' + JSON.stringify(meta.description)
      + ',"author":' + JSON.stringify(meta.author)
      + '},"scriptHandler":"Qinghong","version":"1.0.0"}'
  }
}

export const scriptVM = new ScriptViewModel()
