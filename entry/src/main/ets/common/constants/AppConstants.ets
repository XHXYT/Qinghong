export class AppConstants {

  /** 首选项键 */
  static readonly KEY_UI_SETTINGS: string = 'ui_settings'
  static readonly KEY_APP_SETTINGS: string = 'app_settings'

  /** 首选项文件名 */
  static readonly PREFERENCE_FILE: string = 'qinghong_preference'

  /** KV 存储 */
  static readonly KV_STORE_ID: string = 'qinghong'
  static readonly KV_KEY_SESSION: string = 'last_session'

  /** 数据库 */
  static readonly DB_NAME: string = 'qinghong'

  /** 下载目录（沙箱内相对路径） */
  static readonly DOWNLOAD_DIR: string = 'QingHong/Download'

  /** 标签页上限 */
  static readonly MAX_TABS: number = 32

  /** 默认搜索引擎 */
  static readonly DEFAULT_ENGINE_ID: string = 'bing'

  /** 会话保存防抖间隔(ms) */
  static readonly SESSION_SAVE_DEBOUNCE: number = 500

}
