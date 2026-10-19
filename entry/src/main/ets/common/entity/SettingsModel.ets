import { AppConstants } from "../constants/AppConstants";
import { preferenceUtil } from "../utils/persistence/PreferenceUtil";
import { ConfigurationConstant } from "@kit.AbilityKit";

/**
 * 自定义浏览器标识（UA 对：名称 + UA 字符串）
 */
export class CustomUa {
  id: string = ''
  name: string = ''
  ua: string = ''

  constructor(id: string, name: string, ua: string) {
    this.id = id
    this.name = name
    this.ua = ua
  }
}

/**
 * 自定义搜索引擎
 */
export class CustomSearchEngine {
  id: string = ''
  name: string = ''
  /** 含 %s 占位符的搜索模板，如 https://www.bing.com/search?q=%s */
  url: string = ''

  constructor(id: string, name: string, url: string) {
    this.id = id
    this.name = name
    this.url = url
  }
}

/**
 * UI 设定类（颜色模式、工具栏位置）
 */
@ObservedV2
export class _UISettings {
  @Trace color_mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
  /** 应用布局 'traditional'(传统：地址栏上、工具栏下) | 'top'(工具栏在上：合并) | 'bottom'(工具栏在下：合并) | 'bottom_double'(双行工具栏) */
  @Trace app_layout: string = 'traditional'
  /** 自动隐藏操作栏 'always' | 'slide'(滑动显示隐藏) | 'tap'(点击来显示隐藏) */
  @Trace auto_hide_action_bar: string = 'always'
  /** 启用标签栏（配合 'top'/'bottom' 布局，常驻操作栏正上方） */
  @Trace show_tab_bar: boolean = false
  /** 合并操作栏显示主页按钮 */
  @Trace show_home_button: boolean = false
  /** 合并操作栏显示下载按钮 */
  @Trace show_download_button: boolean = false
  /** 启用书签栏（配合 'top'/'bottom' 布局，贴操作栏内容侧） */
  @Trace show_bookmark_bar: boolean = false
  /** 地址栏内容 'title' | 'url' | 'domain' */
  @Trace address_bar_content: string = 'title'
  /** 操作栏色彩模式（浏览网页时操作栏自适应页面 theme-color） */
  @Trace action_bar_color_mode: boolean = false

  constructor() {
  }

  public async load(): Promise<void> {
    try {
      const jsonStr: string = await preferenceUtil.get<string>(AppConstants.KEY_UI_SETTINGS, "");
      if (!jsonStr) return;
      const json: Record<string, Object> = JSON.parse(jsonStr);
      this.applySyncData(json);

      console.info("[UISettings] UI配置加载成功");
    } catch (e) {
      console.error("[UISettings] JSON 解析失败，使用默认配置", e);
    }
  }

  /**
   * 导出为可同步/可持久化的键值数据
   */
  public toSyncData(): Record<string, Object> {
    return {
      "color_mode": this.color_mode,
      "app_layout": this.app_layout,
      "auto_hide_action_bar": this.auto_hide_action_bar,
      "show_tab_bar": this.show_tab_bar,
      "show_home_button": this.show_home_button,
      "show_download_button": this.show_download_button,
      "show_bookmark_bar": this.show_bookmark_bar,
      "address_bar_content": this.address_bar_content,
      "action_bar_color_mode": this.action_bar_color_mode
    };
  }

  /**
   * 从键值数据应用配置（本地加载与云端同步共用）；
   * 兼容旧版 toolbar_position 迁移到 app_layout
   */
  public applySyncData(json: Record<string, Object>): void {
    this.color_mode = (json["color_mode"] as number) ?? this.color_mode;
    const layout = json["app_layout"] as string;
    if (layout === 'traditional' || layout === 'top' || layout === 'bottom'
      || layout === 'bottom_double') {
      this.app_layout = layout;
    } else {
      // 旧版迁移：'top' → 合并在上，其余（含 'bottom' 传统布局）→ 传统
      this.app_layout = (json["toolbar_position"] as string) === 'top' ? 'top' : 'traditional';
    }
    const hide = json["auto_hide_action_bar"] as string;
    if (hide === 'always' || hide === 'slide' || hide === 'tap') {
      this.auto_hide_action_bar = hide;
    }
    this.show_tab_bar = (json["show_tab_bar"] as boolean) ?? this.show_tab_bar;
    this.show_home_button = (json["show_home_button"] as boolean) ?? this.show_home_button;
    this.show_download_button = (json["show_download_button"] as boolean) ?? this.show_download_button;
    this.show_bookmark_bar = (json["show_bookmark_bar"] as boolean) ?? this.show_bookmark_bar;
    const content = json["address_bar_content"] as string;
    if (content === 'title' || content === 'url' || content === 'domain') {
      this.address_bar_content = content;
    }
    this.action_bar_color_mode = (json["action_bar_color_mode"] as boolean) ?? this.action_bar_color_mode;
  }

