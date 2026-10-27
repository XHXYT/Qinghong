/**
 * 主菜单（≡ 宫格菜单）条目定义：定制菜单页与主菜单共用
 */
export class MenuEntry {
  readonly id: string
  readonly title: ResourceStr
  readonly symbol: Resource

  constructor(id: string, title: ResourceStr, symbol: Resource) {
    this.id = id
    this.title = title
    this.symbol = symbol
  }
}

export class MenuEntries {

  /** 全部条目（顺序：默认菜单 21 项 + 可添加 19 项） */
  static readonly ALL: MenuEntry[] = [
    // —— 默认在菜单中 ——
    new MenuEntry('bookmarks', $r('app.string.bookmarks'), $r('sys.symbol.star')),
    new MenuEntry('history', $r('app.string.history'), $r('sys.symbol.clock')),
    new MenuEntry('downloads', $r('app.string.downloads'), $r('sys.symbol.arrow_down_circle')),
    new MenuEntry('incognito', $r('app.string.incognito'), $r('sys.symbol.eye_slash')),
    new MenuEntry('share', $r('app.string.share'), $r('sys.symbol.share')),
    new MenuEntry('add_bookmark', $r('app.string.add_bookmark'), $r('sys.symbol.edit_badge_star')),
    new MenuEntry('mark_ad', $r('app.string.mark_ad'), $r('sys.symbol.square_and_pencil')),
    new MenuEntry('desktop_mode', $r('app.string.desktop_mode'), $r('sys.symbol.desktop')),
    new MenuEntry('toolbox', $r('app.string.toolbox'), $r('sys.symbol.briefcase')),
    new MenuEntry('settings', $r('app.string.settings'), $r('sys.symbol.gearshape')),
    new MenuEntry('offline_page', $r('app.string.offline_page'), $r('sys.symbol.square_stack_3d')),
    new MenuEntry('translate', $r('app.string.translate'), $r('sys.symbol.translate')),
    new MenuEntry('view_source', $r('app.string.view_source'), $r('sys.symbol.code_slash')),
    new MenuEntry('inspect_element', $r('app.string.inspect_element'), $r('sys.symbol.eyedropper')),
    new MenuEntry('fullscreen', $r('app.string.fullscreen'), $r('sys.symbol.arrow_up_left_and_arrow_down_right')),
    new MenuEntry('resource_sniff', $r('app.string.resource_sniff'), $r('sys.symbol.music_note_circle')),
    new MenuEntry('browser_id', $r('app.string.browser_id'), $r('sys.symbol.pc_ic_tab_index_1')),
    new MenuEntry('network_log', $r('app.string.network_log'), $r('sys.symbol.waveform_path_ecg_square')),
    new MenuEntry('screen_orientation', $r('app.string.screen_orientation'), $r('sys.symbol.rectangle_on_rectangle')),
    new MenuEntry('night_mode', $r('app.string.night_mode'), $r('sys.symbol.moon')),
    new MenuEntry('script', $r('app.string.script'), $r('sys.symbol.code_square')),
    new MenuEntry('customize', $r('app.string.customize'), $r('sys.symbol.paintpalette')),
    // —— 可添加 ——
    new MenuEntry('find_in_page', $r('app.string.find_in_page'), $r('sys.symbol.doc_text_badge_magnifyingglass')),
    new MenuEntry('save', $r('app.string.save'), $r('sys.symbol.square_and_arrow_down')),
    new MenuEntry('image_mode', $r('app.string.image_mode'), $r('sys.symbol.picture')),
    new MenuEntry('refresh_page', $r('app.string.refresh_page'), $r('sys.symbol.arrow_2_circlepath')),
    new MenuEntry('scan_qr', $r('app.string.scan_qr'), $r('sys.symbol.line_viewfinder')),
    new MenuEntry('site_settings', $r('app.string.site_settings'), $r('sys.symbol.electric_install')),
    new MenuEntry('ad_block', $r('app.string.ad_block'), $r('sys.symbol.nosign')),
    new MenuEntry('font_size', $r('app.string.font_size'), $r('sys.symbol.textformat_size_square')),
    new MenuEntry('clear_data', $r('app.string.clear_data'), $r('sys.symbol.trash')),
    new MenuEntry('print_pdf', $r('app.string.print_pdf'), $r('sys.symbol.printer')),
    new MenuEntry('read_aloud', $r('app.string.read_aloud'), $r('sys.symbol.speaker_wave_2')),
    new MenuEntry('add_to_home', $r('app.string.add_to_home'), $r('sys.symbol.plus_square')),
    new MenuEntry('customize_menu', $r('app.string.customize_menu'), $r('sys.symbol.square_grid_2x2')),
    new MenuEntry('read_mode', $r('app.string.read_mode'), $r('sys.symbol.doc_plaintext')),
    new MenuEntry('open_with', $r('app.string.open_with'), $r('sys.symbol.arrowshape_turn_up_right')),
    new MenuEntry('game_mode', $r('app.string.game_mode'), $r('sys.symbol.gamecontroller')),
    new MenuEntry('ai', $r('app.string.ai'), $r('sys.symbol.AI')),
    new MenuEntry('add_home_favorite', $r('app.string.add_home_favorite'), $r('sys.symbol.heart_badge_plus')),
    new MenuEntry('report_site', $r('app.string.report_site'), $r('sys.symbol.flag'))
  ]

  /** 默认菜单布局（从左到右、从上到下） */
  static readonly DEFAULT_MENU: string[] = [
    'bookmarks', 'history', 'downloads', 'incognito', 'share',
    'add_bookmark', 'mark_ad', 'desktop_mode', 'toolbox', 'settings',
    'offline_page', 'translate', 'view_source', 'inspect_element', 'fullscreen', 'resource_sniff',
    'browser_id', 'network_log', 'screen_orientation', 'night_mode', 'script', 'customize'
  ]

  static byId(id: string): MenuEntry | undefined {
    for (const e of MenuEntries.ALL) {
      if (e.id === id) {
        return e
      }
    }
    return undefined
  }

  private constructor() {
  }
}
