import { CustomContentDialog } from '@kit.ArkUI';
import { SettingsSection, SettingsScaffold } from '../../../components/SettingsScaffold';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../components/SheetPicker';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { appSettings } from '../../../common/entity/SettingsModel';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { TranslateLang } from '../../../viewmodel/TranslateViewModel';

/** 可自动翻译的源语言（不含目标语言常选的 zh-CN） */
const AUTO_LANGS: string[] = ['en', 'ja', 'ko', 'ru', 'fr', 'de', 'es', 'zh-TW']

/** 翻译服务显示名 */
function engineLabel(engine: string): string {
  if (engine === 'google') {
    return ResourceUtils.getString($r('app.string.translate_engine_google'))
  }
  if (engine === 'microsoft') {
    return ResourceUtils.getString($r('app.string.translate_engine_microsoft'))
  }
  if (engine === 'baidu') {
    return ResourceUtils.getString($r('app.string.translate_engine_baidu'))
  }
  if (engine === 'youdao') {
    return ResourceUtils.getString($r('app.string.translate_engine_youdao'))
  }
  if (engine === 'deepl') {
    return 'DeepL'
  }
  if (engine === 'libre') {
    return 'LibreTranslate'
  }
  return ResourceUtils.getString($r('app.string.translate_engine_builtin'))
}

/** 密钥脱敏显示（尾 4 位） */
function maskValue(v: string): string {
  const t: string = v.trim()
  if (t === '') {
    return ResourceUtils.getString($r('app.string.translate_not_set'))
  }
  return '••••' + t.slice(-4)
}

/** 明文显示（未设置为占位） */
function plainValue(v: string): string {
  const t: string = v.trim()
  if (t === '') {
    return ResourceUtils.getString($r('app.string.translate_not_set'))
  }
  return t
}

@Builder
export function SettingsTranslateBuilder() {
  TranslateSettingsPage()
}

@ComponentV2
struct TranslateSettingsPage {

  @Local sections: SettingsSection[] = []
  @Local showPicker: boolean = false
  @Local picker: PickerConfig = new PickerConfig()
  @Local pickerHeight: number = 0
  @Local dialogTitle: ResourceStr = ''
  @Local inputValue: string = ''
  private dialogKind: string = ''
  private editDialog: CustomDialogController | undefined = undefined

  // 持久分组/行：V2 深度观测（CustomItemInfo @Trace value / SettingsSection @Trace items），
  // 值变化直接改属性、换引擎只替换 engineSection.items，不重建整页
  private prefSection: SettingsSection = new SettingsSection('pref', $r('app.string.translate_settings'))
  private autoSection: SettingsSection = new SettingsSection('auto', $r('app.string.translate_auto_group'))
  private engineSection: SettingsSection = new SettingsSection('engine', $r('app.string.translate_engine_group'))
  private targetItem: CustomItemInfo = new CustomItemInfo({
    id: 'target',
    title: $r('app.string.translate_target_lang'),
    type: ItemActionType.TEXT
  })
  private bilingualItem: CustomItemInfo = new CustomItemInfo({
    id: 'bilingual',
    title: $r('app.string.translate_bilingual'),
    type: ItemActionType.TOGGLE
  })
  private engineItem: CustomItemInfo = new CustomItemInfo({
    id: 'engine',
    title: $r('app.string.translate_engine'),
    type: ItemActionType.TEXT
  })
  private msKeyItem: CustomItemInfo = new CustomItemInfo({
    id: 'ms_key',
    title: $r('app.string.translate_ms_key'),
    type: ItemActionType.TEXT
  })
  private baiduAppidItem: CustomItemInfo = new CustomItemInfo({
    id: 'baidu_appid',
    title: $r('app.string.translate_baidu_appid'),
    type: ItemActionType.TEXT
  })
  private baiduKeyItem: CustomItemInfo = new CustomItemInfo({
    id: 'baidu_key',
    title: $r('app.string.translate_baidu_key'),
    type: ItemActionType.TEXT
  })
  private youdaoAppidItem: CustomItemInfo = new CustomItemInfo({
    id: 'youdao_appid',
    title: $r('app.string.translate_youdao_appid'),
    type: ItemActionType.TEXT
  })
  private youdaoSecretItem: CustomItemInfo = new CustomItemInfo({
    id: 'youdao_secret',
    title: $r('app.string.translate_youdao_secret'),
    type: ItemActionType.TEXT
  })
  private deeplKeyItem: CustomItemInfo = new CustomItemInfo({
    id: 'deepl_key',
    title: $r('app.string.translate_deepl_key'),
    type: ItemActionType.TEXT
  })
  private libreUrlItem: CustomItemInfo = new CustomItemInfo({
    id: 'libre_url',
    title: $r('app.string.translate_libre_url'),
    type: ItemActionType.TEXT
  })
  private libreKeyItem: CustomItemInfo = new CustomItemInfo({
    id: 'libre_key',
    title: $r('app.string.translate_libre_key'),
    type: ItemActionType.TEXT
  })
  private autoItems: Map<string, CustomItemInfo> = new Map()

