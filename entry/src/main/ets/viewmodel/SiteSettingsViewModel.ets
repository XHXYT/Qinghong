import { SiteSettingDao } from '../common/utils/database/impl/SiteSettingDao';
import SiteSettingInfo from '../common/entity/SiteSettingInfo';
import { appSettings } from '../common/entity/SettingsModel';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { _QhState } from '../entryability/AppState';
import { UaUtils } from '../common/utils/UaUtils';

/** 站点设置档位 */
export class SiteOpt {
  readonly value: string
  readonly label: ResourceStr

  constructor(value: string, label: ResourceStr) {
    this.value = value
    this.label = label
  }
}

/** 站点设置项配置 */
export class SiteItemConfig {
  readonly key: string
  readonly title: ResourceStr
  readonly options: SiteOpt[]
  readonly def: string
  /** 开关型（二档，渲染为 Toggle） */
  readonly isToggle: boolean = false

  constructor(key: string, title: ResourceStr, options: SiteOpt[], def: string, isToggle: boolean = false) {
    this.key = key
    this.title = title
    this.options = options
    this.def = def
    this.isToggle = isToggle
  }
}

/** 站点设置分组 */
export class SiteGroup {
  readonly key: string
  readonly title: ResourceStr
  readonly items: SiteItemConfig[]

  constructor(key: string, title: ResourceStr, items: SiteItemConfig[]) {
    this.key = key
    this.title = title
    this.items = items
  }
}

/**
 * 站点运行时策略（TabWeb 应用到 Web 属性）：
 * 站点覆盖 > 全局默认（显式设置） > 应用设置
 */
export class SitePolicy {
  /** 匹配的页面 host */
  host: string = ''
  /** 字体缩放（%，应用级默认 100） */
  fontZoom: number = 100
  /** 图片：'app' 跟随应用 | 'allow' 有图 | 'block' 无图 | 'wifi' 仅WIFI有图 */
  imageMode: string = 'app'
  /** 是否执行 JavaScript */
  jsEnabled: boolean = true
  /** 广告拦截：'app' 跟随应用 | 'on' 强制开启 | 'off' 强制关闭 */
  adBlock: string = 'app'
  /** UA 覆盖串（'' = 跟随应用全局 UA） */
  uaOverride: string = ''
  /** 位置权限：'app' 跟随应用 | 'allow' | 'ask' | 'block' */
  locationMode: string = 'app'
  /** 摄像头权限：'app' 跟随应用 | 'allow' | 'ask' | 'block' */
  cameraMode: string = 'app'
  /** 麦克风权限：'app' 跟随应用 | 'allow' | 'ask' | 'block' */
  micMode: string = 'app'
  /** 剪贴板文本读写：'allow' | 'ask' | 'block'（默认 allow） */
  clipboardMode: string = 'allow'
  /** 重定向：'allow' | 'ask' | 'block'（默认 allow；拦主框架非手势跨域自动跳转） */
  redirectMode: string = 'allow'
  /** 返回不刷新（BFCache：离开页面时按当前页策略缓存快照，返回瞬时恢复），默认开 */
  backNoReload: boolean = true
}

/** 权限三档（允许/优先询问/已禁止） */
function P(): SiteOpt[] {
  return [
    new SiteOpt('allow', $r('app.string.site_opt_allow')),
    new SiteOpt('ask', $r('app.string.site_opt_ask')),
    new SiteOpt('block', $r('app.string.site_opt_block'))
  ]
}

/** 允许/阻止两档 */
function AB(def: string): SiteOpt[] {
  return [
    new SiteOpt('allow', $r('app.string.site_opt_allow')),
    new SiteOpt('block', $r('app.string.site_opt_block'))
  ]
}

/** 开关两档 */
function T(def: string): SiteOpt[] {
  return [
    new SiteOpt('on', $r('app.string.site_opt_on')),
    new SiteOpt('off', $r('app.string.site_opt_off'))
  ]
}

/**
 * 站点设置：全局默认值存 appSettings.site_defaults（JSON，参与同步），
 * 站点例外存 RDB site_setting 表
 */
@ObservedV2
export class SiteSettingsViewModel {

