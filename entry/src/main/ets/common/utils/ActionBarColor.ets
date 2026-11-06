import { UISettings } from '../entity/SettingsModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { HomeImmersive } from './HomeImmersive';
import { homeBg } from './HomeBg';

/**
 * 操作栏自适应色彩（色彩模式开启时取当前标签页 theme-color）
 */
export class ActionBarColor {

  /** 操作栏背景（未开启或未提取到页面色时返回 fallback；页面顶部为渐变时返回透明，由栏组容器的延续渐变接管；atTop=false 的底部位栏不跟随页面色） */
  static bg(fallback: ResourceColor, atTop: boolean = true): ResourceColor {
    const tab = tabsVM.activeTab
    if (!atTop || !UISettings.action_bar_color_mode || tab === null || tab.themeColor === '') {
      return fallback
    }
    if (tab.themeColor2 !== '') {
      return Color.Transparent
    }
    return tab.themeColor
  }

  /**
   * 页面顶部渐变的延续模拟（色彩模式且页面顶部为渐变时绘制，用于顶栏组容器）：
   * 下端衔接页面顶色向上渐变；其余情况返回全透明渐变（不产生可见绘制）
   */
  static gradient(): LinearGradient {
    const tab = tabsVM.activeTab
    if (!UISettings.action_bar_color_mode || tab === null || tab.themeColor === '' || tab.themeColor2 === '') {
      return { angle: 180, colors: [[Color.Transparent, 0], [Color.Transparent, 1]] }
    }
    return { angle: 180, colors: [[tab.themeColor2, 0], [tab.themeColor, 1]] }
  }

  /** 芯片底色：色彩模式按页面色明暗给半透明叠层（保证内容可读）；atTop=false 的底部位栏返回 fallback */
  static chipBg(fallback: ResourceColor, atTop: boolean = true): ResourceColor {
    const tab = tabsVM.activeTab
    if (!atTop || !UISettings.action_bar_color_mode || tab === null || tab.themeColor === '') {
      return fallback
    }
    return ActionBarColor.isDarkColor(tab.themeColor) ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.06)'
  }

  /** 操作栏前景（主页沉浸时按主页背景明暗取黑/白；色彩模式开启时按页面色亮度；atTop=false 的底部位栏不做页面色适配；其余返回 fallback） */
  static fg(fallback: ResourceColor, atTop: boolean = true): ResourceColor {
    // 主页沉浸：栏透明浮于主页背景上，按主页背景明暗取黑/白保证可读
    if (HomeImmersive.active()) {
      return homeBg.dark ? Color.White : Color.Black
    }
    const tab = tabsVM.activeTab
    if (!atTop || !UISettings.action_bar_color_mode || tab === null || tab.themeColor === '') {
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
