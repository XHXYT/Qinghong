import { webview } from '@kit.ArkWeb';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';

@Builder
export function WebsiteDataBuilder() {
  WebsiteDataPage()
}

/** 字节数格式化（B/KB/MB/GB） */
function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  }
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`
}

@ComponentV2
struct WebsiteDataPage {

  @Local origins: webview.WebStorageOrigin[] = []
  @Local totalUsage: number = 0

  private load(): void {
    webview.WebStorage.getOrigins()
      .then((list: webview.WebStorageOrigin[]): void => {
        const sorted = list.slice().sort((a: webview.WebStorageOrigin, b: webview.WebStorageOrigin): number => {
          return b.usage - a.usage
        })
        this.origins = sorted
        let total: number = 0
        for (const o of sorted) {
          total += o.usage
        }
        this.totalUsage = total
      })
      .catch((e: BusinessError): void => {
        // Web 引擎未初始化（从未创建 Web 组件）等场景：按空列表处理
        console.error(`[WebsiteData] 读取网站数据失败: ${e}`)
        this.origins = []
        this.totalUsage = 0
      })
  }

  private removeOrigin(origin: string): void {
    try {
      webview.WebStorage.deleteOrigin(origin)
    } catch (e) {
      console.error(`[WebsiteData] 删除网站数据失败: ${e}`)
    }
    this.load()
  }

  private confirmClearAll(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.website_data_clear_title'),
      message: $r('app.string.website_data_clear_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            try {
              webview.WebStorage.deleteAllData()
            } catch (e) {
              console.error(`[WebsiteData] 清除全部网站数据失败: ${e}`)
            }
            this.load()
            toastUtil.showToast({ message: $r('app.string.website_data_cleared') })
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'clearWebsiteData')
  }

  build() {
    NaviContainer({
      title: $r('app.string.website_data'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.trash'),
          action: (): void => {
            this.confirmClearAll()
          }
        })
      ],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.load()
      },
      onShown: (): void => {
        this.load()
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List({ space: 12 }) {
      // 汇总卡片
      ListItem() {
        Column({ space: 4 }) {
          Text(ResourceUtils.getStringWithArgs($r('app.string.website_data_summary'),
            [formatBytes(this.totalUsage), `${this.origins.length}`]))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          Text($r('app.string.website_data_desc'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(2)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)

      if (this.origins.length > 0) {
        Repeat<webview.WebStorageOrigin>(this.origins)
          .each((ri: RepeatItem<webview.WebStorageOrigin>) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 3 }) {
                  Text(ri.item.origin)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(formatBytes(ri.item.usage))
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 16, right: 16, top: 13, bottom: 13 })
            }
            .width('100%')
            .backgroundColor($r('app.color.background_color'))
            .borderRadius(16)
            .clip(true)
            .swipeAction({
              end: {
                builder: (): void => {
                  this.swipeEndBuilder(ri.item.origin)
                }
              }
            })
          })
          .key((o: webview.WebStorageOrigin) => o.origin)
      } else {
        ListItem() {
          Column({ space: 6 }) {
            Text($r('app.string.website_data_empty'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.website_data_empty_hint'))
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 20, bottom: 20 })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  swipeEndBuilder(origin: string) {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(16)
        .fontColor([Color.White])
      Text($r('app.string.delete'))
        .fontSize(13)
        .fontColor(Color.White)
    }
    .width(68)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor('#E84026')
    .onClick(() => {
      this.removeOrigin(origin)
    })
  }
}