  aboutToAppear(): void {
    // 翻译偏好
    this.targetItem.onChange = (): void => {
      this.openTargetPicker()
    }
    this.bilingualItem.onChange = (v: string | boolean | number): void => {
      appSettings.translate_bilingual = v === true
    }
    this.prefSection.items = [this.targetItem, this.bilingualItem]
    // 自动翻译
    const desc: CustomItemInfo = new CustomItemInfo({
      id: 'auto_desc',
      title: $r('app.string.translate_auto_desc'),
      type: ItemActionType.TEXT
    })
    desc.enabled = false
    const autoList: CustomItemInfo[] = [desc]
    for (const code of AUTO_LANGS) {
      const it: CustomItemInfo = new CustomItemInfo({
        id: `auto_${code}`,
        title: TranslateLang.labelRes(code),
        type: ItemActionType.TOGGLE,
        value: this.isAlwaysOn(code)
      })
      it.onChange = (v: string | boolean | number): void => {
        this.toggleAlways(code, v === true)
      }
      this.autoItems.set(code, it)
      autoList.push(it)
    }
    this.autoSection.items = autoList
    // 翻译服务
    this.engineItem.onChange = (): void => {
      this.openEnginePicker()
    }
    this.msKeyItem.onChange = (): void => {
      this.openEdit('ms_key')
    }
    this.baiduAppidItem.onChange = (): void => {
      this.openEdit('baidu_appid')
    }
    this.baiduKeyItem.onChange = (): void => {
      this.openEdit('baidu_key')
    }
    this.youdaoAppidItem.onChange = (): void => {
      this.openEdit('youdao_appid')
    }
    this.youdaoSecretItem.onChange = (): void => {
      this.openEdit('youdao_secret')
    }
    this.deeplKeyItem.onChange = (): void => {
      this.openEdit('deepl_key')
    }
    this.libreUrlItem.onChange = (): void => {
      this.openEdit('libre_url')
    }
    this.libreKeyItem.onChange = (): void => {
      this.openEdit('libre_key')
    }
    this.refreshEngineItems()
    this.refreshValues()
    this.sections = [this.prefSection, this.autoSection, this.engineSection]
    this.initDialog()
  }

  /** 按当前引擎替换引擎组行（@Trace items 数组变化驱动重渲染） */
  private refreshEngineItems(): void {
    const eng: string = appSettings.translate_engine
    const items: CustomItemInfo[] = [this.engineItem]
    if (eng === 'microsoft') {
      items.push(this.msKeyItem)
    } else if (eng === 'baidu') {
      items.push(this.baiduAppidItem)
      items.push(this.baiduKeyItem)
    } else if (eng === 'youdao') {
      items.push(this.youdaoAppidItem)
      items.push(this.youdaoSecretItem)
    } else if (eng === 'deepl') {
      items.push(this.deeplKeyItem)
    } else if (eng === 'libre') {
      items.push(this.libreUrlItem)
      items.push(this.libreKeyItem)
    }
    this.engineSection.items = items
  }

  /** 从 appSettings 刷新各行值（@Trace value 直接驱动行刷新） */
  private refreshValues(): void {
    this.targetItem.value = ResourceUtils.getString(TranslateLang.labelRes(appSettings.translate_target_lang))
    this.bilingualItem.value = appSettings.translate_bilingual
    this.engineItem.value = engineLabel(appSettings.translate_engine)
    this.msKeyItem.value = maskValue(appSettings.translate_ms_key)
    this.baiduAppidItem.value = plainValue(appSettings.translate_baidu_appid)
    this.baiduKeyItem.value = maskValue(appSettings.translate_baidu_key)
    this.youdaoAppidItem.value = plainValue(appSettings.translate_youdao_appid)
    this.youdaoSecretItem.value = maskValue(appSettings.translate_youdao_secret)
    this.deeplKeyItem.value = maskValue(appSettings.translate_deepl_key)
    this.libreUrlItem.value = plainValue(appSettings.translate_libre_url)
    this.libreKeyItem.value = maskValue(appSettings.translate_libre_key)
    for (const code of AUTO_LANGS) {
      const it: CustomItemInfo | undefined = this.autoItems.get(code)
      if (it !== undefined) {
        it.value = this.isAlwaysOn(code)
      }
    }
  }

  private isAlwaysOn(code: string): boolean {
    return appSettings.translate_always.split(',').includes(code)
  }

  private toggleAlways(code: string, on: boolean): void {
    const parts: string[] = appSettings.translate_always === '' ? [] : appSettings.translate_always.split(',')
    const idx: number = parts.indexOf(code)
    if (on && idx < 0) {
      parts.push(code)
    }
    if (!on && idx >= 0) {
      parts.splice(idx, 1)
    }
    appSettings.translate_always = parts.join(',')
  }

