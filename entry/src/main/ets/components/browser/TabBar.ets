import { tabsVM, TabInfo } from '../../viewmodel/TabsViewModel';
import { HomeImmersive } from '../../common/utils/home/HomeImmersive';
import { homeBg } from '../../common/utils/home/HomeBg';
import { ActionBarColor } from '../../common/utils/ui/ActionBarColor';
import { UISettings } from '../../common/entity/SettingsModel';
import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import { faviconCache, FaviconCache } from '../../viewmodel/FaviconCache';
import { EXT_SCHEME_PREFIX } from '../../common/utils/extension/ExtensionResources';

/**
 * 标签栏：横向标签条（工具栏在上时紧随操作栏下一行，工具栏在下时置顶）
 */
@ComponentV2
export struct TabBar {

  /** 芯片底色：主页沉浸暗背景用浅色半透明（白字可读），色彩模式按页面色明暗叠层，其余用通用底 */
  private chipBg(selected: boolean): ResourceColor {
    if (!selected) {
      return Color.Transparent
    }
    if (HomeImmersive.active() && homeBg.dark) {
      return 'rgba(255,255,255,0.18)'
    }
    return ActionBarColor.chipBg($r('sys.color.comp_background_tertiary'), UISettings.app_layout === 'top')
  }

  /** 扩展页图标沙箱路径：标签 URL 为扩展 scheme 页时返回对应扩展图标路径，否则 '' */
  private extIconOf(url: string): string {
    if (!url.startsWith(EXT_SCHEME_PREFIX)) {
      return ''
    }
    const rest: string = url.substring(EXT_SCHEME_PREFIX.length)
    const slash: number = rest.indexOf('/')
    const extId: string = slash < 0 ? rest : rest.substring(0, slash)
    for (const ext of extensionVM.extensions) {
      if (ext.extId === extId) {
        return extensionVM.iconPathOf(ext)
      }
    }
    return ''
  }

  /** 标签前置图标：扩展页=扩展图标，主页=house，网页=favicon（书签栏同款缓存），无图标=锁盾 */
  @Builder
  tabLeadingIcon(tab: TabInfo) {
    if (this.extIconOf(tab.url) !== '') {
      Image(`file://${this.extIconOf(tab.url)}`)
        .size({ width: 14, height: 14 })
        .borderRadius(3)
        .objectFit(ImageFit.Cover)
    } else if (tab.isHome) {
      SymbolGlyph($r('sys.symbol.house'))
        .fontSize(14)
        .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
    } else if (faviconCache.has(FaviconCache.hostOf(tab.url))) {
      Image(`file://${faviconCache.pathOf(FaviconCache.hostOf(tab.url))}`)
        .size({ width: 14, height: 14 })
        .objectFit(ImageFit.Cover)
    } else {
      SymbolGlyph($r('sys.symbol.lock_shield'))
        .fontSize(14)
        .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
    }
  }

  @Builder
  tabChip(tab: TabInfo) {
    Row({ space: 5 }) {
      this.tabLeadingIcon(tab)
      Text(tab.title)
        .fontSize(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 140 })
        .fontColor(ActionBarColor.fg($r('sys.color.font_primary'), UISettings.app_layout === 'top'))
      // 播放角标：播放中显示小喇叭，点击切换静音/恢复
      if (tab.audioPlaying) {
        SymbolGlyph(tab.audioMuted ? $r('sys.symbol.speaker_slash') : $r('sys.symbol.speaker_wave_2'))
          .fontSize(11)
          .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
          .onClick(() => {
            tabsVM.toggleTabMute(tab)
          })
      }
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(11)
        .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
        .onClick(() => {
          tabsVM.closeTab(tab.id)
        })
    }
    .height(26)
    .padding({ left: 10, right: 7 })
    .borderRadius(13)
    .backgroundColor(this.chipBg(tabsVM.activeTabId === tab.id))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (tabsVM.hasTab(tab.id)) {
        tabsVM.switchTab(tab.id)
      }
    })
  }

  build() {
    Scroll() {
      Row({ space: 6 }) {
        Repeat<TabInfo>(tabsVM.tabs)
          .each((ri: RepeatItem<TabInfo>) => {
            this.tabChip(ri.item)
          })
          .key((tab: TabInfo) => tab.id.toString())

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(15)
          .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), UISettings.app_layout === 'top')])
          .onClick(() => {
            tabsVM.newTab('')
          })
      }
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(27)
    .align(Alignment.Start)
    // 主页沉浸时背景透明透出全屏主页背景层；色彩模式随操作栏自适应（渐变时透明由栏组渐变接管）
    .backgroundColor(HomeImmersive.active() ? Color.Transparent
      : ActionBarColor.bg($r('sys.color.comp_background_primary'), UISettings.app_layout === 'top'))
  }
}
