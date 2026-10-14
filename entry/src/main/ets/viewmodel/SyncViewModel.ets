import { WebDavClient, WebDavConfig, ConnectionTestResult } from '@ya520/webdav';
import { buffer, util } from '@kit.ArkTS';
import { preferenceUtil } from '../common/utils/persistence/PreferenceUtil';
import { AppConstants } from '../common/constants/AppConstants';
import { appSettings, UISettings } from '../common/entity/SettingsModel';
import { bookmarkVM } from './BookmarkViewModel';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import { BookmarkDao } from '../common/utils/database/impl/BookmarkDao';
import { _QhState } from '../entryability/AppState';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('SyncViewModel')

/** 云端同步文件夹默认路径 */
export const DEFAULT_REMOTE_DIR: string = '/QingHong'

/**
 * WebDAV 同步配置（持久化于首选项，独立于被同步的 appSettings）
 */
@ObservedV2
export class WebDavSyncConfig {
  /** WebDAV 服务器地址，如 https://dav.jianguoyun.com/dav/ */
  @Trace baseUrl: string = ''
  @Trace username: string = ''
  @Trace password: string = ''
  /** 云端同步文件夹路径，空串表示使用默认路径 */
  @Trace folderPath: string = ''
  /** 使用摘要认证（Digest），关闭时使用 Basic 认证 */
  @Trace useDigestAuth: boolean = false
  /** 自动同步（应用启动时合并本地与云端） */
  @Trace autoSync: boolean = false
  /** 同步数据选择 */
  @Trace syncBookmarks: boolean = true
  @Trace syncSettings: boolean = true
  /** 上次成功同步的时间戳（毫秒） */
  @Trace lastSyncTime: number = 0

  isConfigured(): boolean {
    return this.baseUrl.trim() !== ''
  }
}

/**
 * WebDAV 同步引擎
 * - 上传覆盖云端：本机 bookmarks.json / settings.json → 云端
 * - 云端覆盖本地：云端数据替换本机书签与设置
 * - 合并：书签按 URL 并集合并；设置以较新的一侧（云端 syncedAt > lastSyncTime）为准
 */
@ObservedV2
export class SyncViewModel {
  @Trace config: WebDavSyncConfig = new WebDavSyncConfig()
  @Trace isSyncing: boolean = false

  private client: WebDavClient | null = null
  private clientSig: string = ''
  private bookmarkDao: BookmarkDao | null = null
  private configLoaded: boolean = false

  // --- 配置持久化 ---

  async loadConfig(): Promise<void> {
    if (this.configLoaded) return
    try {
      const jsonStr: string = await preferenceUtil.get<string>(AppConstants.KEY_WEBDAV_CONFIG, '')
      if (jsonStr) {
        const json: Record<string, Object> = JSON.parse(jsonStr)
        this.config.baseUrl = (json['baseUrl'] as string) ?? ''
        this.config.username = (json['username'] as string) ?? ''
        this.config.password = (json['password'] as string) ?? ''
        this.config.folderPath = (json['folderPath'] as string) ?? ''
        this.config.useDigestAuth = (json['useDigestAuth'] as boolean) ?? false
        this.config.autoSync = (json['autoSync'] as boolean) ?? false
        this.config.syncBookmarks = (json['syncBookmarks'] as boolean) ?? true
        this.config.syncSettings = (json['syncSettings'] as boolean) ?? true
        this.config.lastSyncTime = (json['lastSyncTime'] as number) ?? 0
      }
      this.configLoaded = true
    } catch (e) {
      logger.error('loadConfig', `${e}`)
    }
  }

  async saveConfig(): Promise<void> {
    try {
      const data: Record<string, Object> = {
        'baseUrl': this.config.baseUrl.trim(),
        'username': this.config.username.trim(),
        'password': this.config.password,
        'folderPath': this.config.folderPath,
        'useDigestAuth': this.config.useDigestAuth,
        'autoSync': this.config.autoSync,
        'syncBookmarks': this.config.syncBookmarks,
        'syncSettings': this.config.syncSettings,
        'lastSyncTime': this.config.lastSyncTime
      }
      await preferenceUtil.put(AppConstants.KEY_WEBDAV_CONFIG, JSON.stringify(data))
    } catch (e) {
      logger.error('saveConfig', `${e}`)
    }
  }

  // --- 连接 ---

  private buildDavConfig(baseUrl: string, username: string, password: string, useDigest: boolean): WebDavConfig {
    const cfg: WebDavConfig = {
      baseUrl: baseUrl.trim(),
      username: username.trim(),
      password: password,
      authType: useDigest ? 'digest' : 'basic'
    }
    return cfg
  }