  @Monitor('color_mode', 'app_layout', 'auto_hide_action_bar', 'show_tab_bar',
    'show_home_button', 'show_download_button', 'show_bookmark_bar',
    'address_bar_content', 'action_bar_color_mode')
  public async save(): Promise<void> {
    try {
      const jsonStr: string = JSON.stringify(this.toSyncData());
      await preferenceUtil.put(AppConstants.KEY_UI_SETTINGS, jsonStr);
    } catch (error) {
      console.error("[UISettings] 保存失败:", error);
    }
  }

  public async reset(): Promise<void> {
    this.color_mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    this.app_layout = 'traditional';
    this.auto_hide_action_bar = 'always';
    this.show_tab_bar = false;
    this.show_home_button = false;
    this.show_download_button = false;
    this.show_bookmark_bar = false;
    this.address_bar_content = 'title';
    this.action_bar_color_mode = false;
    this.save();
  }
}

export const UISettings: _UISettings = new _UISettings()

/**
 * 应用设定类（搜索引擎、主页、会话）
 */
@ObservedV2
export class AppSettings {
  /** 当前搜索引擎 id */
  @Trace search_engine_id: string = AppConstants.DEFAULT_ENGINE_ID
  /** 自定义搜索引擎列表 */
  @Trace custom_engines: CustomSearchEngine[] = []
  /** 主页是否显示 Logo */
  @Trace show_homepage_logo: boolean = true
  /** 启动恢复模式 'never' | 'always' | 'ask' */
  @Trace restore_mode: string = 'always'
  /** 默认无痕模式 */
  @Trace default_incognito: boolean = false
  /** 隐私：不跟踪 */
  @Trace do_not_track: boolean = true
  /** 隐私：禁用 WebRTC */
  @Trace disable_webrtc: boolean = false
  /** 隐私：不出售或分享数据 */
  @Trace do_not_sell: boolean = false
  /** 隐私：智能防跟踪（跨站跟踪型网站请求不携带 Cookie，ArkWeb 内核执行） */
  @Trace intelligent_tracking_prevention: boolean = true
  /** 广告拦截总开关 */
  @Trace ad_block_enabled: boolean = true
  /** 广告拦截：启用内建规则 */
  @Trace ad_block_builtin: boolean = true
  /** 隐私：允许网页获取位置 */
  @Trace geolocation_access: boolean = true
  /** 语言 'system' | 'en' | 'zh' */
  @Trace language: string = 'system'
  /** 屏幕方向 'auto' | 'portrait' | 'landscape' */
  @Trace screen_orientation: string = 'auto'
  /** 浏览器标识（预置 id 或自定义 UA id），默认选中「默认」 */
  @Trace ua_mode: string = 'default'
  /** 电脑模式下的浏览器标识：'windows_chrome' | 'windows_ie' | 'macos' | 'custom' */
  @Trace ua_desktop: string = 'windows_chrome'
  /** 电脑模式：请求桌面版网站（UA 改用「电脑模式标识」） */
  @Trace desktop_mode: boolean = false
  /** 简化浏览器标识：从 UA 中移除设备及次要版本信息 */
  @Trace ua_simplify: boolean = false
  /** 自定义浏览器标识列表 */
  @Trace custom_uas: CustomUa[] = []
  /** 外置视频播放器 'system' | 'none' */
  @Trace video_player: string = 'system'
  /** 退出时清除数据（逗号分隔的 key 列表） */
  @Trace exit_clear_data: string = ''
  /** 高级：无图模式（不加载网页在线图片） */
  @Trace no_image_mode: boolean = false
  /** 高级：自动展示嗅探按钮 */
  @Trace show_sniff_button: boolean = true
  /** 高级：允许调试网页 */
  @Trace allow_debug_web: boolean = true
  /** 高级：禁用安全浏览 */
  @Trace disable_safe_browsing: boolean = false
  /** 高级：忽略 SSL 证书警告 */
  @Trace ignore_ssl_warning: boolean = false
  /** 高级：网页振动（navigator.vibrate 脚本） */
  @Trace web_vibration_enabled: boolean = false
  /** 高级：保留文本长按选择的触感反馈（网页振动关闭时独立生效） */
  @Trace web_haptic_enabled: boolean = true
  /** 显示撤销关闭标签的提示 */
  @Trace show_undo_close_tip: boolean = true
  /** 打开网页时自动展开网页中折叠的内容 */
  @Trace auto_expand_web: boolean = false
  /** 强制缩放网页（忽略网页对缩放的限制） */
  @Trace force_enable_zoom: boolean = false
  /** Cookies：允许网站保存和读取 Cookies */
  @Trace cookies_enabled: boolean = true
  /** 弹出式窗口：开启后网页可直接弹出新窗口（以新标签打开）；关闭时需先询问许可 */
  @Trace popup_allowed: boolean = false
  /** Cookies：拦截第三方 Cookies */
  @Trace cookies_block_third_party: boolean = false
  /** 站点设置默认值（JSON: key→档位标识；例外站点存 RDB 不参与同步） */
  @Trace site_defaults: string = ''
  /** 夜间模式：网页蒙版滤镜 */
  @Trace night_mask_enabled: boolean = false
  /** 夜间模式：蒙版不透明度（百分比 5-90） */
  @Trace night_mask_opacity: number = 40
  /** 夜间模式：蒙版颜色 'black' | 'amber' */
  @Trace night_mask_color: string = 'black'
  /** 夜间模式：强制深色网页 */
  @Trace force_dark_web: boolean = false
  /** 阅读模式：地址栏阅读按钮（页面检测为适合阅读时自动出现，点击直接进入） */
  @Trace read_mode_address_button: boolean = true
  /** 阅读模式：点击地址栏阅读按钮时先二次确认再进入（菜单入口不受影响） */
  @Trace read_mode_confirm: boolean = true

