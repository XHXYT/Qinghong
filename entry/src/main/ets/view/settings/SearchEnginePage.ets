import { NaviContainer } from '../../components/NaviContainer';
import { CustomContentDialog } from '@kit.ArkUI';
import { appSettings, CustomSearchEngine } from '../../common/entity/SettingsModel';
import { SearchEngines, SearchEngine } from '../../common/constants/SearchEngines';
import { CustomItemInfo, ItemActionType, RadioConfig } from '../../common/entity/CusItemInfo';
import { CustomListItem } from '../../components/CusItemBuilder';
import { buildDialogButtons } from '../../components/dialog/AppContentDialog';
import { toastUtil } from '../../common/utils/ToastUtils';

@Builder
export function SearchEngineBuilder() {
  SearchEnginePage()
}

@ComponentV2
struct SearchEnginePage {
  @Local items: CustomItemInfo[] = []
  @Local inputName: string = ''
  @Local inputUrl: string = ''
  private addDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.rebuildItems()
    this.addDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.add_engine'),
        contentBuilder: (): void => {
          this.addDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doAddEngine()
            }
            this.addDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.inputName = ''
        this.inputUrl = ''
      }
    })
  }

  private rebuildItems(): void {
    const items: CustomItemInfo[] = []
    const engines = SearchEngines.getAllEngines()
    for (const e of engines) {
      const isCustom = appSettings.custom_engines.some((ce: CustomSearchEngine): boolean => ce.id === e.id)
      items.push(new CustomItemInfo({
        id: e.id,
        symbol: isCustom ? $r('sys.symbol.plus_circle_fill') : $r('sys.symbol.curve_magnifyingglass'),
        title: e.name,
        type: ItemActionType.RADIO,
        value: appSettings.search_engine_id,
        radioConfig: new RadioConfig(e.id, 'engine'),
        onChange: (v: string | boolean | number): void => {
          this.selectEngine(v as string)
        }
      }))
    }
    this.items = items
  }

  private selectEngine(id: string): void {
    appSettings.search_engine_id = id
    // 同步所有行的选中态
    for (const item of this.items) {
      item.value = id
    }
  }

  private doAddEngine(): void {
    const name = this.inputName.trim()
    const url = this.inputUrl.trim()
    if (!name || !url) return
    if (url.indexOf('%s') < 0) {
      toastUtil.showToast({ message: $r('app.string.engine_url_invalid') })
      return
    }
    const id = `custom_${new Date().getTime()}`
    appSettings.custom_engines.push(new CustomSearchEngine(id, name, url))
    appSettings.save()
    this.rebuildItems()
  }

  private confirmDeleteEngine(engine: SearchEngine): void {
    toastUtil.showAlertDialog({
      title: engine.name,
      message: $r('app.string.delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            const rest = appSettings.custom_engines.filter((ce: CustomSearchEngine): boolean => ce.id !== engine.id)
            appSettings.custom_engines = rest
            appSettings.save()
            if (appSettings.search_engine_id === engine.id) {
              appSettings.search_engine_id = 'bing'
            }
            this.rebuildItems()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deleteEngine')
  }

  @Builder
  addDialogContent() {
    Column({ space: 12 }) {
      TextInput({ placeholder: $r('app.string.engine_name_hint') })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.inputName = v
        })
      TextInput({ placeholder: $r('app.string.engine_url_hint') })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.inputUrl = v
        })
    }
    .width('100%')
  }

  @Builder
  pageContent() {
    Column() {
      List() {
        ForEach(this.items, (item: CustomItemInfo) => {
          ListItem() {
            CustomListItem({
              item: item,
              itemPadding: { left: 16, right: 16, top: 14, bottom: 14 }
            })
            .gesture(
              LongPressGesture({ repeat: false, duration: 400 })
                .onAction(() => {
                  // 仅自定义引擎可删除
                  const isCustom = appSettings.custom_engines.some(
                    (ce: CustomSearchEngine): boolean => ce.id === item.id)
                  if (isCustom) {
                    this.confirmDeleteEngine(SearchEngines.getEngine(item.id))
                  }
                })
            )
          }
        }, (item: CustomItemInfo) => `${item.id}_${appSettings.search_engine_id}_${appSettings.custom_engines.length}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
        startMargin: 56,
        endMargin: 16
      })

      // 添加搜索引擎
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
        Text($r('app.string.add_engine'))
          .fontSize(15)
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .onClick(() => {
        this.addDialog?.open()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_secondary'))
  }

  build() {
    NaviContainer({
      title: $r('app.string.search_engine'),
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
}
