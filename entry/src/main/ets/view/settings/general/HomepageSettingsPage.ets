import { NaviContainer } from '../../../components/NaviContainer';
import { appSettings } from '../../../common/entity/SettingsModel';
import { bookmarkVM } from '../../../viewmodel/BookmarkViewModel';
import BookmarkInfo from '../../../common/entity/BookmarkInfo';
import { toastUtil } from '../../../common/utils/ToastUtils';

@Builder
export function HomepageSettingsBuilder() {
  HomepageSettingsPage()
}

@ComponentV2
struct HomepageSettingsPage {

  build() {
    NaviContainer({
      title: $r('app.string.homepage_settings'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    Scroll() {
      Column() {
        // 显示主页 Logo
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.show_homepage_logo'))
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
            Text($r('app.string.show_homepage_logo_desc'))
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: appSettings.show_homepage_logo })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .borderRadius(16)
        .backgroundColor($r('app.color.background_color'))
        .margin({ left: 16, right: 16, top: 10 })
        .onClick(() => {
          appSettings.show_homepage_logo = !appSettings.show_homepage_logo
        })

        // 快捷图标
        Row() {
          Text($r('app.string.quick_links'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding({ left: 28, right: 16, top: 16, bottom: 8 })

        if (bookmarkVM.quickLinks.length === 0) {
          Column() {
            Text($r('app.string.empty_quick_links'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding(24)
          .borderRadius(16)
          .backgroundColor($r('app.color.background_color'))
          .margin({ left: 16, right: 16 })
        } else {
          Column() {
            ForEach(bookmarkVM.quickLinks, (b: BookmarkInfo, bi: number) => {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.website'))
                  .fontSize(22)
                  .fontColor([$r('sys.color.font_secondary')])
                Column({ space: 2 }) {
                  Text(b.title)
                    .fontSize(15)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontColor($r('sys.color.font_primary'))
                  Text(b.url)
                    .fontSize(12)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontColor($r('sys.color.font_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button($r('app.string.remove'))
                  .fontSize(13)
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .fontColor(Color.Red)
                  .onClick(() => {
                    bookmarkVM.setQuick(b.url, false)
                    toastUtil.showToast({ message: $r('app.string.removed') })
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              if (bi < bookmarkVM.quickLinks.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color($r('sys.color.comp_divider'))
                  .margin({ left: 50, right: 16 })
              }
            }, (b: BookmarkInfo) => `${b.id}_${b.isQuick}`)
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor($r('app.color.background_color'))
          .clip(true)
          .margin({ left: 16, right: 16 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor($r('app.color.background_color_accent'))
  }
}
