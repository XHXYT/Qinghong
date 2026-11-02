import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer } from '../../../components/NaviContainer';
import { syncVM } from '../../../viewmodel/SyncViewModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';

/**
 * 同步数据选择弹窗用的勾选行
 */
@ComponentV2
struct SyncCheckRow {
  @Require @Param label: ResourceStr
  @Param checked: boolean = false
  @Event onToggle: (v: boolean) => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      Checkbox()
        .size({ width: 24, height: 24 })
        .select(this.checked)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(48)
    .onClick(() => {
      this.onToggle(!this.checked)
    })
  }
}

/**
 * 设置分组：组头标题 + 组内条目（分组卡片渲染用）
 */
class SyncGroup {
  readonly key: string
  title: ResourceStr
  items: CustomItemInfo[] = []

  constructor(key: string, title: ResourceStr) {
    this.key = key
    this.title = title
  }
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

/** 从 baseUrl 中提取主机名用于展示 */
function hostOf(url: string): string {
  const stripped: string = url.trim().replace(/^https?:\/\//, '')
  const host: string = stripped.split('/')[0]
  return host
}

/** 规范化云端文件夹路径：补前导斜杠、去尾部斜杠 */
function normalizeFolderPath(p: string): string {
  let path: string = p.trim()
  if (path === '') {
    return ''
  }
  if (!path.startsWith('/')) {
    path = `/${path}`
  }
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1)
  }
  return path
}

@Builder
export function SyncSettingsBuilder() {
  SyncSettingsPage()
}

@ComponentV2
struct SyncSettingsPage {

  @Local groups: SyncGroup[] = []

  // WebDAV 配置半模态表单
  @Local showConfigSheet: boolean = false
  @Local cfgUrl: string = ''
  @Local cfgUser: string = ''
  @Local cfgPwd: string = ''
  @Local cfgAdvancedOpen: boolean = false
  @Local cfgFolderPath: string = ''
  @Local cfgDigest: boolean = false
  @Local testing: boolean = false
  @Local testOk: boolean = false
  @Local testResult: string = ''

  // 同步数据选择
  @Local dataSel: boolean[] = [true, true]