  /** 阅读模式：背景色 'paper' | 'green' | 'white' | 'black' | 'custom' */
  @Trace read_mode_bg_color: string = 'paper'
  /** 阅读模式：自定义背景色（#RRGGBB） */
  @Trace read_mode_custom_bg: string = '#F2E8D5'
  /** 阅读模式：正文字号 */
  @Trace read_mode_font_size: number = 18
  /** 阅读模式：衬线字体 */
  @Trace read_mode_serif: boolean = false
  /** 应用字体 family（空串 = 默认字体） */
  @Trace font_family: string = ''
  /** 密码管理器：提示保存密码（应用自建密码库） */
  @Trace password_save_prompt: boolean = true
  /** 密码管理器：托管给系统密码管理器（Web enableAutoFill） */
  @Trace system_password_manager: boolean = false
  /** 主页模式：default 默认 / blank 空白 / bookmarks 书签 / web 网页 */
  @Trace home_page_mode: string = 'default'
  /** 主页模式为网页时的主页地址 */
  @Trace home_page_url: string = ''
  /** 搜索建议来源（启用项逗号分隔） */
  @Trace search_suggest_sources: string = 'favorites,bookmarks,tabs,history,engine,search_history'
  /** 搜索工具栏启用 */
  @Trace search_toolbar_enabled: boolean = false
  /** 搜索工具栏引擎列表（'id:1,id:0' 形式，顺序即显示顺序） */
  @Trace search_toolbar_engines: string = 'baidu:1,google:1,bing:1,sogou:1,so360:1,toutiao:1,shenma:1'
  /** 主菜单条目布局（逗号分隔 id，顺序即显示顺序；空 = 默认布局） */
  @Trace menu_layout: string = ''
  /** 定制长按菜单：已启用动作项（逗号分隔 id；空 = 默认全开但「保存图片」关闭） */
  @Trace long_press_menu: string = ''
  /** 书签文件夹注册表（JSON 字符串数组，'/' 分层，顺序即显示顺序） */
  @Trace bookmark_folders: string = '[]'
  /** 操作设定：滑动屏幕前进后退 */
  @Trace swipe_nav_enabled: boolean = false
  /** 操作设定：使用音量键翻页（网页中一般为控制上下滚动） */
  @Trace volume_key_paging: boolean = false
  /** 操作设定：启用播放器手势（网页内全屏视频滑动调整进度/亮度/音量，功能预留） */
  @Trace player_gestures: boolean = true
  /** 键盘快捷键自定义（逗号分隔 id:key 覆盖项，空 = 全默认） */
  @Trace keyboard_shortcuts: string = ''
  /** 底部工具栏事件绑定（逗号分隔 事件id:动作id，未存条目 = 无操作） */
  @Trace toolbar_events: string = ''

