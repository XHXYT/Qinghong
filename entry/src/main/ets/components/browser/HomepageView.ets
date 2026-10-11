import { QhState } from '../../entryability/AppState';
import { TabInfo } from '../../viewmodel/TabsViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { appSettings } from '../../common/entity/SettingsModel';
import BookmarkInfo from '../../common/entity/BookmarkInfo';
import { HomepageQuickColumns, gridColumnsTemplate } from '../../common/utils/breakpoint/BreakPoint';
import { SearchEngines, UrlUtils } from '../../common/constants/SearchEngines';
import { toastUtil } from '../../common/utils/ToastUtils';

/**
 * 主页：Logo + 搜索框 + 快捷图标
 */
@ComponentV2
export struct HomepageView {
  @Require @Param tab: TabInfo

  aboutToAppear(): void {
    bookmarkVM.loadAll()
  }

  /**
   * 快捷图标长按：移除快捷（保留书签）
   */
  private confirmRemoveQuick(b: BookmarkInfo): void {
    toastUtil.showAlertDialog({
      title: b.title,
      message: b.url,
      buttons: [
        {
          value: $r('app.string.remove_quick'),
          action: (): void => {
            bookmarkVM.setQuick(b.url, false)
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'removeQuick')
  }

  @Builder
  quickGridItem(b: BookmarkInfo) {
    GridItem() {
      Column({ space: 6 }) {
        Text(b.title.length > 0 ? b.title.substring(0, 1) : '?')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(48)
          .height(48)
          .textAlign(TextAlign.Center)
          .borderRadius(24)
          .backgroundColor(QhState.currentThemeColor)
        Text(b.title)
          .fontSize(11)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('sys.color.font_primary'))
          .constraintSize({ maxWidth: '90%' })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 4, bottom: 4 })
    }
    .onClick(() => {
      browserVM.openUrl(b.url)
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.confirmRemoveQuick(b)
        })
    )
  }

  build() {
    Scroll() {
      Column({ space: 28 }) {
        // 无痕提示
        if (this.tab.isIncognito) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.eye_slash'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_secondary')])
            Text($r('app.string.incognito_hint'))
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
        }

        // Logo
        if (appSettings.show_homepage_logo) {
          Text($r('app.string.app_name'))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .margin({ top: 56 })
        } else {
          Blank().height(56)
        }

        // 搜索框
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([$r('sys.color.font_secondary')])
          Column({ space: 2 }) {
            Text($r('app.string.search_hint'))
              .fontSize(15)
              .fontColor($r('sys.color.font_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('86%')
        .height(46)
        .padding({ left: 16, right: 16 })
        .borderRadius(23)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          browserVM.isEditingAddress = true
        })

        // 快捷图标
        if (bookmarkVM.quickLinks.length > 0) {
          Grid() {
            ForEach(bookmarkVM.quickLinks, (b: BookmarkInfo) => {
              this.quickGridItem(b)
            }, (b: BookmarkInfo) => b.id !== null ? `${b.id}` : b.url)
          }
          .columnsTemplate(gridColumnsTemplate(HomepageQuickColumns(QhState.widthBp)))
          .columnsGap(12)
          .rowsGap(16)
          .width('90%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