  private getClient(): WebDavClient {
    const sig: string =
      `${this.config.baseUrl}|${this.config.username}|${this.config.password}|${this.config.useDigestAuth ? 'digest' : 'basic'}`
    if (this.client && sig === this.clientSig) {
      return this.client
    }
    if (this.client) {
      this.client.destroy()
    }
    this.client =
      new WebDavClient(this.buildDavConfig(this.config.baseUrl, this.config.username, this.config.password,
        this.config.useDigestAuth))
    this.clientSig = sig
    return this.client
  }

  /**
   * 测试连接（使用表单临时参数，不要求已保存）
   */
  async testConnection(baseUrl: string, username: string, password: string, useDigest: boolean):
    Promise<ConnectionTestResult> {
    const client: WebDavClient = new WebDavClient(this.buildDavConfig(baseUrl, username, password, useDigest))
    try {
      return await client.testConnection()
    } finally {
      client.destroy()
    }
  }

  /**
   * 释放底层网络资源（应用退出时调用）
   */
  destroy(): void {
    if (this.client) {
      this.client.destroy()
      this.client = null
      this.clientSig = ''
    }
  }

  // --- 云端读写 ---

  /** 云端同步目录：配置的文件夹路径，空则使用默认路径 */
  private remoteDir(): string {
    const p: string = this.config.folderPath.trim()
    if (p === '') {
      return DEFAULT_REMOTE_DIR
    }
    return p.startsWith('/') ? p : `/${p}`
  }

  private remoteBookmarks(): string {
    return `${this.remoteDir()}/bookmarks.json`
  }

  private remoteSettings(): string {
    return `${this.remoteDir()}/settings.json`
  }

  private async ensureRemoteDir(): Promise<void> {
    try {
      const resp = await this.getClient().mkcol(this.remoteDir())
      // 201 新建成功；405/409 表示已存在
      if (resp.statusCode !== 201 && resp.statusCode !== 405 && resp.statusCode !== 409) {
        logger.warn('ensureRemoteDir', `创建同步目录返回 ${resp.statusCode}`)
      }
    } catch (e) {
      logger.warn('ensureRemoteDir', `${e}`)
    }
  }

  private async putJson(path: string, payload: Record<string, Object>): Promise<void> {
    const body: ArrayBuffer = buffer.from(JSON.stringify(payload), 'utf-8').buffer as ArrayBuffer
    const resp = await this.getClient().put(path, body, { 'Content-Type': 'application/json' })
    if (resp.statusCode !== 201 && resp.statusCode !== 204) {
      throw new Error(`WebDAV 上传失败 (HTTP ${resp.statusCode})`)
    }
  }

  private async getJson(path: string): Promise<Record<string, Object> | null> {
    const resp = await this.getClient().get(path)
    if (resp.statusCode === 404) {
      return null
    }
    if (resp.statusCode !== 200) {
      throw new Error(`WebDAV 下载失败 (HTTP ${resp.statusCode})`)
    }
    if (!resp.data) {
      return null
    }
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
    const text: string = decoder.decodeToString(new Uint8Array(resp.data as ArrayBuffer))
    return JSON.parse(text) as Record<string, Object>
  }

  // --- 数据序列化/应用 ---

  private getDao(): BookmarkDao {
    if (!this.bookmarkDao) {
      this.bookmarkDao = new BookmarkDao(_QhState.Context)
    }
    return this.bookmarkDao
  }

  private async bookmarksPayload(): Promise<Record<string, Object>> {
    const list: BookmarkInfo[] = await this.getDao().queryAll()
    const items: Record<string, Object>[] = []
    for (const b of list) {
      const rec: Record<string, Object> = {
        'title': b.title,
        'url': b.url,
        'isQuick': b.isQuick,
        'orderIndex': b.orderIndex,
        'createTime': b.createTime
      }
      items.push(rec)
    }
    const payload: Record<string, Object> = {
      'version': 1,
      'syncedAt': new Date().getTime(),
      'items': items
    }
    return payload
  }

