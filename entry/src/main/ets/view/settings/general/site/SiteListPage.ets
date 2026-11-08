import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer, NaviBarButton } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../../common/utils/ui/ToastUtils';
import { siteSettingsVM } from '../../../../viewmodel/SiteSettingsViewModel';

@Builder
export function SettingsSiteListBuilder() {
  SiteListPage()
}

@ComponentV2
struct SiteListPage {

  @Local sites: string[] = []
  @Local inputSite: string = ''

  private addDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.addDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.site_add_site'),
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
        this.inputSite = ''
      }
    })
  }

  build() {
    NaviContainer({
      title: $r('app.string.site_all_sites'),
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

  private doAdd(): void {
    const site: string = this.inputSite.trim().toLowerCase()
    if (site === '' || site.startsWith('http://') || site.startsWith('https://')) {
      toastUtil.showToast({ message: $r('app.string.site_site_invalid') })
      return
    }
    for (const s of this.sites) {
      if (s === site) {
        toastUtil.showToast({ message: $r('app.string.site_site_exists') })
        return
      }
    }
    siteSettingsVM.addSite(site).then((): void => {
      this.load()
      QhState.pushPage('settings_site_detail', site)
    })
  }

  private load(): void {
    siteSettingsVM.listSites().then((sites: string[]): void => {
      this.sites = sites
    })
  }

  private siteItem(site: string): CustomItemInfo {
    return new CustomItemInfo({
      id: site,
      title: site,
      type: ItemActionType.TEXT,
      contextMenuItems: [
        new ContextMenuItem($r('app.string.delete'), (): void => {
          this.confirmDelete(site)
        }, undefined, true)
      ],
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('settings_site_detail', site)
      }
    })
  }

  private confirmDelete(site: string): void {
    toastUtil.showAlertDialog({
      title: site,
      message: $r('app.string.site_delete_site_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            siteSettingsVM.removeSite(site).then((): void => {
              this.load()
            })
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteSite')
  }

  @Builder
  pageContent() {
    List() {
      if (this.sites.length > 0) {
        Repeat<string>(this.sites)
          .each((ri: RepeatItem<string>) => {
            ListItem() {
              CustomListItem({
                item: this.siteItem(ri.item),
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
          .key((site: string) => site)
      } else {
        ListItem() {
          Text($r('app.string.site_all_sites_empty'))
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
    TextInput({ placeholder: $r('app.string.site_site_hint'), text: this.inputSite })
      .height(44)
      .fontSize(15)
      .onChange((v: string): void => {
        this.inputSite = v
      })
  }

  @Builder
  swipeEndBuilder(site: string) {
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
      this.confirmDelete(site)
    })
  }
}
