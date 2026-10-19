import { NaviContainer, NaviBarButton } from './NaviContainer';
import { CustomItemInfo } from '../common/entity/CusItemInfo';
import { CustomListItem } from './CusItemBuilder';

/**
 * 设置分组：组头标题 + 组内条目（分组卡片渲染用）
 */
export class SettingsSection {
  readonly key: string
  title: ResourceStr = ''
  items: CustomItemInfo[] = []
  /** 无标题时卡片顶部间距（默认：首组且无 header 时 10，否则 18） */
  topMargin?: number

  constructor(key: string, title: ResourceStr = '') {
    this.key = key
    this.title = title
  }
}

/**
 * 通用设置页脚手架：标准标题栏 + 分组卡片列表
 */
@ComponentV2
export struct SettingsScaffold {

  @Param title: ResourceStr | undefined = undefined
  @Param subTitle: ResourceStr = ''
  @Param buttons: NaviBarButton[] = []
  @Param sections: SettingsSection[] = []
  /** 外部持有的列表滚动器（需要 scrollToIndex 等能力时传入） */
  @Param scroller: Scroller = new Scroller()

  @BuilderParam header?: () => void
  @BuilderParam footer?: () => void

  @Event onReady: (ctx: NavDestinationContext) => void = (ctx: NavDestinationContext): void => {
  }
  @Event onShown: () => void = () => {
  }
  @Event onBackPressed: () => boolean = (): boolean => {
    return false
  }

  /** 分组默认顶部间距：首组且无 header 时 10，其余 18 */
  private sectionTopMargin(index: number): number {
    if (index === 0 && !this.header) {
      return 10
    }
    return 18
  }

  /** 卡片顶部间距：有标题时 0（标题负责间距），无标题时按配置/默认值 */
  private cardTopMargin(section: SettingsSection, index: number): number {
    if (section.title !== '') {
      return 0
    }
    if (section.topMargin !== undefined) {
      return section.topMargin
    }
    return this.sectionTopMargin(index)
  }

  build() {
    NaviContainer({
      title: this.title,
      subTitle: this.subTitle,
      buttons: this.buttons,
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.onReady(ctx)
      },
      onShown: (): void => {
        this.onShown()
      },
      onBackPressed: (): boolean => {
        return this.onBackPressed()
      }
    })
  }

  @Builder
  pageContent() {
    List({ scroller: this.scroller }) {
      if (this.header) {
        ListItem() {
          this.header()
        }
        .width('100%')
      }
      Repeat<SettingsSection>(this.sections)
        .each((ri: RepeatItem<SettingsSection>) => {
          ListItem() {
            Column() {
              if (ri.item.title !== '') {
                Text(ri.item.title)
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                  .margin({ left: 4, bottom: 6, top: this.sectionTopMargin(ri.index) })
              }
              Column() {
                Repeat<CustomItemInfo>(ri.item.items)
                  .each((ci: RepeatItem<CustomItemInfo>) => {
                    CustomListItem({
                      item: ci.item,
                      itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                    })
                  })
                  .key((item: CustomItemInfo) => item.id)
              }
              .width('100%')
              .borderRadius(16)
              .backgroundColor($r('app.color.background_color'))
              .clip(true)
              .margin({ top: this.cardTopMargin(ri.item, ri.index) })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        })
        .key((section: SettingsSection) => section.key)
      if (this.footer) {
        ListItem() {
          this.footer()
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(56)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }
}

/**
 * 自定义内容卡片：统一圆角/底色，内容由页面通过 builder 提供
 */
@ComponentV2
export struct SettingsCard {

  /** 卡片顶部间距 */
  @Param topMargin: Length = 0

  @BuilderParam content?: () => void

  build() {
    Column() {
      if (this.content) {
        Column() {
          this.content()
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.background_color'))
        .clip(true)
      }
    }
    .width('100%')
    .margin({ top: this.topMargin })
    .alignItems(HorizontalAlign.Start)
  }
}