  constructor() {
  }

  /** 蒙版颜色的十六进制值 */
  maskColorHex(): string {
    return this.night_mask_color === 'amber' ? '#FFBD69' : '#000000'
  }

  /** 搜索建议来源是否启用 */
  isSuggestSourceOn(key: string): boolean {
    return this.search_suggest_sources.split(',').includes(key)
  }

  /** 阅读模式背景色的十六进制值 */
  readModeBgHex(): string {
    if (this.read_mode_bg_color === 'custom') {
      return this.read_mode_custom_bg
    }
    if (this.read_mode_bg_color === 'green') {
      return '#C7EDCC'
    }
    if (this.read_mode_bg_color === 'white') {
      return '#FFFFFF'
    }
    if (this.read_mode_bg_color === 'black') {
      return '#1C1C1C'
    }
    return '#F6F1E7'
  }

  public async load(): Promise<void> {
    try {
      const jsonStr: string = await preferenceUtil.get<string>(AppConstants.KEY_APP_SETTINGS, "");
      if (!jsonStr) return;
      const json: Record<string, Object> = JSON.parse(jsonStr);
      this.applySyncData(json);

      console.info("[AppSettings] App配置加载成功");
    } catch (e) {
      console.error("[AppSettings] JSON 解析失败，使用默认配置", e);
    }
  }

  /**
   * 导出为可同步/可持久化的键值数据
   */
  public toSyncData(): Record<string, Object> {
    return {
      "search_engine_id": this.search_engine_id,
      "custom_engines": this.custom_engines,
      "show_homepage_logo": this.show_homepage_logo,
      "restore_mode": this.restore_mode,
      "default_incognito": this.default_incognito,
      "do_not_track": this.do_not_track,
      "disable_webrtc": this.disable_webrtc,
      "do_not_sell": this.do_not_sell,
      "intelligent_tracking_prevention": this.intelligent_tracking_prevention,
      "ad_block_enabled": this.ad_block_enabled,
      "ad_block_builtin": this.ad_block_builtin,
      "geolocation_access": this.geolocation_access,
      "language": this.language,
      "screen_orientation": this.screen_orientation,
      "ua_mode": this.ua_mode,
      "ua_desktop": this.ua_desktop,
      "desktop_mode": this.desktop_mode,
      "ua_simplify": this.ua_simplify,
      "custom_uas": this.custom_uas,
      "video_player": this.video_player,
      "exit_clear_data": this.exit_clear_data,
      "no_image_mode": this.no_image_mode,
      "show_sniff_button": this.show_sniff_button,
      "allow_debug_web": this.allow_debug_web,
      "disable_safe_browsing": this.disable_safe_browsing,
      "ignore_ssl_warning": this.ignore_ssl_warning,
      "web_vibration_enabled": this.web_vibration_enabled,
      "web_haptic_enabled": this.web_haptic_enabled,
      "show_undo_close_tip": this.show_undo_close_tip,
      "auto_expand_web": this.auto_expand_web,
      "force_enable_zoom": this.force_enable_zoom,
      "cookies_enabled": this.cookies_enabled,
      "popup_allowed": this.popup_allowed,
      "cookies_block_third_party": this.cookies_block_third_party,
      "site_defaults": this.site_defaults,
      "night_mask_enabled": this.night_mask_enabled,
      "night_mask_opacity": this.night_mask_opacity,
      "night_mask_color": this.night_mask_color,
      "force_dark_web": this.force_dark_web,
      "read_mode_address_button": this.read_mode_address_button,
      "read_mode_confirm": this.read_mode_confirm,
      "read_mode_bg_color": this.read_mode_bg_color,
      "read_mode_custom_bg": this.read_mode_custom_bg,
      "read_mode_font_size": this.read_mode_font_size,
      "read_mode_serif": this.read_mode_serif,
      "font_family": this.font_family,
      "password_save_prompt": this.password_save_prompt,
      "system_password_manager": this.system_password_manager,
      "home_page_mode": this.home_page_mode,
      "home_page_url": this.home_page_url,
      "search_suggest_sources": this.search_suggest_sources,
      "search_toolbar_enabled": this.search_toolbar_enabled,
      "search_toolbar_engines": this.search_toolbar_engines,
      "menu_layout": this.menu_layout,
      "long_press_menu": this.long_press_menu,
      "bookmark_folders": this.bookmark_folders,
      "swipe_nav_enabled": this.swipe_nav_enabled,
      "volume_key_paging": this.volume_key_paging,
      "player_gestures": this.player_gestures,
      "keyboard_shortcuts": this.keyboard_shortcuts,
      "toolbar_events": this.toolbar_events
    };
  }

