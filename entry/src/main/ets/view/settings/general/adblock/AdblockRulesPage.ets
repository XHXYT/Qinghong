import { NaviContainer, NaviBarButton } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { adBlockEngine } from '../../../../common/utils/adblock/AdBlockEngine';
import { toastUtil } from '../../../../common/utils/ui/ToastUtils';
import { tabsVM } from '../../../../viewmodel/TabsViewModel';

@Builder
export function SettingsAdblockRulesBuilder() {
  AdblockRulesPage()
}

@ComponentV2
struct AdblockRulesPage {

  @Local ruleText: string = ''

  aboutToAppear(): void {
    this.ruleText = adBlockEngine.loadCustomRulesSync()
  }

  private save(): void {
    adBlockEngine.saveCustomRules(this.ruleText).then((): void => {
      toastUtil.showToast({ message: $r('app.string.saved') })
    })
  }

  private showHelp(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.help'),
      message: $r('app.string.ad_block_rules_help'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.ad_block_rules_help_view'),
          action: (): void => {
            QhState.clearAllPages()
            tabsVM.newTab('https://adblockplus.org/filters')
          }
        },
        {
          value: $r('app.string.ad_block_rules_help_close'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'adblockRulesHelp')
  }

  build() {
    NaviContainer({
      title: $r('app.string.ad_block_custom_rules'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.questionmark_circle'),
          action: (): void => {
            this.showHelp()
          }
        }),
        new NaviBarButton({
          symbol: $r('sys.symbol.checkmark'),
          action: (): void => {
            this.save()
          }
        })
      ],
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
    Column() {
      Text($r('app.string.ad_block_rules_hint'))
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ bottom: 8 })
      TextArea({ text: this.ruleText, placeholder: '||example.com^' })
        .onChange((v: string): void => {
          this.ruleText = v
        })
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .padding(12)
        .fontSize(14)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: QhState.bottomRectHeight + 12 })
  }
}
