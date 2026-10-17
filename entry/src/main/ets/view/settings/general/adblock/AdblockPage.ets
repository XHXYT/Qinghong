import { NaviContainer } from '../../../../components/NaviContainer';
import { appSettings } from '../../../../common/entity/SettingsModel';
import { AdBlockStore, adBlockStore } from '../../../../common/utils/AdBlockStore';
import { AdBlockEngine, adBlockEngine } from '../../../../common/utils/AdBlockEngine';
import { CustomItemInfo, ItemActionType } from '../../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../../components/CusItemBuilder';
import { QhState } from '../../../../entryability/AppState';

@Builder
export function SettingsAdblockBuilder() {
  AdBlockPage()
}

@ComponentV2
struct AdBlockPage {

  @Local blockItem: CustomItemInfo = new CustomItemInfo({ id: 'ad_block', type: ItemActionType.TOGGLE })
  @Local builtinItem: CustomItemInfo = new CustomItemInfo({ id: 'ad_block_builtin', type: ItemActionType.TOGGLE })
  @Local customRulesItem: CustomItemInfo = new CustomItemInfo({ id: 'ad_block_custom_rules', type: ItemActionType.ROUTER })
  @Local subscriptionItem: CustomItemInfo = new CustomItemInfo({ id: 'ad_block_subscription', type: ItemActionType.ROUTER })

  aboutToAppear(): void {
    // 总开关关闭时，下方规则相关条目整体置灰
    const syncEnabled = (): void => {
      const on: boolean = appSettings.ad_block_enabled
      this.builtinItem.enabled = on
      this.customRulesItem.enabled = on
      this.subscriptionItem.enabled = on
    }
    // 广告拦截总开关（副标题为拦截统计）
    this.blockItem.title = $r('app.string.ad_block')
    this.blockItem.subtitle = $r('app.string.ad_block_stats', adBlockStore.count,
      AdBlockStore.formatBytes(adBlockStore.bytes))
    this.blockItem.value = appSettings.ad_block_enabled
    this.blockItem.onChange = (v: string | boolean | number): void => {
      appSettings.ad_block_enabled = v as boolean
      syncEnabled()
      // 全局开关变化：向所有已创建 Web 实例重新应用原生 AdsBlock 开关
      AdBlockEngine.applyEnableToAll()
    }
    syncEnabled()
    adBlockStore.load().then((): void => {
      this.blockItem.subtitle = $r('app.string.ad_block_stats', adBlockStore.count,
        AdBlockStore.formatBytes(adBlockStore.bytes))
    })

    // 启用内建规则
    this.builtinItem.title = $r('app.string.ad_block_builtin')
    this.builtinItem.subtitle = $r('app.string.ad_block_builtin_desc')
    this.builtinItem.value = appSettings.ad_block_builtin
    this.builtinItem.onChange = (v: string | boolean | number): void => {
      appSettings.ad_block_builtin = v as boolean
      appSettings.save()
      // 内建规则开关变化：重建规则文件并同步到原生 AdsBlock 引擎
      adBlockEngine.syncToWebEngine()
    }

    // 自定义规则（编辑页）
    this.customRulesItem.title = $r('app.string.ad_block_custom_rules')
    this.customRulesItem.subtitle = $r('app.string.ad_block_custom_rules_desc')
    this.customRulesItem.onChange = (v: string | boolean | number): void => {
      QhState.pushPage('settings_adblock_custom', null)
    }

    // 规则订阅（订阅管理页）
    this.subscriptionItem.title = $r('app.string.ad_block_subscription')
    this.subscriptionItem.subtitle = $r('app.string.ad_block_subscription_desc')
    this.subscriptionItem.onChange = (v: string | boolean | number): void => {
      QhState.pushPage('settings_adblock_subs', null)
    }
  }

  build() {
    NaviContainer({
      title: $r('app.string.ad_block'),
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
      // 开关卡片
      ListItem() {
        Column() {
          CustomListItem({
            item: this.blockItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 16 })
          CustomListItem({
            item: this.builtinItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .margin({ top: 10 })

      // 规则卡片（自定义规则 / 规则订阅）
      ListItem() {
        Column() {
          CustomListItem({
            item: this.customRulesItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 16 })
          CustomListItem({
            item: this.subscriptionItem,
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }
      .width('100%')
      .margin({ top: 12, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(QhState.bottomRectHeight)
    .padding({ left: 16, right: 16 })
  }
}