  /** 字体缩放下限（%） */
  static readonly FONT_MIN: number = 90
  /** 字体缩放上限（%） */
  static readonly FONT_MAX: number = 130
  /** 字体预览基准字号（fp） */
  static readonly PREVIEW_BASE: number = 16

  private db: SiteSettingDao | null = null

  private getDB(): SiteSettingDao {
    if (!this.db) {
      this.db = new SiteSettingDao(_QhState.Context)
    }
    return this.db
  }

  /** 设置项配置缓存（key → config） */
  private static configMap: Map<string, SiteItemConfig> | null = null

  /** 全部分组（主页渲染） */
  static groups(): SiteGroup[] {
    return [
      new SiteGroup('content', $r('app.string.site_group_content'), [
        new SiteItemConfig('site_font_size', $r('app.string.site_font_size'), [
          new SiteOpt('90', '90%'),
          new SiteOpt('100', '100%'),
          new SiteOpt('115', '115%'),
          new SiteOpt('130', '130%')
        ], '100'),
        new SiteItemConfig('site_ua', $r('app.string.site_ua'), [
          new SiteOpt('global', $r('app.string.site_opt_follow_global'))
        ], 'global'),
        new SiteItemConfig('site_desktop', $r('app.string.site_desktop'), T('off'), 'off', true),
        new SiteItemConfig('site_image', $r('app.string.site_image'), [
          new SiteOpt('allow', $r('app.string.site_opt_image_show')),
          new SiteOpt('block', $r('app.string.site_opt_image_none')),
          new SiteOpt('wifi', $r('app.string.site_opt_image_wifi'))
        ], 'allow'),
        new SiteItemConfig('site_js', $r('app.string.site_js'), AB('allow'), 'allow'),
        new SiteItemConfig('site_cookies', $r('app.string.site_cookies'), [], 'allow'),
        new SiteItemConfig('site_popup', $r('app.string.site_popup'), [], 'off')
      ]),
      new SiteGroup('basic', $r('app.string.site_group_basic'), [
        new SiteItemConfig('site_ad_block', $r('app.string.site_ad_block'), T('on'), 'on', true),
        new SiteItemConfig('site_incognito', $r('app.string.site_incognito'), T('off'), 'off', true)
      ]),
      new SiteGroup('permission', $r('app.string.site_group_permission'), [
        new SiteItemConfig('site_clipboard', $r('app.string.site_clipboard'), P(), 'allow'),
        new SiteItemConfig('site_location', $r('app.string.site_location'), P(), 'block'),
        new SiteItemConfig('site_camera', $r('app.string.site_camera'), P(), 'ask'),
        new SiteItemConfig('site_microphone', $r('app.string.site_microphone'), P(), 'ask'),
        new SiteItemConfig('site_redirect', $r('app.string.site_redirect'), P(), 'allow'),
        new SiteItemConfig('site_vibration', $r('app.string.web_vibration'), [], 'off')
      ]),
      new SiteGroup('advanced', $r('app.string.site_group_advanced'), [
        new SiteItemConfig('site_back_no_reload', $r('app.string.site_back_no_reload'), T('on'), 'on', true)
      ])
    ]
  }

  /** 按 key 查配置 */
  static config(key: string): SiteItemConfig | null {
    if (SiteSettingsViewModel.configMap === null) {
      const map: Map<string, SiteItemConfig> = new Map()
      for (const g of SiteSettingsViewModel.groups()) {
        for (const item of g.items) {
          map.set(item.key, item)
        }
      }
      SiteSettingsViewModel.configMap = map
    }
    return SiteSettingsViewModel.configMap.get(key) ?? null
  }

  /** 解析全局默认值 JSON */
  private static defaultsRaw(): Record<string, Object> {
    if (appSettings.site_defaults === '') {
      return {}
    }
    try {
      return JSON.parse(appSettings.site_defaults) as Record<string, Object>
    } catch (e) {
      return {}
    }
  }

