import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer, NaviBarButton } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../../components/CusItemBuilder';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../../components/SheetPicker';
import { buildDialogButtons } from '../../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../../common/utils/ResourceUtil';
import { ColorUtils } from '../../../../common/utils/ColorUtils';
import SiteSettingInfo from '../../../../common/entity/SiteSettingInfo';
import { appSettings } from '../../../../common/entity/SettingsModel';
import { tabsVM } from '../../../../viewmodel/TabsViewModel';
import { UaUtils } from '../../../../common/utils/UaUtils';
import { SiteItemConfig, SiteOpt, SiteSettingsViewModel, siteSettingsVM } from '../../../../viewmodel/SiteSettingsViewModel';

/** 字体大小项 key（专属布局：强制缩放 + 全局滑条 + 例外列表） */
const FONT_SIZE_KEY = 'site_font_size'
/** 浏览器标识项 key（专属布局：应用标识入口 + 例外列表） */
const UA_KEY = 'site_ua'
/** 显示图片项 key（高级-无图模式开启时置灰） */
const IMAGE_KEY = 'site_image'
/** Cookies 项 key（专属布局：全局双开关，无例外列表） */
const COOKIES_KEY = 'site_cookies'
/** 网页振动项 key（专属布局：全局单开关，无例外列表） */
const VIBRATION_KEY = 'site_vibration'
/** 弹出式窗口项 key（专属布局：全局开关，未开启时需先询问；无例外列表） */
const POPUP_KEY = 'site_popup'
/** 无痕模式项 key（全局默认即「默认无痕浏览」开关，与隐私设置联动） */
const INCOGNITO_KEY = 'site_incognito'

@Builder
export function SettingsSiteItemBuilder() {
  SiteItemPage()
}

@ComponentV2
struct SiteItemPage {

  @Local config: SiteItemConfig | null = null
  @Local itemKey: string = ''
  @Local defaultItem: CustomItemInfo = new CustomItemInfo({ id: 'default', type: ItemActionType.TEXT })
  @Local hapticItem: CustomItemInfo = new CustomItemInfo({ id: 'haptic', type: ItemActionType.TEXT })
  @Local overrides: SiteSettingInfo[] = []
  @Local showPicker: boolean = false
  @Local picker: PickerConfig = new PickerConfig()
  @Local pickerHeight: number = 0
  @Local inputSite: string = ''
  // 字体大小专属：强制缩放开关 + 全局缩放滑条
  @Local forceZoomItem: CustomItemInfo = new CustomItemInfo({ id: 'force_zoom', type: ItemActionType.TOGGLE })
  // Cookies 专属：拦截第三方开关
  @Local thirdPartyItem: CustomItemInfo = new CustomItemInfo({ id: 'cookies_third', type: ItemActionType.TOGGLE })
  @Local globalFontCustom: number = 100
  // 例外站点字体编辑半模态
  @Local showFontSheet: boolean = false
  @Local editSite: string = ''
  @Local editFollowGlobal: boolean = true
  @Local editFontCustom: number = 100

  private addDialog: CustomDialogController | undefined = undefined

  private get isFont(): boolean {
    return this.itemKey === FONT_SIZE_KEY
  }

  private get isUa(): boolean {
    return this.itemKey === UA_KEY
  }

  private get isImage(): boolean {
    return this.itemKey === IMAGE_KEY
  }

  private get isCookies(): boolean {
    return this.itemKey === COOKIES_KEY
  }

  private get isVibration(): boolean {
    return this.itemKey === VIBRATION_KEY
  }

  private get isPopup(): boolean {
    return this.itemKey === POPUP_KEY
  }

  /** 显示图片：高级-无图模式开启时置灰不可设置 */
  private imageLocked(): boolean {
    return this.isImage && appSettings.no_image_mode
  }

  /** 置灰行公共属性（enabled + 点击提示） */
  private applyLock(item: CustomItemInfo): void {
    if (this.imageLocked()) {
      item.enabled = false
      item.disabledHint = $r('app.string.site_image_disabled_hint')
    }
  }

