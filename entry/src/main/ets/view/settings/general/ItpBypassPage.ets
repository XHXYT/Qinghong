import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ui/ToastUtils';
import { ResourceUtils } from '../../../common/utils/app/ResourceUtil';
import { appSettings } from '../../../common/entity/SettingsModel';
import { ItpBypassUtils } from '../../../common/utils/security/ItpBypassUtils';

@Builder
export function ItpBypassBuilder() {
  ItpBypassPage()
}

@ComponentV2
struct ItpBypassPage {

  @Local inputHost: string = ''

  private addDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.addDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.itp_bypass_add'),
        contentBuilder: (): void => {
          this.addDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.add')], false,
          (index: number): void => {
            if (index === 1) {
              this.doAdd()
            }
            this.addDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.inputHost = ''
      }
    })
  }

  private doAdd(): void {
    const ok: boolean = ItpBypassUtils.addHost(this.inputHost)
    if (!ok) {
      toastUtil.showToast({ message: $r('app.string.itp_bypass_invalid') })
      return
    }
    toastUtil.showToast({ message: $r('app.string.privacy_report_bypass_done') })
  }

  private hostItem(host: string): CustomItemInfo {
    return new CustomItemInfo({
      id: host,
      title: host,
      type: ItemActionType.TEXT,
      contextMenuItems: [
        new ContextMenuItem($r('app.string.delete'), (): void => {
          this.confirmDelete(host)
        }, undefined, true)
      ],
      onChange: (v: string | boolean | number): void => {
      }
    })
  }

  private confirmDelete(host: string): void {
    toastUtil.showAlertDialog({
      title: host,
      message: ResourceUtils.getStringWithArgs($r('app.string.itp_bypass_remove_confirm'), [host]),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            ItpBypassUtils.removeHost(host)
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteItpBypassHost')
  }

  build() {
    NaviContainer({
      title: $r('app.string.itp_bypass_title'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.plus'),
          action: (): void => {
            this.addDialog?.open()
          }
        })
      ],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onShown: (): void => {
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      if (appSettings.itp_bypass_hosts.length > 0) {
        Repeat<string>(appSettings.itp_bypass_hosts)
          .each((ri: RepeatItem<string>) => {
            ListItem() {
              CustomListItem({
                item: this.hostItem(ri.item),
                itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.background_color'))
            .borderRadius(16)
            .clip(true)
            .margin({ top: ri.index === 0 ? 10 : 12 })
            .swipeAction({
              end: {
                builder: (): void => {
                  this.swipeEndBuilder(ri.item)
                }
              }
            })
          })
          .key((host: string) => host)
      } else {
        ListItem() {
          Text($r('app.string.itp_bypass_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: 10 })
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
  addDialogContent() {
    TextInput({ placeholder: $r('app.string.itp_bypass_add_hint'), text: this.inputHost })
      .height(44)
      .fontSize(15)
      .onChange((v: string): void => {
        this.inputHost = v
      })
  }

  @Builder
  swipeEndBuilder(host: string) {
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
      this.confirmDelete(host)
    })
  }
}