  /**
   * 从键值数据应用配置（本地加载与云端同步共用）
   */
  public applySyncData(json: Record<string, Object>): void {
    this.search_engine_id = (json["search_engine_id"] as string) ?? this.search_engine_id;
    this.show_homepage_logo = (json["show_homepage_logo"] as boolean) ?? this.show_homepage_logo;
    // 兼容旧版布尔字段 restore_session
    const oldRestore = json["restore_session"] as boolean;
    this.restore_mode = (json["restore_mode"] as string) ??
      (oldRestore === undefined ? this.restore_mode : (oldRestore ? 'always' : 'never'));
    this.default_incognito = (json["default_incognito"] as boolean) ?? this.default_incognito;
    this.do_not_track = (json["do_not_track"] as boolean) ?? this.do_not_track;
    this.disable_webrtc = (json["disable_webrtc"] as boolean) ?? this.disable_webrtc;
    this.do_not_sell = (json["do_not_sell"] as boolean) ?? this.do_not_sell;
    this.intelligent_tracking_prevention =
      (json["intelligent_tracking_prevention"] as boolean) ?? this.intelligent_tracking_prevention;
    this.ad_block_enabled = (json["ad_block_enabled"] as boolean) ?? this.ad_block_enabled;
    this.ad_block_builtin = (json["ad_block_builtin"] as boolean) ?? this.ad_block_builtin;
    this.geolocation_access = (json["geolocation_access"] as boolean) ?? this.geolocation_access;
    this.language = (json["language"] as string) ?? this.language;
    this.screen_orientation = (json["screen_orientation"] as string) ?? this.screen_orientation;
    this.ua_mode = (json["ua_mode"] as string) ?? this.ua_mode;
    this.ua_desktop = (json["ua_desktop"] as string) ?? this.ua_desktop;
    this.desktop_mode = (json["desktop_mode"] as boolean) ?? this.desktop_mode;
    this.ua_simplify = (json["ua_simplify"] as boolean) ?? this.ua_simplify;
    this.video_player = (json["video_player"] as string) ?? this.video_player;
    this.exit_clear_data = (json["exit_clear_data"] as string) ?? this.exit_clear_data;
    this.no_image_mode = (json["no_image_mode"] as boolean) ?? this.no_image_mode;
    this.show_sniff_button = (json["show_sniff_button"] as boolean) ?? this.show_sniff_button;
    this.allow_debug_web = (json["allow_debug_web"] as boolean) ?? this.allow_debug_web;
    this.disable_safe_browsing = (json["disable_safe_browsing"] as boolean) ?? this.disable_safe_browsing;
    this.ignore_ssl_warning = (json["ignore_ssl_warning"] as boolean) ?? this.ignore_ssl_warning;
    this.web_vibration_enabled = (json["web_vibration_enabled"] as boolean) ?? this.web_vibration_enabled;
    this.web_haptic_enabled = (json["web_haptic_enabled"] as boolean) ?? this.web_haptic_enabled;
    this.show_undo_close_tip = (json["show_undo_close_tip"] as boolean) ?? this.show_undo_close_tip;
    this.auto_expand_web = (json["auto_expand_web"] as boolean) ?? this.auto_expand_web;
    this.force_enable_zoom = (json["force_enable_zoom"] as boolean) ?? this.force_enable_zoom;
    this.cookies_enabled = (json["cookies_enabled"] as boolean) ?? this.cookies_enabled;
    this.popup_allowed = (json["popup_allowed"] as boolean) ?? this.popup_allowed;
    this.cookies_block_third_party = (json["cookies_block_third_party"] as boolean) ?? this.cookies_block_third_party;
    this.site_defaults = (json["site_defaults"] as string) ?? this.site_defaults;
    this.night_mask_enabled = (json["night_mask_enabled"] as boolean) ?? this.night_mask_enabled;
    this.night_mask_opacity = (json["night_mask_opacity"] as number) ?? this.night_mask_opacity;
    this.night_mask_color = (json["night_mask_color"] as string) ?? this.night_mask_color;
    this.force_dark_web = (json["force_dark_web"] as boolean) ?? this.force_dark_web;
    this.read_mode_address_button = (json["read_mode_address_button"] as boolean) ?? this.read_mode_address_button;
    this.read_mode_confirm = (json["read_mode_confirm"] as boolean) ?? this.read_mode_confirm;
    this.read_mode_bg_color = (json["read_mode_bg_color"] as string) ?? this.read_mode_bg_color;
    this.read_mode_custom_bg = (json["read_mode_custom_bg"] as string) ?? this.read_mode_custom_bg;
    this.read_mode_font_size = (json["read_mode_font_size"] as number) ?? this.read_mode_font_size;
    this.read_mode_serif = (json["read_mode_serif"] as boolean) ?? this.read_mode_serif;
    this.font_family = (json["font_family"] as string) ?? this.font_family;
    this.password_save_prompt = (json["password_save_prompt"] as boolean) ?? this.password_save_prompt;
    this.system_password_manager = (json["system_password_manager"] as boolean) ?? this.system_password_manager;
    this.home_page_mode = (json["home_page_mode"] as string) ?? this.home_page_mode;
    this.home_page_url = (json["home_page_url"] as string) ?? this.home_page_url;
    this.search_suggest_sources = (json["search_suggest_sources"] as string) ?? this.search_suggest_sources;
    this.search_toolbar_enabled = (json["search_toolbar_enabled"] as boolean) ?? this.search_toolbar_enabled;
    this.search_toolbar_engines = (json["search_toolbar_engines"] as string) ?? this.search_toolbar_engines;
    this.menu_layout = (json["menu_layout"] as string) ?? this.menu_layout;
    this.long_press_menu = (json["long_press_menu"] as string) ?? this.long_press_menu;
    this.bookmark_folders = (json["bookmark_folders"] as string) ?? this.bookmark_folders;
    this.swipe_nav_enabled = (json["swipe_nav_enabled"] as boolean) ?? this.swipe_nav_enabled;
    this.volume_key_paging = (json["volume_key_paging"] as boolean) ?? this.volume_key_paging;
    this.player_gestures = (json["player_gestures"] as boolean) ?? this.player_gestures;
    this.keyboard_shortcuts = (json["keyboard_shortcuts"] as string) ?? this.keyboard_shortcuts;
    this.toolbar_events = (json["toolbar_events"] as string) ?? this.toolbar_events;

    const rawUas = json["custom_uas"] as Object[];
    if (rawUas) {
      const uas: CustomUa[] = [];
      for (const raw of rawUas) {
        const rec = raw as Record<string, Object>;
        uas.push(new CustomUa(
          (rec["id"] as string) ?? '',
          (rec["name"] as string) ?? '',
          (rec["ua"] as string) ?? ''
        ));
      }
      this.custom_uas = uas;
    }

    const rawEngines = json["custom_engines"] as Object[];
    if (rawEngines) {
      const engines: CustomSearchEngine[] = [];
      for (const raw of rawEngines) {
        const rec = raw as Record<string, Object>;
        engines.push(new CustomSearchEngine(
          (rec["id"] as string) ?? '',
          (rec["name"] as string) ?? '',
          (rec["url"] as string) ?? ''
        ));
      }
      this.custom_engines = engines;
    }
  }