  /** 全局默认档位（未自定义时返回配置默认值） */
  static getDefault(key: string): string {
    const config: SiteItemConfig | null = SiteSettingsViewModel.config(key)
    const raw: Record<string, Object> = SiteSettingsViewModel.defaultsRaw()
    const v: Object | undefined = raw[key]
    if (v !== undefined && typeof v === 'string' && v !== '') {
      return v
    }
    return config !== null ? config.def : ''
  }

  /** 写入全局默认档位（落盘 + 同步） */
  static setDefault(key: string, value: string): void {
    const raw: Record<string, Object> = SiteSettingsViewModel.defaultsRaw()
    raw[key] = value
    appSettings.site_defaults = JSON.stringify(raw)
    appSettings.save()
    SiteSettingsViewModel.policyCache.clear()
  }

  /** 档位标识 → 文案 */
  static labelOf(config: SiteItemConfig, value: string): string {
    // 浏览器标识：档位来自全局 UA 列表（预置 + 自定义），单独解析
    if (config.key === 'site_ua') {
      return SiteSettingsViewModel.uaLabel(value)
    }
    for (const opt of config.options) {
      if (opt.value === value) {
        return typeof opt.label === 'string' ? opt.label : ResourceUtils.getString(opt.label as Resource)
      }
    }
    return value
  }

  /** 浏览器标识档位文案（global 跟随全局） */
  static uaLabel(value: string): string {
    if (value === 'global') {
      return ResourceUtils.getString($r('app.string.site_opt_follow_global'))
    }
    const name: ResourceStr = UaUtils.presetName(value)
    return typeof name === 'string' ? name : ResourceUtils.getString(name as Resource)
  }

  /** 浏览器标识可选档位：跟随全局 + 预置 UA + 自定义 UA */
  static uaOptions(): SiteOpt[] {
    const opts: SiteOpt[] = [
      new SiteOpt('global', $r('app.string.site_opt_follow_global'))
    ]
    for (const p of UaUtils.PRESETS) {
      opts.push(new SiteOpt(p.id, p.nameRes))
    }
    for (const c of appSettings.custom_uas) {
      opts.push(new SiteOpt(c.id, c.name))
    }
    return opts
  }

  // --- 站点例外（RDB） ---

  /** 站点运行时策略缓存（host → policy；任何写入后清空） */
  private static policyCache: Map<string, SitePolicy> = new Map()
  /** 缓存建立时的全局默认签名（site_defaults 变化即失效，含同步写入场景） */
  private static policyDefaultsSig: string = ''

  /** 同步获取已缓存的站点策略（onLoadIntercept 提前应用 UA 用） */
  cachedPolicy(host: string): SitePolicy | null {
    const cached: SitePolicy | undefined = SiteSettingsViewModel.policyCache.get(host)
    return cached !== undefined ? cached : null
  }