  private openTargetPicker(): void {
    const options: PickerOption[] = []
    for (const code of TranslateLang.CODES) {
      options.push(new PickerOption(code, TranslateLang.labelRes(code)))
    }
    this.picker.title = $r('app.string.translate_target_lang')
    this.picker.options = options
    this.picker.selected = appSettings.translate_target_lang
    this.picker.onSelect = (v: string): void => {
      appSettings.translate_target_lang = v
      this.targetItem.value = ResourceUtils.getString(TranslateLang.labelRes(v))
    }
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showPicker = true
  }

  private openEnginePicker(): void {
    const options: PickerOption[] = [
      new PickerOption('builtin', $r('app.string.translate_engine_builtin')),
      new PickerOption('google', $r('app.string.translate_engine_google')),
      new PickerOption('microsoft', $r('app.string.translate_engine_microsoft')),
      new PickerOption('baidu', $r('app.string.translate_engine_baidu')),
      new PickerOption('youdao', $r('app.string.translate_engine_youdao')),
      new PickerOption('deepl', 'DeepL'),
      new PickerOption('libre', 'LibreTranslate')
    ]
    this.picker.title = $r('app.string.translate_engine')
    this.picker.options = options
    this.picker.selected = appSettings.translate_engine
    this.picker.onSelect = (v: string): void => {
      appSettings.translate_engine = v
      this.refreshEngineItems()
      this.refreshValues()
    }
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showPicker = true
  }

  private inputPlaceholder(): ResourceStr {
    if (this.dialogKind === 'libre_url') {
      return 'https://libre.example.com'
    }
    if (this.dialogKind === 'ms_key') {
      return $r('app.string.translate_ms_key_hint')
    }
    return $r('app.string.translate_key_hint')
  }

  private openEdit(kind: string): void {
    this.dialogKind = kind
    if (kind === 'deepl_key') {
      this.dialogTitle = $r('app.string.translate_deepl_key')
      this.inputValue = appSettings.translate_deepl_key
    } else if (kind === 'libre_url') {
      this.dialogTitle = $r('app.string.translate_libre_url')
      this.inputValue = appSettings.translate_libre_url
    } else if (kind === 'libre_key') {
      this.dialogTitle = $r('app.string.translate_libre_key')
      this.inputValue = appSettings.translate_libre_key
    } else if (kind === 'ms_key') {
      this.dialogTitle = $r('app.string.translate_ms_key')
      this.inputValue = appSettings.translate_ms_key
    } else if (kind === 'baidu_appid') {
      this.dialogTitle = $r('app.string.translate_baidu_appid')
      this.inputValue = appSettings.translate_baidu_appid
    } else if (kind === 'baidu_key') {
      this.dialogTitle = $r('app.string.translate_baidu_key')
      this.inputValue = appSettings.translate_baidu_key
    } else if (kind === 'youdao_appid') {
      this.dialogTitle = $r('app.string.translate_youdao_appid')
      this.inputValue = appSettings.translate_youdao_appid
    } else {
      this.dialogTitle = $r('app.string.translate_youdao_secret')
      this.inputValue = appSettings.translate_youdao_secret
    }
    this.editDialog?.open()
  }

  private confirmEdit(): void {
    const v: string = this.inputValue.trim()
    if (this.dialogKind === 'deepl_key') {
      appSettings.translate_deepl_key = v
    } else if (this.dialogKind === 'libre_url') {
      appSettings.translate_libre_url = v
    } else if (this.dialogKind === 'libre_key') {
      appSettings.translate_libre_key = v
    } else if (this.dialogKind === 'ms_key') {
      appSettings.translate_ms_key = v
    } else if (this.dialogKind === 'baidu_appid') {
      appSettings.translate_baidu_appid = v
    } else if (this.dialogKind === 'baidu_key') {
      appSettings.translate_baidu_key = v
    } else if (this.dialogKind === 'youdao_appid') {
      appSettings.translate_youdao_appid = v
    } else if (this.dialogKind === 'youdao_secret') {
      appSettings.translate_youdao_secret = v
    }
    this.refreshValues()
  }

  private initDialog(): void {
    this.editDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: this.dialogTitle,
        contentBuilder: (): void => {
          this.dialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.confirm')], false,
          (index: number): void => {
            if (index === 1) {
              this.confirmEdit()
            }
            this.editDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.translate_settings'),
      sections: this.sections,
      onShown: (): void => {
        this.refreshValues()
      },
      footer: (): void => {
        this.pageFooter()
      }
    })
  }

  @Builder
  pageFooter() {
    Row()
      .height(1)
      .width('100%')
      .bindSheet(this.showPicker!!, this.pickerBuilder(), {
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
  dialogContent() {
    TextInput({ placeholder: this.inputPlaceholder(), text: this.inputValue })
      .height(44)
      .fontSize(15)
      .onChange((v: string): void => {
        this.inputValue = v
      })
  }
}
