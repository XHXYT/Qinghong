import { appSettings } from './SettingsModel';

/**
 * 底部工具栏事件（5 个按钮长按 + 工具栏左滑/右滑）可绑定的动作条目
 */
export class ToolbarAction {
  id: string = ''
  label: ResourceStr = ''

  constructor(id: string, label: ResourceStr) {
    this.id = id
    this.label = label
  }
}

/**
 * 行为分组（选择行为页的展示结构）
 */
export class ToolbarActionGroup {
  id: string = ''
  title: ResourceStr = ''
  actions: ToolbarAction[] = []

  constructor(id: string, title: ResourceStr, actions: ToolbarAction[]) {
    this.id = id
    this.title = title
    this.actions = actions
  }
}

/**
 * 全量行为目录（顺序即显示顺序）
 */
export function toolbarActionGroups(): ToolbarActionGroup[] {
  return [
    new ToolbarActionGroup('tab', $r('app.string.group_tab_actions'), [
      new ToolbarAction('none', $r('app.string.action_none')),
      new ToolbarAction('new_tab', $r('app.string.new_tab')),
      new ToolbarAction('prev_tab', $r('app.string.previous_tab')),
      new ToolbarAction('next_tab', $r('app.string.next_tab')),
      new ToolbarAction('go_back', $r('app.string.web_back')),
      new ToolbarAction('go_forward', $r('app.string.web_forward')),
      new ToolbarAction('close_tab', $r('app.string.close_tab')),
      new ToolbarAction('close_all_tabs', $r('app.string.close_all_tabs')),
      new ToolbarAction('duplicate_tab', $r('app.string.duplicate_tab'))
    ]),
    new ToolbarActionGroup('feature', $r('app.string.group_feature_actions'), [
      new ToolbarAction('bookmarks', $r('app.string.open_bookmarks')),
      new ToolbarAction('bookmark_dialog', $r('app.string.bookmark_dialog')),
      new ToolbarAction('history', $r('app.string.open_history')),
      new ToolbarAction('downloads', $r('app.string.open_downloads')),
      new ToolbarAction('settings', $r('app.string.open_settings')),
      new ToolbarAction('find_in_page', $r('app.string.find_in_page')),
      new ToolbarAction('translate', $r('app.string.translate')),
      new ToolbarAction('read_aloud', $r('app.string.read_aloud')),
      new ToolbarAction('read_mode', $r('app.string.read_mode')),
      new ToolbarAction('ai_panel', $r('app.string.open_ai_panel'))
    ]),
    new ToolbarActionGroup('address', $r('app.string.group_address_actions'), [
      new ToolbarAction('enter_url', $r('app.string.enter_url'))
    ]),
    new ToolbarActionGroup('web', $r('app.string.group_web_actions'), [
      new ToolbarAction('save_page', $r('app.string.save_page')),
      new ToolbarAction('refresh', $r('app.string.refresh_page')),
      new ToolbarAction('view_source', $r('app.string.view_source')),
      new ToolbarAction('add_bookmark', $r('app.string.add_bookmark')),
      new ToolbarAction('page_down', $r('app.string.page_down')),
      new ToolbarAction('page_up', $r('app.string.page_up')),
      new ToolbarAction('scroll_top', $r('app.string.scroll_top')),
      new ToolbarAction('scroll_bottom', $r('app.string.scroll_bottom'))
    ])
  ]
}

/**
 * 按动作 id 查找目录条目
 */
export function findToolbarAction(id: string): ToolbarAction | undefined {
  for (const g of toolbarActionGroups()) {
    for (const a of g.actions) {
      if (a.id === id) {
        return a
      }
    }
  }
  return undefined
}

/** 底部工具栏全部事件 id（5 按钮长按 + 左滑/右滑） */
export const TOOLBAR_EVENT_IDS: string[] =
  ['back_long', 'forward_long', 'home_long', 'tabs_long', 'menu_long', 'swipe_left', 'swipe_right']

/**
 * 事件说明文案（选择行为页标题后缀用，如「选择行为 - 左箭头长按」）
 */
export function toolbarEventLabel(eventId: string): ResourceStr {
  if (eventId === 'back_long') {
    return $r('app.string.event_back_long')
  }
  if (eventId === 'forward_long') {
    return $r('app.string.event_forward_long')
  }
  if (eventId === 'home_long') {
    return $r('app.string.event_home_long')
  }
  if (eventId === 'tabs_long') {
    return $r('app.string.event_tabs_long')
  }
  if (eventId === 'menu_long') {
    return $r('app.string.event_menu_long')
  }
  if (eventId === 'swipe_left') {
    return $r('app.string.event_swipe_left')
  }
  if (eventId === 'swipe_right') {
    return $r('app.string.event_swipe_right')
  }
  return ''
}

/** 各事件默认绑定动作 */
const DEFAULT_EVENT_ACTIONS: Record<string, string> = {
  'back_long': 'downloads',
  'forward_long': 'history',
  'home_long': 'refresh',
  'tabs_long': 'add_bookmark',
  'menu_long': 'find_in_page',
  'swipe_left': 'next_tab',
  'swipe_right': 'prev_tab'
}

/**
 * 读取事件当前绑定的动作 id（未存储时取默认绑定）
 */
export function getToolbarEventAction(eventId: string): string {
  const raw: string = appSettings.toolbar_events
  if (raw !== '') {
    for (const part of raw.split(',')) {
      const idx: number = part.indexOf(':')
      if (idx > 0 && part.substring(0, idx) === eventId) {
        return part.substring(idx + 1)
      }
    }
  }
  const def: string | undefined = DEFAULT_EVENT_ACTIONS[eventId]
  return def === undefined ? 'none' : def
}

/**
 * 写入事件绑定（全量持久化，保留显式「无操作」）
 */
export function setToolbarEventAction(eventId: string, actionId: string): void {
  const parts: string[] = []
  for (const id of TOOLBAR_EVENT_IDS) {
    const action: string = id === eventId ? actionId : getToolbarEventAction(id)
    parts.push(`${id}:${action}`)
  }
  appSettings.toolbar_events = parts.join(',')
}