  /**
   * 解析站点运行时策略（站点覆盖 > 全局显式默认 > 应用设置）：
   * - 全局默认仅显式设置过的 key 生效（未设置的 key 跟随应用）
   * - 站点按最长后缀匹配（含子域），站点设定停用时仅应用级
   */
  async resolvePolicy(host: string): Promise<SitePolicy> {
    if (SiteSettingsViewModel.policyDefaultsSig !== appSettings.site_defaults) {
      SiteSettingsViewModel.policyCache.clear()
      SiteSettingsViewModel.policyDefaultsSig = appSettings.site_defaults
    }
    const cached: SitePolicy | undefined = SiteSettingsViewModel.policyCache.get(host)
    if (cached !== undefined) {
      return cached
    }
    const merged: Map<string, string> = new Map()
    // 第一层：显式全局默认（浏览器标识除外：全局 UA 即应用 UA，入口在 UA 设置页）
    const raw: Record<string, Object> = SiteSettingsViewModel.defaultsRaw()
    for (const g of SiteSettingsViewModel.groups()) {
      for (const item of g.items) {
        if (item.key === 'site_ua') {
          continue
        }
        const v: Object | undefined = raw[item.key]
        if (v !== undefined && typeof v === 'string' && v !== '') {
          merged.set(item.key, v as string)
        }
      }
    }
    // 第二层：站点覆盖
    const sites: string[] = await this.getDB().listSites()
    let best: string = ''
    for (const s of sites) {
      if (SiteSettingsViewModel.hostMatches(host, s) && s.length > best.length) {
        best = s
      }
    }
    if (best !== '') {
      const rows: SiteSettingInfo[] = await this.getDB().listBySite(best)
      let enabled: boolean = true
      for (const r of rows) {
        if (r.key === SiteSettingsViewModel.SITE_ENABLED_KEY && r.value === 'off') {
          enabled = false
        }
      }
      if (enabled) {
        for (const r of rows) {
          if (r.key !== SiteSettingsViewModel.SITE_ENABLED_KEY && r.value !== '') {
            merged.set(r.key, r.value)
          }
        }
      } else {
        // 站点设定停用：仅应用级
        merged.clear()
      }
    }
    // 合成策略
    const policy: SitePolicy = new SitePolicy()
    policy.host = host
    // 字体缩放
    const fs: string = merged.get('site_font_size') ?? ''
    if (fs !== '' && fs !== 'global') {
      const n: number = Number(fs)
      if (!Number.isNaN(n) && n > 0 && n <= 500) {
        policy.fontZoom = Math.round(n)
      }
    }
    // 图片
    const im: string = merged.get('site_image') ?? ''
    policy.imageMode = im === 'block' || im === 'allow' || im === 'wifi' ? im : 'app'
    // JavaScript
    policy.jsEnabled = (merged.get('site_js') ?? '') !== 'block'
    // 广告拦截
    const ab: string = merged.get('site_ad_block') ?? ''
    policy.adBlock = ab === 'on' || ab === 'off' ? ab : 'app'
    // 位置/摄像头/麦克风权限
    policy.locationMode = SiteSettingsViewModel.permMode(merged.get('site_location') ?? '')
    policy.cameraMode = SiteSettingsViewModel.permMode(merged.get('site_camera') ?? '')
    policy.micMode = SiteSettingsViewModel.permMode(merged.get('site_microphone') ?? '')
    // 剪贴板文本读写
    const cbv: string = merged.get('site_clipboard') ?? ''
    policy.clipboardMode = cbv === 'allow' || cbv === 'ask' || cbv === 'block' ? cbv : 'allow'
    // 重定向
    const rd: string = merged.get('site_redirect') ?? ''
    policy.redirectMode = rd === 'allow' || rd === 'ask' || rd === 'block' ? rd : 'allow'
    // 返回不刷新（BFCache）
    policy.backNoReload = (merged.get('site_back_no_reload') ?? '') === 'on'
    // 浏览器标识 / 电脑模式
    const uaId: string = merged.get('site_ua') ?? ''
    if (uaId !== '' && uaId !== 'global') {
      policy.uaOverride = SiteSettingsViewModel.resolveUaString(uaId)
    } else if ((merged.get('site_desktop') ?? '') === 'on') {
      policy.uaOverride = UaUtils.desktopUa()
    }
    SiteSettingsViewModel.policyCache.set(host, policy)
    return policy
  }

  /** 权限档位归一化（'allow'/'ask'/'block'，其余跟随应用） */
  private static permMode(v: string): string {
    return v === 'allow' || v === 'ask' || v === 'block' ? v : 'app'
  }

  /** 浏览器标识档位 → UA 串（'' = 跟随应用） */
  private static resolveUaString(id: string): string {
    let ua: string = UaUtils.resolveUa(id)
    if (ua === '') {
      return ''
    }
    if (appSettings.ua_simplify) {
      ua = UaUtils.simplify(ua)
    }
    return ua
  }

  /** 从 URL 提取 host（小写；忽略协议/端口/路径） */
  static hostOf(url: string): string {
    let u: string = url
    const schemeIdx: number = u.indexOf('://')
    if (schemeIdx >= 0) {
      u = u.substring(schemeIdx + 3)
    }
    const slashIdx: number = u.indexOf('/')
    if (slashIdx >= 0) {
      u = u.substring(0, slashIdx)
    }
    const atIdx: number = u.lastIndexOf('@')
    if (atIdx >= 0) {
      u = u.substring(atIdx + 1)
    }
    const colonIdx: number = u.indexOf(':')
    if (colonIdx >= 0) {
      u = u.substring(0, colonIdx)
    }
    return u.toLowerCase()
  }

