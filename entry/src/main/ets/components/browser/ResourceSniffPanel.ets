import { QhState } from '../../entryability/AppState';
import { sniffVM, SniffResource, ResourceSniffViewModel } from '../../viewmodel/SniffViewModel';

/**
 * 资源嗅探半模态面板（Toolbar/MergedActionBar bindSheet 挂载）：
 * 筛选（全部/视频/音频/图片）+ 当前页媒体资源列表；
 * 点击下载、长按复制链接
 */
@ComponentV2
export struct ResourceSniffPanel {

  @Builder
  filterChip(f: string, label: ResourceStr) {
    Text(label)
      .fontSize(12)
      .fontColor(sniffVM.filter === f ? Color.White : $r('sys.color.font_secondary'))
      .padding({ left: 14, right: 14, top: 5, bottom: 5 })
      .borderRadius(14)
      .backgroundColor(sniffVM.filter === f
        ? QhState.currentThemeColor
        : $r('sys.color.comp_background_tertiary'))
      .onClick(() => {
        sniffVM.filter = f
      })
  }

  @Builder
  resourceItem(r: SniffResource) {
    Row() {
      Text(ResourceSniffViewModel.kindBadge(r.kind))
        .fontSize(9)
        .fontColor($r('sys.color.font_secondary'))
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .borderRadius(4)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .margin({ top: 2 })
      Column() {
        Text(r.fileName)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(r.host)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
      SymbolGlyph($r('sys.symbol.arrow_down_circle'))
        .fontSize(20)
        .fontColor([$r('sys.color.font_secondary')])
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => {
      sniffVM.download(r)
    })
    .gesture(LongPressGesture()
      .onAction(() => {
        sniffVM.copyLink(r)
      }))
  }

  build() {
    Column() {
      // 标题行
      Row() {
        Text($r('app.string.resource_sniff'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
        Text(` (${sniffVM.resources.length})`)
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
        Blank()
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
          .onClick(() => {
            sniffVM.showPanel = false
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })
      // 筛选 chips
      Row({ space: 8 }) {
        this.filterChip('all', $r('app.string.sniff_filter_all'))
        this.filterChip('video', $r('app.string.sniff_filter_video'))
        this.filterChip('audio', $r('app.string.sniff_filter_audio'))
        this.filterChip('image', $r('app.string.sniff_filter_image'))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ bottom: 4 })
      // 资源列表
      if (sniffVM.filtered().length === 0) {
        Column() {
          Text($r('app.string.sniff_empty'))
            .fontSize(14)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          Repeat<SniffResource>(sniffVM.filtered())
            .each((ri: RepeatItem<SniffResource>) => {
              ListItem() {
                this.resourceItem(ri.item)
              }
            })
            .key((r: SniffResource): string => r.url)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
