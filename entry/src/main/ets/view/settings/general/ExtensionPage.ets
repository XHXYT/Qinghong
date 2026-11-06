import { CustomContentDialog } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { extensionVM } from '../../../viewmodel/ExtensionViewModel';
import ExtensionInfo from '../../../common/entity/ExtensionInfo';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { appSettings } from '../../../common/entity/SettingsModel';
import { ExtensionEngine } from '../../../common/utils/ExtensionEngine';
import { tabsVM } from '../../../viewmodel/TabsViewModel';

@Builder
export function ExtensionPageBuilder() {
  ExtensionPage()
}

@ComponentV2
struct ExtensionPage {

  @Local installUrl: string = ''
  @Local enabledItem: CustomItemInfo = new CustomItemInfo({ id: 'extension_enable', type: ItemActionType.TOGGLE })

  private installDialog: CustomDialogController | undefined = undefined
  private working: boolean = false

  aboutToAppear(): void {
    extensionVM.loadAll().then((): void => {
    })
    this.enabledItem.title = $r('app.string.ext_master_enable')
    this.enabledItem.value = appSettings.extension_enabled
    this.enabledItem.onChange = (v: string | boolean | number): void => {
      appSettings.extension_enabled = v as boolean
      this.enabledItem.value = appSettings.extension_enabled
      if (!appSettings.extension_enabled) {
        // 收起已打开的 popup 半模态（仅切可见性，卸载由 bindSheet onDisappear 完成）
        extensionVM.requestPopupDismiss()
      }
    }
    this.installDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.ext_install_url'),
        contentBuilder: (): void => {
          this.installDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], false,
          (index: number): void => {
            if (index === 1) {
              this.confirmInstall()
            }
            this.installDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  /** 从链接安装：CRX/ZIP 直链、Chrome Web Store / Edge Add-ons 商店页 */
  private confirmInstall(): void {
    const url: string = this.installUrl.trim()
    if (url === '' || !url.startsWith('http')) {
      toastUtil.showToast({ message: $r('app.string.ext_url_invalid') })
      return
    }
    if (this.working) {
      return
    }
    this.working = true
    extensionVM.installFromUrl(url).then((ok: boolean): void => {
      this.working = false
      if (ok) {
        toastUtil.showToast({ message: $r('app.string.ext_added') })
      } else {
        toastUtil.showToast({ message: $r('app.string.ext_download_failed') })
      }
    })
  }

  /** 导入本地扩展（.crx / .zip） */
  private importExtension(): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const options: picker.DocumentSelectOptions = {
      maxSelectNumber: 1,
      fileSuffixFilters: ['.crx', '.zip']
    }
    docPicker.select(options).then((uris: string[]): void => {
      if (uris.length === 0) {
        return
      }
      if (this.working) {
        return
      }
      this.working = true
      extensionVM.importFromUri(uris[0]).then((ok: boolean): void => {
        this.working = false
        if (ok) {
          toastUtil.showToast({ message: $r('app.string.ext_imported') })
        } else {
          toastUtil.showToast({ message: $r('app.string.ext_import_failed') })
        }
      })
    })
  }

  private confirmDelete(e: ExtensionInfo): void {
    toastUtil.showAlertDialog({
      title: e.name,
      message: $r('app.string.ext_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            extensionVM.deleteExt(e)
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteExtension')
  }

  /** 商店入口卡片 */
  @Builder
  storeEntry(id: string, title: Resource, subtitle: string, symbol: Resource, url: string) {
    CustomListItem({
      item: new CustomItemInfo({
        id: id,
        symbol: symbol,
        title: title,
        subtitle: subtitle,
        type: ItemActionType.ROUTER,
        onChange: (v: string | boolean | number): void => {
          QhState.pageStack.clear()
          tabsVM.newTab(url, false)
        }
      }),
      itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
    })
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_extension'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.plus'),
          disabled: !appSettings.extension_enabled,
          menuItems: [
            new ContextMenuItem($r('app.string.ext_install_url'), (): void => {
              this.installUrl = ''
              this.installDialog?.open()
            }),
            new ContextMenuItem($r('app.string.ext_import'), (): void => {
              this.importExtension()
            })
          ]
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
      // 扩展总开关
      ListItem() {
        CustomListItem({
          item: this.enabledItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 说明（总开关关闭时置灰）
      ListItem() {
        Text($r('app.string.ext_compat_note'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 4 })
      }
      .width('100%')
      .opacity(appSettings.extension_enabled ? 1 : 0.38)

      // 获取扩展（商店入口，总开关关闭时置灰不可点）
      ListItem() {
        Column() {
          Text($r('app.string.ext_get_more'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ top: 14, bottom: 4 })
          Column() {
            this.storeEntry('store_cws', $r('app.string.ext_store_chrome'), 'chromewebstore.google.com',
              $r('sys.symbol.circle_circle_2'), ExtensionEngine.CWS_HOME)
            this.storeEntry('store_edge', $r('app.string.ext_store_edge'), 'microsoftedge.microsoft.com',
              $r('sys.symbol.nearby_devices'), ExtensionEngine.EDGE_ADDONS_HOME)
          }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
          .borderRadius(16)
          .clip(true)
        }
        .width('100%')
      }
      .width('100%')
      .margin({ top: 10 })
      .opacity(appSettings.extension_enabled ? 1 : 0.38)
      .enabled(appSettings.extension_enabled)

      // 已安装列表（总开关关闭时置灰）
      ListItem() {
        Text($r('app.string.ext_installed'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ top: 14, bottom: 4 })
      }
      .width('100%')
      .opacity(appSettings.extension_enabled ? 1 : 0.38)
      if (extensionVM.extensions.length > 0) {
        ForEach(extensionVM.extensions, (e: ExtensionInfo, index: number) => {
          ListItem() {
            Column() {
              Text(e.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
              if (e.description !== '') {
                Text(e.description)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              Row() {
                Text(`v${e.version} · MV${e.manifestVersion}`)
                  .fontSize(12)
                  .fontColor($r('sys.color.font_tertiary'))
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: e.enabled })
                  .onChange((v: boolean): void => {
                    extensionVM.toggle(e, v)
                  })
              }
              .width('100%')
              .margin({ top: 8 })
              Row({ space: 24 }) {
                Text($r('app.string.ext_detail'))
                  .fontSize(13)
                  .fontColor($r('sys.color.font_primary'))
                  .onClick(() => {
                    QhState.pushPage('settings_extension_detail', e.extId)
                  })
                Text($r('app.string.ext_remove'))
                  .fontSize(13)
                  .fontColor(Color.Red)
                  .onClick(() => {
                    this.confirmDelete(e)
                  })
              }
              .width('100%')
              .margin({ top: 10, bottom: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
          .borderRadius(16)
          .clip(true)
          // 首卡紧贴分组标题（标题自带 bottom padding 4，与「获取扩展」组一致），后续卡间隔 10
          .margin({ top: index === 0 ? 0 : 10 })
          // 总开关关闭时置灰不可点（含卡内开关/详情/删除）
          .opacity(appSettings.extension_enabled ? 1 : 0.38)
          .enabled(appSettings.extension_enabled)
        }, (e: ExtensionInfo) => `ext_${e.id}_${e.enabled}_${e.name}_${e.version}`)
      } else {
        ListItem() {
          Text($r('app.string.ext_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        // 紧贴分组标题（与「获取扩展」组一致）；总开关关闭时置灰
        .margin({ top: 0 })
        .opacity(appSettings.extension_enabled ? 1 : 0.38)
      }
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(QhState.bottomRectHeight)
    .padding({ left: 16, right: 16 })
  }

  /** 安装链接输入对话框内容 */
  @Builder
  installDialogContent() {
    TextInput({ placeholder: $r('app.string.ext_url_hint'), text: this.installUrl })
      .height(44)
      .fontSize(15)
      .type(InputType.URL)
      .onChange((v: string): void => {
        this.installUrl = v
      })
  }
}
