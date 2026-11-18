import { CustomContentDialog } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { defaultAppManager, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SettingsScaffold, SettingsSection } from '../../../components/SettingsScaffold';
import { QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { historyVM } from '../../../viewmodel/HistoryViewModel';
import { bookmarkVM } from '../../../viewmodel/BookmarkViewModel';
import { dataBackupVM, DataBackupViewModel } from '../../../viewmodel/DataBackupViewModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ui/ToastUtils';
import { ResourceUtils } from '../../../common/utils/app/ResourceUtil';
import { DataClearer } from '../../../common/utils/app/DataClearer';
import { SettingsUtils } from '../../../common/utils/app/SettingsUtils';
import { AppConstants } from '../../../common/constants/AppConstants';

const CLEAR_KEYS: string[] = DataClearer.KEYS;

function parseExitClear(v: string): boolean[] {
  const parts: string[] = v ? v.split(',') : [];
  return CLEAR_KEYS.map((k: string): boolean => parts.includes(k));
}

function exitClearKeys(selected: boolean[]): string {
  const picked: string[] = [];
  for (let i = 0; i < selected.length && i < CLEAR_KEYS.length; i++) {
    if (selected[i]) {
      picked.push(CLEAR_KEYS[i]);
    }
  }
  return picked.join(',');
}

function langLabel(v: string): ResourceStr {
  if (v === 'en') {
    return $r('app.string.lang_english');
  }
  if (v === 'zh') {
    return $r('app.string.lang_chinese');
  }
  return $r('app.string.lang_follow_system');
}

function orientationLabel(v: string): ResourceStr {
  if (v === 'portrait') {
    return $r('app.string.orientation_portrait');
  }
  if (v === 'landscape') {
    return $r('app.string.orientation_landscape');
  }
  return $r('app.string.orientation_auto');
}

function restoreLabel(v: string): ResourceStr {
  if (v === 'never') {
    return $r('app.string.restore_never');
  }
  if (v === 'keep') {
    return $r('app.string.restore_keep');
  }
  if (v === 'ask') {
    return $r('app.string.restore_ask');
  }
  return $r('app.string.restore_always');
}

function homeModeLabel(v: string): ResourceStr {
  if (v === 'blank') {
    return $r('app.string.home_mode_blank');
  }
  if (v === 'bookmarks') {
    return $r('app.string.home_mode_bookmarks');
  }
  if (v === 'web') {
    return $r('app.string.home_mode_web');
  }
  return $r('app.string.home_mode_default');
}

@ComponentV2
struct CheckRow {
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

@ComponentV2
struct ActionRow {
  @Require @Param label: ResourceStr
  @Event onTap: () => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(20)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .width('100%')
    .height(48)
    .onClick(() => {
      this.onTap()
    })
  }
}

@Builder
export function GeneralSettingsBuilder() {
  GeneralSettingsPage()
}

@ComponentV2
struct GeneralSettingsPage {

  @Local groups: SettingsSection[] = []
  @Local picker: PickerConfig = new PickerConfig()
  @Local showPicker: boolean = false
  @Local pickerHeight: number = pickerSheetHeight(3)

  @Local clearSel: boolean[] = [false, false, false, false, false, false, false]
  @Local exitSel: boolean[] = parseExitClear('')
  @Local exportSel: boolean[] = [false, false, false, false, false, false, false, false, false, false]
  @Local inputUrl: string = ''

  private clearDataDialog: CustomDialogController | undefined = undefined
  private exitClearDialog: CustomDialogController | undefined = undefined
  private bookmarkDialog: CustomDialogController | undefined = undefined
  private exportDialog: CustomDialogController | undefined = undefined
  private urlDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.buildItems()
    this.initDialogs()
  }

  private routerItem(id: string, title: ResourceStr, route: string): CustomItemInfo {
    return new CustomItemInfo({
      id: id,
      title: title,
      type: ItemActionType.ROUTER,
      onChange: (v: string | boolean | number): void => {
        QhState.pushPage(route, null)
      }
    })
  }

  private textItem(id: string, title: ResourceStr, value: string, onClick: () => void): CustomItemInfo {
    return new CustomItemInfo({
      id: id,
      title: title,
      type: ItemActionType.ROUTER,
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
          item.value = v;
          return;
        }
      }
    }
  }

  private buildItems(): void {
    const groups: SettingsSection[] = []
    // 启动与系统
    let g = new SettingsSection('startup', $r('app.string.general_group_startup'))
    g.items.push(this.textItem('restore_tabs', $r('app.string.restore_tabs'),
      ResourceUtils.getString(restoreLabel(appSettings.restore_mode)), (): void => {
        this.openRestorePicker()
      }))
    g.items.push(new CustomItemInfo({
      id: 'undo_close_tip',
      title: $r('app.string.undo_close_tip'),
      subtitle: $r('app.string.undo_close_tip_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.show_undo_close_tip,
      onChange: (v: string | boolean | number): void => {
        appSettings.show_undo_close_tip = v as boolean
      }
    }))
    g.items.push(new CustomItemInfo({
      id: 'auto_expand_web',
      title: $r('app.string.auto_expand_web'),
      subtitle: $r('app.string.auto_expand_web_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.auto_expand_web,
      onChange: (v: string | boolean | number): void => {
        appSettings.auto_expand_web = v as boolean
      }
    }))
    g.items.push(this.textItem('set_default_browser', $r('app.string.set_default_browser'),
      this.defaultBrowserStatus(), (): void => {
        this.openDefaultBrowserSetting()
      }))
    g.items.push(this.routerItem('sync', $r('app.string.settings_sync'), 'settings_sync'))
    groups.push(g)
    // 菜单与操作
    g = new SettingsSection('menu', $r('app.string.general_group_menu'))
    g.items.push(this.routerItem('toolbar_settings', $r('app.string.toolbar_settings'), 'settings_toolbar'))
    g.items.push(this.routerItem('customize_menu', $r('app.string.customize_menu'), 'settings_menu_custom'))
    g.items.push(this.routerItem('customize_long_press_menu', $r('app.string.customize_long_press_menu'), 'settings_long_press'))
    g.items.push(this.routerItem('operations_settings', $r('app.string.operations_settings'), 'settings_operations'))
    groups.push(g)
    // 外观与显示
    g = new SettingsSection('appearance', $r('app.string.general_group_appearance'))
    g.items.push(this.routerItem('night_mode', $r('app.string.night_mode'), 'settings_night_mode'))
    g.items.push(this.routerItem('read_mode', $r('app.string.read_mode'), 'settings_read_mode'))
    g.items.push(this.routerItem('font', $r('app.string.font'), 'settings_font'))
    g.items.push(this.textItem('language', $r('app.string.language'),
      ResourceUtils.getString(langLabel(appSettings.language)), (): void => {
        this.openLanguagePicker()
      }))
    g.items.push(this.textItem('screen_orientation', $r('app.string.screen_orientation'),
      ResourceUtils.getString(orientationLabel(appSettings.screen_orientation)), (): void => {
        this.openOrientationPicker()
      }))
    groups.push(g)
    // 网页浏览
    g = new SettingsSection('browsing', $r('app.string.general_group_browsing'))
    g.items.push(this.routerItem('ua', $r('app.string.settings_ua'), 'settings_ua'))
    g.items.push(this.routerItem('dns', $r('app.string.settings_dns'), 'settings_dns'))
    g.items.push(this.routerItem('proxy', $r('app.string.settings_proxy'), 'settings_proxy'))
    g.items.push(this.routerItem('ad_block', $r('app.string.ad_block'), 'settings_adblock'))
    g.items.push(this.routerItem('site_settings', $r('app.string.site_settings'), 'settings_site'))
    g.items.push(this.routerItem('translate_settings', $r('app.string.translate_settings'), 'settings_translate'))
    g.items.push(this.routerItem('password_manager', $r('app.string.password_manager'), 'settings_password'))
    groups.push(g)
    // 搜索与主页
    g = new SettingsSection('search', $r('app.string.general_group_search'))
    g.items.push(this.textItem('home_page', $r('app.string.home_page'),
      ResourceUtils.getString(homeModeLabel(appSettings.home_page_mode)), (): void => {
        this.openHomePicker()
      }))
    g.items.push(this.routerItem('search_settings', $r('app.string.search_settings'), 'search_settings'))
    g.items.push(this.routerItem('ai_settings', $r('app.string.ai_settings'), 'settings_ai'))
    groups.push(g)
    // 下载与数据
    g = new SettingsSection('data', $r('app.string.general_group_data'))
    g.items.push(this.routerItem('download_settings', $r('app.string.download_settings'), 'settings_download'))
    g.items.push(this.textItem('clear_data', $r('app.string.clear_data'), '', (): void => {
      this.clearDataDialog?.open()
    }))
    g.items.push(this.textItem('exit_clear_data', $r('app.string.exit_clear_data'), '', (): void => {
      this.exitClearDialog?.open()
    }))
    g.items.push(this.textItem('import_backup_bookmarks', $r('app.string.import_backup_bookmarks'), '', (): void => {
      this.bookmarkDialog?.open()
    }))
    g.items.push(this.textItem('import_data', $r('app.string.import_data'), '', (): void => {
      this.importDataFromPicker()
    }))
    g.items.push(this.textItem('export_data', $r('app.string.export_data'), '', (): void => {
      this.exportDialog?.open()
    }))
    groups.push(g)
    this.groups = groups
  }

  private initDialogs(): void {
    this.clearDataDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.clear_data'),
        contentBuilder: (): void => {
          this.clearDataContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.clear')], true,
          (index: number): void => {
            if (index === 1) {
              this.doClearData()
            }
            this.clearDataDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        // 默认勾选：缓存/历史记录/网页存储
        this.clearSel = [true, true, false, false, true, false, false]
      }
    })
    this.exitClearDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.exit_clear_data'),
        contentBuilder: (): void => {
          this.exitClearContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.saveExitClear()
            }
            this.exitClearDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.exitSel = parseExitClear(appSettings.exit_clear_data)
      }
    })
    this.bookmarkDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.import_backup_bookmarks'),
        contentBuilder: (): void => {
          this.bookmarkDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel')], false,
          (index: number): void => {
            this.bookmarkDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
    this.exportDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.export_data'),
        contentBuilder: (): void => {
          this.exportDataContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.export')], false,
          (index: number): void => {
            if (index === 1) {
              this.doExportData()
            }
            this.exportDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
    this.urlDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.home_page'),
        contentBuilder: (): void => {
          this.urlDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.applyWebUrl()
            }
            this.urlDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.inputUrl = appSettings.home_page_url
      }
    })
  }

  private openPicker(title: ResourceStr, options: PickerOption[], selected: string,
    onSelect: (v: string) => void): void {
    this.picker.title = title
    this.picker.options = options
    this.picker.selected = selected
    this.picker.onSelect = onSelect
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showPicker = true
  }

  private openLanguagePicker(): void {
    this.openPicker($r('app.string.language'), [
      new PickerOption('system', $r('app.string.lang_follow_system')),
      new PickerOption('en', $r('app.string.lang_english')),
      new PickerOption('zh', $r('app.string.lang_chinese'))
    ], appSettings.language, (v: string): void => {
      appSettings.language = v
      SettingsUtils.applyLanguage()
      this.setItemValue('language', ResourceUtils.getString(langLabel(v)))
    })
  }

  private openOrientationPicker(): void {
    this.openPicker($r('app.string.screen_orientation'), [
      new PickerOption('auto', $r('app.string.orientation_auto')),
      new PickerOption('portrait', $r('app.string.orientation_portrait')),
      new PickerOption('landscape', $r('app.string.orientation_landscape'))
    ], appSettings.screen_orientation, (v: string): void => {
      appSettings.screen_orientation = v
      SettingsUtils.applyOrientation()
      this.setItemValue('screen_orientation', ResourceUtils.getString(orientationLabel(v)))
    })
  }

  private openRestorePicker(): void {
    this.openPicker($r('app.string.restore_tabs'), [
      new PickerOption('never', $r('app.string.restore_never')),
      new PickerOption('keep', $r('app.string.restore_keep')),
      new PickerOption('always', $r('app.string.restore_always')),
      new PickerOption('ask', $r('app.string.restore_ask'))
    ], appSettings.restore_mode, (v: string): void => {
      appSettings.restore_mode = v
      this.setItemValue('restore_tabs', ResourceUtils.getString(restoreLabel(v)))
    })
  }

  private openHomePicker(): void {
    this.openPicker($r('app.string.home_page'), [
      new PickerOption('default', $r('app.string.home_mode_default')),
      new PickerOption('blank', $r('app.string.home_mode_blank')),
      new PickerOption('bookmarks', $r('app.string.home_mode_bookmarks')),
      new PickerOption('web', $r('app.string.home_mode_web'))
    ], appSettings.home_page_mode, (v: string): void => {
      if (v === 'web') {
        // 网页模式：先输入主页网址，取消则保持原模式
        this.urlDialog?.open()
        return
      }
      appSettings.home_page_mode = v
      this.setItemValue('home_page', ResourceUtils.getString(homeModeLabel(v)))
    })
  }

  private applyWebUrl(): void {
    let url = this.inputUrl.trim()
    if (!url) {
      toastUtil.showToast({ message: $r('app.string.home_page_url_hint') })
      return
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = `https://${url}`
    }
    appSettings.home_page_url = url
    appSettings.home_page_mode = 'web'
    this.setItemValue('home_page', ResourceUtils.getString(homeModeLabel('web')))
  }

  private doClearData(): void {
    const keys: string[] = []
    for (let i = 0; i < this.clearSel.length && i < CLEAR_KEYS.length; i++) {
      if (this.clearSel[i]) {
        keys.push(CLEAR_KEYS[i])
      }
    }
    DataClearer.clearByKeys(keys)
    toastUtil.showToast({ message: $r('app.string.cleared') })
  }

  private saveExitClear(): void {
    appSettings.exit_clear_data = exitClearKeys(this.exitSel)
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  /** 备份书签：导出为 Netscape HTML 书签文件，写入 Download/<包名>/backup */
  private backupBookmarks(): void {
    dataBackupVM.exportBookmarksHtml().then((html: string): void => {
      if (html === '') {
        toastUtil.showToast({ message: $r('app.string.bookmarks_export_empty') })
        return
      }
      DataBackupViewModel.writeBackupFile('qinghong_bookmarks.html', html).then((): void => {
        toastUtil.showToast({ message: $r('app.string.bookmarks_export_success') })
      }).catch((error: BusinessError): void => {
        console.error(`[GeneralSettings] 写出书签文件失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.bookmarks_export_failed') })
      })
    }).catch((error: BusinessError): void => {
      console.error(`[GeneralSettings] 导出书签失败: ${error.code} ${error.message}`)
      toastUtil.showToast({ message: $r('app.string.bookmarks_export_failed') })
    })
  }

  /** 导入书签：选择 Netscape HTML 书签文件（Chrome/Firefox 通用格式） */
  private importBookmarks(): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const options: picker.DocumentSelectOptions = {
      maxSelectNumber: 1,
      fileSuffixFilters: ['html', 'htm']
    }
    docPicker.select(options).then((uris: string[]): void => {
      if (uris.length === 0) {
        return
      }
      dataBackupVM.importBookmarksFromUri(uris[0]).then((count: number): void => {
        if (count > 0) {
          toastUtil.showToast({
            message: ResourceUtils.getStringWithArgs($r('app.string.bookmarks_imported_count'), [count])
          })
          bookmarkVM.loadAll()
        } else {
          toastUtil.showToast({ message: $r('app.string.bookmarks_import_failed') })
        }
      }).catch((error: BusinessError): void => {
        console.error(`[GeneralSettings] 导入书签失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.bookmarks_import_failed') })
      })
    }).catch((error: BusinessError): void => {
      console.error(`[GeneralSettings] 选择书签文件失败: ${error.code} ${error.message}`)
    })
  }

  /** 导入数据：直接打开文件选择器，选择此前导出的 JSON 备份 */
  private importDataFromPicker(): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const options: picker.DocumentSelectOptions = {
      maxSelectNumber: 1,
      fileSuffixFilters: ['json', 'zip']
    }
    docPicker.select(options).then((uris: string[]): void => {
      if (uris.length === 0) {
        return
      }
      dataBackupVM.importDataFromUri(uris[0]).then((ok: boolean): void => {
        if (ok) {
          toastUtil.showToast({ message: $r('app.string.data_import_success') })
          bookmarkVM.loadAll()
          historyVM.loadAll()
        } else {
          toastUtil.showToast({ message: $r('app.string.data_import_failed') })
        }
      }).catch((error: BusinessError): void => {
        console.error(`[GeneralSettings] 导入数据失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.data_import_failed') })
      })
    }).catch((error: BusinessError): void => {
      console.error(`[GeneralSettings] 选择备份文件失败: ${error.code} ${error.message}`)
    })
  }

  /** 导出数据：按勾选项打包 zip（backup.json + 壁纸/logo + 扩展文件），写入 Download/<包名>/backup */
  private doExportData(): void {
    if (!this.exportSel.includes(true)) {
      toastUtil.showToast({ message: $r('app.string.data_export_none_selected') })
      return
    }
    dataBackupVM.exportBackup(this.exportSel)
      .then((): void => {
        toastUtil.showToast({ message: $r('app.string.data_export_success') })
      })
      .catch((error: BusinessError): void => {
        console.error(`[GeneralSettings] 导出数据失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.data_export_failed') })
      })
  }

  /**
   * 查询本应用是否已是默认浏览器（官方 defaultAppManager，无需权限）
   */
  private queryIsDefaultBrowser(): boolean {
    try {
      return defaultAppManager.isDefaultApplicationSync(defaultAppManager.ApplicationType.BROWSER)
    } catch (e) {
      console.error(`[GeneralSettings] 查询默认浏览器状态失败: ${e}`)
      return false
    }
  }

  private defaultBrowserStatus(): string {
    return ResourceUtils.getString(this.queryIsDefaultBrowser()
      ? $r('app.string.default_browser_on')
      : $r('app.string.default_browser_off'))
  }

  /**
   * 跳转系统设置的本应用详情页，由用户手动设为默认浏览器
   */
  private openDefaultBrowserSetting(): void {
    if (this.queryIsDefaultBrowser()) {
      toastUtil.showToast({ message: $r('app.string.already_default_browser') })
      return
    }
    const context = toastUtil.context
    if (!context) {
      toastUtil.showToast({ message: $r('app.string.set_default_browser_toast') })
      return
    }
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: {
        pushParams: 'com.ya.qinghong'
      }
    }
    context.startAbility(want).catch((error: BusinessError) => {
      console.error(`[GeneralSettings] 跳转系统设置失败: ${error.code} ${error.message}`)
      toastUtil.showToast({ message: $r('app.string.set_default_browser_toast') })
    })
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.settings_general'),
      sections: this.groups,
      onShown: (): void => {
        // 从系统设置返回后刷新默认浏览器状态
        this.setItemValue('set_default_browser', this.defaultBrowserStatus())
      },
      footer: (): void => {
        this.pageFooter()
      }
    })
  }

  /** 列表末尾锚点：挂载选择器 bindSheet */
  @Builder
  pageFooter() {
    Row()
      .height(1)
      .width('100%')
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
  pickerBuilder() {
    SheetPicker({
      config: this.picker,
      close: (): void => {
        this.showPicker = false
      }
    })
  }

  @Builder
  urlDialogContent() {
    TextInput({ text: this.inputUrl, placeholder: $r('app.string.home_page_url_hint') })
      .height(44)
      .fontSize(15)
      .type(InputType.URL)
      .onChange((v: string) => {
        this.inputUrl = v
      })
  }

  @Builder
  clearDataContent() {
    Column() {
      CheckRow({ label: $r('app.string.clear_cache_label'), checked: this.clearSel[0],
        onToggle: (v: boolean): void => { this.clearSel[0] = v } })
      CheckRow({ label: $r('app.string.clear_history_label'), checked: this.clearSel[1],
        onToggle: (v: boolean): void => { this.clearSel[1] = v } })
      CheckRow({ label: $r('app.string.clear_search_history_label'), checked: this.clearSel[2],
        onToggle: (v: boolean): void => { this.clearSel[2] = v } })
      CheckRow({ label: $r('app.string.clear_closed_tabs'), checked: this.clearSel[3],
        onToggle: (v: boolean): void => { this.clearSel[3] = v } })
      CheckRow({ label: $r('app.string.clear_web_storage'), checked: this.clearSel[4],
        onToggle: (v: boolean): void => { this.clearSel[4] = v } })
      CheckRow({ label: $r('app.string.clear_cookies_login'), checked: this.clearSel[5],
        onToggle: (v: boolean): void => { this.clearSel[5] = v } })
      CheckRow({ label: $r('app.string.clear_app_cache'), checked: this.clearSel[6],
        onToggle: (v: boolean): void => { this.clearSel[6] = v } })
    }
    .width('100%')
  }

  @Builder
  exitClearContent() {
    Column() {
      CheckRow({ label: $r('app.string.clear_cache_label'), checked: this.exitSel[0],
        onToggle: (v: boolean): void => { this.exitSel[0] = v } })
      CheckRow({ label: $r('app.string.clear_history_label'), checked: this.exitSel[1],
        onToggle: (v: boolean): void => { this.exitSel[1] = v } })
      CheckRow({ label: $r('app.string.clear_search_history_label'), checked: this.exitSel[2],
        onToggle: (v: boolean): void => { this.exitSel[2] = v } })
      CheckRow({ label: $r('app.string.clear_closed_tabs'), checked: this.exitSel[3],
        onToggle: (v: boolean): void => { this.exitSel[3] = v } })
      CheckRow({ label: $r('app.string.clear_web_storage'), checked: this.exitSel[4],
        onToggle: (v: boolean): void => { this.exitSel[4] = v } })
      CheckRow({ label: $r('app.string.clear_cookies_login'), checked: this.exitSel[5],
        onToggle: (v: boolean): void => { this.exitSel[5] = v } })
      CheckRow({ label: $r('app.string.clear_app_cache'), checked: this.exitSel[6],
        onToggle: (v: boolean): void => { this.exitSel[6] = v } })
    }
    .width('100%')
  }

  @Builder
  bookmarkDialogContent() {
    Column() {
      ActionRow({ label: $r('app.string.backup_bookmarks'), onTap: (): void => {
        this.bookmarkDialog?.close()
        this.backupBookmarks()
      } })
      ActionRow({ label: $r('app.string.import_bookmarks'), onTap: (): void => {
        this.bookmarkDialog?.close()
        this.importBookmarks()
      } })
    }
    .width('100%')
  }

  @Builder
  exportDataContent() {
    Column() {
      CheckRow({ label: $r('app.string.bookmarks'), checked: this.exportSel[0],
        onToggle: (v: boolean): void => { this.exportSel[0] = v } })
      CheckRow({ label: $r('app.string.history'), checked: this.exportSel[1],
        onToggle: (v: boolean): void => { this.exportSel[1] = v } })
      CheckRow({ label: $r('app.string.settings'), checked: this.exportSel[2],
        onToggle: (v: boolean): void => { this.exportSel[2] = v } })
      CheckRow({ label: $r('app.string.clear_search_history_label'), checked: this.exportSel[3],
        onToggle: (v: boolean): void => { this.exportSel[3] = v } })
      CheckRow({ label: $r('app.string.download_records'), checked: this.exportSel[4],
        onToggle: (v: boolean): void => { this.exportSel[4] = v } })
      CheckRow({ label: $r('app.string.site_settings'), checked: this.exportSel[5],
        onToggle: (v: boolean): void => { this.exportSel[5] = v } })
      CheckRow({ label: $r('app.string.hosts'), checked: this.exportSel[6],
        onToggle: (v: boolean): void => { this.exportSel[6] = v } })
      CheckRow({ label: $r('app.string.ad_block_subscription'), checked: this.exportSel[7],
        onToggle: (v: boolean): void => { this.exportSel[7] = v } })
      CheckRow({ label: $r('app.string.user_scripts'), checked: this.exportSel[8],
        onToggle: (v: boolean): void => { this.exportSel[8] = v } })
      CheckRow({ label: $r('app.string.extensions'), checked: this.exportSel[9],
        onToggle: (v: boolean): void => { this.exportSel[9] = v } })
    }
    .width('100%')
  }
}