  /** 站点匹配：相等或子域后缀（a.b.com 匹配已存 b.com） */
  static hostMatches(host: string, site: string): boolean {
    if (site === '') {
      return false
    }
    return host === site || host.endsWith('.' + site)
  }

  /** 站点设定启用状态专用 key（存 site_setting 表，不参与分组渲染） */
  static readonly SITE_ENABLED_KEY: string = 'site_enabled'

  /** 站点设定是否启用（无记录默认启用） */
  async isSiteEnabled(site: string): Promise<boolean> {
    const v: string | null = await this.getDB().getOverride(site, SiteSettingsViewModel.SITE_ENABLED_KEY)
    return v !== 'off'
  }

  async setSiteEnabled(site: string, enabled: boolean): Promise<void> {
    await this.getDB().setOverride(site, SiteSettingsViewModel.SITE_ENABLED_KEY, enabled ? 'on' : 'off')
    SiteSettingsViewModel.policyCache.clear()
  }

  async getOverride(site: string, key: string): Promise<string | null> {
    return this.getDB().getOverride(site, key)
  }

  async listByKey(key: string): Promise<SiteSettingInfo[]> {
    return this.getDB().listByKey(key)
  }

  async listBySite(site: string): Promise<SiteSettingInfo[]> {
    return this.getDB().listBySite(site)
  }

  async listSites(): Promise<string[]> {
    return this.getDB().listSites()
  }

  async setOverride(site: string, key: string, value: string): Promise<void> {
    await this.getDB().setOverride(site, key, value)
    SiteSettingsViewModel.policyCache.clear()
    if (key === 'site_incognito' && this.incognitoCache !== null) {
      this.incognitoCache.set(site, value)
    }
  }

  /** 主动添加站点：仅建档启用状态，设定项按需覆盖（详情页始终渲染全量配置） */
  async addSite(site: string): Promise<void> {
    await this.getDB().setOverride(site, SiteSettingsViewModel.SITE_ENABLED_KEY, 'on')
    SiteSettingsViewModel.policyCache.clear()
  }

  async removeOverride(site: string, key: string): Promise<void> {
    await this.getDB().removeOverride(site, key)
    SiteSettingsViewModel.policyCache.clear()
    if (key === 'site_incognito' && this.incognitoCache !== null) {
      this.incognitoCache.delete(site)
    }
  }

  async removeSite(site: string): Promise<void> {
    await this.getDB().removeSite(site)
    SiteSettingsViewModel.policyCache.clear()
    if (this.incognitoCache !== null) {
      this.incognitoCache.delete(site)
    }
  }

  /** site_incognito 覆盖缓存（host → 'on'|'off'），Web 创建期同步判定用 */
  private incognitoCache: Map<string, string> | null = null

  /** 预加载无痕覆盖缓存（EntryAbility 初始化时调用） */
  async preloadIncognitoCache(): Promise<void> {
    try {
      const list: SiteSettingInfo[] = await this.getDB().listByKey('site_incognito')
      const map: Map<string, string> = new Map()
      for (const r of list) {
        map.set(r.site, r.value)
      }
      this.incognitoCache = map
    } catch (e) {
      console.error('[SiteSettings] 预加载无痕覆盖失败:', e)
    }
  }

  /**
   * Web 创建期无痕判定：站点覆盖（最长后缀匹配）优先于全局默认无痕；
   * 无覆盖或缓存未加载时返回 null（沿用标签当前无痕状态）
   */
  siteIncognitoOf(host: string): boolean | null {
    const cache: Map<string, string> | null = this.incognitoCache
    if (cache === null || host === '') {
      return null
    }
    let best: string = ''
    cache.forEach((v: string, s: string): void => {
      if (SiteSettingsViewModel.hostMatches(host, s) && s.length > best.length) {
        best = s
      }
    })
    return best === '' ? null : (cache.get(best) ?? '') === 'on'
  }
}

export const siteSettingsVM: SiteSettingsViewModel = new SiteSettingsViewModel()
