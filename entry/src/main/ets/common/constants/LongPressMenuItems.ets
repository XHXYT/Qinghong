/**
 * 网页元素长按菜单（PC 窗口模式为右键菜单）动作项定义
 * 设置页与运行时菜单共用；appSettings.long_press_menu 存已启用 id（逗号分隔，'' = 默认）
 */
import { appSettings } from '../entity/SettingsModel';

/** 动作作用对象 */
export class LongPressTarget {
  static readonly LINK = 'link'
  static readonly IMAGE = 'image'
  static readonly GENERAL = 'general'
}

export class LongPressMenuItem {
  readonly id: string
  readonly title: ResourceStr
  readonly target: string
  readonly defaultOn: boolean

  constructor(id: string, title: ResourceStr, target: string, defaultOn: boolean) {
    this.id = id
    this.title = title
    this.target = target
    this.defaultOn = defaultOn
  }
}

export class LongPressMenuItems {

  /** 全部动作项（顺序即显示顺序，默认全开仅「保存图片」关闭） */
  static readonly ALL: LongPressMenuItem[] = [
    new LongPressMenuItem('open_bg', $r('app.string.long_press_open_bg'), LongPressTarget.LINK, true),
    new LongPressMenuItem('open_new', $r('app.string.long_press_open_new'), LongPressTarget.LINK, true),
    new LongPressMenuItem('view_image', $r('app.string.long_press_view_image'), LongPressTarget.IMAGE, true),
    new LongPressMenuItem('save_image', $r('app.string.long_press_save_image'), LongPressTarget.IMAGE, false),
    new LongPressMenuItem('download_image', $r('app.string.long_press_download_image'), LongPressTarget.IMAGE, true),
    new LongPressMenuItem('share_image', $r('app.string.long_press_share_image'), LongPressTarget.IMAGE, true),
    new LongPressMenuItem('search_image', $r('app.string.long_press_search_image'), LongPressTarget.IMAGE, true),
    new LongPressMenuItem('image_viewer', $r('app.string.long_press_image_viewer'), LongPressTarget.IMAGE, true),
    new LongPressMenuItem('page_info', $r('app.string.long_press_page_info'), LongPressTarget.GENERAL, true),
    new LongPressMenuItem('mark_ad', $r('app.string.mark_ad'), LongPressTarget.GENERAL, true),
    new LongPressMenuItem('copy_link_text', $r('app.string.long_press_copy_link_text'), LongPressTarget.LINK, true),
    new LongPressMenuItem('scan_qr', $r('app.string.scan_qr'), LongPressTarget.IMAGE, true),
    new LongPressMenuItem('copy_link', $r('app.string.copy_link'), LongPressTarget.LINK, true),
    new LongPressMenuItem('share', $r('app.string.share'), LongPressTarget.GENERAL, true),
  ]

  /** 文字选中菜单动作项（自绘面板，不参与设置页开关） */
  static readonly TEXT_MENU: LongPressMenuItem[] = [
    new LongPressMenuItem('text_copy', $r('app.string.text_menu_copy'), LongPressTarget.GENERAL, true),
    new LongPressMenuItem('text_select_all', $r('app.string.text_menu_select_all'), LongPressTarget.GENERAL, true),
    new LongPressMenuItem('text_search', $r('app.string.text_menu_search'), LongPressTarget.GENERAL, true),
    new LongPressMenuItem('text_translate', $r('app.string.translate_selection'), LongPressTarget.GENERAL, true),
    new LongPressMenuItem('text_share', $r('app.string.share'), LongPressTarget.GENERAL, true),
  ]

  /** 已启用动作项 id 列表（'' = 取默认） */
  static enabledIds(): string[] {
    if (appSettings.long_press_menu !== '') {
      return appSettings.long_press_menu.split(',')
    }
    const ids: string[] = []
    for (const item of LongPressMenuItems.ALL) {
      if (item.defaultOn) {
        ids.push(item.id)
      }
    }
    return ids
  }

  /** 指定动作是否启用 */
  static isEnabled(id: string): boolean {
    return LongPressMenuItems.enabledIds().includes(id)
  }

  /** 切换指定动作启用状态（写回 appSettings.long_press_menu） */
  static toggle(id: string): void {
    const ids = LongPressMenuItems.enabledIds()
    const idx = ids.indexOf(id)
    if (idx >= 0) {
      ids.splice(idx, 1)
    } else {
      ids.push(id)
    }
    appSettings.long_press_menu = ids.join(',')
  }
}
