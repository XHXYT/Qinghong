import { AppConstants } from "../constants/AppConstants";
import { preferenceUtil } from "../utils/persistence/PreferenceUtil";
import { ConfigurationConstant } from "@kit.AbilityKit";
import { webview } from "@kit.ArkWeb";

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
  /** 操作栏显示拓展按钮（扩展入口，默认关闭） */
  @Trace show_extension_button: boolean = false
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
      "show_extension_button": this.show_extension_button,
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
    this.show_extension_button = (json["show_extension_button"] as boolean) ?? this.show_extension_button;
    const content = json["address_bar_content"] as string;
    if (content === 'title' || content === 'url' || content === 'domain') {
      this.address_bar_content = content;
    }
    this.action_bar_color_mode = (json["action_bar_color_mode"] as boolean) ?? this.action_bar_color_mode;
  }

  @Monitor('color_mode', 'app_layout', 'auto_hide_action_bar', 'show_tab_bar',
    'show_home_button', 'show_download_button', 'show_bookmark_bar',
    'show_extension_button', 'address_bar_content', 'action_bar_color_mode')
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
    this.show_extension_button = false;
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
  /** 启动恢复模式 'never' | 'always' | 'keep' | 'ask'（keep：新主页启动，上次标签留后台） */
  @Trace restore_mode: string = 'keep'
  /** 默认无痕模式 */
  @Trace default_incognito: boolean = false
  /** 隐私：不跟踪 */
  @Trace do_not_track: boolean = true
  /** 隐私：禁用 WebRTC */
  @Trace disable_webrtc: boolean = false
  /** 隐私：禁止 WebRTC 非代理 UDP（API 26 高级安全模式，防 WebRTC 经 UDP 绕过代理泄露真实 IP） */
  @Trace disable_webrtc_udp: boolean = false
  /** 隐私：不出售或分享数据 */
  @Trace do_not_sell: boolean = false
  /** 隐私：智能防跟踪（跨站跟踪型网站请求不携带 Cookie，ArkWeb 内核执行） */
  @Trace intelligent_tracking_prevention: boolean = true
  /** 隐私：允许第三方 Cookie（关闭后跨站 Cookie 被拒，部分网站登录可能异常） */
  @Trace third_party_cookie: boolean = true
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
  /** DNS 优化：使用 DoH 加密解析（加速 & 防污染） */
  @Trace dns_doh_enabled: boolean = false
  /** DNS 优化服务商：预置 id（alidns/dnspod/google/cloudflare/qihoo360）| 'custom' */
  @Trace dns_doh_provider: string = 'alidns'
  /** DNS 优化自定义 DoH 服务器地址（https:// 开头，provider=custom 时使用） */
  @Trace dns_doh_custom: string = ''
  /** 代理：启用代理（走代理范围由网站设定「走代理」的默认与例外决定） */
  @Trace proxy_enabled: boolean = false
  /** 代理协议 'http' | 'socks' */
  @Trace proxy_type: string = 'http'
  /** 代理服务器主机（IP 或域名） */
  @Trace proxy_host: string = ''
  /** 代理端口（1-65535，0 表示未设置） */
  @Trace proxy_port: number = 0
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
  /** 智能防跟踪（ITP）豁免域名列表（应用级，内核不持久化，启动时重设） */
  @Trace itp_bypass_hosts: string[] = []
  /** 外置视频播放器 'system' | 'none' */
  @Trace video_player: string = 'system'
  /** 视频控制：启用视频手势（网页视频触屏手势总开关） */
  @Trace video_gesture_enabled: boolean = false
  /** 视频手势：双击快进/快退（双击视频左侧快退、右侧快进） */
  @Trace video_gesture_double_tap: boolean = true
  /** 视频手势：滑动调节进度（按住视频左右滑动，松开生效） */
  @Trace video_gesture_swipe_seek: boolean = true
  /** 视频手势：上下滑调亮度音量（全屏时左侧亮度、右侧音量） */
  @Trace video_gesture_side_slide: boolean = true
  /** 视频手势：单击暂停/播放 */
  @Trace video_gesture_tap_toggle: boolean = true
  /** 视频手势：长按倍速（3 倍速播放，松开恢复） */
  @Trace video_gesture_long_press: boolean = true
  /** 视频控制：常用键盘快捷键（空格/方向键/M/F 等控制视频） */
  @Trace video_keyboard_shortcuts: boolean = false
  /** 视频快捷键自定义键位（"id:键,...", 空串=全部默认） */
  @Trace video_kb_keys: string = ''
  /** 退出时清除数据（逗号分隔的 key 列表）；默认勾选：缓存/应用缓存 */
  @Trace exit_clear_data: string = 'cache,app_cache'
  /** 高级：无图模式（不加载网页在线图片） */
  @Trace no_image_mode: boolean = false
  /** 高级：应用切后台暂停全部网页 JS 定时器（省电，回前台自动恢复） */
  @Trace pause_web_timers: boolean = false
  /** 高级：网页助手（视频/可下载资源时展示悬浮按钮入口） */
  @Trace web_assistant: boolean = true
  /** 高级：资源嗅探（网页助手菜单中的嗅探入口；依赖网页助手开启） */
  @Trace resource_sniff: boolean = true
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
  /** 高级：点击状态栏回到网页顶部（ArkWeb backToTop，系统默认开启） */
  @Trace back_to_top: boolean = true
   /** 高级：白屏检测自动重试（导航后 5s 检测，白屏则刷新重试一次，同 URL 仅一次防循环） */
   @Trace blank_screen_retry: boolean = true
   /** 高级：网页滚动到边缘时回弹（ArkWeb overScrollMode ALWAYS；更改后新开标签生效） */
   @Trace web_overscroll_bounce: boolean = false
   /** 高级：最小字号（px，网页 CSS 小字强制提升到该下限；内核默认 8） */
   @Trace web_min_font_size: number = 8
   /** 高级：文本自动适配（窄屏密集小字自动放大；内核默认开） */
   @Trace web_text_autosizing: boolean = true
  /** 高级：关闭标签后立即释放网页内核资源（FAST_MODE；关闭则系统延迟释放 NORMAL_MODE，默认更流畅） */
   @Trace web_fast_destroy: boolean = false
   /** 禁止网页访问局域网（开=子资源局域网请求需 CORS 预检授权，未授权即拦截；内核默认开） */
   @Trace web_block_private_network: boolean = true
  /** 高级：预解析加速（自动预连接高频访问的站点） */
  @Trace dns_preconnect_enabled: boolean = true
  /** 高级：预加载网页（地址栏输入停顿时按回车目标预取/预连接，无痕标签不预热） */
  @Trace web_prefetch: boolean = true
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
  /** 弹出式窗口为「询问」时，与当前页面同域名的窗口直接放行（about:blank 视为同域） */
  @Trace popup_allow_same_host: boolean = true
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
  /** 将所选字体应用到网页文字（等宽代码字体不受影响） */
  @Trace web_font_enabled: boolean = false
  /** 密码管理器：提示保存密码（应用自建密码库） */
  @Trace password_save_prompt: boolean = true
  /** 密码管理器：托管给系统密码管理器（Web enableAutoFill） */
  @Trace system_password_manager: boolean = false
  /** 主页模式：default 默认 / blank 空白 / bookmarks 书签 / web 网页 */
  @Trace home_page_mode: string = 'default'
  /** 主页模式为网页时的主页地址 */
  @Trace home_page_url: string = ''
  // —— 主页定制（定制面板）——
  /** 主页 Logo 模式：default 默认 / image 图片 / text 文字 / html 代码 / none 无 */
  @Trace home_logo_mode: string = 'default'
  /** 主页 Logo：自定义图片路径（logo_mode=image） */
  @Trace home_logo_image: string = ''
  /** 主页 Logo：自定义文字（logo_mode=text） */
  @Trace home_logo_text: string = ''
  /** 主页 Logo：HTML 代码（logo_mode=html，将启用本地 HTML 主页） */
  @Trace home_logo_html: string = ''
  /** 主页搜索框：圆角值（vp，矩形样式生效） */
  @Trace home_search_radius: number = 23
  /** 主页搜索框：底色不透明度（%） */
  @Trace home_search_opacity: number = 100
  /** 主页搜索框：描边粗细（vp，0=无边框） */
  @Trace home_search_border_width: number = 0
  /** 主页搜索框：描边不透明度（%） */
  @Trace home_search_border_opacity: number = 100
  /** 主页搜索框样式：rect 矩形 / line 线条 */
  @Trace home_search_style: string = 'rect'
  /** 主页背景：图片路径（空=纯色） */
  @Trace home_bg_image: string = ''
  /** 主页背景主题：system 跟随系统 / light 亮 / dark 暗 */
  @Trace home_bg_theme: string = 'system'
  /** 主页背景图片不透明度（%） */
  @Trace home_bg_opacity: number = 100
  /** 主页背景图片模糊（px，0=不模糊） */
  @Trace home_bg_blur: number = 0
  /** 主页收藏块宽度（vp，0=自适应） */
  @Trace home_quick_width: number = 0
  /** 主页收藏块高度（vp，0=自适应） */
  @Trace home_quick_height: number = 0
  /** 主页收藏块圆角值（vp） */
  @Trace home_quick_radius: number = 24
  /** 主页收藏图标样式：text 文字 / icon 图标优先（favicon 缓存） */
  @Trace home_quick_icon_style: string = 'text'
  /** 主页高级：搜索框效果 blur 模糊 / transparent 透明（底色不透明度归零） */
  @Trace home_search_effect: string = 'blur'
  /** 主页高级：搜索框模糊程度（px，blur 效果生效，0=不模糊） */
  @Trace home_search_blur: number = 16
  /** 主页高级：搜索区域垂直偏移（vp，负=上移 正=下移） */
  @Trace home_search_offset: number = 0
  /** 主页高级：搜索框高度（vp） */
  @Trace home_search_height: number = 46
  /** 主页高级：显示搜索区域（Logo + 搜索框） */
  @Trace home_show_search_area: boolean = true
  /** 主页高级：自定义 CSS（非空时启用本地 HTML 主页，优先级最高） */
  @Trace home_custom_css: string = ''
  /** 主页高级：使用自定义 CSS（关闭则不注入，内容保留不清空） */
  @Trace home_custom_css_enabled: boolean = true
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
  /** 书签文件夹注册表（JSON 条目数组：'/' 分层，条目含路径与统一顺序值） */
  @Trace bookmark_folders: string = '[]'
  /** 操作设定：滑动屏幕前进后退 */
  @Trace swipe_nav_enabled: boolean = false
  /** 操作设定：使用音量键翻页（网页中一般为控制上下滚动） */
  @Trace volume_key_paging: boolean = false
  /** 用户脚本：启用脚本总开关（脚本列表见设置-脚本页） */
  @Trace userscript_enabled: boolean = true
  /** 用户脚本：调试悬浮窗（页面右下角显示注入状态与 GM 调用计数） */
  @Trace userscript_debug: boolean = false
  /** 扩展程序：启用扩展总开关（默认关；关闭后停止内容脚本注入、扩展页面宿主、后台宿主与 popup，且不显示扩展入口按钮） */
  @Trace extension_enabled: boolean = false
  /** 键盘快捷键自定义（逗号分隔 id:key 覆盖项，空 = 全默认） */
  @Trace keyboard_shortcuts: string = ''
  /** 底部工具栏事件绑定（逗号分隔 事件id:动作id，未存条目 = 无操作） */
  @Trace toolbar_events: string = ''
  /** 操作设定：工具栏滑动事件（底部工具栏左滑/右滑触发绑定动作，关闭后工具栏不再响应横滑） */
  @Trace toolbar_swipe_enabled: boolean = true
  /** 下载配置：HLS 分片并发下载数（1-8，代理掐连接环境下并发成倍提速） */
  @Trace download_concurrency: number = 4
  /** 下载配置：同时下载任务数上限（1-4，超出排队等待） */
  @Trace download_task_limit: number = 3
  /** 下载配置：下载进度通知 */
  @Trace download_notify: boolean = true
  /** 翻译：目标语言（如 zh-CN） */
  @Trace translate_target_lang: string = 'zh-CN'
  /** 翻译：双语对照（译文后附原文） */
  @Trace translate_bilingual: boolean = false
  /** 翻译：总是自动翻译的页面语言（逗号分隔，如 en,ja） */
  @Trace translate_always: string = ''
  /** 翻译：服务 builtin 内置免费 / deepl / libre */
  @Trace translate_engine: string = 'builtin'
  /** 翻译：DeepL API 密钥（free key 以 :fx 结尾） */
  @Trace translate_deepl_key: string = ''
  /** 翻译：LibreTranslate 服务地址 */
  @Trace translate_libre_url: string = ''
  /** 翻译：LibreTranslate 密钥（可空） */
  @Trace translate_libre_key: string = ''
  /** 翻译：微软 Azure 密钥（可附 #region，如 key#eastasia） */
  @Trace translate_ms_key: string = ''
  /** 翻译：百度翻译 APP ID */
  @Trace translate_baidu_appid: string = ''
  /** 翻译：百度翻译密钥 */
  @Trace translate_baidu_key: string = ''
  /** 翻译：有道智云应用 ID */
  @Trace translate_youdao_appid: string = ''
  /** 翻译：有道智云应用密钥 */
  @Trace translate_youdao_secret: string = ''

  constructor() {
  }

  /** 蒙版颜色的十六进制值 */
  maskColorHex(): string {
    return this.night_mask_color === 'amber' ? '#FFBD69' : '#000000'
  }

  /** 自定义 CSS 是否生效：开关开启且内容非空 */
  customCssEnabled(): boolean {
    return this.home_custom_css_enabled && this.home_custom_css.trim() !== ''
  }

  /** 主页定制：是否启用本地 HTML 主页（Logo 用 HTML 代码或自定义 CSS 生效中） */
  isHomeHtmlMode(): boolean {
    return this.home_logo_mode === 'html' || this.customCssEnabled()
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
      // Web 销毁模式须在首个 Web 组件创建前应用（全局静态配置）
      this.applyWebDestroyMode();
      // 局域网访问限制同为全局静态配置，配置加载后立即应用
      this.applyPrivateNetworkAccess();

      console.info("[AppSettings] App配置加载成功");
    } catch (e) {
      console.error("[AppSettings] JSON 解析失败，使用默认配置", e);
    }
  }

  /** 高级：应用 Web 销毁模式（开=FAST_MODE 立即释放内核资源；关=NORMAL_MODE 系统延迟释放，默认） */
  @Monitor('web_fast_destroy')
  public applyWebDestroyMode(): void {
    try {
      webview.WebviewController.setWebDestroyMode(
        this.web_fast_destroy ? webview.WebDestroyMode.FAST_MODE : webview.WebDestroyMode.NORMAL_MODE)
    } catch (e) {
      console.error('[AppSettings] setWebDestroyMode 失败', e)
    }
  }

  /** 高级：应用局域网访问限制（开=enablePrivateNetworkAccess(true)，网页子资源访问局域网需预检授权；全局静态配置） */
  @Monitor('web_block_private_network')
  public applyPrivateNetworkAccess(): void {
    try {
      webview.WebviewController.enablePrivateNetworkAccess(this.web_block_private_network)
    } catch (e) {
      console.error('[AppSettings] enablePrivateNetworkAccess 失败', e)
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
      "disable_webrtc_udp": this.disable_webrtc_udp,
      "do_not_sell": this.do_not_sell,
      "intelligent_tracking_prevention": this.intelligent_tracking_prevention,
      "third_party_cookie": this.third_party_cookie,
      "ad_block_enabled": this.ad_block_enabled,
      "ad_block_builtin": this.ad_block_builtin,
      "geolocation_access": this.geolocation_access,
      "language": this.language,
      "screen_orientation": this.screen_orientation,
      "dns_doh_enabled": this.dns_doh_enabled,
      "dns_doh_provider": this.dns_doh_provider,
      "dns_doh_custom": this.dns_doh_custom,
      "proxy_enabled": this.proxy_enabled,
      "proxy_type": this.proxy_type,
      "proxy_host": this.proxy_host,
      "proxy_port": this.proxy_port,
      "ua_mode": this.ua_mode,
      "ua_desktop": this.ua_desktop,
      "desktop_mode": this.desktop_mode,
      "ua_simplify": this.ua_simplify,
      "custom_uas": this.custom_uas,
      "itp_bypass_hosts": this.itp_bypass_hosts,
      "video_player": this.video_player,
      "video_gesture_enabled": this.video_gesture_enabled,
      "video_gesture_double_tap": this.video_gesture_double_tap,
      "video_gesture_swipe_seek": this.video_gesture_swipe_seek,
      "video_gesture_side_slide": this.video_gesture_side_slide,
      "video_gesture_tap_toggle": this.video_gesture_tap_toggle,
      "video_gesture_long_press": this.video_gesture_long_press,
      "video_keyboard_shortcuts": this.video_keyboard_shortcuts,
      "video_kb_keys": this.video_kb_keys,
      "exit_clear_data": this.exit_clear_data,
      "no_image_mode": this.no_image_mode,
      "pause_web_timers": this.pause_web_timers,
      "web_assistant": this.web_assistant,
      "resource_sniff": this.resource_sniff,
      "allow_debug_web": this.allow_debug_web,
      "disable_safe_browsing": this.disable_safe_browsing,
      "ignore_ssl_warning": this.ignore_ssl_warning,
      "web_vibration_enabled": this.web_vibration_enabled,
      "web_haptic_enabled": this.web_haptic_enabled,
      "back_to_top": this.back_to_top,
       "blank_screen_retry": this.blank_screen_retry,
      "web_overscroll_bounce": this.web_overscroll_bounce,
      "web_min_font_size": this.web_min_font_size,
      "web_text_autosizing": this.web_text_autosizing,
      "web_fast_destroy": this.web_fast_destroy,
      "web_block_private_network": this.web_block_private_network,
      "dns_preconnect_enabled": this.dns_preconnect_enabled,
      "web_prefetch": this.web_prefetch,
      "show_undo_close_tip": this.show_undo_close_tip,
      "auto_expand_web": this.auto_expand_web,
      "force_enable_zoom": this.force_enable_zoom,
      "cookies_enabled": this.cookies_enabled,
      "popup_allowed": this.popup_allowed,
      "popup_allow_same_host": this.popup_allow_same_host,
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
      "web_font_enabled": this.web_font_enabled,
      "password_save_prompt": this.password_save_prompt,
      "system_password_manager": this.system_password_manager,
      "home_page_mode": this.home_page_mode,
      "home_page_url": this.home_page_url,
      "home_logo_mode": this.home_logo_mode,
      "home_logo_image": this.home_logo_image,
      "home_logo_text": this.home_logo_text,
      "home_logo_html": this.home_logo_html,
      "home_search_radius": this.home_search_radius,
      "home_search_opacity": this.home_search_opacity,
      "home_search_border_width": this.home_search_border_width,
      "home_search_border_opacity": this.home_search_border_opacity,
      "home_search_style": this.home_search_style,
      "home_bg_image": this.home_bg_image,
      "home_bg_theme": this.home_bg_theme,
      "home_bg_opacity": this.home_bg_opacity,
      "home_bg_blur": this.home_bg_blur,
      "home_quick_width": this.home_quick_width,
      "home_quick_height": this.home_quick_height,
      "home_quick_radius": this.home_quick_radius,
      "home_quick_icon_style": this.home_quick_icon_style,
      "home_search_effect": this.home_search_effect,
      "home_search_blur": this.home_search_blur,
      "home_search_offset": this.home_search_offset,
      "home_search_height": this.home_search_height,
      "home_show_search_area": this.home_show_search_area,
      "home_custom_css": this.home_custom_css,
      "home_custom_css_enabled": this.home_custom_css_enabled,
      "search_suggest_sources": this.search_suggest_sources,
      "search_toolbar_enabled": this.search_toolbar_enabled,
      "search_toolbar_engines": this.search_toolbar_engines,
      "menu_layout": this.menu_layout,
      "long_press_menu": this.long_press_menu,
      "bookmark_folders": this.bookmark_folders,
      "swipe_nav_enabled": this.swipe_nav_enabled,
      "volume_key_paging": this.volume_key_paging,
      "userscript_enabled": this.userscript_enabled,
      "userscript_debug": this.userscript_debug,
      "extension_enabled": this.extension_enabled,
      "keyboard_shortcuts": this.keyboard_shortcuts,
      "toolbar_events": this.toolbar_events,
      "toolbar_swipe_enabled": this.toolbar_swipe_enabled,
      "download_concurrency": this.download_concurrency,
      "download_task_limit": this.download_task_limit,
      "download_notify": this.download_notify,
      "translate_target_lang": this.translate_target_lang,
      "translate_bilingual": this.translate_bilingual,
      "translate_always": this.translate_always,
      "translate_engine": this.translate_engine,
      "translate_deepl_key": this.translate_deepl_key,
      "translate_libre_url": this.translate_libre_url,
      "translate_libre_key": this.translate_libre_key,
      "translate_ms_key": this.translate_ms_key,
      "translate_baidu_appid": this.translate_baidu_appid,
      "translate_baidu_key": this.translate_baidu_key,
      "translate_youdao_appid": this.translate_youdao_appid,
      "translate_youdao_secret": this.translate_youdao_secret
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
    this.disable_webrtc_udp = (json["disable_webrtc_udp"] as boolean) ?? this.disable_webrtc_udp;
    this.do_not_sell = (json["do_not_sell"] as boolean) ?? this.do_not_sell;
    this.intelligent_tracking_prevention =
      (json["intelligent_tracking_prevention"] as boolean) ?? this.intelligent_tracking_prevention;
    this.third_party_cookie =
      (json["third_party_cookie"] as boolean) ?? this.third_party_cookie;
    this.ad_block_enabled = (json["ad_block_enabled"] as boolean) ?? this.ad_block_enabled;
    this.ad_block_builtin = (json["ad_block_builtin"] as boolean) ?? this.ad_block_builtin;
    this.geolocation_access = (json["geolocation_access"] as boolean) ?? this.geolocation_access;
    this.language = (json["language"] as string) ?? this.language;
    this.screen_orientation = (json["screen_orientation"] as string) ?? this.screen_orientation;
    this.dns_doh_enabled = (json["dns_doh_enabled"] as boolean) ?? this.dns_doh_enabled;
    this.dns_doh_provider = (json["dns_doh_provider"] as string) ?? this.dns_doh_provider;
    this.dns_doh_custom = (json["dns_doh_custom"] as string) ?? this.dns_doh_custom;
    this.proxy_enabled = (json["proxy_enabled"] as boolean) ?? this.proxy_enabled;
    this.proxy_type = (json["proxy_type"] as string) ?? this.proxy_type;
    this.proxy_host = (json["proxy_host"] as string) ?? this.proxy_host;
    this.proxy_port = (json["proxy_port"] as number) ?? this.proxy_port;
    this.ua_mode = (json["ua_mode"] as string) ?? this.ua_mode;
    this.ua_desktop = (json["ua_desktop"] as string) ?? this.ua_desktop;
    this.desktop_mode = (json["desktop_mode"] as boolean) ?? this.desktop_mode;
    this.ua_simplify = (json["ua_simplify"] as boolean) ?? this.ua_simplify;
    this.video_player = (json["video_player"] as string) ?? this.video_player;
    this.video_gesture_enabled = (json["video_gesture_enabled"] as boolean) ?? this.video_gesture_enabled;
    this.video_gesture_double_tap = (json["video_gesture_double_tap"] as boolean) ?? this.video_gesture_double_tap;
    this.video_gesture_swipe_seek = (json["video_gesture_swipe_seek"] as boolean) ?? this.video_gesture_swipe_seek;
    this.video_gesture_side_slide = (json["video_gesture_side_slide"] as boolean) ?? this.video_gesture_side_slide;
    this.video_gesture_tap_toggle = (json["video_gesture_tap_toggle"] as boolean) ?? this.video_gesture_tap_toggle;
    this.video_gesture_long_press = (json["video_gesture_long_press"] as boolean) ?? this.video_gesture_long_press;
    this.video_keyboard_shortcuts = (json["video_keyboard_shortcuts"] as boolean) ?? this.video_keyboard_shortcuts;
    this.video_kb_keys = (json["video_kb_keys"] as string) ?? this.video_kb_keys;
    this.exit_clear_data = (json["exit_clear_data"] as string) ?? this.exit_clear_data;
    this.no_image_mode = (json["no_image_mode"] as boolean) ?? this.no_image_mode;
    this.pause_web_timers = (json["pause_web_timers"] as boolean) ?? this.pause_web_timers;
    this.web_assistant = (json["web_assistant"] as boolean) ?? this.web_assistant;
    this.resource_sniff = (json["resource_sniff"] as boolean) ?? this.resource_sniff;
    this.allow_debug_web = (json["allow_debug_web"] as boolean) ?? this.allow_debug_web;
    this.disable_safe_browsing = (json["disable_safe_browsing"] as boolean) ?? this.disable_safe_browsing;
    this.ignore_ssl_warning = (json["ignore_ssl_warning"] as boolean) ?? this.ignore_ssl_warning;
    this.web_vibration_enabled = (json["web_vibration_enabled"] as boolean) ?? this.web_vibration_enabled;
    this.web_haptic_enabled = (json["web_haptic_enabled"] as boolean) ?? this.web_haptic_enabled;
    this.back_to_top = (json["back_to_top"] as boolean) ?? this.back_to_top;
     this.blank_screen_retry = (json["blank_screen_retry"] as boolean) ?? this.blank_screen_retry;
    this.web_overscroll_bounce = (json["web_overscroll_bounce"] as boolean) ?? this.web_overscroll_bounce;
    this.web_min_font_size = (json["web_min_font_size"] as number) ?? this.web_min_font_size;
    this.web_text_autosizing = (json["web_text_autosizing"] as boolean) ?? this.web_text_autosizing;
    this.web_fast_destroy = (json["web_fast_destroy"] as boolean) ?? this.web_fast_destroy;
    this.web_block_private_network = (json["web_block_private_network"] as boolean) ?? this.web_block_private_network;
    this.dns_preconnect_enabled = (json["dns_preconnect_enabled"] as boolean) ?? this.dns_preconnect_enabled;
    this.web_prefetch = (json["web_prefetch"] as boolean) ?? this.web_prefetch;
    this.show_undo_close_tip = (json["show_undo_close_tip"] as boolean) ?? this.show_undo_close_tip;
    this.auto_expand_web = (json["auto_expand_web"] as boolean) ?? this.auto_expand_web;
    this.force_enable_zoom = (json["force_enable_zoom"] as boolean) ?? this.force_enable_zoom;
    this.cookies_enabled = (json["cookies_enabled"] as boolean) ?? this.cookies_enabled;
    this.popup_allowed = (json["popup_allowed"] as boolean) ?? this.popup_allowed;
    this.popup_allow_same_host = (json["popup_allow_same_host"] as boolean) ?? this.popup_allow_same_host;
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
    this.web_font_enabled = (json["web_font_enabled"] as boolean) ?? this.web_font_enabled;
    this.password_save_prompt = (json["password_save_prompt"] as boolean) ?? this.password_save_prompt;
    this.system_password_manager = (json["system_password_manager"] as boolean) ?? this.system_password_manager;
    this.home_page_mode = (json["home_page_mode"] as string) ?? this.home_page_mode;
    this.home_page_url = (json["home_page_url"] as string) ?? this.home_page_url;
    this.home_logo_mode = (json["home_logo_mode"] as string) ?? this.home_logo_mode;
    this.home_logo_image = (json["home_logo_image"] as string) ?? this.home_logo_image;
    this.home_logo_text = (json["home_logo_text"] as string) ?? this.home_logo_text;
    this.home_logo_html = (json["home_logo_html"] as string) ?? this.home_logo_html;
    this.home_search_radius = (json["home_search_radius"] as number) ?? this.home_search_radius;
    this.home_search_opacity = (json["home_search_opacity"] as number) ?? this.home_search_opacity;
    this.home_search_border_width = (json["home_search_border_width"] as number) ?? this.home_search_border_width;
    this.home_search_border_opacity = (json["home_search_border_opacity"] as number) ?? this.home_search_border_opacity;
    this.home_search_style = (json["home_search_style"] as string) ?? this.home_search_style;
    this.home_bg_image = (json["home_bg_image"] as string) ?? this.home_bg_image;
    this.home_bg_theme = (json["home_bg_theme"] as string) ?? this.home_bg_theme;
    this.home_bg_opacity = (json["home_bg_opacity"] as number) ?? this.home_bg_opacity;
    this.home_bg_blur = (json["home_bg_blur"] as number) ?? this.home_bg_blur;
    this.home_quick_width = (json["home_quick_width"] as number) ?? this.home_quick_width;
    this.home_quick_height = (json["home_quick_height"] as number) ?? this.home_quick_height;
    this.home_quick_radius = (json["home_quick_radius"] as number) ?? this.home_quick_radius;
    this.home_quick_icon_style = (json["home_quick_icon_style"] as string) ?? this.home_quick_icon_style;
    this.home_search_effect = (json["home_search_effect"] as string) ?? this.home_search_effect;
    this.home_search_blur = (json["home_search_blur"] as number) ?? this.home_search_blur;
    this.home_search_offset = (json["home_search_offset"] as number) ?? this.home_search_offset;
    this.home_search_height = (json["home_search_height"] as number) ?? this.home_search_height;
    this.home_show_search_area = (json["home_show_search_area"] as boolean) ?? this.home_show_search_area;
    this.home_custom_css = (json["home_custom_css"] as string) ?? this.home_custom_css;
    this.home_custom_css_enabled = (json["home_custom_css_enabled"] as boolean) ?? this.home_custom_css_enabled;
    this.search_suggest_sources = (json["search_suggest_sources"] as string) ?? this.search_suggest_sources;
    this.search_toolbar_enabled = (json["search_toolbar_enabled"] as boolean) ?? this.search_toolbar_enabled;
    this.search_toolbar_engines = (json["search_toolbar_engines"] as string) ?? this.search_toolbar_engines;
    this.menu_layout = (json["menu_layout"] as string) ?? this.menu_layout;
    this.long_press_menu = (json["long_press_menu"] as string) ?? this.long_press_menu;
    this.bookmark_folders = (json["bookmark_folders"] as string) ?? this.bookmark_folders;
    this.swipe_nav_enabled = (json["swipe_nav_enabled"] as boolean) ?? this.swipe_nav_enabled;
    this.volume_key_paging = (json["volume_key_paging"] as boolean) ?? this.volume_key_paging;
    this.userscript_enabled = (json["userscript_enabled"] as boolean) ?? this.userscript_enabled;
    this.userscript_debug = (json["userscript_debug"] as boolean) ?? this.userscript_debug;
    this.extension_enabled = (json["extension_enabled"] as boolean) ?? this.extension_enabled;
    this.keyboard_shortcuts = (json["keyboard_shortcuts"] as string) ?? this.keyboard_shortcuts;
    this.toolbar_events = (json["toolbar_events"] as string) ?? this.toolbar_events;
    this.toolbar_swipe_enabled = (json["toolbar_swipe_enabled"] as boolean) ?? this.toolbar_swipe_enabled;
    const conc = json["download_concurrency"] as number;
    if (conc !== undefined && conc >= 1 && conc <= 8) {
      this.download_concurrency = Math.round(conc);
    }
    const limit = json["download_task_limit"] as number;
    if (limit !== undefined && limit >= 1 && limit <= 4) {
      this.download_task_limit = Math.round(limit);
    }
    this.download_notify = (json["download_notify"] as boolean) ?? this.download_notify;
    this.translate_target_lang = (json["translate_target_lang"] as string) ?? this.translate_target_lang;
    this.translate_bilingual = (json["translate_bilingual"] as boolean) ?? this.translate_bilingual;
    this.translate_always = (json["translate_always"] as string) ?? this.translate_always;
    this.translate_engine = (json["translate_engine"] as string) ?? this.translate_engine;
    this.translate_deepl_key = (json["translate_deepl_key"] as string) ?? this.translate_deepl_key;
    this.translate_libre_url = (json["translate_libre_url"] as string) ?? this.translate_libre_url;
    this.translate_libre_key = (json["translate_libre_key"] as string) ?? this.translate_libre_key;
    this.translate_ms_key = (json["translate_ms_key"] as string) ?? this.translate_ms_key;
    this.translate_baidu_appid = (json["translate_baidu_appid"] as string) ?? this.translate_baidu_appid;
    this.translate_baidu_key = (json["translate_baidu_key"] as string) ?? this.translate_baidu_key;
    this.translate_youdao_appid = (json["translate_youdao_appid"] as string) ?? this.translate_youdao_appid;
    this.translate_youdao_secret = (json["translate_youdao_secret"] as string) ?? this.translate_youdao_secret;

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

    const rawBypassHosts = json["itp_bypass_hosts"] as Object[];
    if (rawBypassHosts) {
      const hosts: string[] = [];
      for (const raw of rawBypassHosts) {
        const h = raw as string;
        if (typeof h === 'string' && h !== '') {
          hosts.push(h);
        }
      }
      this.itp_bypass_hosts = hosts;
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
    'do_not_track', 'disable_webrtc', 'disable_webrtc_udp', 'do_not_sell', 'intelligent_tracking_prevention', 'third_party_cookie', 'geolocation_access', 'language', 'screen_orientation', 'ua_mode', 'ua_desktop', 'desktop_mode', 'ua_simplify', 'custom_uas',     'video_player', 'video_gesture_enabled', 'video_gesture_double_tap', 'video_gesture_swipe_seek',
    'video_gesture_side_slide', 'video_gesture_tap_toggle', 'video_gesture_long_press', 'video_keyboard_shortcuts', 'video_kb_keys',
    'exit_clear_data', 'no_image_mode', 'pause_web_timers', 'web_assistant', 'resource_sniff', 'allow_debug_web', 'disable_safe_browsing',
    'ignore_ssl_warning', 'web_vibration_enabled', 'web_haptic_enabled', 'back_to_top', 'blank_screen_retry', 'web_overscroll_bounce', 'web_min_font_size', 'web_text_autosizing', 'web_fast_destroy', 'web_block_private_network', 'dns_preconnect_enabled', 'web_prefetch',
    'dns_doh_enabled', 'dns_doh_provider', 'dns_doh_custom',
    'proxy_enabled', 'proxy_type', 'proxy_host', 'proxy_port',
    'show_undo_close_tip', 'auto_expand_web', 'force_enable_zoom', 'cookies_enabled', 'cookies_block_third_party', 'popup_allowed', 'popup_allow_same_host', 'site_defaults', 'ad_block_enabled', 'ad_block_builtin', 'night_mask_enabled', 'night_mask_opacity', 'night_mask_color', 'force_dark_web',
    'read_mode_address_button', 'read_mode_confirm', 'read_mode_bg_color', 'read_mode_custom_bg', 'read_mode_font_size', 'read_mode_serif', 'font_family', 'web_font_enabled',
    'password_save_prompt', 'system_password_manager', 'home_page_mode', 'home_page_url',
    'home_logo_mode', 'home_logo_image', 'home_logo_text', 'home_logo_html',
    'home_search_radius', 'home_search_opacity', 'home_search_border_width', 'home_search_border_opacity',
    'home_search_style', 'home_bg_image', 'home_bg_theme', 'home_bg_opacity', 'home_bg_blur',
    'home_quick_width', 'home_quick_height', 'home_quick_radius', 'home_quick_icon_style',
    'home_search_effect', 'home_search_blur', 'home_search_offset', 'home_search_height',
    'home_show_search_area', 'home_custom_css', 'home_custom_css_enabled',
    'search_suggest_sources',     'search_toolbar_enabled', 'search_toolbar_engines', 'menu_layout', 'long_press_menu', 'bookmark_folders',
    'swipe_nav_enabled', 'volume_key_paging', 'keyboard_shortcuts', 'toolbar_events', 'toolbar_swipe_enabled',
    'userscript_enabled', 'userscript_debug', 'extension_enabled',
    'download_concurrency', 'download_task_limit', 'download_notify',
    'translate_target_lang', 'translate_bilingual', 'translate_always', 'translate_engine',
    'translate_deepl_key', 'translate_libre_url', 'translate_libre_key',
    'translate_ms_key', 'translate_baidu_appid', 'translate_baidu_key',
    'translate_youdao_appid', 'translate_youdao_secret')
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
    this.restore_mode = 'keep';
    this.default_incognito = false;
    this.do_not_track = true;
    this.disable_webrtc = false;
    this.disable_webrtc_udp = false;
    this.do_not_sell = false;
    this.intelligent_tracking_prevention = true;
    this.third_party_cookie = true;
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
    this.itp_bypass_hosts = [];
    this.video_player = 'system';
    this.video_gesture_enabled = false;
    this.video_gesture_double_tap = true;
    this.video_gesture_swipe_seek = true;
    this.video_gesture_side_slide = true;
    this.video_gesture_tap_toggle = true;
    this.video_gesture_long_press = true;
    this.video_keyboard_shortcuts = false;
    this.video_kb_keys = '';
    this.exit_clear_data = 'cache,app_cache';
    this.no_image_mode = false;
    this.pause_web_timers = false;
    this.web_assistant = true;
    this.resource_sniff = true;
    this.allow_debug_web = true;
    this.disable_safe_browsing = false;
    this.ignore_ssl_warning = false;
    this.web_vibration_enabled = false;
    this.web_haptic_enabled = true;
    this.back_to_top = true;
    this.blank_screen_retry = true;
    this.web_overscroll_bounce = false;
    this.web_min_font_size = 8;
    this.web_text_autosizing = true;
    this.web_fast_destroy = false;
    this.web_block_private_network = true;
    this.dns_preconnect_enabled = true;
    this.web_prefetch = true;
    this.dns_doh_enabled = false;
    this.dns_doh_provider = 'alidns';
    this.dns_doh_custom = '';
    this.proxy_enabled = false;
    this.proxy_type = 'http';
    this.proxy_host = '';
    this.proxy_port = 0;
    this.show_undo_close_tip = true;
    this.auto_expand_web = false;
    this.force_enable_zoom = false;
    this.cookies_enabled = true;
    this.popup_allowed = false;
    this.popup_allow_same_host = true;
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
    this.web_font_enabled = false;
    this.password_save_prompt = true;
    this.system_password_manager = false;
    this.home_page_mode = 'default';
    this.home_page_url = '';
    this.home_logo_mode = 'default';
    this.home_logo_image = '';
    this.home_logo_text = '';
    this.home_logo_html = '';
    this.home_search_radius = 23;
    this.home_search_opacity = 100;
    this.home_search_border_width = 0;
    this.home_search_border_opacity = 100;
    this.home_search_style = 'rect';
    this.home_bg_image = '';
    this.home_bg_theme = 'system';
    this.home_bg_opacity = 100;
    this.home_bg_blur = 0;
    this.home_quick_width = 0;
    this.home_quick_height = 0;
    this.home_quick_radius = 24;
    this.home_quick_icon_style = 'text';
    this.home_search_effect = 'blur';
    this.home_search_blur = 16;
    this.home_search_offset = 0;
    this.home_search_height = 46;
    this.home_show_search_area = true;
    this.home_custom_css = '';
    this.home_custom_css_enabled = true;
    this.search_suggest_sources = 'favorites,bookmarks,tabs,history,engine,search_history';
    this.search_toolbar_enabled = false;
    this.search_toolbar_engines = 'baidu:1,google:1,bing:1,sogou:1,so360:1,toutiao:1,shenma:1';
    this.menu_layout = '';
    this.long_press_menu = '';
    this.bookmark_folders = '[]';
    this.swipe_nav_enabled = false;
    this.volume_key_paging = false;
    this.userscript_enabled = true;
    this.userscript_debug = false;
    this.extension_enabled = false;
    this.keyboard_shortcuts = '';
    this.toolbar_events = '';
    this.toolbar_swipe_enabled = true;
    this.download_concurrency = 4;
    this.download_task_limit = 3;
    this.download_notify = true;
    this.translate_target_lang = 'zh-CN';
    this.translate_bilingual = false;
    this.translate_always = '';
    this.translate_engine = 'builtin';
    this.translate_deepl_key = '';
    this.translate_libre_url = '';
    this.translate_libre_key = '';
    this.translate_ms_key = '';
    this.translate_baidu_appid = '';
    this.translate_baidu_key = '';
    this.translate_youdao_appid = '';
    this.translate_youdao_secret = '';
    this.save();
  }

  /** 重置主页定制项（不动 home_page_mode / home_page_url） */
  public async resetHomeCustomize(): Promise<void> {
    this.home_logo_mode = 'default';
    this.home_logo_image = '';
    this.home_logo_text = '';
    this.home_logo_html = '';
    this.home_search_radius = 23;
    this.home_search_opacity = 100;
    this.home_search_border_width = 0;
    this.home_search_border_opacity = 100;
    this.home_search_style = 'rect';
    this.home_bg_image = '';
    this.home_bg_theme = 'system';
    this.home_bg_opacity = 100;
    this.home_bg_blur = 0;
    this.home_quick_width = 0;
    this.home_quick_height = 0;
    this.home_quick_radius = 24;
    this.home_quick_icon_style = 'text';
    this.home_search_effect = 'blur';
    this.home_search_blur = 16;
    this.home_search_offset = 0;
    this.home_search_height = 46;
    this.home_show_search_area = true;
    this.home_custom_css = '';
    this.home_custom_css_enabled = true;
    this.save();
  }
}

export const appSettings: AppSettings = new AppSettings()