  @Monitor('search_engine_id', 'custom_engines', 'show_homepage_logo', 'restore_mode', 'default_incognito',
    'do_not_track', 'disable_webrtc', 'do_not_sell', 'intelligent_tracking_prevention', 'geolocation_access', 'language', 'screen_orientation', 'ua_mode', 'ua_desktop', 'desktop_mode', 'ua_simplify', 'custom_uas', 'video_player',
    'exit_clear_data', 'no_image_mode', 'show_sniff_button', 'allow_debug_web', 'disable_safe_browsing',
    'ignore_ssl_warning', 'web_vibration_enabled', 'web_haptic_enabled', 'show_undo_close_tip', 'auto_expand_web', 'force_enable_zoom', 'cookies_enabled', 'cookies_block_third_party', 'popup_allowed', 'site_defaults', 'ad_block_enabled', 'ad_block_builtin', 'night_mask_enabled', 'night_mask_opacity', 'night_mask_color', 'force_dark_web',
    'read_mode_address_button', 'read_mode_confirm', 'read_mode_bg_color', 'read_mode_custom_bg', 'read_mode_font_size', 'read_mode_serif', 'font_family',
    'password_save_prompt', 'system_password_manager', 'home_page_mode', 'home_page_url',
    'search_suggest_sources',     'search_toolbar_enabled', 'search_toolbar_engines', 'menu_layout', 'long_press_menu', 'bookmark_folders',
    'swipe_nav_enabled', 'volume_key_paging', 'player_gestures', 'keyboard_shortcuts', 'toolbar_events')
  public async save(): Promise<void> {
    try {
      const jsonStr: string = JSON.stringify(this.toSyncData());
      await preferenceUtil.put(AppConstants.KEY_APP_SETTINGS, jsonStr);
    } catch (error) {
      console.error("[AppSettings] 保存失败:", error);
    }
  }

