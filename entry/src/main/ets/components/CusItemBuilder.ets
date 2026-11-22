import { CustomContentDialog, LengthMetrics, SymbolGlyphModifier } from "@kit.ArkUI"
import UIConstants from "../common/constants/UIConstants";
import { CustomItemInfo, ItemActionType, MenuOption, ContextMenuItem } from "../common/entity/CusItemInfo";
import { ColorUtils } from "../common/utils/ui/ColorUtils";
import { ButtonOptions } from "@ohos.arkui.advanced.Dialog"
import { toastUtil } from "../common/utils/ui/ToastUtils";
import { ResourceUtils } from "../common/utils/app/ResourceUtil";
import { QhState } from "../entryability/AppState";
import { appSettings, UISettings } from "../common/entity/SettingsModel";


@ComponentV2
export struct CustomListItem {

  @Require @Param item: CustomItemInfo
  @BuilderParam icon: CustomBuilder
  @BuilderParam dialogContent?: (data: CustomItemInfo) => void

  @Param itemPadding: Padding = { left: 0, right: 0, top: 0, bottom: 0 }

  @Local showMenu: boolean = false
  @Local showCtxMenu: boolean = false
  @Local dialogController: CustomDialogController | undefined

  aboutToAppear(): void {
    if (this.item.type == ItemActionType.DIALOG) {
      const dialogButtons: ButtonOptions[] =
        this.item.dialogConfig?.buttons?.map((btn: ResourceStr, index: number): ButtonOptions => {
          return {
            value: btn,
            buttonStyle: ButtonStyleMode.TEXTUAL,
            fontColor: this.item.isDanger && index == Number(this.item.dialogConfig?.buttons?.length) - 1 ? Color.Red : QhState.currentThemeColor,
            action: () => {
              if (this.item.dialogConfig?.onClick) {
                this.item.dialogConfig.onClick(btn, index, this.dialogController)
              } else {
                if (this.item.onChange && !this.item.dialogConfig?.buttons) {
                  this.item.onChange(index == 1)
                }
                this.dialogController?.close()
              }
            }
          }
        }) || [];

      const contentPadding: Padding = { top: 15, bottom: 15, left: 24, right: 24 };

      this.dialogController = new CustomDialogController({
        builder: CustomContentDialog({
          primaryTitle: this.item.title,
          secondaryTitle: this.item.subtitle,
          contentBuilder: (): void => {
            if (this.dialogContent) {
              this.dialogContent(this.item)
            }
          },
          buttons: dialogButtons,
          contentAreaPadding: contentPadding,
          themeColorMode: UISettings.color_mode + 1,
        }),
        autoCancel: true,
        alignment: DialogAlignment.Center,
        cornerRadius: 32,
        width: this.item.dialogConfig?.width,
        onWillAppear: () => {
          if (this.item.dialogConfig?.onWillAppear != null) {
            this.item.dialogConfig?.onWillAppear()
          }
        },
      })
    }
  }

