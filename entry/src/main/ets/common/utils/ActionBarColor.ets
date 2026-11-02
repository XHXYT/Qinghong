import { UISettings } from '../entity/SettingsModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { HomeImmersive } from './HomeImmersive';
import { homeBg } from './HomeBg';

/**
 * 操作栏自适应色彩（色彩模式开启时取当前标签页 theme-color）
 */
export class ActionBarColor {

  /** 操作栏背景（未开启或未提取到页面色时返回 fallback） */
  static bg(fallback: ResourceColor): ResourceColor {
    const tab = tabsVM.activeTab
    if (!UISettings.action_bar_color_mode || tab === null || tab.themeColor === '') {
      return fallback
    }
    return tab.themeColor
  }

  /** 操作栏前景（主页沉浸时按主页背景明暗取黑/白；色彩模式开启时按页面色亮度；其余返回 fallback） */
  static fg(fallback: ResourceColor): ResourceColor {
    // 主页沉浸：栏透明浮于主页背景上，按主页背景明暗取黑/白保证可读
    if (HomeImmersive.active()) {
      return homeBg.dark ? Color.White : Color.Black
    }
    const tab = tabsVM.activeTab
    if (!UISettings.action_bar_color_mode || tab === null || tab.themeColor === '') {
      return fallback
    }
    return ActionBarColor.isDarkColor(tab.themeColor) ? Color.White : Color.Black
  }

  /** #RGB/#RRGGBB/#AARRGGBB 亮度判定（加权亮度低于阈值视为深色） */
  static isDarkColor(hex: string): boolean {
    let h: string = hex.trim()
    if (h.startsWith('#')) {
      h = h.substring(1)
    }
    if (h.length === 3) {
      let expanded: string = ''
      for (const c of h.split('')) {
        expanded += c + c
      }
      h = expanded
    }
    if (h.length === 8) {
      h = h.substring(2)
    }
    if (h.length !== 6) {
      return true
    }
    const r: number = parseInt(h.substring(0, 2), 16)
    const g: number = parseInt(h.substring(2, 4), 16)
    const b: number = parseInt(h.substring(4, 6), 16)
    if (Number.isNaN(r) || Number.isNaN(g) || Number.isNaN(b)) {
      return true
    }
    return (0.299 * r + 0.587 * g + 0.114 * b) < 140
  }
}
