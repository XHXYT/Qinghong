import { NaviContainer, NaviBarButton } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../../components/CusItemBuilder';
import { PickerConfig, PickerOption, pickerSheetHeight, SheetPicker } from '../../../../components/SheetPicker';
import { toastUtil } from '../../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../../common/utils/ResourceUtil';
import { ColorUtils } from '../../../../common/utils/ColorUtils';
import SiteSettingInfo from '../../../../common/entity/SiteSettingInfo';
import { appSettings } from '../../../../common/entity/SettingsModel';
import { SiteItemConfig, SiteOpt, SiteSettingsViewModel, siteSettingsVM } from '../../../../viewmodel/SiteSettingsViewModel';

/** 字体大小项 key（点击打开专属半模态：跟随全局开关 + 自定义滑条 + 预览） */
const FONT_SIZE_KEY = 'site_font_size'
/** 自定义字体缩放下限（%） */
const FONT_MIN = 90
/** 自定义字体缩放上限（%） */
const FONT_MAX = 130
/** 预览基准字号 */
const PREVIEW_BASE = 16

/** 详情页分组（与主设定页分类一致） */
class DetailGroup {
  readonly key: string
  readonly title: ResourceStr
  readonly items: SiteItemConfig[] = []

  constructor(key: string, title: ResourceStr) {
    this.key = key
    this.title = title
  }
}

@Builder
export function SettingsSiteDetailBuilder() {
  SiteDetailPage()
}

@ComponentV2
struct SiteDetailPage {

  @Local site: string = ''
  @Local groups: DetailGroup[] = []
  @Local siteEnabled: boolean = true
  @Local enabledItem: CustomItemInfo = new CustomItemInfo({ id: 'site_enabled', type: ItemActionType.TOGGLE })
  @Local fontFollowGlobal: boolean = true
  @Local fontSizeCustom: number = 100
  @Local showSheet: boolean = false
  @Local sheetMode: string = ''
  @Local picker: PickerConfig = new PickerConfig()
  @Local pickerHeight: number = 0

  /** 行组件缓存（key → CustomItemInfo，@Trace 原地更新，规避 keyed Repeat 不刷新问题） */
  private itemCache: Map<string, CustomItemInfo> = new Map()
  /** 当前站点覆盖表（key → 覆盖行） */
  private overrideMap: Map<string, SiteSettingInfo> = new Map()

