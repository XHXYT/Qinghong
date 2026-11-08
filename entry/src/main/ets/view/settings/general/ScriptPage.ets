import { CustomContentDialog } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { scriptVM } from '../../../viewmodel/ScriptViewModel';
import UserScriptInfo from '../../../common/entity/UserScriptInfo';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ui/ToastUtils';
import { ResourceUtils } from '../../../common/utils/app/ResourceUtil';

@Builder
export function ScriptPageBuilder() {
  ScriptPage()
}

@ComponentV2
struct ScriptPage {

  @Local downloadUrl: string = ''
  @Local enabledItem: CustomItemInfo = new CustomItemInfo({ id: 'script_enable', type: ItemActionType.TOGGLE })
  @Local debugItem: CustomItemInfo = new CustomItemInfo({ id: 'script_debug', type: ItemActionType.TOGGLE })

  private downloadDialog: CustomDialogController | undefined = undefined
  private updating: boolean = false

  aboutToAppear(): void {
    scriptVM.loadAll().then((): void => {
    })
    this.enabledItem.title = $r('app.string.script_enable')
    this.enabledItem.value = appSettings.userscript_enabled
    this.enabledItem.onChange = (v: string | boolean | number): void => {
      appSettings.userscript_enabled = v as boolean
      this.enabledItem.value = appSettings.userscript_enabled
    }
    this.debugItem.title = $r('app.string.script_debug')
    this.debugItem.subtitle = $r('app.string.script_debug_desc')
    this.debugItem.value = appSettings.userscript_debug
    this.debugItem.onChange = (v: string | boolean | number): void => {
      appSettings.userscript_debug = v as boolean
      this.debugItem.value = appSettings.userscript_debug
    }
    this.downloadDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.script_download'),
        contentBuilder: (): void => {
          this.downloadDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], false,
          (index: number): void => {
            if (index === 1) {
              this.confirmDownload()
            }
            this.downloadDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  private scriptItem(s: UserScriptInfo): CustomItemInfo {
    const menuItems: ContextMenuItem[] = [
      new ContextMenuItem($r('app.string.script_edit'), (): void => {
        QhState.pushPage('settings_script_edit', s.id === null ? '' : `${s.id}`)
      })
    ]
    // 有下载链接时提供复制链接
    if (s.updateUrl !== '') {
      menuItems.push(new ContextMenuItem($r('app.string.copy_link'), (): void => {
        const data: pasteboard.PasteData =
          pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, s.updateUrl)
        pasteboard.getSystemPasteboard().setData(data)
          .then((): void => {
            toastUtil.showToast({ message: $r('app.string.script_copied') })
          })
          .catch((): void => {
          })
      }))
    }
    menuItems.push(new ContextMenuItem($r('app.string.script_update_one'), (): void => {
      this.updateOne(s)
    }))
    menuItems.push(new ContextMenuItem($r('app.string.delete'), (): void => {
      this.confirmDelete(s)
    }, undefined, true))
    return new CustomItemInfo({
      id: `script_${s.id}`,
      title: s.name,
      subtitle: s.version,
      type: ItemActionType.TOGGLE,
      value: s.enabled,
      onChange: (v: string | boolean | number): void => {
        scriptVM.toggle(s, v as boolean)
      },
      contextMenuItems: menuItems,
      contextMenuPlacement: Placement.Right
    })
  }

  /** 下载脚本：输入链接 → 拉取安装 */
  private confirmDownload(): void {
    const url: string = this.downloadUrl.trim()
    if (url === '' || !url.startsWith('http')) {
      toastUtil.showToast({ message: $r('app.string.script_url_invalid') })
      return
    }
    scriptVM.downloadFromUrl(url).then((ok: boolean): void => {
      if (ok) {
        toastUtil.showToast({ message: $r('app.string.script_added') })
      } else {
        toastUtil.showToast({ message: $r('app.string.script_download_failed') })
      }
    })
  }

  /** 导入脚本：本地 .js/.txt 文件 */
  private importScript(): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const options: picker.DocumentSelectOptions = {
      maxSelectNumber: 1,
      fileSuffixFilters: ['.js', '.txt']
    }
    docPicker.select(options).then((uris: string[]): void => {
      if (uris.length === 0) {
        return
      }
      scriptVM.importFromUri(uris[0]).then((ok: boolean): void => {
        if (ok) {
          toastUtil.showToast({ message: $r('app.string.script_imported') })
        } else {
          toastUtil.showToast({ message: $r('app.string.script_import_failed') })
        }
      })
    })
  }

