import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { LongPressMenuItem, LongPressMenuItems } from '../../../common/constants/LongPressMenuItems';
import { appSettings } from '../../../common/entity/SettingsModel';
import { QhState } from '../../../entryability/AppState';

@Builder
export function SettingsLongPressBuilder() {
  LongPressMenuPage()
}

@ComponentV2
struct LongPressMenuPage {

  build() {
    NaviContainer({
      title: $r('app.string.customize_long_press_menu'),
      buttons: [new NaviBarButton({
        text: $r('app.string.reset'),
        width: 56,
        backgroundColor: Color.Transparent,
        action: (): void => {
          appSettings.long_press_menu = ''
        }
      })],
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
      ForEach(LongPressMenuItems.ALL, (item: LongPressMenuItem) => {
        ListItem() {
          this.menuRow(item)
        }
      }, (item: LongPressMenuItem) => item.id)
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /** 纯文字行 + 通用开关（无图标/无副标题/无分隔线） */
  @Builder
  menuRow(item: LongPressMenuItem) {
    Row() {
      Text(item.title)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
      this.rowToggle(item.id)
    }
    .width('100%')
    .height(56)
    .padding({ left: 24, right: 24 })
    .onClick(() => {
      LongPressMenuItems.toggle(item.id)
    })
  }

  /** 通用行开关样式：与设置页 TOGGLE 行一致 */
  @Builder
  rowToggle(id: string) {
    Toggle({ type: ToggleType.Switch, isOn: LongPressMenuItems.isEnabled(id) })
      .selectedColor($r('sys.color.icon_emphasize'))
      .hitTestBehavior(HitTestMode.None)
  }
}