  public async reset(): Promise<void> {
    this.search_engine_id = AppConstants.DEFAULT_ENGINE_ID;
    this.custom_engines = [];
    this.show_homepage_logo = true;
    this.restore_mode = 'always';
    this.default_incognito = false;
    this.do_not_track = true;
    this.disable_webrtc = false;
    this.do_not_sell = false;
    this.intelligent_tracking_prevention = true;
    this.ad_block_enabled = true;
    this.ad_block_builtin = true;
    this.geolocation_access = true;
    this.language = 'system';
    this.screen_orientation = 'auto';
    this.ua_mode = 'default';
    this.ua_desktop = 'windows_chrome';
    this.desktop_mode = false;
    this.ua_simplify = false;
    this.custom_uas = [];
    this.video_player = 'system';
    this.exit_clear_data = '';
    this.no_image_mode = false;
    this.show_sniff_button = true;
    this.allow_debug_web = true;
    this.disable_safe_browsing = false;
    this.ignore_ssl_warning = false;
    this.web_vibration_enabled = false;
    this.web_haptic_enabled = true;
    this.show_undo_close_tip = true;
    this.auto_expand_web = false;
    this.force_enable_zoom = false;
    this.cookies_enabled = true;
    this.popup_allowed = false;
    this.cookies_block_third_party = false;
    this.site_defaults = '';
    this.night_mask_enabled = false;
    this.night_mask_opacity = 40;
    this.night_mask_color = 'black';
    this.force_dark_web = false;
    this.read_mode_address_button = true;
    this.read_mode_confirm = true;
    this.read_mode_bg_color = 'paper';
    this.read_mode_custom_bg = '#F2E8D5';
    this.read_mode_font_size = 18;
    this.read_mode_serif = false;
    this.font_family = '';
    this.password_save_prompt = true;
    this.system_password_manager = false;
    this.home_page_mode = 'default';
    this.home_page_url = '';
    this.search_suggest_sources = 'favorites,bookmarks,tabs,history,engine,search_history';
    this.search_toolbar_enabled = false;
    this.search_toolbar_engines = 'baidu:1,google:1,bing:1,sogou:1,so360:1,toutiao:1,shenma:1';
    this.menu_layout = '';
    this.long_press_menu = '';
    this.bookmark_folders = '[]';
    this.swipe_nav_enabled = false;
    this.volume_key_paging = false;
    this.player_gestures = true;
    this.keyboard_shortcuts = '';
    this.toolbar_events = '';
    this.save();
  }
}

export const appSettings: AppSettings = new AppSettings()
