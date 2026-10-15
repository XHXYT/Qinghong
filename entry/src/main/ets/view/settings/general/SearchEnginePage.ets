import { NaviContainer } from '../../../components/NaviContainer';
import { CustomContentDialog } from '@kit.ArkUI';
import { appSettings, CustomSearchEngine } from '../../../common/entity/SettingsModel';
import { SearchEngines, SearchEngine } from '../../../common/constants/SearchEngines';
import { AppConstants } from '../../../common/constants/AppConstants';
import { CustomItemInfo, ItemActionType, RadioConfig } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { QhState } from '../../../entryability/AppState';

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
    const engines = SearchEngines.getAllEngines()
    // 自愈：持久化的引擎 id 已不在当前引擎列表（如旧版本引擎被删），回退默认引擎
    const current = appSettings.search_engine_id
    if (!engines.some((e: SearchEngine): boolean => e.id === current)) {
      appSettings.search_engine_id = AppConstants.DEFAULT_ENGINE_ID
    }
    const items: CustomItemInfo[] = []
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
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            const rest = appSettings.custom_engines.filter((ce: CustomSearchEngine): boolean => ce.id !== engine.id)
            appSettings.custom_engines = rest
            appSettings.save()
            if (appSettings.search_engine_id === engine.id) {
              appSettings.search_engine_id = 'baidu'
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
    List() {
      ForEach(this.items, (item: CustomItemInfo, idx: number) => {
        ListItem() {
          CustomListItem({
            item: item,
            itemPadding: { left: 16, right: 16, top: 14, bottom: 14 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: idx === 0 ? 10 : 12 })
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
      }, (item: CustomItemInfo) => `${item.id}_${appSettings.search_engine_id}_${appSettings.custom_engines.length}`)

      // 添加搜索引擎
      ListItem() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(18)
          Text($r('app.string.add_engine'))
            .fontSize(15)
        }
        .width('100%')
        .height(48)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 12 })
      .onClick(() => {
        this.addDialog?.open()
      })
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
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