  build() {
    NaviContainer({
      title: this.config !== null ? this.config.title : '',
      buttons: this.isCookies || this.isVibration || this.isPopup ? [] : [
        new NaviBarButton({
          symbol: $r('sys.symbol.plus'),
          action: (): void => {
            if (this.imageLocked()) {
              toastUtil.showToast({ message: $r('app.string.site_image_disabled_hint') })
              return
            }
            this.addDialog?.open()
          }
        })
      ],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        const key: string = ctx.pathInfo.param as string
        const config: SiteItemConfig | null = SiteSettingsViewModel.config(key)
        if (config === null) {
          return
        }
        this.itemKey = key
        this.config = config
        this.initAddDialog()
        this.loadOverrides()
      },
      onShown: (): void => {
        if (this.itemKey !== '') {
          this.loadOverrides()
        }
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  private initAddDialog(): void {
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

  private doAdd(): void {
    if (this.imageLocked()) {
      toastUtil.showToast({ message: $r('app.string.site_image_disabled_hint') })
      return
    }
    const site: string = this.inputSite.trim().toLowerCase()
    if (site === '') {
      toastUtil.showToast({ message: $r('app.string.site_site_invalid') })
      return
    }
    if (site.startsWith('http://') || site.startsWith('https://')) {
      toastUtil.showToast({ message: $r('app.string.site_site_invalid') })
      return
    }
    for (const o of this.overrides) {
      if (o.site === site) {
        toastUtil.showToast({ message: $r('app.string.site_site_exists') })
        return
      }
    }
    // 字体/浏览器标识：新例外先占位「跟随全局」，点击行再设置档位
    const placeholder: string = this.isFont || this.isUa
      ? 'global' : SiteSettingsViewModel.getDefault(this.itemKey)
    siteSettingsVM.setOverride(site, this.itemKey, placeholder).then((): void => {
      this.loadOverrides()
    })
  }

  private loadOverrides(): void {
    const config: SiteItemConfig | null = this.config
    if (config === null) {
      return
    }
    // Cookies：全局双开关专属布局，无默认档行与例外列表
    if (this.isCookies) {
      this.buildCookiesItems()
      return
    }
    // 网页振动：全局单开关专属布局（无站点例外）
    if (this.isVibration) {
      this.buildVibrationItem()
      return
    }
    // 弹出式窗口：全局开关专属布局（未开启时需先询问；无站点例外）
    if (this.isPopup) {
      this.buildPopupItem()
      return
    }
    this.buildDefaultItem(config)
    this.applyLock(this.defaultItem)
    if (this.isFont) {
      this.globalFontCustom = Number(SiteSettingsViewModel.getDefault(this.itemKey))
    }
    siteSettingsVM.listByKey(this.itemKey).then((list: SiteSettingInfo[]): void => {
      this.overrides = list
    })
  }

  private buildDefaultItem(config: SiteItemConfig): void {
    // 字体大小：无默认档行，页面为专属布局（强制缩放 + 滑条）
    if (this.isFont) {
      this.buildForceZoomItem()
      return
    }
    // 无痕模式：全局默认即「默认无痕浏览」开关（与隐私设置联动，变更应用到全部标签）
    if (this.itemKey === INCOGNITO_KEY) {
      this.defaultItem = new CustomItemInfo({
        id: 'default',
        title: $r('app.string.site_default'),
        type: ItemActionType.TOGGLE,
        value: appSettings.default_incognito,
        onChange: (v: string | boolean | number): void => {
          const target = v === true
          appSettings.default_incognito = target
          tabsVM.applyGlobalIncognito(target)
          this.buildDefaultItem(config)
        }
      })
      return
    }
    // 浏览器标识：全局即应用 UA，入口跳 UA 设置页
    if (this.isUa) {
      const name: ResourceStr = UaUtils.presetName(appSettings.ua_mode)
      this.defaultItem = new CustomItemInfo({
        id: 'default',
        title: $r('app.string.site_ua'),
        type: ItemActionType.ROUTER,
        value: typeof name === 'string' ? name : ResourceUtils.getString(name as Resource),
        onChange: (v: string | boolean | number): void => {
          QhState.pushPage('settings_ua', null)
        }
      })
      return
    }
    const def: string = SiteSettingsViewModel.getDefault(this.itemKey)
    if (config.isToggle) {
      this.defaultItem = new CustomItemInfo({
        id: 'default',
        title: $r('app.string.site_default'),
        type: ItemActionType.TOGGLE,
        value: def === 'on',
        onChange: (v: string | boolean | number): void => {
          SiteSettingsViewModel.setDefault(this.itemKey, v === true ? 'on' : 'off')
          this.buildDefaultItem(config)
        }
      })
    } else {
      this.defaultItem = new CustomItemInfo({
        id: 'default',
        title: $r('app.string.site_default'),
        subtitle: this.itemKey === 'site_image' ? $r('app.string.site_image_desc') : '',
        type: ItemActionType.TEXT,
        value: SiteSettingsViewModel.labelOf(config, def),
        onChange: (v: string | boolean | number): void => {
          this.openPicker(ResourceUtils.getString($r('app.string.site_default')), def, (val: string): void => {
            SiteSettingsViewModel.setDefault(this.itemKey, val)
            this.buildDefaultItem(config)
          })
        }
      })
    }
  }

  private buildForceZoomItem(): void {
    this.forceZoomItem = new CustomItemInfo({
      id: 'force_zoom',
      title: $r('app.string.force_enable_zoom'),
      subtitle: $r('app.string.force_enable_zoom_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.force_enable_zoom,
      onChange: (v: string | boolean | number): void => {
        appSettings.force_enable_zoom = v === true
      }
    })
  }

  /** Cookies 专属：总开关 + 拦截第三方（总开关关闭时置灰） */
  private buildCookiesItems(): void {
    this.defaultItem = new CustomItemInfo({
      id: 'cookies_main',
      title: $r('app.string.site_cookies'),
      subtitle: $r('app.string.cookies_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.cookies_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.cookies_enabled = v === true
        this.buildCookiesItems()
      }
    })
    this.thirdPartyItem = new CustomItemInfo({
      id: 'cookies_third',
      title: $r('app.string.cookies_block_third_party'),
      type: ItemActionType.TOGGLE,
      value: appSettings.cookies_block_third_party,
      enabled: appSettings.cookies_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.cookies_block_third_party = v === true
      }
    })
  }

  /** 网页振动专属：全局双开关（无站点例外）；长按选择振动在网页振动开启时被强制开启、置灰 */
  private buildVibrationItem(): void {
    this.defaultItem = new CustomItemInfo({
      id: 'web_vibration',
      title: $r('app.string.web_vibration'),
      subtitle: $r('app.string.web_vibration_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_vibration_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_vibration_enabled = v === true
        this.hapticItem.enabled = v !== true
      }
    })
    this.hapticItem = new CustomItemInfo({
      id: 'web_haptic',
      title: $r('app.string.web_haptic'),
      subtitle: $r('app.string.web_haptic_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_haptic_enabled,
      enabled: !appSettings.web_vibration_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_haptic_enabled = v === true
      }
    })
  }

  /** 弹出式窗口专属：全局开关（提示文字在卡片下方，随开关联动；无站点例外） */
  private buildPopupItem(): void {
    this.defaultItem = new CustomItemInfo({
      id: 'popup',
      title: $r('app.string.site_popup'),
      type: ItemActionType.TOGGLE,
      value: appSettings.popup_allowed,
      onChange: (v: string | boolean | number): void => {
        appSettings.popup_allowed = v === true
      }
    })
  }

  private overrideItem(o: SiteSettingInfo): CustomItemInfo {
    const item: CustomItemInfo = this.buildOverrideItem(o)
    this.applyLock(item)
    return item
  }

  private buildOverrideItem(o: SiteSettingInfo): CustomItemInfo {
    const config: SiteItemConfig | null = this.config
    if (config === null) {
      return new CustomItemInfo({ id: o.id?.toString() ?? o.site, title: o.site, type: ItemActionType.TEXT })
    }
    const menuItems: ContextMenuItem[] = [
      new ContextMenuItem($r('app.string.delete'), (): void => {
        this.removeOverride(o)
      }, undefined, true)
    ]
    // 字体大小例外：点击行打开站点字体半模态
    if (this.isFont) {
      return new CustomItemInfo({
        id: `${o.site}`,
        title: o.site,
        type: ItemActionType.TEXT,
        value: this.fontLabel(o.value),
        contextMenuItems: menuItems,
        onChange: (v: string | boolean | number): void => {
          this.openFontSheet(o)
        }
      })
    }
    if (config.isToggle) {
      return new CustomItemInfo({
        id: `${o.site}`,
        title: o.site,
        type: ItemActionType.TOGGLE,
        value: o.value === 'on',
        contextMenuItems: menuItems,
        onChange: (v: string | boolean | number): void => {
          o.value = v === true ? 'on' : 'off'
          siteSettingsVM.setOverride(o.site, this.itemKey, o.value).then((): void => {
            this.loadOverrides()
          })
        }
      })
    }
    return new CustomItemInfo({
      id: `${o.site}`,
      title: o.site,
      type: ItemActionType.TEXT,
      value: SiteSettingsViewModel.labelOf(config, o.value),
      contextMenuItems: menuItems,
      onChange: (v: string | boolean | number): void => {
        this.openPicker(o.site, o.value, (val: string): void => {
          o.value = val
          siteSettingsVM.setOverride(o.site, this.itemKey, val).then((): void => {
            this.loadOverrides()
          })
        })
      }
    })
  }

  /** 字体大小例外行右侧文案 */
  private fontLabel(value: string): string {
    if (value === 'global') {
      return ResourceUtils.getString($r('app.string.site_opt_follow_global'))
    }
    const n: number = Number(value)
    return Number.isNaN(n) ? value : `${n}%`
  }

  private openFontSheet(o: SiteSettingInfo): void {
    const custom: boolean = o.value !== 'global' && !Number.isNaN(Number(o.value))
    this.editSite = o.site
    this.editFollowGlobal = !custom
    this.editFontCustom = custom ? Number(o.value) : this.globalFontCustom
    this.showFontSheet = true
  }

  /** 例外站点编辑：跟随全局 ⇄ 自定义缩放 */
  private toggleEditFollowGlobal(): void {
    if (this.editFollowGlobal) {
      siteSettingsVM.setOverride(this.editSite, FONT_SIZE_KEY, `${this.editFontCustom}`).then((): void => {
        this.editFollowGlobal = false
        this.loadOverrides()
      })
    } else {
      siteSettingsVM.setOverride(this.editSite, FONT_SIZE_KEY, 'global').then((): void => {
        this.editFollowGlobal = true
        this.loadOverrides()
      })
    }
  }

  private removeOverride(o: SiteSettingInfo): void {
    siteSettingsVM.removeOverride(o.site, this.itemKey).then((): void => {
      this.loadOverrides()
    })
  }

  private openPicker(title: string, selected: string, onSelect: (v: string) => void): void {
    const config: SiteItemConfig | null = this.config
    if (config === null) {
      return
    }
    // 浏览器标识：档位来自全局 UA 列表（预置 + 自定义）
    const opts: SiteOpt[] = config.key === UA_KEY ? SiteSettingsViewModel.uaOptions() : config.options
    const options: PickerOption[] = []
    for (const opt of opts) {
      options.push(new PickerOption(opt.value, opt.label))
    }
    this.picker.title = title
    this.picker.options = options
    this.picker.selected = selected
    this.picker.onSelect = onSelect
    this.pickerHeight = pickerSheetHeight(options.length)
    this.showPicker = true
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
  pageContent() {
    if (this.isCookies) {
      this.cookiesContent()
    } else if (this.isVibration) {
      this.vibrationContent()
    } else if (this.isPopup) {
      this.popupContent()
    } else if (this.isFont) {
      this.fontContent()
    } else {
      this.genericContent()
    }
  }

  /** 全局开关专属页（网页振动/弹出式窗口：单开关，无例外网站） */
  @Builder
  vibrationContent() {
    List() {
      ListItem() {
        CustomListItem({
          item: this.defaultItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 保留长按选择振动（网页振动开启时置灰）
      ListItem() {
        CustomListItem({
          item: this.hapticItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }

  /** Cookies 专属页：全局双开关（无例外网站） */
  @Builder
  cookiesContent() {
    List() {
      // Cookies 总开关
      ListItem() {
        CustomListItem({
          item: this.defaultItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 拦截第三方 Cookies（总开关关闭时置灰）
      ListItem() {
        CustomListItem({
          item: this.thirdPartyItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }

  /** 弹出式窗口专属页：全局开关 + 卡片下方说明文字（随开关联动） */
  @Builder
  popupContent() {
    List() {
      ListItem() {
        CustomListItem({
          item: this.defaultItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 状态说明：未开启需先询问，开启后可直接弹出
      ListItem() {
        Text(appSettings.popup_allowed
          ? $r('app.string.popup_allowed_desc') : $r('app.string.popup_ask_desc'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .lineHeight(19)
      }
      .width('100%')
      .align(Alignment.Start)
      .padding({ left: 6, right: 6 })
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

  /** 字体大小专属页：强制缩放 + 全局滑条 + 预览 + 例外网站 */
  @Builder
  fontContent() {
    List() {
      // 强制缩放（应用级）
      ListItem() {
        CustomListItem({
          item: this.forceZoomItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 全局字体缩放滑条 + 效果预览
      ListItem() {
        Column({ space: 10 }) {
          Row() {
            Text(`${SiteSettingsViewModel.FONT_MIN}%`)
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text(`${this.globalFontCustom}%`)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(`${SiteSettingsViewModel.FONT_MAX}%`)
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')

          Slider({
            value: this.globalFontCustom,
            min: SiteSettingsViewModel.FONT_MIN,
            max: SiteSettingsViewModel.FONT_MAX,
            step: 5,
            style: SliderStyle.InSet
          })
            .selectedColor(QhState.currentThemeColor)
            .blockColor(QhState.currentThemeColor)
            .onChange((v: number, mode: SliderChangeMode): void => {
              const rounded: number = Math.round(v)
              this.globalFontCustom = rounded
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                SiteSettingsViewModel.setDefault(FONT_SIZE_KEY, `${rounded}`)
              }
            })

          Text($r('app.string.site_font_preview'))
            .fontSize(SiteSettingsViewModel.PREVIEW_BASE * this.globalFontCustom / 100)
            .fontColor($r('sys.color.font_primary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .borderRadius(12)
        }
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 12 })

      // 例外网站
      if (this.overrides.length > 0) {
        ListItem() {
          Text($r('app.string.site_exceptions'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .margin({ left: 4, top: 18, bottom: 6 })
        }
        Repeat<SiteSettingInfo>(this.overrides)
          .each((ri: RepeatItem<SiteSettingInfo>) => {
            ListItem() {
              CustomListItem({
                item: this.overrideItem(ri.item),
                itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
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
                  this.swipeEndBuilder(ri.item)
                }
              }
            })
          })
          .key((o: SiteSettingInfo) => `${o.site}|${o.value}`)
      } else {
        ListItem() {
          Text($r('app.string.site_exceptions_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .margin({ left: 4, top: 18, bottom: 6 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
    .bindSheet(this.showFontSheet!!, this.fontSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showFontSheet = false
      }
    })
  }

  /** 例外站点字体半模态（同详情页样式：跟随全局开关 + 滑条 + 预览） */
  @Builder
  fontSheetBuilder() {
    Column() {
      Text(this.editSite)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .height(48)

      // 跟随全局（整行可点击）
      Row() {
        Text($r('app.string.site_opt_follow_global'))
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.editFollowGlobal })
          .selectedColor(QhState.currentThemeColor)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height(52)
      .padding({ left: 24, right: 24 })
      .onClick(() => {
        this.toggleEditFollowGlobal()
      })

      // 自定义滑条（跟随全局时置灰、不可拖动，滑块停在全局生效值）
      Column({ space: 10 }) {
        Row() {
          Text(`${SiteSettingsViewModel.FONT_MIN}%`)
            .fontSize(12)
            .fontColor(this.editFollowGlobal
              ? ColorUtils.getUnableColor($r('sys.color.font_secondary')) : $r('sys.color.font_secondary'))
          Blank()
          Text(`${this.editFontCustom}%`)
            .fontSize(14)
            .fontColor(this.editFollowGlobal
              ? ColorUtils.getUnableColor($r('sys.color.font_primary')) : $r('sys.color.font_primary'))
          Blank()
          Text(`${SiteSettingsViewModel.FONT_MAX}%`)
            .fontSize(12)
            .fontColor(this.editFollowGlobal
              ? ColorUtils.getUnableColor($r('sys.color.font_secondary')) : $r('sys.color.font_secondary'))
        }
        .width('100%')

        Slider({
          value: this.editFontCustom,
          min: SiteSettingsViewModel.FONT_MIN,
          max: SiteSettingsViewModel.FONT_MAX,
          step: 5,
          style: SliderStyle.InSet
        })
          .selectedColor(this.editFollowGlobal
            ? ColorUtils.getUnableColor(QhState.currentThemeColor) : QhState.currentThemeColor)
          .blockColor(this.editFollowGlobal
            ? ColorUtils.getUnableColor(QhState.currentThemeColor) : QhState.currentThemeColor)
          .enabled(!this.editFollowGlobal)
          .onChange((v: number, mode: SliderChangeMode): void => {
            const rounded: number = Math.round(v)
            this.editFontCustom = rounded
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              siteSettingsVM.setOverride(this.editSite, FONT_SIZE_KEY, `${rounded}`).then((): void => {
                this.editFollowGlobal = false
                this.loadOverrides()
              })
            }
          })

        // 字体效果预览
        Text($r('app.string.site_font_preview'))
          .fontSize(SiteSettingsViewModel.PREVIEW_BASE * this.editFontCustom / 100)
          .fontColor(this.editFollowGlobal
            ? ColorUtils.getUnableColor($r('sys.color.font_primary')) : $r('sys.color.font_primary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 14, bottom: 14 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 16 })
    }
    .width('100%')
    .padding({ bottom: 8 + QhState.bottomRectHeight })
  }

  /** 通用布局：默认值行 + 例外网站 */
  @Builder
  genericContent() {
    List() {
      // 默认值
      ListItem() {
        CustomListItem({
          item: this.defaultItem,
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 例外网站
      if (this.overrides.length > 0) {
        ListItem() {
          Text($r('app.string.site_exceptions'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .margin({ left: 4, top: 18, bottom: 6 })
        }
        Repeat<SiteSettingInfo>(this.overrides)
          .each((ri: RepeatItem<SiteSettingInfo>) => {
            ListItem() {
              CustomListItem({
                item: this.overrideItem(ri.item),
                itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
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
                  this.swipeEndBuilder(ri.item)
                }
              }
            })
          })
          .key((o: SiteSettingInfo) => `${o.site}|${o.value}`)
      } else {
        ListItem() {
          Text($r('app.string.site_exceptions_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .margin({ left: 4, top: 18, bottom: 6 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
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
  swipeEndBuilder(o: SiteSettingInfo) {
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
      this.removeOverride(o)
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