  build() {
    Row({ space: 50 }) {
      Row({ space: 12 }) {
        if (this.icon) {
          this.icon()
        } else if (this.item.symbol) {
          SymbolGlyph(this.item.symbol)
            .fontColor([this.item.enabled ? this.item.isDanger ? Color.Red : this.item.iconColor : ColorUtils.getUnableColor(this.item.iconColor)])
            .fontSize(24)
        } else if (this.item.icon) {
          Image(this.item.icon)
            .width(25)
            .aspectRatio(1)
            .borderRadius(100)
        }

        Column({ space: 2 }) {
          if (this.item.type === ItemActionType.INPUT) {
            Text(this.item.title)
              .fontColor(this.item.enabled ? this.item.isDanger ? Color.Red : $r('sys.color.font_primary') : ColorUtils.getUnableColor($r('sys.color.font_primary')))
              .fontSize(12)
            TextInput({ text: this.item.value as ResourceStr, placeholder: this.item.subtitle })
              .type(InputType.Normal)
              .width('100%')
              .height(48)
              .borderRadius(8)
              .fontSize(14)
              .enabled(this.item.enabled)
              .onChange((v) => {
              this.item.value = v;
              if (this.item.onChange != null) {
                this.item.onChange(v)
              }
            })
          } else {
            Text(this.item.title)
              .fontColor(this.item.enabled ? this.item.isDanger ? Color.Red : $r('sys.color.font_primary') : ColorUtils.getUnableColor($r('sys.color.font_primary')))
              .fontSize(16)
              .fontFamily(appSettings.font_family)
            if (this.item.subtitle && this.item.type != ItemActionType.DIALOG) {
              Text(this.item.subtitle)
                .fontColor(this.item.enabled ? this.item.isDanger ? Color.Red : $r("sys.color.font_secondary") : ColorUtils.getUnableColor($r("sys.color.font_secondary")))
                .fontSize(12)
                .fontFamily(appSettings.font_family)
            }
          }
        }
        .enabled(this.item.enabled)
        .alignItems(HorizontalAlign.Start)
      }.layoutWeight(1)

      if (this.item.type !== ItemActionType.INPUT) {
        ListItemRightAction({
          item: this.item,
          onSliderChange: (v: number) => {
            this.item.value = v;
            if (this.item.onChange) {
              this.item.onChange(v)
            }
          }
        })
      }

    }
    .padding(this.itemPadding)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .bindMenu(
      this.showMenu,
      this.item.type == ItemActionType.MENU ? MenuSelectWitch(this.item, (menu) => {
        this.item.value = menu.value
        toastUtil.showToast({ message: `${ResourceUtils.getString(this.item.title)}切换为: ${ResourceUtils.getString(menu?.title || menu.value)}` })
      }) : undefined,
      {
        placement: Placement.BottomRight,
        backgroundBlurStyle: BlurStyle.NONE,
        onDisappear: () => {
          this.showMenu = false
        }
      })
    .width("100%")
    .onClick(() => {
      if (!this.item.enabled) {
        // 置灰行点击提示（如无图模式开启时的显示图片设置）
        if (this.item.disabledHint !== '') {
          toastUtil.showToast({ message: this.item.disabledHint })
        }
        return
      }
      if (this.showMenu) return
      if (this.item.type == ItemActionType.MENU) {
        this.showMenu = true
        return
      }

      if (this.item.type == ItemActionType.TOGGLE) {
        this.item.value = !this.item.value
      }

      if (this.item.type == ItemActionType.RADIO) {
        this.item.value = this.item.radioConfig?.value || ''
      }

      if (this.item.type == ItemActionType.CHECK) {
        this.item.value = !this.item.value
      }

      if (this.item.type == ItemActionType.DIALOG) {
        this.dialogController?.open()
      }

      if (this.item.onChange) this.item.onChange(this.item.value)
    })
    // 长按弹出上下文菜单（isShown 模式，ResponseType.LongPress 在部分场景识别器不注册）
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((event?: GestureEvent) => {
          if (!this.item.enabled) return
          if (this.item.contextMenuItems && this.item.contextMenuItems.length > 0) {
            this.showCtxMenu = !this.showCtxMenu
          }
        })
    )
    .bindContextMenu(this.showCtxMenu!!, this.ctxMenuBuilder(), {
      placement: this.item.contextMenuPlacement,
      onDisappear: (): void => {
        this.showCtxMenu = false
      }
    })
  }

  @Builder
  ctxMenuBuilder() {
    Menu() {
      ForEach(this.item.contextMenuItems ?? [], (mi: ContextMenuItem, index: number) => {
        MenuItem({
          content: mi.title,
          symbolStartIcon: mi.symbol !== undefined ? new SymbolGlyphModifier(mi.symbol) : undefined
        })
          .contentFontColor(mi.isDanger ? Color.Red : $r('sys.color.font_primary'))
          .onClick(() => {
            this.showCtxMenu = false
            mi.action()
          })
      }, (mi: ContextMenuItem, index: number) => `${index}`)
    }
    .backgroundColor($r("app.color.background_color"))
    .borderRadius(UIConstants.BORDER_RADIUS_20)
  }
}

