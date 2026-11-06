import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { appSettings } from '../../../common/entity/SettingsModel';
import { QhState } from '../../../entryability/AppState';
import { FontInfo, FontStore } from '../../../common/utils/FontStore';
import { toastUtil } from '../../../common/utils/ToastUtils';

@Builder
export function SettingsFontBuilder() {
  FontPage()
}

@ComponentV2
struct FontPage {

  @Local fonts: FontInfo[] = []
  @Local webFontItem: CustomItemInfo =
    new CustomItemInfo({ id: 'web_font', type: ItemActionType.TOGGLE })

  aboutToAppear(): void {
    this.fonts = FontStore.list()
    this.webFontItem = new CustomItemInfo({
      id: 'web_font',
      title: $r('app.string.web_font_apply'),
      subtitle: $r('app.string.web_font_apply_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.web_font_enabled,
      onChange: (v: string | boolean | number): void => {
        appSettings.web_font_enabled = v as boolean
      }
    })
  }

  private addFont(): void {
    const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker()
    const options: picker.DocumentSelectOptions = {
      maxSelectNumber: 1,
      fileSuffixFilters: ['.ttf', '.otf']
    }
    docPicker.select(options).then((uris: string[]) => {
      if (uris.length === 0) {
        return
      }
      const family: string = FontStore.addFromUri(uris[0])
      if (family === '') {
        toastUtil.showToast({ message: $r('app.string.font_add_failed') })
        return
      }
      this.fonts = FontStore.list()
      appSettings.font_family = family
      toastUtil.showToast({ message: $r('app.string.font_added') })
    }).catch((error: BusinessError) => {
      toastUtil.showToast({ message: $r('app.string.font_pick_failed') })
    })
  }

  private confirmDeleteFont(info: FontInfo): void {
    toastUtil.showAlertDialog({
      title: info.family,
      message: $r('app.string.font_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            if (FontStore.remove(info.family)) {
              if (appSettings.font_family === info.family) {
                appSettings.font_family = ''
              }
              this.fonts = FontStore.list()
            }
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteFont')
  }

  build() {
    NaviContainer({
      title: $r('app.string.font'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.plus'),
          action: (): void => {
            this.addFont()
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
      // 应用到网页（通用开关行）
      ListItem() {
        Column() {
          CustomListItem({
            item: this.webFontItem,
            itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .margin({ top: 10, bottom: 12 })

      // 可用字体
      ListItem() {
        Text($r('app.string.font_available'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 4, top: 2, bottom: 6 })
      }
      .width('100%')

      // 字体单选列表
      ListItem() {
        Column() {
          this.defaultFontRow()
          ForEach(this.fonts, (f: FontInfo) => {
            Column() {
              Divider()
                .color($r('sys.color.comp_divider'))
              this.customFontRow(f)
            }
            .width('100%')
          }, (f: FontInfo) => f.path)
          if (this.fonts.length === 0) {
            Text($r('app.string.font_empty_hint'))
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .padding({ top: 4, bottom: 14 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  defaultFontRow() {
    Row() {
      Text($r('app.string.font_default'))
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (appSettings.font_family === '') {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([QhState.currentThemeColor])
      }
    }
    .width('100%')
    .height(52)
    .onClick(() => {
      appSettings.font_family = ''
    })
  }

  @Builder
  customFontRow(f: FontInfo) {
    Row() {
      Text(f.family)
        .fontSize(16)
        .fontFamily(f.family)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (appSettings.font_family === f.family) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([QhState.currentThemeColor])
      }
    }
    .width('100%')
    .height(52)
    .onClick(() => {
      appSettings.font_family = f.family
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 400 })
        .onAction(() => {
          this.confirmDeleteFont(f)
        })
    )
  }
}