  /** 批量更新：重新下载所有带来源链接的脚本 */
  private updateAll(): void {
    if (this.updating) {
      return
    }
    if (!scriptVM.hasUpdatable()) {
      toastUtil.showToast({ message: $r('app.string.script_update_none') })
      return
    }
    this.updating = true
    scriptVM.updateAll().then((n: number): void => {
      this.updating = false
      if (n > 0) {
        toastUtil.showToast({
          message: ResourceUtils.getStringWithArgs($r('app.string.script_updated_n'), [n])
        })
      } else {
        toastUtil.showToast({ message: $r('app.string.script_update_failed') })
      }
    })
  }

  /** 单个脚本更新（右键菜单） */
  private updateOne(s: UserScriptInfo): void {
    if (s.updateUrl === '') {
      toastUtil.showToast({ message: $r('app.string.script_update_none') })
      return
    }
    scriptVM.downloadFromUrl(s.updateUrl).then((ok: boolean): void => {
      if (ok) {
        toastUtil.showToast({ message: $r('app.string.saved') })
      } else {
        toastUtil.showToast({ message: $r('app.string.script_update_failed') })
      }
    })
  }

  private confirmDelete(s: UserScriptInfo): void {
    toastUtil.showAlertDialog({
      title: s.name,
      message: $r('app.string.script_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            scriptVM.deleteScript(s)
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteScript')
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_script'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.plus'),
          menuItems: [
            new ContextMenuItem($r('app.string.script_add'), (): void => {
              QhState.pushPage('settings_script_code', '')
            }),
            new ContextMenuItem($r('app.string.script_download'), (): void => {
              this.downloadUrl = ''
              this.downloadDialog?.open()
            }),
            new ContextMenuItem($r('app.string.script_import'), (): void => {
              this.importScript()
            })
          ]
        }),
        new NaviBarButton({
          symbol: $r('sys.symbol.arrow_clockwise'),
          action: (): void => {
            this.updateAll()
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
      // 总开关：启用脚本
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

      // 调试开关：注入状态悬浮窗
      ListItem() {
        CustomListItem({
          item: this.debugItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 分组标签（对齐 Via「脚本」小字标签）
      ListItem() {
        Text($r('app.string.script_section'))
          .fontSize(13)
          .fontColor(QhState.currentThemeColor)
          .width('100%')
          .padding({ left: 16, top: 14, bottom: 4 })
      }
      .width('100%')

      // 脚本列表
      if (scriptVM.scripts.length > 0) {
        ForEach(scriptVM.scripts, (s: UserScriptInfo) => {
          ListItem() {
            CustomListItem({
              item: this.scriptItem(s),
              itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
          .borderRadius(16)
          .clip(true)
          .margin({ top: 12 })
        }, (s: UserScriptInfo) => `script_${s.id}_${s.enabled}_${s.name}_${s.version}`)
      } else {
        ListItem() {
          Text($r('app.string.script_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: 12 })
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

  /** 下载脚本输入对话框内容 */
  @Builder
  downloadDialogContent() {
    TextInput({ placeholder: $r('app.string.script_url_hint'), text: this.downloadUrl })
      .height(44)
      .fontSize(15)
      .type(InputType.URL)
      .onChange((v: string): void => {
        this.downloadUrl = v
      })
  }
}