// 右侧通用操作组件
@ComponentV2
export struct ListItemRightAction {
  @Require @Param item: CustomItemInfo
  @Event onSliderChange: (p: number) => void

  getMenuLabel(): ResourceStr {
    const currentVal = this.item.value;
    const found = this.item.menuOptions?.find(m => m.value === currentVal);
    return found?.title || found?.value || currentVal as ResourceStr;
  }

  build() {
    Row() {
      if (this.item.type == ItemActionType.MENU) {
        Row({ space: 8 }) {
          Text(this.getMenuLabel()).menuText()
            .fontColor(this.item.enabled ? $r('sys.color.font_primary') : ColorUtils.getUnableColor($r('sys.color.font_primary')))
          SymbolGlyph($r("sys.symbol.arrowtriangle_down_fill")).menuSymbolGlyph(14, this.item.enabled)
        }
      } else if (this.item.type == ItemActionType.TOGGLE) {
        Toggle({ type: ToggleType.Switch, isOn: this.item.value as boolean })
          .selectedColor(this.item.iconColor)
          .enabled(this.item.enabled)
          .hitTestBehavior(HitTestMode.None)
      } else if (this.item.type == ItemActionType.ROUTER) {
        Row({ space: 8 }) {
          Text(this.item.value as ResourceStr)
            .fontSize(15)
            .fontColor(this.item.enabled ? $r('sys.color.font_primary') : ColorUtils.getUnableColor($r('sys.color.font_primary')))
          SymbolGlyph($r("sys.symbol.chevron_right")).menuSymbolGlyph(24, this.item.enabled)
            .hitTestBehavior(HitTestMode.None)
        }
      } else if (this.item.type == ItemActionType.TEXT) {
        Text(this.item.value as ResourceStr)
          .fontSize(15)
          .fontColor(this.item.enabled ? $r('sys.color.font_primary') : ColorUtils.getUnableColor($r('sys.color.font_primary')))
      } else if (this.item.type == ItemActionType.RADIO) {
        Radio({ value: this.item.radioConfig?.value || '', group: this.item.radioConfig?.group || '' })
          .size({ width: 24, height: 24 })
          .radioStyle({ checkedBackgroundColor: this.item.iconColor })
          .hitTestBehavior(HitTestMode.None)
          .checked(this.item.value == this.item.radioConfig?.value)
      } else if (this.item.type == ItemActionType.CHECK) {
        Checkbox().size({ width: 24, height: 24 }).select(this.item.value as boolean).hitTestBehavior(HitTestMode.None)
      } else if (this.item.type == ItemActionType.DIALOG) {
        Row({ space: 4 }) {
          Text(this.item.value as ResourceStr).menuText()
            .fontColor(this.item.enabled ? $r('sys.color.font_primary') : ColorUtils.getUnableColor($r('sys.color.font_primary')))
          SymbolGlyph($r("sys.symbol.chevron_right")).menuSymbolGlyph(24, this.item.enabled)
        }
      } else if (this.item.type == ItemActionType.SLIDER) {
        Row() {
          Text(`${((this.item.value || 0) as number).toFixed(1)} ${this.item.sliderConfig?.unit || ""}`)
            .menuText()
            .margin({ right: this.item.sliderConfig?.showControl ? 5 : 0 })
          if (this.item.sliderConfig?.showControl) {
            SymbolGlyph($r("sys.symbol.minus_circle_fill"))
              .menuSymbolGlyph(21)
              .onClick(() => {
                if (!this.item.enabled) return
                const minus = this.item.sliderConfig?.step || 1
                const old = this.item.value as number
                this.onSliderChange(old - minus)
              })
          }
          Slider({
            value: this.item.value as number,
            min: this.item.sliderConfig?.min || 0,
            max: this.item.sliderConfig?.max || 100,
            style: SliderStyle.InSet,
            step: this.item.sliderConfig?.step || 5
          }).showSteps(true)
            .enabled(this.item.enabled)
            .blockColor(Color.White)
            .trackThickness(20)
            .minResponsiveDistance(1)
            .onChange((v: number) => {
              this.onSliderChange(v)
            }).layoutWeight(1)
          if (this.item.sliderConfig?.showControl) {
            SymbolGlyph($r("sys.symbol.plus_circle_fill"))
              .menuSymbolGlyph(21)
              .onClick(() => {
                if (!this.item.enabled) return
                const plus = this.item.sliderConfig?.step || 1
                const old = this.item.value as number
                this.onSliderChange(old + plus)
              })
          }
        }
      }
    }
    .height(35)
    .layoutWeight(this.item.type == ItemActionType.SLIDER ? 2 : undefined)
    .justifyContent(FlexAlign.End)
  }
}

