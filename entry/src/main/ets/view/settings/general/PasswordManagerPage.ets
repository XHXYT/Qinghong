import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NaviContainer } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { passwordVM } from '../../../viewmodel/PasswordViewModel';
import { DataBackupViewModel } from '../../../viewmodel/DataBackupViewModel';

@Builder
export function SettingsPasswordBuilder() {
  PasswordManagerPage()
}

@ComponentV2
struct PasswordManagerPage {

  @Local items: CustomItemInfo[] = []

  /** 托管给系统密码管理器时置灰的子项（保存的密码/不保存的网站/导入/导出） */
  private managedItems: CustomItemInfo[] = []

  aboutToAppear(): void {
    const items: CustomItemInfo[] = []
    const managed: CustomItemInfo[] = []
    items.push(new CustomItemInfo({
      id: 'password_save_prompt',
      title: $r('app.string.password_save_prompt'),
      subtitle: $r('app.string.password_save_prompt_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.password_save_prompt,
      onChange: (v: string | boolean | number): void => {
        appSettings.password_save_prompt = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'system_password_manager',
      title: $r('app.string.system_password_manager'),
      subtitle: $r('app.string.system_password_manager_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.system_password_manager,
      onChange: (v: string | boolean | number): void => {
        appSettings.system_password_manager = v as boolean
        this.applyManaged()
      }
    }))
    const savedItem: CustomItemInfo = new CustomItemInfo({
      id: 'saved_passwords',
      title: $r('app.string.saved_passwords'),
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('settings_password_saved', null)
      }
    })
    managed.push(savedItem)
    items.push(savedItem)
    const neverItem: CustomItemInfo = new CustomItemInfo({
      id: 'never_save_passwords',
      title: $r('app.string.never_save_passwords'),
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage('settings_password_never', null)
      }
    })
    managed.push(neverItem)
    items.push(neverItem)
    const importItem: CustomItemInfo = new CustomItemInfo({
      id: 'import_passwords',
      title: $r('app.string.import_passwords'),
      subtitle: $r('app.string.import_passwords_desc'),
      type: ItemActionType.TEXT,
      onChange: (v: string | boolean | number): void => {
        this.importPasswords()
      }
    })
    managed.push(importItem)
    items.push(importItem)
    const exportItem: CustomItemInfo = new CustomItemInfo({
      id: 'export_passwords',
      title: $r('app.string.export_passwords'),
      subtitle: $r('app.string.export_passwords_desc'),
      type: ItemActionType.TEXT,
      onChange: (v: string | boolean | number): void => {
        this.exportPasswords()
      }
    })
    managed.push(exportItem)
    items.push(exportItem)
    this.items = items
    this.managedItems = managed
    this.applyManaged()
  }

  /** 系统密码管理器接管后，自建密码库相关子项置灰 */
  private applyManaged(): void {
    const managed: boolean = appSettings.system_password_manager
    for (const item of this.managedItems) {
      item.enabled = !managed
      item.disabledHint = managed ? $r('app.string.password_system_managed') : ''
    }
  }

  /** 从 CSV 文件导入密码（Chrome 导出格式） */
  private importPasswords(): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const options: picker.DocumentSelectOptions = {
      maxSelectNumber: 1,
      fileSuffixFilters: ['csv']
    }
    docPicker.select(options).then((uris: string[]): void => {
      if (uris.length === 0) {
        return
      }
      passwordVM.importFromUri(uris[0]).then((count: number): void => {
        if (count > 0) {
          toastUtil.showToast({
            message: ResourceUtils.getStringWithArgs($r('app.string.password_imported_count'), [count])
          })
        } else {
          toastUtil.showToast({ message: $r('app.string.password_import_failed') })
        }
      }).catch((error: BusinessError): void => {
        console.error(`[PasswordManager] 导入密码失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.password_import_failed') })
      })
    }).catch((error: BusinessError): void => {
      console.error(`[PasswordManager] 选择 CSV 文件失败: ${error.code} ${error.message}`)
    })
  }

  /** 导出密码为 Chrome CSV 格式，写入 Download/<包名>/backup */
  private exportPasswords(): void {
    passwordVM.exportToCsv().then((csv: string): void => {
      if (csv === '') {
        toastUtil.showToast({ message: $r('app.string.password_export_empty') })
        return
      }
      DataBackupViewModel.writeBackupFile('qinghong_passwords.csv', csv).then((): void => {
        toastUtil.showToast({ message: $r('app.string.password_export_success') })
      }).catch((error: BusinessError): void => {
        console.error(`[PasswordManager] 写出密码文件失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.password_export_failed') })
      })
    }).catch((error: BusinessError): void => {
      console.error(`[PasswordManager] 导出密码失败: ${error.code} ${error.message}`)
      toastUtil.showToast({ message: $r('app.string.password_export_failed') })
    })
  }

  build() {
    NaviContainer({
      title: $r('app.string.password_manager'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onShown: (): void => {
        this.applyManaged()
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      ListItem() {
        Column() {
          Repeat<CustomItemInfo>(this.items)
            .each((ri: RepeatItem<CustomItemInfo>) => {
              CustomListItem({
                item: ri.item,
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
      .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }
}
