import { searchVM, SuggestItem, SuggestType } from '../../viewmodel/SearchViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';

/**
 * 搜索联想面板：按「搜索设置-搜索建议」来源渲染联想条目
 * （搜索历史/收藏/书签/标签页/历史浏览/引擎联想），点击直达/搜索/切换标签。
 * 由宿主决定挂载位置与展开方向（顶部地址栏向下、底部栏向上）
 */
@ComponentV2
export struct SearchSuggestPanel {
  /** 点击联想条目回调（宿主清空输入、收起焦点） */
  @Event onPick: () => void = () => {}
  /** 面板背景色（与宿主搜索框底色同步，默认应用背景色） */
  @Param panelBg: ResourceColor = $r('app.color.background_color')
  /** 毛玻璃背景（与搜索框模糊效果同步，开启时忽略 panelBg） */
  @Param panelBlur: boolean = false
  /** 毛玻璃底色不透明度（与搜索框底色不透明度同步，0-100） */
  @Param panelOpacity: number = 100
  /** 面板圆角（与搜索框圆角同步） */
  @Param panelRadius: number = 16
  /** 面板限高（键盘避让：搜索框底边到键盘顶边的可视空间） */
  @Param panelMaxHeight: number = 420

  private iconOf(type: SuggestType): Resource {
    if (type === SuggestType.BOOKMARK) {
      return $r('sys.symbol.bookmark')
    }
    if (type === SuggestType.HISTORY) {
      return $r('sys.symbol.clock')
    }
    if (type === SuggestType.TAB) {
      return $r('sys.symbol.square_stack_3d')
    }
    if (type === SuggestType.FAVORITES) {
      return $r('sys.symbol.star')
    }
    if (type === SuggestType.NETWORK_SUGGEST) {
      return $r('sys.symbol.lightbulb')
    }
    return $r('sys.symbol.magnifyingglass')
  }

  /** 联想条目点击：标签切换 / URL 直达 / 搜索词提交 */
  private pick(item: SuggestItem): void {
    searchVM.clear()
    this.onPick()
    if (item.type === SuggestType.TAB && item.tabId >= 0) {
      tabsVM.switchTab(item.tabId)
      return
    }
    if (item.url !== '') {
      browserVM.openUrl(item.url)
      return
    }
    browserVM.submitAddress(item.text)
  }

  build() {
    Stack() {
      // 毛玻璃底色层：与搜索框模糊效果/底色不透明度同步
      if (this.panelBlur) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .opacity(this.panelOpacity / 100)
          .backgroundBlurStyle(BlurStyle.Thin)
      }
      List() {
        Repeat<SuggestItem>(searchVM.suggestions)
          .each((ri: RepeatItem<SuggestItem>) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph(this.iconOf(ri.item.type))
                  .fontSize(17)
                  .fontColor([$r('sys.color.font_secondary')])
                Text(ri.item.text)
                  .fontSize(15)
                  .fontColor($r('sys.color.font_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (ri.item.url !== '') {
                  Text(ri.item.url)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: '40%' })
                }
              }
              .width('100%')
              .height(46)
              .padding({ left: 16, right: 16 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.pick(ri.item)
              })
            }
          })
          .key((item: SuggestItem) => `${item.type}|${item.text}|${item.url}`)
      }
      .width('100%')
      .constraintSize({ maxHeight: this.panelMaxHeight })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .backgroundColor(this.panelBlur ? Color.Transparent : this.panelBg)
    .borderRadius(this.panelRadius)
    .clip(true)
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.16)', offsetY: 4 })
  }
}