// 样式扩展
@Extend(Text)
function menuText() {
  .fontSize(14).fontColor($r('sys.color.font_primary'))
}

@Extend(SymbolGlyph)
function menuSymbolGlyph(size: number, enable: boolean = true) {
  .fontSize(size)
  .fontColor([enable ? $r("sys.color.menu_text_normal_color") : ColorUtils.getUnableColor($r("sys.color.menu_text_normal_color"))])
}

// 菜单通用组件
@Builder
export function MenuSelectWitch(item: CustomItemInfo, onSelect: (item: MenuOption) => void) {
  Menu() {
    MenuItem({ content: item.title }).contentFont({ weight: FontWeight.Bold })

    Repeat<MenuOption>(item.menuOptions || [])
      .each((ri: RepeatItem<MenuOption>) => {
        MenuItem({
          content: ri.item.title ?? ri.item.value,
          symbolStartIcon: ri.item.symbolIcon ? defaultIcon(ri) : undefined,
          symbolEndIcon: item.value == ri.item.value ? new SymbolGlyphModifier($r("sys.symbol.checkmark")).fontColor([menuColor(item, ri)]) : undefined,
        })
          .contentFont({ size: 16 })
          .contentFontColor(menuColor(item, ri))
          .onClick(() => {
            if (item.menuDisabled && item.menuDisabled(ri.item, ri.index)) {
              // 禁用状态不处理
            } else {
              onSelect(ri.item)
              if (item.onChange) {
                item.onChange(ri.item.value)
              }
              item.value = ri.item.value
            }
          })
      }).key((menu: MenuOption) => menu.value.toString())
  }
  .menuItemDivider({ color: $r("sys.color.alert_divider_color"), strokeWidth: LengthMetrics.vp(1), startMargin: LengthMetrics.vp(UIConstants.PADDING_VALUE_12), endMargin: LengthMetrics.vp(UIConstants.PADDING_VALUE_12) })
  .backgroundColor($r("app.color.background_color"))
  .borderRadius(UIConstants.BORDER_RADIUS_20)
}

function defaultIcon(menu: RepeatItem<MenuOption>) {
  if (menu.item.symbolIcon == null) return new SymbolGlyphModifier($r("sys.symbol.checkmark"))
  return menu.item.symbolIcon
}

function menuColor(item: CustomItemInfo, menu: RepeatItem<MenuOption>): ResourceColor {
  if (item.menuDisabled == null) {
    return $r("sys.color.font_primary");
  }
  return item.menuDisabled(menu.item, menu.index) ? $r("sys.color.font_tertiary") : $r("sys.color.font_primary");
}

// 辅助构建函数
export function makeCustomItems<T>(data: T, callBack: (t: T) => CustomItemInfo[]) {
  return callBack(data);
}
