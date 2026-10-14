import { NaviContainer } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { AdBlockSubscription, adBlockSubsStore } from '../../../../common/utils/AdBlockSubs';

/** 规则行懒加载数据源 */
class RuleLinesSource implements IDataSource {
  private lines: string[] = []

  setLines(lines: string[]): void {
    this.lines = lines
  }

  totalCount(): number {
    return this.lines.length
  }

  getData(index: number): string {
    return this.lines[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
  }
}

@Builder
export function SettingsAdblockSubPreviewBuilder() {
  AdblockSubPreviewPage()
}

@ComponentV2
struct AdblockSubPreviewPage {
  @Local title: string = ''
  @Local empty: boolean = false
  private source: RuleLinesSource = new RuleLinesSource()

  build() {
    NaviContainer({
      title: this.title,
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        const url: string = ctx.pathInfo.param as string
        for (const s of adBlockSubsStore.subs) {
          if (s.url === url) {
            this.load(s)
            return
          }
        }
        this.empty = true
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  private load(sub: AdBlockSubscription): void {
    this.title = sub.name
    const text: string = adBlockSubsStore.readRules(sub)
    const lines: string[] = []
    const raw: string[] = text.split('\n')
    for (const line of raw) {
      if (line.trim() !== '') {
        lines.push(line)
      }
    }
    this.empty = lines.length === 0
    this.source.setLines(lines)
  }

  @Builder
  pageContent() {
    if (this.empty) {
      Column() {
        Text($r('app.string.ad_block_sub_preview_empty'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .padding({ top: 64 })
      .alignItems(HorizontalAlign.Center)
    } else {
      List() {
        LazyForEach(this.source, (line: string) => {
          ListItem() {
            Text(line)
              .fontSize(13)
              .fontColor($r('sys.color.font_primary'))
              .width('100%')
              .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
        }, (line: string, index: number) => `${index}`)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentEndOffset(QhState.bottomRectHeight)
      .backgroundColor($r('app.color.background_color'))
    }
  }
}
