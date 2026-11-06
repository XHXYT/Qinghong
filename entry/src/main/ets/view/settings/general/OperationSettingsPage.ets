import { SettingsScaffold, SettingsSection } from '../../../components/SettingsScaffold';
import { QhState } from '../../../entryability/AppState';
import { appSettings } from '../../../common/entity/SettingsModel';
import { tabsVM } from '../../../viewmodel/TabsViewModel';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { ToolbarAction, findToolbarAction, getToolbarEventAction } from '../../../common/entity/ToolbarEvent';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { volumeKeyPaging } from '../../../common/utils/VolumeKeyPaging';


@Builder
export function OperationSettingsBuilder() {
  OperationSettingsPage()
}

@ComponentV2
struct OperationSettingsPage {

  @Local items: CustomItemInfo[] = []
  @Local sections: SettingsSection[] = []
  /** 工具栏行跟手拖拽偏移（松手回弹） */
  @Local dragOffset: number = 0

  aboutToAppear(): void {
    this.buildItems()
  }

  private buildItems(): void {
    this.items = [
      new CustomItemInfo({
        id: 'swipe_nav',
        title: $r('app.string.swipe_nav'),
        type: ItemActionType.TOGGLE,
        value: appSettings.swipe_nav_enabled,
        onChange: (v: string | boolean | number): void => {
          appSettings.swipe_nav_enabled = v === true
        }
      }),
      new CustomItemInfo({
        id: 'toolbar_swipe',
        title: $r('app.string.toolbar_swipe'),
        subtitle: $r('app.string.toolbar_swipe_desc'),
        type: ItemActionType.TOGGLE,
        value: appSettings.toolbar_swipe_enabled,
        onChange: (v: string | boolean | number): void => {
          appSettings.toolbar_swipe_enabled = v === true
        }
      }),
      new CustomItemInfo({
        id: 'volume_key_paging',
        title: $r('app.string.volume_key_paging'),
        subtitle: $r('app.string.volume_key_paging_desc'),
        type: ItemActionType.TOGGLE,
        value: appSettings.volume_key_paging,
        onChange: (v: string | boolean | number): void => {
          appSettings.volume_key_paging = v === true
          volumeKeyPaging.sync()
        }
      }),
      new CustomItemInfo({
        id: 'video_settings',
        title: $r('app.string.video_settings'),
        type: ItemActionType.ROUTER,
        onChange: (v: string | boolean | number): void => {
          QhState.pushPage('settings_video', null)
        }
      }),
      new CustomItemInfo({
        id: 'keyboard_shortcuts',
        title: $r('app.string.keyboard_shortcuts'),
        type: ItemActionType.ROUTER,
        onChange: (v: string | boolean | number): void => {
          QhState.pushPage('settings_keyboard', null)
        }
      })
    ]
    const section: SettingsSection = new SettingsSection('operations')
    section.items = this.items
    this.sections = [section]
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.operations_settings'),
      sections: this.sections,
      footer: (): void => {
        this.toolbarEventsSection()
      }
    })
  }

  /** 长按按钮查看当前绑定的行为 */
  private showCurrentAction(eventId: string): void {
    const action: ToolbarAction | undefined = findToolbarAction(getToolbarEventAction(eventId))
    const label: string = action === undefined ? '' : ResourceUtils.getString(action.label)
    toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.current_action')) + label })
  }

  /** 松手回弹 */
  private snapBack(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.dragOffset = 0
    })
  }

  /** 松手：回弹并按滑动方向打开滑动事件设置（位移超过阈值且工具栏滑动事件开启时才触发） */
  private finishSwipe(): void {
    const offset: number = this.dragOffset
    this.snapBack()
    if (appSettings.toolbar_swipe_enabled && Math.abs(offset) >= 24) {
      QhState.pushPage('settings_toolbar_event', offset < 0 ? 'swipe_left' : 'swipe_right')
    }
  }

  /** 工具栏事件设置区的单个按钮：点击设置长按事件，长按查看当前行为 */
  @Builder
  toolbarEventButton(symbol: Resource, isTabCount: boolean, eventId: string) {
    Row() {
      if (isTabCount) {
        Stack() {
          Text(`${tabsVM.tabCount}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
        }
        .width(22)
        .height(22)
        .alignContent(Alignment.Center)
        .border({
          width: 1.5,
          color: $r('sys.color.font_primary'),
          radius: 4
        })
      } else {
        SymbolGlyph(symbol)
          .fontSize(26)
          .fontColor([$r('sys.color.font_primary')])
      }
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      QhState.pushPage('settings_toolbar_event', eventId)
    })
    .gesture(LongPressGesture()
      .onAction(() => {
        this.showCurrentAction(eventId)
      }))
  }

  /** 底部工具栏长按/滑动事件设置区：提示文案 + 传统布局五按钮 */
  @Builder
  toolbarEventsSection() {
    Column() {
      Text($r('app.string.toolbar_events_hint'))
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeight(19)
        .margin({ left: 4, right: 4, top: 18, bottom: 6 })
      Column() {
        Row() {
          this.toolbarEventButton($r('sys.symbol.chevron_left'), false, 'back_long')
          this.toolbarEventButton($r('sys.symbol.chevron_right'), false, 'forward_long')
          this.toolbarEventButton($r('sys.symbol.house'), false, 'home_long')
          this.toolbarEventButton($r('sys.symbol.house'), true, 'tabs_long')
          this.toolbarEventButton($r('sys.symbol.square_grid_2x2'), false, 'menu_long')
        }
        .width('100%')
        .height(56)
        .translate({ x: this.dragOffset })
        .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
          .onActionUpdate((e: GestureEvent) => {
            if (!appSettings.toolbar_swipe_enabled) {
              return
            }
            this.dragOffset = e.offsetX
          })
          .onActionEnd(() => {
            this.finishSwipe()
          })
          .onActionCancel(() => {
            this.snapBack()
          }))
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.background_color'))
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
