import { CustomContentDialog } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { NaviContainer, NaviBarButton } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { adBlockEngine } from '../../../../common/utils/AdBlockEngine';
import { AdBlockSubscription, AdBlockSubsStore, adBlockSubsStore } from '../../../../common/utils/AdBlockSubs';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../../components/CusItemBuilder';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../../components/SheetPicker';
import { buildDialogButtons } from '../../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../../common/utils/ResourceUtil';

@Builder
export function SettingsAdblockSubsBuilder() {
  AdblockSubsPage()
}

@ComponentV2
struct AdblockSubsPage {

  @Local intervalItem: CustomItemInfo = new CustomItemInfo({ id: 'subs_interval', type: ItemActionType.TEXT })
  @Local showPicker: boolean = false
  @Local picker: PickerConfig = new PickerConfig()
  @Local pickerHeight: number = pickerSheetHeight(5)
  @Local subDialogTitle: ResourceStr = $r('app.string.ad_block_subs_add_title')
  @Local subDialogAction: ResourceStr = $r('app.string.ad_block_subs_add')
  @Local subName: string = ''
  @Local subUrl: string = ''

  private subDialog: CustomDialogController | undefined = undefined
  private updating: boolean = false
  private editingSub: AdBlockSubscription | null = null

  aboutToAppear(): void {
    adBlockSubsStore.load().then((): void => {
      this.refreshIntervalItem()
    })
    this.intervalItem.title = $r('app.string.ad_block_subs_auto_update')
    this.intervalItem.onChange = (v: string | boolean | number): void => {
      this.openIntervalPicker()
    }
    this.picker.title = $r('app.string.ad_block_subs_auto_update')
    this.picker.options = [
      new PickerOption('manual', $r('app.string.ad_block_subs_interval_manual')),
      new PickerOption('12h', $r('app.string.ad_block_subs_interval_12h')),
      new PickerOption('daily', $r('app.string.ad_block_subs_interval_daily')),
      new PickerOption('weekly', $r('app.string.ad_block_subs_interval_weekly')),
      new PickerOption('monthly', $r('app.string.ad_block_subs_interval_monthly'))
    ]
    this.picker.selected = adBlockSubsStore.interval
    this.picker.onSelect = (v: string): void => {
      adBlockSubsStore.setInterval(v)
      this.refreshIntervalItem()
    }
    // 添加/编辑共用弹窗
    this.subDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: this.subDialogTitle,
        contentBuilder: (): void => {
          this.subDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), this.subDialogAction], false,
          (index: number): void => {
            if (index === 1) {
              this.confirmSubDialog()
            }
            this.subDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  private refreshIntervalItem(): void {
    this.intervalItem.value = ResourceUtils.getString(this.intervalLabel(adBlockSubsStore.interval))
    if (adBlockSubsStore.lastAutoUpdate <= 0) {
      this.intervalItem.subtitle = $r('app.string.ad_block_subs_never_auto')
    } else {
      this.intervalItem.subtitle = ResourceUtils.getStringWithArgs($r('app.string.ad_block_subs_last_auto'),
        [this.timeAgoStr(adBlockSubsStore.lastAutoUpdate)])
    }
  }

  private intervalLabel(v: string): ResourceStr {
    switch (v) {
      case '12h':
        return $r('app.string.ad_block_subs_interval_12h')
      case 'weekly':
        return $r('app.string.ad_block_subs_interval_weekly')
      case 'monthly':
        return $r('app.string.ad_block_subs_interval_monthly')
      case 'daily':
        return $r('app.string.ad_block_subs_interval_daily')
      default:
        return $r('app.string.ad_block_subs_interval_manual')
    }
  }

  private timeAgoStr(ts: number): string {
    if (ts <= 0) {
      return ResourceUtils.getStringWithArgs($r('app.string.time_never'), [])
    }
    const diff: number = Date.now() - ts
    const min: number = Math.floor(diff / 60000)
    if (min < 1) {
      return ResourceUtils.getStringWithArgs($r('app.string.time_just_now'), [])
    }
    if (min < 60) {
      return ResourceUtils.getStringWithArgs($r('app.string.time_minutes_ago'), [min])
    }
    const hours: number = Math.floor(min / 60)
    if (hours < 24) {
      return ResourceUtils.getStringWithArgs($r('app.string.time_hours_ago'), [hours])
    }
    return ResourceUtils.getStringWithArgs($r('app.string.time_days_ago'), [Math.floor(hours / 24)])
  }

  private subDesc(sub: AdBlockSubscription): string {
    if (sub.updating) {
      const stateRes: Resource = sub.lastUpdated > 0
        ? $r('app.string.ad_block_sub_updating') : $r('app.string.ad_block_sub_downloading')
      return ResourceUtils.getString(stateRes)
    }
    return ResourceUtils.getStringWithArgs($r('app.string.ad_block_sub_item_desc'),
      [ResourceUtils.getStringWithArgs($r('app.string.ad_block_sub_rules'), [sub.ruleCount]),
        this.timeAgoStr(sub.lastUpdated)])
  }

  private subItem(sub: AdBlockSubscription): CustomItemInfo {
    return new CustomItemInfo({
      id: sub.url,
      title: sub.name,
      subtitle: this.subDesc(sub),
      type: ItemActionType.TOGGLE,
      value: sub.enabled,
      onChange: (v: string | boolean | number): void => {
        adBlockSubsStore.toggle(sub, v as boolean)
        adBlockEngine.syncToWebEngine()
      },
      contextMenuItems: [
        new ContextMenuItem($r('app.string.ad_block_sub_menu_preview'), (): void => {
          QhState.pushPage('settings_adblock_sub_preview', sub.url)
        }),
        new ContextMenuItem($r('app.string.ad_block_sub_menu_update'), (): void => {
          this.updateSub(sub)
        }),
        new ContextMenuItem($r('app.string.ad_block_sub_menu_rename'), (): void => {
          this.renameSub(sub)
        }),
        new ContextMenuItem($r('app.string.edit'), (): void => {
          this.openEdit(sub)
        }),
        new ContextMenuItem($r('app.string.ad_block_sub_menu_copy_link'), (): void => {
          this.copyLink(sub)
        }),
        new ContextMenuItem($r('app.string.delete'), (): void => {
          this.confirmDelete(sub)
        }, undefined, true)
      ]
    })
  }

  private openIntervalPicker(): void {
    this.picker.selected = adBlockSubsStore.interval
    this.showPicker = true
  }

  /** 打开添加订阅弹窗 */
  private openAdd(): void {
    this.editingSub = null
    this.subDialogTitle = $r('app.string.ad_block_subs_add_title')
    this.subDialogAction = $r('app.string.ad_block_subs_add')
    this.subName = ''
    this.subUrl = ''
    this.subDialog?.open()
  }

  /** 打开编辑订阅弹窗 */
  private openEdit(sub: AdBlockSubscription): void {
    this.editingSub = sub
    this.subDialogTitle = $r('app.string.ad_block_sub_edit_title')
    this.subDialogAction = $r('app.string.save')
    this.subName = sub.name
    this.subUrl = sub.url
    this.subDialog?.open()
  }

  /** 添加/编辑共用弹窗确认 */
  private confirmSubDialog(): void {
    const url: string = this.subUrl.trim()
    if (url === '' || !url.startsWith('http')) {
      toastUtil.showToast({ message: $r('app.string.ad_block_subs_url_invalid') })
      return
    }
    const nameInput: string = this.subName.trim()
    const name: string = nameInput === '' ? AdBlockSubsStore.nameFromUrl(url) : nameInput
    if (this.editingSub === null) {
      // 添加：先入列表展示，规则后台下载（成功后引擎经回调自动重载）
      if (adBlockSubsStore.add(url)) {
        toastUtil.showToast({ message: $r('app.string.ad_block_subs_added') })
      } else {
        toastUtil.showToast({ message: $r('app.string.ad_block_subs_exists') })
      }
      return
    }
    // 编辑
    const sub: AdBlockSubscription = this.editingSub
    const autoName: boolean = nameInput === ''
    const urlChanged: boolean = url !== sub.url
    if (!adBlockSubsStore.edit(sub, name, url, autoName)) {
      toastUtil.showToast({ message: $r('app.string.ad_block_subs_exists') })
      return
    }
    toastUtil.showToast({ message: $r('app.string.saved') })
    if (autoName) {
      // 名称留空：跟随规则 Title，尝试立即从已下载的规则读取
      adBlockSubsStore.renameFromRule(sub)
    }
    if (urlChanged) {
      // 链接已变化，后台重新下载规则，成功后引擎经回调自动重载
      adBlockSubsStore.update(sub).then((): void => {
      })
    }
  }

  /** 长按菜单：从规则文件读取 Title 重命名 */
  private renameSub(sub: AdBlockSubscription): void {
    if (adBlockSubsStore.renameFromRule(sub)) {
      toastUtil.showToast({ message: $r('app.string.ad_block_sub_updated') })
    } else {
      toastUtil.showToast({ message: $r('app.string.ad_block_sub_rename_failed') })
    }
  }

  private updateAll(): void {
    if (this.updating) {
      return
    }
    let enabledCount: number = 0
    for (const s of adBlockSubsStore.subs) {
      if (s.enabled) {
        enabledCount++
      }
    }
    if (enabledCount === 0) {
      toastUtil.showToast({ message: $r('app.string.ad_block_subs_none_enabled') })
      return
    }
    this.updating = true
    adBlockSubsStore.updateAll(false).then((n: number): void => {
      this.updating = false
      if (n > 0) {
        toastUtil.showToast({
          message: ResourceUtils.getStringWithArgs($r('app.string.ad_block_subs_updated'), [n])
        })
      } else {
        toastUtil.showToast({ message: $r('app.string.ad_block_subs_update_failed') })
      }
    })
  }

  private updateSub(sub: AdBlockSubscription): void {
    adBlockSubsStore.update(sub).then((ok: boolean): void => {
      if (ok) {
        toastUtil.showToast({ message: $r('app.string.ad_block_sub_updated') })
      } else if (!sub.updating) {
        toastUtil.showToast({ message: $r('app.string.ad_block_subs_update_failed') })
      }
    })
  }

  private copyLink(sub: AdBlockSubscription): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, sub.url)
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      toastUtil.showToast({ message: $r('app.string.link_copied') })
    })
  }

  private confirmDelete(sub: AdBlockSubscription): void {
    toastUtil.showAlertDialog({
      title: sub.name,
      message: $r('app.string.ad_block_subs_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            adBlockSubsStore.remove(sub)
            adBlockEngine.syncToWebEngine()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteSub')
  }

  build() {
    NaviContainer({
      title: $r('app.string.ad_block_subscription'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.plus'),
          action: (): void => {
            this.openAdd()
          }
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
      // 自动更新间隔设置
      ListItem() {
        CustomListItem({
          item: this.intervalItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 订阅列表
      if (adBlockSubsStore.subs.length > 0) {
        ForEach(adBlockSubsStore.subs, (sub: AdBlockSubscription) => {
          ListItem() {
            CustomListItem({
              item: this.subItem(sub),
              itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.background_color'))
          .borderRadius(16)
          .clip(true)
          .margin({ top: 12 })
          .swipeAction({
            end: {
              builder: (): void => {
                this.swipeEndBuilder(sub)
              }
            }
          })
        }, (sub: AdBlockSubscription) => sub.url)
      } else {
        ListItem() {
          Text($r('app.string.ad_block_subs_empty'))
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
    .bindSheet(this.showPicker!!, this.pickerBuilder(), {
      preferType: SheetType.CENTER,
      height: this.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showPicker = false
      }
    })
  }

  @Builder
  subDialogContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: $r('app.string.ad_block_sub_name_hint'), text: this.subName })
        .height(44)
        .fontSize(15)
        .onChange((v: string): void => {
          this.subName = v
        })
      TextInput({ placeholder: $r('app.string.ad_block_subs_url_hint'), text: this.subUrl })
        .height(44)
        .fontSize(15)
        .onChange((v: string): void => {
          this.subUrl = v
        })
    }
    .width('100%')
  }

  @Builder
  swipeEndBuilder(sub: AdBlockSubscription) {
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
      this.confirmDelete(sub)
    })
  }

  @Builder
  pickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showPicker = false
      }
    })
  }
}