  private dataSelectDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    syncVM.loadConfig().then((): void => {
      this.dataSel = [syncVM.config.syncBookmarks, syncVM.config.syncSettings]
      this.buildItems()
    })
    this.initDialogs()
  }

  private textItem(id: string, title: ResourceStr, subtitle: ResourceStr | undefined, value: string,
    onClick: () => void): CustomItemInfo {
    return new CustomItemInfo({
      id: id,
      title: title,
      subtitle: subtitle,
      type: ItemActionType.TEXT,
      value: value,
      onChange: (v: string | boolean | number): void => {
        onClick()
      }
    })
  }

  private setItemValue(id: string, v: string): void {
    for (const group of this.groups) {
      for (const item of group.items) {
        if (item.id === id) {
          item.value = v
          return
        }
      }
    }
  }

  private buildItems(): void {
    const groups: SyncGroup[] = []

    const gAccount = new SyncGroup('account', $r('app.string.sync_group_account'))
    gAccount.items.push(this.textItem('webdav_config', $r('app.string.webdav_config'), undefined,
      this.configStatusText(), (): void => {
        this.openConfigSheet()
      }))
    gAccount.items.push(this.textItem('last_sync', $r('app.string.sync_last_time'), undefined,
      this.lastSyncText(), (): void => {
      }))
    groups.push(gAccount)

    const gOptions = new SyncGroup('options', $r('app.string.sync_group_options'))
    gOptions.items.push(new CustomItemInfo({
      id: 'auto_sync',
      title: $r('app.string.auto_sync'),
      subtitle: $r('app.string.auto_sync_desc'),
      type: ItemActionType.TOGGLE,
      value: syncVM.config.autoSync,
      onChange: (v: string | boolean | number): void => {
        syncVM.config.autoSync = v as boolean
        syncVM.saveConfig()
      }
    }))
    gOptions.items.push(this.textItem('sync_data', $r('app.string.sync_data_select'), undefined,
      this.syncDataSummary(), (): void => {
        this.dataSel = [syncVM.config.syncBookmarks, syncVM.config.syncSettings]
        this.dataSelectDialog?.open()
      }))
    groups.push(gOptions)

    const gManual = new SyncGroup('manual', $r('app.string.sync_group_manual'))
    gManual.items.push(this.textItem('sync_upload', $r('app.string.sync_upload'),
      $r('app.string.sync_upload_desc'), '', (): void => {
        this.confirmSync('upload')
      }))
    gManual.items.push(this.textItem('sync_download', $r('app.string.sync_download'),
      $r('app.string.sync_download_desc'), '', (): void => {
        this.confirmSync('download')
      }))
    gManual.items.push(this.textItem('sync_merge', $r('app.string.sync_merge'),
      $r('app.string.sync_merge_desc'), '', (): void => {
        this.confirmSync('merge')
      }))
    groups.push(gManual)

    this.groups = groups
  }

  private initDialogs(): void {
    this.dataSelectDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.sync_data_select'),
        contentBuilder: (): void => {
          this.syncDataContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], false,
          (index: number): void => {
            if (index === 1) {
              if (!this.dataSel[0] && !this.dataSel[1]) {
                toastUtil.showToast({ message: $r('app.string.sync_no_data_selected') })
              } else {
                syncVM.config.syncBookmarks = this.dataSel[0]
                syncVM.config.syncSettings = this.dataSel[1]
                syncVM.saveConfig()
                this.setItemValue('sync_data', this.syncDataSummary())
              }
            }
            this.dataSelectDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  // --- 状态文案 ---

  private configStatusText(): string {
    if (!syncVM.config.isConfigured()) {
      return ResourceUtils.getString($r('app.string.webdav_not_configured'))
    }
    return hostOf(syncVM.config.baseUrl)
  }

  private lastSyncText(): string {
    const t: number = syncVM.config.lastSyncTime
    if (!t) {
      return ResourceUtils.getString($r('app.string.sync_never'))
    }
    const d: Date = new Date(t)
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`
  }

  private syncDataSummary(): string {
    const parts: string[] = []
    if (syncVM.config.syncBookmarks) {
      parts.push(ResourceUtils.getString($r('app.string.sync_data_bookmarks')))
    }
    if (syncVM.config.syncSettings) {
      parts.push(ResourceUtils.getString($r('app.string.sync_data_settings')))
    }
    if (parts.length === 0) {
      return ResourceUtils.getString($r('app.string.sync_none'))
    }
    return parts.join('、')
  }

  // --- WebDAV 配置半模态 ---

  private openConfigSheet(): void {
    this.cfgUrl = syncVM.config.baseUrl
    this.cfgUser = syncVM.config.username
    this.cfgPwd = syncVM.config.password
    this.cfgAdvancedOpen = false
    this.cfgFolderPath = syncVM.config.folderPath
    this.cfgDigest = syncVM.config.useDigestAuth
    this.testResult = ''
    this.testOk = false
    this.showConfigSheet = true
  }

  private async doTestConnection(): Promise<void> {
    if (this.testing) {
      return
    }
    if (!this.cfgUrl.trim()) {
      this.testOk = false
      this.testResult = ResourceUtils.getString($r('app.string.webdav_url_required'))
      return
    }
    this.testing = true
    this.testResult = ''
    try {
      const result = await syncVM.testConnection(this.cfgUrl, this.cfgUser, this.cfgPwd, this.cfgDigest)
      this.testOk = result.success
      this.testResult = result.success
        ? ResourceUtils.getString($r('app.string.webdav_test_success'))
        : result.message
    } catch (e) {
      this.testOk = false
      this.testResult = e instanceof Error ? e.message : `${e}`
    }
    this.testing = false
  }

  private async doSaveConfig(): Promise<void> {
    if (!this.cfgUrl.trim()) {
      this.testOk = false
      this.testResult = ResourceUtils.getString($r('app.string.webdav_url_required'))
      return
    }
    syncVM.config.baseUrl = this.cfgUrl.trim()
    syncVM.config.username = this.cfgUser.trim()
    syncVM.config.password = this.cfgPwd
    syncVM.config.folderPath = normalizeFolderPath(this.cfgFolderPath)
    syncVM.config.useDigestAuth = this.cfgDigest
    await syncVM.saveConfig()
    this.setItemValue('webdav_config', this.configStatusText())
    this.showConfigSheet = false
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  // --- 手动同步 ---

  private confirmSync(mode: string): void {
    if (syncVM.isSyncing) {
      return
    }
    if (!syncVM.config.isConfigured()) {
      toastUtil.showToast({ message: $r('app.string.sync_not_configured') })
      return
    }
    if (!syncVM.config.syncBookmarks && !syncVM.config.syncSettings) {
      toastUtil.showToast({ message: $r('app.string.sync_no_data_selected') })
      return
    }
    if (mode === 'upload') {
      this.confirmUpload()
    } else if (mode === 'download') {
      this.confirmDownload()
    } else {
      this.confirmMerge()
    }
  }

  private confirmUpload(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.sync_upload'),
      message: $r('app.string.sync_confirm_upload'),
      buttons: [
        { value: $r('app.string.cancel'), action: (): void => {
        } },
        {
          value: $r('app.string.confirm'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            this.runSync('upload')
          }
        }
      ]
    }, 'syncConfirmUpload')
  }

  private confirmDownload(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.sync_download'),
      message: $r('app.string.sync_confirm_download'),
      buttons: [
        { value: $r('app.string.cancel'), action: (): void => {
        } },
        {
          value: $r('app.string.confirm'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            this.runSync('download')
          }
        }
      ]
    }, 'syncConfirmDownload')
  }

  private confirmMerge(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.sync_merge'),
      message: $r('app.string.sync_confirm_merge'),
      buttons: [
        { value: $r('app.string.cancel'), action: (): void => {
        } },
        {
          value: $r('app.string.confirm'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
            this.runSync('merge')
          }
        }
      ]
    }, 'syncConfirmMerge')
  }

  private async runSync(mode: string): Promise<void> {
    if (syncVM.isSyncing) {
      return
    }
    toastUtil.showToast({ message: $r('app.string.sync_in_progress') })
    try {
      if (mode === 'upload') {
        await syncVM.uploadOverwrite()
      } else if (mode === 'download') {
        await syncVM.downloadOverwrite()
      } else {
        await syncVM.mergeSync()
      }
      this.setItemValue('last_sync', this.lastSyncText())
      toastUtil.showToast({ message: $r('app.string.sync_success') })
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : `${e}`
      toastUtil.showToast({ message: msg })
    }
  }

  build() {
    NaviContainer({
      title: $r('app.string.settings_sync'),
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
      Repeat<SyncGroup>(this.groups)
        .each((ri: RepeatItem<SyncGroup>) => {
          ListItem() {
            Column() {
              Text(ri.item.title)
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
                .margin({ left: 4, bottom: 6, top: ri.index === 0 ? 10 : 18 })
              Column() {
                Repeat<CustomItemInfo>(ri.item.items)
                  .each((ci: RepeatItem<CustomItemInfo>) => {
                    CustomListItem({
                      item: ci.item,
                      itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                    })
                  })
                  .key((item: CustomItemInfo) => item.id)
              }
              .width('100%')
              .borderRadius(16)
              .backgroundColor($r('app.color.background_color'))
              .clip(true)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        })
        .key((group: SyncGroup) => group.key)
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(56)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
    .bindSheet(this.showConfigSheet!!, this.configSheetContent(), {
      preferType: SheetType.CENTER,
      height: 460,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showConfigSheet = false
      }
    })
  }

  @Builder
  configSheetContent() {
    Column() {
      Text($r('app.string.webdav_config'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ top: 8, bottom: 4 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 4 }) {
            Text($r('app.string.webdav_server_address'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            TextInput({ text: this.cfgUrl, placeholder: $r('app.string.webdav_server_placeholder') })
              .textAlign(TextAlign.Start)
              .onChange((v: string): void => {
                this.cfgUrl = v
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 4 }) {
            Text($r('app.string.webdav_account'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            TextInput({ text: this.cfgUser })
              .textAlign(TextAlign.Start)
              .onChange((v: string): void => {
                this.cfgUser = v
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 4 }) {
            Text($r('app.string.webdav_password_hint'))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            TextInput({ text: this.cfgPwd })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .textAlign(TextAlign.Start)
              .onChange((v: string): void => {
                this.cfgPwd = v
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          // 高级配置（可展开）
          Column({ space: 16 }) {
            Row() {
              Text($r('app.string.webdav_advanced'))
                .fontSize(15)
                .fontColor($r('sys.color.font_secondary'))
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([$r('sys.color.font_secondary')])
                .rotate({ angle: this.cfgAdvancedOpen ? 90 : 0 })
                .animation({ duration: 200, curve: Curve.Friction })
            }
            .width('100%')
            .height(40)
            .onClick(() => {
              this.cfgAdvancedOpen = !this.cfgAdvancedOpen
            })

            if (this.cfgAdvancedOpen) {
              Column({ space: 4 }) {
                Text($r('app.string.webdav_folder_path'))
                  .fontSize(14)
                  .fontColor($r('sys.color.font_secondary'))
                TextInput({ text: this.cfgFolderPath, placeholder: $r('app.string.webdav_folder_path_placeholder') })
                  .textAlign(TextAlign.Start)
                  .onChange((v: string): void => {
                    this.cfgFolderPath = v
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)

              Row() {
                Column({ space: 2 }) {
                  Text($r('app.string.webdav_digest_auth'))
                    .fontSize(15)
                    .fontColor($r('sys.color.font_primary'))
                  Text($r('app.string.webdav_digest_auth_desc'))
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.cfgDigest })
                  .hitTestBehavior(HitTestMode.None)
              }
              .width('100%')
              .onClick((): void => {
                this.cfgDigest = !this.cfgDigest
              })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.testResult !== '') {
            Text(this.testResult)
              .fontSize(14)
              .fontColor(this.testOk ? $r('sys.color.font_secondary') : Color.Red)
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)

      Row({ space: 12 }) {
        Button($r('app.string.webdav_test_connection'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .enabled(!this.testing && this.cfgUrl.trim() !== '')
          .layoutWeight(1)
          .onClick(() => {
            this.doTestConnection()
          })
        Button($r('app.string.webdav_save'))
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .enabled(this.cfgUrl.trim() !== '')
          .layoutWeight(1)
          .onClick(() => {
            this.doSaveConfig()
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  syncDataContent() {
    Column() {
      SyncCheckRow({ label: $r('app.string.sync_data_bookmarks'), checked: this.dataSel[0],
        onToggle: (v: boolean): void => {
          this.dataSel[0] = v
        } })
      SyncCheckRow({ label: $r('app.string.sync_data_settings'), checked: this.dataSel[1],
        onToggle: (v: boolean): void => {
          this.dataSel[1] = v
        } })
    }
    .width('100%')
  }
}
