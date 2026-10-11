import { bundleManager } from '@kit.AbilityKit';
import { NaviContainer } from '../../components/NaviContainer';
import { _QhState } from '../../entryability/AppState';

@Builder
export function AboutBuilder() {
  AboutPage()
}

@ComponentV2
struct AboutPage {
  @Local versionName: string = '1.0.0'

  aboutToAppear(): void {
    this.loadVersion()
  }

  private loadVersion(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => {
        this.versionName = info.versionName
      })
      .catch(() => {
        this.versionName = _QhState.appVersion
      })
  }

  @Builder
  pageContent() {
    Column() {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.website'))
          .fontSize(64)
          .fontColor([$r('sys.color.icon_emphasize')])
        Text($r('app.string.app_name'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text(`v${this.versionName}`)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
        Text($r('app.string.about_desc'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32 })
      }
      .width('100%')
      .margin({ top: 80 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.about'),
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
}