  build() {
    NaviContainer({
      title: this.site,
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.trash'),
          action: (): void => {
            this.confirmDeleteSite()
          }
        })
      ],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.site = ctx.pathInfo.param as string
        this.buildGroups()
        this.load()
      },
      onShown: (): void => {
        if (this.site !== '') {
          this.load()
        }
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  /** 分组结构仅构建一次（静态配置），数据变化靠行组件 @Trace 原地刷新 */
  private buildGroups(): void {
    const groups: DetailGroup[] = []
    for (const g of SiteSettingsViewModel.groups()) {
      const dg: DetailGroup = new DetailGroup(g.key, g.title)
      for (const cfg of g.items) {
        // Cookies / 网页振动为全局开关，无按站点语义，不在站点详情页展示
        if (cfg.key === 'site_cookies' || cfg.key === 'site_vibration') {
          continue
        }
        dg.items.push(cfg)
      }
      groups.push(dg)
    }
    this.groups = groups
  }

  private load(): void {
    siteSettingsVM.isSiteEnabled(this.site).then((enabled: boolean): void => {
      this.siteEnabled = enabled
      this.buildEnabledItem()
    })
    siteSettingsVM.listBySite(this.site).then((all: SiteSettingInfo[]): void => {
      if (all.length === 0) {
        // 整站设置已被清空，自动返回
        QhState.popPage()
        return
      }
      const map: Map<string, SiteSettingInfo> = new Map()
      for (const r of all) {
        if (r.key !== SiteSettingsViewModel.SITE_ENABLED_KEY) {
          map.set(r.key, r)
        }
      }
      this.overrideMap = map
      this.syncItems()
    })
  }

  /** 数据落地后原地刷新全部行 */
  private syncItems(): void {
    for (const g of this.groups) {
      for (const cfg of g.items) {
        this.syncItem(cfg)
      }
    }
    this.syncFontSize()
  }

  private syncItem(cfg: SiteItemConfig): void {
    const o: SiteSettingInfo | null = this.overrideMap.get(cfg.key) ?? null
    const effective: string = o !== null ? o.value : SiteSettingsViewModel.getDefault(cfg.key)
    const item: CustomItemInfo = this.itemOf(cfg)
    if (cfg.key === FONT_SIZE_KEY) {
      // 无覆盖 = 跟随全局（与半模态开关状态一致），有覆盖显示覆盖值
      item.value = o === null
        ? ResourceUtils.getString($r('app.string.site_opt_follow_global'))
        : this.fontLabel(o.value)
    } else {
      item.value = cfg.isToggle ? effective === 'on' : SiteSettingsViewModel.labelOf(cfg, effective)
    }
    item.enabled = this.siteEnabled
    // 显示图片：高级-无图模式开启时置灰不可设置
    if (cfg.key === 'site_image' && appSettings.no_image_mode) {
      item.enabled = false
      item.disabledHint = $r('app.string.site_image_disabled_hint')
    }
    item.contextMenuItems = this.siteEnabled && o !== null ? this.menuItemsOf(cfg.key) : undefined
  }

  /** 取或建行组件（回调创建一次，运行时读 overrideMap 最新值） */
  private itemOf(cfg: SiteItemConfig): CustomItemInfo {
    const cached: CustomItemInfo | undefined = this.itemCache.get(cfg.key)
    if (cached !== undefined) {
      return cached
    }
    const item: CustomItemInfo = new CustomItemInfo({
      id: cfg.key,
      title: cfg.title,
      type: cfg.isToggle ? ItemActionType.TOGGLE : ItemActionType.TEXT,
      onChange: (v: string | boolean | number): void => {
        if (cfg.isToggle) {
          siteSettingsVM.setOverride(this.site, cfg.key, v === true ? 'on' : 'off').then((): void => {
            this.load()
          })
        } else if (cfg.key === FONT_SIZE_KEY) {
          this.openFontSheet()
        } else {
          this.openPicker(cfg)
        }
      }
    })
    this.itemCache.set(cfg.key, item)
    return item
  }

  private menuItemsOf(key: string): ContextMenuItem[] {
    return [
      new ContextMenuItem($r('app.string.delete'), (): void => {
        siteSettingsVM.removeOverride(this.site, key).then((): void => {
          this.load()
        })
      }, undefined, true)
    ]
  }

  /** 字体大小行右侧文案 */
  private fontLabel(effective: string): string {
    if (effective === 'global') {
      return ResourceUtils.getString($r('app.string.site_opt_follow_global'))
    }
    const n: number = Number(effective)
    return Number.isNaN(n) ? effective : `${n}%`
  }

  private syncFontSize(): void {
    const o: SiteSettingInfo | null = this.overrideMap.get(FONT_SIZE_KEY) ?? null
    const effective: string = o !== null ? o.value : SiteSettingsViewModel.getDefault(FONT_SIZE_KEY)
    // 无覆盖 = 跟随全局；覆盖 'global' = 显式跟随全局
    this.fontFollowGlobal = o === null || o.value === 'global'
    if (this.fontFollowGlobal) {
      // 滑条停在全局生效值（切自定义时的初值）
      this.fontSizeCustom = Number(SiteSettingsViewModel.getDefault(FONT_SIZE_KEY))
    } else {
      this.fontSizeCustom = Number(effective)
    }
  }

  private buildEnabledItem(): void {
    this.enabledItem = new CustomItemInfo({
      id: 'site_enabled',
      title: ResourceUtils.getStringWithArgs($r('app.string.site_enable_settings'), [this.site]),
      type: ItemActionType.TOGGLE,
      value: this.siteEnabled,
      onChange: (v: string | boolean | number): void => {
        const enabled: boolean = v === true
        this.siteEnabled = enabled
        siteSettingsVM.setSiteEnabled(this.site, enabled).then((): void => {
          this.load()
        })
      }
    })
  }

  private openPicker(cfg: SiteItemConfig): void {
    const o: SiteSettingInfo | null = this.overrideMap.get(cfg.key) ?? null
    // 浏览器标识：档位来自全局 UA 列表（预置 + 自定义）
    const opts: SiteOpt[] = cfg.key === 'site_ua' ? SiteSettingsViewModel.uaOptions() : cfg.options
    const options: PickerOption[] = []
    for (const opt of opts) {
      options.push(new PickerOption(opt.value, opt.label))
    }
    this.picker.title = cfg.title
    this.picker.options = options
    this.picker.selected = o !== null ? o.value : SiteSettingsViewModel.getDefault(cfg.key)
    this.picker.onSelect = (val: string): void => {
      siteSettingsVM.setOverride(this.site, cfg.key, val).then((): void => {
        this.load()
      })
    }
    this.pickerHeight = pickerSheetHeight(options.length)
    this.sheetMode = 'picker'
    this.showSheet = true
  }

  private openFontSheet(): void {
    this.syncFontSize()
    this.sheetMode = 'font'
    this.showSheet = true
  }

  /** 切换跟随全局：开启存 'global'（与例外编辑一致，解析为全局默认行），关闭以当前滑条值建档 */
  private toggleFollowGlobal(): void {
    if (this.fontFollowGlobal) {
      siteSettingsVM.setOverride(this.site, FONT_SIZE_KEY, `${this.fontSizeCustom}`).then((): void => {
        this.load()
      })
    } else {
      siteSettingsVM.setOverride(this.site, FONT_SIZE_KEY, 'global').then((): void => {
        this.load()
      })
    }
  }

  private confirmDeleteSite(): void {
    toastUtil.showAlertDialog({
      title: this.site,
      message: $r('app.string.site_delete_site_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            siteSettingsVM.removeSite(this.site).then((): void => {
              QhState.popPage()
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
    }, 'deleteSiteAll')
  }

  @Builder
  pageContent() {
    List() {
      // 启用/停用该站点的设定
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

      // 分组全量渲染（与主设定页一致）
      Repeat<DetailGroup>(this.groups)
        .each((ri: RepeatItem<DetailGroup>) => {
          ListItem() {
            Column() {
              Text(ri.item.title)
                .fontSize(14)
                .fontColor($r('sys.color.font_secondary'))
                .margin({ left: 4, bottom: 6, top: 18 })
              Column() {
                Repeat<SiteItemConfig>(ri.item.items)
                  .each((r2: RepeatItem<SiteItemConfig>) => {
                    CustomListItem({
                      item: this.itemOf(r2.item),
                      itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                    })
                  })
                  .key((cfg: SiteItemConfig) => cfg.key)
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
        .key((g: DetailGroup) => g.key)
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
    .bindSheet(this.showSheet!!, this.sheetBuilder(), {
      preferType: SheetType.CENTER,
      height: this.sheetMode === 'font' ? SheetSize.FIT_CONTENT : this.pickerHeight,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showSheet = false
      }
    })
  }

  @Builder
  sheetBuilder() {
    if (this.sheetMode === 'font') {
      this.fontSizeSheet()
    } else {
      SheetPicker({
        config: this.picker,
        close: (): void => {
          this.showSheet = false
        }
      })
    }
  }

  /** 字体大小专属半模态：跟随全局开关 + 自定义滑条 + 效果预览（跟随全局时下方置灰、滑块停在全局生效值） */
  @Builder
  fontSizeSheet() {
    Column() {
      Text($r('app.string.site_font_size'))
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
        Toggle({ type: ToggleType.Switch, isOn: this.fontFollowGlobal })
          .selectedColor(QhState.currentThemeColor)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height(52)
      .padding({ left: 24, right: 24 })
      .onClick(() => {
        this.toggleFollowGlobal()
      })

      // 自定义滑条（跟随全局时置灰、不可拖动，滑块停在全局生效值）
      Column({ space: 10 }) {
        Row() {
          Text(`${FONT_MIN}%`)
            .fontSize(12)
            .fontColor(this.fontFollowGlobal
              ? ColorUtils.getUnableColor($r('sys.color.font_secondary')) : $r('sys.color.font_secondary'))
          Blank()
          Text(`${this.fontSizeCustom}%`)
            .fontSize(14)
            .fontColor(this.fontFollowGlobal
              ? ColorUtils.getUnableColor($r('sys.color.font_primary')) : $r('sys.color.font_primary'))
          Blank()
          Text(`${FONT_MAX}%`)
            .fontSize(12)
            .fontColor(this.fontFollowGlobal
              ? ColorUtils.getUnableColor($r('sys.color.font_secondary')) : $r('sys.color.font_secondary'))
        }
        .width('100%')

        Slider({ value: this.fontSizeCustom, min: FONT_MIN, max: FONT_MAX, step: 5, style: SliderStyle.InSet })
          .selectedColor(this.fontFollowGlobal
            ? ColorUtils.getUnableColor(QhState.currentThemeColor) : QhState.currentThemeColor)
          .blockColor(this.fontFollowGlobal
            ? ColorUtils.getUnableColor(QhState.currentThemeColor) : QhState.currentThemeColor)
          .enabled(!this.fontFollowGlobal)
          .onChange((v: number, mode: SliderChangeMode): void => {
            this.fontSizeCustom = v
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              siteSettingsVM.setOverride(this.site, FONT_SIZE_KEY, `${v}`).then((): void => {
                this.load()
              })
            }
          })

        // 字体效果预览
        Text($r('app.string.site_font_preview'))
          .fontSize(PREVIEW_BASE * this.fontSizeCustom / 100)
          .fontColor(this.fontFollowGlobal
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
}
