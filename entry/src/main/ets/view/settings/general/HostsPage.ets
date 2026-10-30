import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { appSettings } from '../../../common/entity/SettingsModel';
import { hostsVM, HostsViewModel } from '../../../viewmodel/HostsViewModel';
import HostsRuleInfo from '../../../common/entity/HostsRuleInfo';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { QhState } from '../../../entryability/AppState';

@Builder
export function HostsPageBuilder() {
  HostsPage()
}

@ComponentV2
struct HostsPage {

  @Local rules: HostsRuleInfo[] = []
  @Local inputHost: string = ''
  @Local inputIp: string = ''
  @Local importText: string = ''

  private editingHost: string = ''
  private addDialog: CustomDialogController | undefined = undefined
  private editDialog: CustomDialogController | undefined = undefined
  private importDialog: CustomDialogController | undefined = undefined
  private deleteDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.reload()
    this.addDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.hosts_add_title'),
        contentBuilder: (): void => {
          this.hostInputContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
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
        this.inputIp = ''
      }
    })
    this.editDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.hosts_edit_title'),
        contentBuilder: (): void => {
          this.hostInputContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doEdit()
            }
            this.editDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        for (const r of this.rules) {
          if (r.host === this.editingHost) {
            this.inputHost = r.host
            this.inputIp = r.ip
            return
          }
        }
        this.inputHost = ''
        this.inputIp = ''
      }
    })
    this.importDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.hosts_import_title'),
        contentBuilder: (): void => {
          this.importContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], false,
          (index: number): void => {
            if (index === 1) {
              this.doImport()
            }
            this.importDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.importText = ''
      }
    })
    this.deleteDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.hosts_delete_title'),
        contentBuilder: (): void => {
          this.deleteContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.delete')], true,
          (index: number): void => {
            if (index === 1) {
              this.doDelete()
            }
            this.deleteDialog?.close()
          }),
        contentAreaPadding: { top: 16, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  private reload(): void {
    hostsVM.listAll().then((list: HostsRuleInfo[]): void => {
      this.rules = list
    })
  }

  private doAdd(): void {
    const host: string = this.inputHost.trim().toLowerCase()
    const ip: string = this.inputIp.trim()
    if (!HostsViewModel.isValidHost(host) || !HostsViewModel.isValidIpList(ip)) {
      toastUtil.showToast({ message: $r('app.string.hosts_invalid') })
      return
    }
    hostsVM.addRule(host, ip).then((): void => {
      this.reload()
      toastUtil.showToast({ message: $r('app.string.saved') })
    })
  }

  private doEdit(): void {
    const host: string = this.inputHost.trim().toLowerCase()
    const ip: string = this.inputIp.trim()
    if (!HostsViewModel.isValidHost(host) || !HostsViewModel.isValidIpList(ip)) {
      toastUtil.showToast({ message: $r('app.string.hosts_invalid') })
      return
    }
    const old: string = this.editingHost
    hostsVM.setRule(host, ip).then((): void => {
      if (old !== '' && old !== host) {
        hostsVM.removeByHost(old).then((): void => {
          this.reload()
        })
        return
      }
      this.reload()
    })
  }

  private doDelete(): void {
    const host: string = this.editingHost
    hostsVM.removeByHost(host).then((): void => {
      this.reload()
    })
  }

  private doImport(): void {
    if (this.importText.trim() === '') {
      return
    }
    hostsVM.importRules(this.importText).then((count: number): void => {
      this.reload()
      toastUtil.showToast({
        message: ResourceUtils.getStringWithArgs($r('app.string.hosts_import_done'), [count])
      })
    })
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_hosts'),
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
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      if (this.rules.length > 0) {
        ForEach(this.rules, (r: HostsRuleInfo, idx: number) => {
          ListItem() {
            Column() {
              Divider()
                .color($r('sys.color.comp_divider'))
                .margin({ left: 16 })
                .visibility(idx === 0 ? Visibility.None : Visibility.Visible)
              Row() {
                Column({ space: 2 }) {
                  Text(r.host)
                    .fontSize(16)
                    .fontColor($r('sys.color.font_primary'))
                    .fontFamily(appSettings.font_family)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(r.ip)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .fontFamily(appSettings.font_family)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([$r('sys.color.icon_tertiary')])
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 16, right: 16, top: 11, bottom: 11 })
              .onClick(() => {
                this.editingHost = r.host
                this.editDialog?.open()
              })
              .bindContextMenu(this.ruleMenu(r), ResponseType.LongPress)
            }
            .width('100%')
          }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
          .borderRadius({
            topLeft: idx === 0 ? 16 : 0,
            topRight: idx === 0 ? 16 : 0,
            bottomLeft: idx === this.rules.length - 1 ? 16 : 0,
            bottomRight: idx === this.rules.length - 1 ? 16 : 0
          })
          .margin({ top: idx === 0 ? 10 : 0 })
          .swipeAction({
            end: {
              builder: (): void => {
                this.swipeEndBuilder(r)
              }
            }
          })
        }, (r: HostsRuleInfo) => `${r.id}_${r.host}_${r.ip}`)
      } else {
        ListItem() {
          Column() {
            Text($r('app.string.hosts_empty'))
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .fontFamily(appSettings.font_family)
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 18 })
          }
          .width('100%')
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .margin({ top: 10 })
      }

      // 批量导入入口
      ListItem() {
        Row() {
          Text($r('app.string.hosts_import_title'))
            .fontSize(16)
            .fontColor(QhState.currentThemeColor)
            .fontFamily(appSettings.font_family)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(() => {
          this.importDialog?.open()
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(QhState.bottomRectHeight)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  ruleMenu(r: HostsRuleInfo) {
    Menu() {
      MenuItem({ content: ResourceUtils.getString($r('app.string.edit')) })
        .onClick(() => {
          this.editingHost = r.host
          this.editDialog?.open()
        })
      MenuItem({ content: ResourceUtils.getString($r('app.string.delete')) })
        .onClick(() => {
          this.editingHost = r.host
          this.deleteDialog?.open()
        })
    }
  }

  @Builder
  swipeEndBuilder(r: HostsRuleInfo) {
    Row({ space: 8 }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(16)
          .fontColor([Color.White])
        Text($r('app.string.edit'))
          .fontSize(13)
          .fontColor(Color.White)
      }
      .width(68)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor(QhState.currentThemeColor)
      .onClick(() => {
        this.editingHost = r.host
        this.editDialog?.open()
      })

      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(16)
          .fontColor([Color.White])
        Text($r('app.string.delete'))
          .fontSize(13)
          .fontColor(Color.White)
      }
      .width(68)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor('#E84026')
      .onClick(() => {
        this.editingHost = r.host
        this.deleteDialog?.open()
      })
    }
    .height(72)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  hostInputContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: $r('app.string.hosts_host_hint'), text: this.inputHost })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.inputHost = v
        })
      TextInput({ placeholder: $r('app.string.hosts_ip_hint'), text: this.inputIp })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.inputIp = v
        })
    }
    .width('100%')
  }

  @Builder
  importContent() {
    Column({ space: 12 }) {
      Text($r('app.string.hosts_import_hint'))
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
      TextArea({ placeholder: $r('app.string.hosts_import_hint'), text: this.importText })
        .height(160)
        .fontSize(14)
        .onChange((v: string) => {
          this.importText = v
        })
    }
    .width('100%')
  }

  @Builder
  deleteContent() {
    Column() {
      Text(this.editingHost)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
    }
    .width('100%')
  }
}
