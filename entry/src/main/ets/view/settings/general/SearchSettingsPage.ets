import { NaviContainer } from '../../../components/NaviContainer';
import { CustomContentDialog } from '@kit.ArkUI';
import { appSettings } from '../../../common/entity/SettingsModel';
import { SearchEngines } from '../../../common/constants/SearchEngines';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { QhState } from '../../../entryability/AppState';

const SUGGEST_SOURCES: string[] = ['favorites', 'bookmarks', 'tabs', 'history', 'engine', 'search_history']

function suggestSourceLabel(key: string): ResourceStr {
  if (key === 'favorites') {
    return $r('app.string.suggest_source_favorites')
  }
  if (key === 'bookmarks') {
    return $r('app.string.suggest_source_bookmarks')
  }
  if (key === 'tabs') {
    return $r('app.string.suggest_source_tabs')
  }
  if (key === 'history') {
    return $r('app.string.suggest_source_history')
  }
  if (key === 'engine') {
    return $r('app.string.suggest_source_engine')
  }
  return $r('app.string.suggest_source_search_history')
}

@Builder
export function SearchSettingsBuilder() {
  SearchSettingsPage()
}

@ComponentV2
struct SearchSettingsPage {
  @Local items: CustomItemInfo[] = []
  @Local suggestSel: boolean[] = [false, false, false, false, false, false]
  private suggestDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.buildItems()
    this.suggestDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.search_suggestions'),
        contentBuilder: (): void => {
          this.suggestDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.saveSuggestSources()
            }
            this.suggestDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        for (let i = 0; i < SUGGEST_SOURCES.length; i++) {
          this.suggestSel[i] = appSettings.isSuggestSourceOn(SUGGEST_SOURCES[i])
        }
      }
    })
  }

  private buildItems(): void {
    if (this.items.length === 0) {
      const items: CustomItemInfo[] = []
      // 搜索引擎
      items.push(new CustomItemInfo({
        id: 'engine',
        title: $r('app.string.search_engine'),
        type: ItemActionType.ROUTER,
        value: '',
        onChange: (v: string | boolean | number): void => {
          QhState.pushPage('search_engine', null)
        }
      }))
      // 搜索建议
      items.push(new CustomItemInfo({
        id: 'suggest',
        title: $r('app.string.search_suggestions'),
        type: ItemActionType.ROUTER,
        value: '',
        onChange: (v: string | boolean | number): void => {
          this.suggestDialog?.open()
        }
      }))
      // 搜索工具栏
      items.push(new CustomItemInfo({
        id: 'toolbar',
        title: $r('app.string.search_toolbar'),
        type: ItemActionType.ROUTER,
        value: '',
        onChange: (v: string | boolean | number): void => {
          QhState.pushPage('search_toolbar', null)
        }
      }))
      this.items = items
    }
    // 引擎名走 @Trace 直改，避免 ForEach key 竞态导致返回不刷新
    this.items[0].value = SearchEngines.getCurrentEngine().name
    // 工具栏启用状态指示
    this.items[2].value = ResourceUtils.getString(
      appSettings.search_toolbar_enabled ? $r('app.string.search_toolbar_on') : $r('app.string.search_toolbar_off'))
  }

  private saveSuggestSources(): void {
    const picked: string[] = []
    for (let i = 0; i < SUGGEST_SOURCES.length; i++) {
      if (this.suggestSel[i]) {
        picked.push(SUGGEST_SOURCES[i])
      }
    }
    appSettings.search_suggest_sources = picked.join(',')
    toastUtil.showToast({ message: $r('app.string.saved') })
  }

  @Builder
  suggestDialogContent() {
    Column() {
      Text($r('app.string.search_suggest_desc'))
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ bottom: 8 })
        .alignSelf(ItemAlign.Start)
      ForEach(SUGGEST_SOURCES, (key: string, idx: number) => {
        Row() {
          Text(suggestSourceLabel(key))
            .fontSize(16)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          Checkbox()
            .size({ width: 24, height: 24 })
            .select(this.suggestSel[idx])
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height(44)
        .onClick(() => {
          this.suggestSel[idx] = !this.suggestSel[idx]
        })
      }, (key: string) => key)
    }
    .width('100%')
  }

  build() {
    NaviContainer({
      title: $r('app.string.search_settings'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
      },
      onShown: (): void => {
        // 从引擎子页返回后刷新当前引擎名
        this.buildItems()
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      ListItem() {
        Column() {
          ForEach(this.items, (item: CustomItemInfo) => {
            CustomListItem({
              item: item,
              itemPadding: { left: 16, right: 16, top: 14, bottom: 14 }
            })
          }, (item: CustomItemInfo) => item.id)
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.background_color'))
        .clip(true)
      }
      .width('100%')
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
}
