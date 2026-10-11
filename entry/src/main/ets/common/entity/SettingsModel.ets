import { AppConstants } from "../constants/AppConstants";
import { preferenceUtil } from "../utils/persistence/PreferenceUtil";
import { ConfigurationConstant } from "@kit.AbilityKit";

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
  /** 工具栏位置 'bottom' | 'top' */
  @Trace toolbar_position: string = 'bottom'

  constructor() {
  }

  public async load(): Promise<void> {
    try {
      const jsonStr: string = await preferenceUtil.get<string>(AppConstants.KEY_UI_SETTINGS, "");
      if (!jsonStr) return;
      const json: Record<string, Object> = JSON.parse(jsonStr);

      this.color_mode = (json["color_mode"] as number) ?? this.color_mode;
      this.toolbar_position = (json["toolbar_position"] as string) ?? this.toolbar_position;

      console.info("[UISettings] UI配置加载成功");
    } catch (e) {
      console.error("[UISettings] JSON 解析失败，使用默认配置", e);
    }
  }

  @Monitor('color_mode', 'toolbar_position')
  public async save(): Promise<void> {
    try {
      const data: Record<string, Object> = {
        "color_mode": this.color_mode,
        "toolbar_position": this.toolbar_position
      };
      const jsonStr: string = JSON.stringify(data);
      await preferenceUtil.put(AppConstants.KEY_UI_SETTINGS, jsonStr);
    } catch (error) {
      console.error("[UISettings] 保存失败:", error);
    }
  }

  public async reset(): Promise<void> {
    this.color_mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    this.toolbar_position = 'bottom';
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
  /** 启动时恢复上次会话 */
  @Trace restore_session: boolean = true
  /** 默认无痕模式 */
  @Trace default_incognito: boolean = false

  constructor() {
  }

  public async load(): Promise<void> {
    try {
      const jsonStr: string = await preferenceUtil.get<string>(AppConstants.KEY_APP_SETTINGS, "");
      if (!jsonStr) return;
      const json: Record<string, Object> = JSON.parse(jsonStr);

      this.search_engine_id = (json["search_engine_id"] as string) ?? this.search_engine_id;
      this.show_homepage_logo = (json["show_homepage_logo"] as boolean) ?? this.show_homepage_logo;
      this.restore_session = (json["restore_session"] as boolean) ?? this.restore_session;
      this.default_incognito = (json["default_incognito"] as boolean) ?? this.default_incognito;

      const rawEngines = json["custom_engines"] as Object[];
      if (rawEngines) {
        const engines: CustomSearchEngine[] = []
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

      console.info("[AppSettings] App配置加载成功");
    } catch (e) {
      console.error("[AppSettings] JSON 解析失败，使用默认配置", e);
    }
  }

  @Monitor('search_engine_id', 'custom_engines', 'show_homepage_logo', 'restore_session', 'default_incognito')
  public async save(): Promise<void> {
    try {
      const data: Record<string, Object> = {
        "search_engine_id": this.search_engine_id,
        "custom_engines": this.custom_engines,
        "show_homepage_logo": this.show_homepage_logo,
        "restore_session": this.restore_session,
        "default_incognito": this.default_incognito
      };
      const jsonStr: string = JSON.stringify(data);
      await preferenceUtil.put(AppConstants.KEY_APP_SETTINGS, jsonStr);
    } catch (error) {
      console.error("[AppSettings] 保存失败:", error);
    }
  }

  public async reset(): Promise<void> {
    this.search_engine_id = AppConstants.DEFAULT_ENGINE_ID;
    this.custom_engines = [];
    this.show_homepage_logo = true;
    this.restore_session = true;
    this.default_incognito = false;
    this.save();
  }
}

export const appSettings: AppSettings = new AppSettings()
