import { NaviContainer } from '../../../components/NaviContainer';
import { appSettings } from '../../../common/entity/SettingsModel';
import { SearchToolbarEngines, ToolbarEngineEntry } from '../../../common/constants/SearchEngines';
import { QhState } from '../../../entryability/AppState';

@Builder
export function SearchToolbarBuilder() {
  SearchToolbarPage()
}

@ComponentV2
struct SearchToolbarPage {
  @Local engines: ToolbarEngineEntry[] = []

  aboutToAppear(): void {
    this.engines = SearchToolbarEngines.list()
  }

  private toggleEngine(e: ToolbarEngineEntry): void {
    e.enabled = !e.enabled
    SearchToolbarEngines.save(this.engines)
  }

  build() {
    NaviContainer({
      title: $r('app.string.search_toolbar'),
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
    // List 全宽不设内边距（容器边距会裁剪拖动排序预览），卡片用 ListItem 外边距内缩
    List() {
      // 启用开关行
      ListItem() {
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.search_toolbar'))
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
            Text($r('app.string.search_toolbar_desc'))
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: appSettings.search_toolbar_enabled })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      }
      .width('calc(100% - 32vp)')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ left: 16, right: 16, top: 10 })
      .onClick(() => {
        appSettings.search_toolbar_enabled = !appSettings.search_toolbar_enabled
      })

      // 待显示引擎
      ListItem() {
        Column({ space: 2 }) {
          Text($r('app.string.search_toolbar_engines_title'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
          Text($r('app.string.search_toolbar_engines_hint'))
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 16, top: 16, bottom: 8 })
      }
      .width('calc(100% - 32vp)')
      .margin({ left: 16, right: 16 })
      .opacity(appSettings.search_toolbar_enabled ? 1 : 0.4)

      // 引擎列表（长按拖动排序）
      ForEach(this.engines, (e: ToolbarEngineEntry, idx: number) => {
        ListItem() {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.line_3_horizontal'))
              .fontSize(18)
              .fontColor([$r('sys.color.font_tertiary')])
            Text(e.name)
              .fontSize(15)
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Toggle({ type: ToggleType.Switch, isOn: e.enabled })
              .hitTestBehavior(HitTestMode.None)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .alignItems(VerticalAlign.Center)
        }
        .width('calc(100% - 32vp)')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ left: 16, right: 16, top: idx === 0 ? 0 : 12 })
        .opacity(appSettings.search_toolbar_enabled ? 1 : 0.4)
        .onClick(() => {
          if (!appSettings.search_toolbar_enabled) {
            return
          }
          this.toggleEngine(e)
        })
      }, (e: ToolbarEngineEntry) => e.id)
        .onMove((from: number, to: number) => {
          if (!appSettings.search_toolbar_enabled) {
            return
          }
          const moved = this.engines.splice(from, 1)[0]
          this.engines.splice(to, 0, moved)
          SearchToolbarEngines.save(this.engines)
        })
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
