import { NaviContainer } from '../../components/NaviContainer';

@ComponentV2
struct PlaceholderPage {
  @Param title: ResourceStr = ''

  build() {
    NaviContainer({
      title: this.title,
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
    Column() {
      Text($r('app.string.placeholder_hint'))
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Builder
export function SettingsCustomBuilder() {
  PlaceholderPage({ title: $r('app.string.settings_custom') })
}

@Builder
export function SettingsScriptBuilder() {
  PlaceholderPage({ title: $r('app.string.settings_script') })
}

@Builder
export function SettingsPasswordBuilder() {
  PlaceholderPage({ title: $r('app.string.password_manager') })
}

@Builder
export function SettingsMenuCustomBuilder() {
  PlaceholderPage({ title: $r('app.string.customize_menu') })
}

@Builder
export function SettingsLongPressBuilder() {
  PlaceholderPage({ title: $r('app.string.customize_long_press_menu') })
}

@Builder
export function SettingsAiBuilder() {
  PlaceholderPage({ title: $r('app.string.ai_settings') })
}

@Builder
export function SettingsOperationsBuilder() {
  PlaceholderPage({ title: $r('app.string.operations_settings') })
}

@Builder
export function SettingsImportBuilder() {
  PlaceholderPage({ title: $r('app.string.import_data') })
}
