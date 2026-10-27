import { appSettings } from '../entity/SettingsModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';

/**
 * 主页沉浸态：活动标签为定制主页（原生或 HTML 渲染）时，
 * 主页背景/网页全屏铺底，延伸至状态栏与底部操作栏、小白条避让区域（各操作栏随之透明化）
 */
export class HomeImmersive {
  static active(): boolean {
    const tab = tabsVM.activeTab
    return tab !== null && tab.isHome
      && appSettings.home_page_mode === 'default'
  }
}