  private async applyBookmarksPayload(payload: Record<string, Object>, merge: boolean): Promise<void> {
    const rawItems: Object[] = payload['items'] as Object[]
    if (!rawItems) {
      return
    }
    const dao: BookmarkDao = this.getDao()
    if (!merge) {
      await dao.clearTable()
    }
    for (const raw of rawItems) {
      const rec: Record<string, Object> = raw as Record<string, Object>
      const url: string = (rec['url'] as string) ?? ''
      if (!url) {
        continue
      }
      const bm: BookmarkInfo = new BookmarkInfo(
        (rec['title'] as string) ?? url,
        url,
        (rec['isQuick'] as boolean) ?? false,
        (rec['orderIndex'] as number) ?? 0,
        (rec['createTime'] as number) ?? new Date().getTime()
      )
      if (merge) {
        await dao.saveOrUpdate(bm)
      } else {
        bm.id = null
        await dao.insert(bm)
      }
    }
    await bookmarkVM.loadAll()
  }

  private settingsPayload(): Record<string, Object> {
    const payload: Record<string, Object> = {
      'version': 1,
      'syncedAt': new Date().getTime(),
      'appSettings': appSettings.toSyncData(),
      'uiSettings': UISettings.toSyncData()
    }
    return payload
  }

  private applySettingsPayload(payload: Record<string, Object>): void {
    const rawApp: Record<string, Object> = payload['appSettings'] as Record<string, Object>
    if (rawApp) {
      appSettings.applySyncData(rawApp)
    }
    const rawUi: Record<string, Object> = payload['uiSettings'] as Record<string, Object>
    if (rawUi) {
      UISettings.applySyncData(rawUi)
    }
  }

  // --- 三种手动同步 ---

  /**
   * 上传本地数据覆盖云端
   */
  async uploadOverwrite(): Promise<void> {
    await this.runSync(async (): Promise<void> => {
      await this.ensureRemoteDir()
      if (this.config.syncBookmarks) {
        await this.putJson(this.remoteBookmarks(), await this.bookmarksPayload())
      }
      if (this.config.syncSettings) {
        await this.putJson(this.remoteSettings(), this.settingsPayload())
      }
    })
  }

  /**
   * 使用云端数据覆盖本地
   */
  async downloadOverwrite(): Promise<void> {
    await this.runSync(async (): Promise<void> => {
      if (this.config.syncBookmarks) {
        const payload: Record<string, Object> | null = await this.getJson(this.remoteBookmarks())
        if (payload !== null) {
          await this.applyBookmarksPayload(payload, false)
        }
      }
      if (this.config.syncSettings) {
        const payload: Record<string, Object> | null = await this.getJson(this.remoteSettings())
        if (payload !== null) {
          this.applySettingsPayload(payload)
        }
      }
    })
  }

  /**
   * 合并云端和本地的数据
   * - 书签：按 URL 并集合并后回传云端
   * - 设置：云端较新（syncedAt > lastSyncTime）时采用云端，随后统一回传
   */
  async mergeSync(): Promise<void> {
    await this.runSync(async (): Promise<void> => {
      await this.ensureRemoteDir()
      if (this.config.syncBookmarks) {
        const cloud: Record<string, Object> | null = await this.getJson(this.remoteBookmarks())
        if (cloud !== null) {
          await this.applyBookmarksPayload(cloud, true)
        }
        await this.putJson(this.remoteBookmarks(), await this.bookmarksPayload())
      }
      if (this.config.syncSettings) {
        const cloud: Record<string, Object> | null = await this.getJson(this.remoteSettings())
        if (cloud !== null) {
          const cloudAt: number = (cloud['syncedAt'] as number) ?? 0
          if (cloudAt > this.config.lastSyncTime) {
            this.applySettingsPayload(cloud)
          }
        }
        await this.putJson(this.remoteSettings(), this.settingsPayload())
      }
    })
  }

  /**
   * 自动同步入口（应用启动时调用）：配置了自动同步则执行合并
   */
  async autoSyncIfNeeded(): Promise<void> {
    await this.loadConfig()
    if (!this.config.autoSync || !this.config.isConfigured()) {
      return
    }
    if (!this.config.syncBookmarks && !this.config.syncSettings) {
      return
    }
    try {
      await this.mergeSync()
      logger.info('autoSync', '自动同步成功')
    } catch (e) {
      logger.error('autoSync', `自动同步失败: ${e}`)
    }
  }

  /**
   * 同步执行包装：互斥、成功后记录时间
   */
  private async runSync(task: () => Promise<void>): Promise<void> {
    if (this.isSyncing) {
      throw new Error('正在同步中，请稍候')
    }
    this.isSyncing = true
    try {
      await task()
      this.config.lastSyncTime = new Date().getTime()
      await this.saveConfig()
    } finally {
      this.isSyncing = false
    }
  }
}

export const syncVM: SyncViewModel = new SyncViewModel()
