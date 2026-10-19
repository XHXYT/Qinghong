import { SettingsScaffold, SettingsSection } from '../../components/SettingsScaffold';
import { appSettings } from '../../common/entity/SettingsModel';
import { CustomItemInfo, ItemActionType } from '../../common/entity/CusItemInfo';
import { tabsVM } from '../../viewmodel/TabsViewModel';

@Builder
export function PrivacySettingsBuilder() {
  PrivacySettingsPage()
}

@ComponentV2
struct PrivacySettingsPage {

  @Local sections: SettingsSection[] = []

  aboutToAppear(): void {
    const items: CustomItemInfo[] = []
    items.push(new CustomItemInfo({
      id: 'do_not_track',
      title: $r('app.string.do_not_track'),
      subtitle: $r('app.string.do_not_track_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.do_not_track,
      onChange: (v: string | boolean | number): void => {
        appSettings.do_not_track = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'intelligent_tracking_prevention',
      title: $r('app.string.intelligent_tracking_prevention'),
      subtitle: $r('app.string.intelligent_tracking_prevention_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.intelligent_tracking_prevention,
      onChange: (v: string | boolean | number): void => {
        const target = v === true
        appSettings.intelligent_tracking_prevention = target
        // 全局开关变化：向所有已创建 Web 实例重新应用（新标签在挂载时应用）
        for (const tab of tabsVM.tabs) {
          const c = tab.controller
          if (c) {
            try {
              c.enableIntelligentTrackingPrevention(target)
            } catch (e) {
              console.error(`[PrivacySettings] enableIntelligentTrackingPrevention 失败: ${e}`)
            }
          }
        }
      }
    }))
    items.push(new CustomItemInfo({
      id: 'disable_webrtc',
      title: $r('app.string.disable_webrtc'),
      subtitle: $r('app.string.disable_webrtc_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.disable_webrtc,
      onChange: (v: string | boolean | number): void => {
        appSettings.disable_webrtc = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'geolocation_access',
      title: $r('app.string.geolocation_access'),
      subtitle: $r('app.string.geolocation_access_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.geolocation_access,
      onChange: (v: string | boolean | number): void => {
        appSettings.geolocation_access = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'do_not_sell',
      title: $r('app.string.do_not_sell'),
      subtitle: $r('app.string.do_not_sell_desc'),
      type: ItemActionType.TOGGLE,
      value: appSettings.do_not_sell,
      onChange: (v: string | boolean | number): void => {
        appSettings.do_not_sell = v as boolean
      }
    }))
    items.push(new CustomItemInfo({
      id: 'default_incognito',
      title: $r('app.string.default_incognito'),
      type: ItemActionType.TOGGLE,
      value: appSettings.default_incognito,
      onChange: (v: string | boolean | number): void => {
        const target = v === true
        appSettings.default_incognito = target
        tabsVM.applyGlobalIncognito(target)
      }
    }))
    const section: SettingsSection = new SettingsSection('privacy')
    section.items = items
    this.sections = [section]
  }

  build() {
    SettingsScaffold({
      title: $r('app.string.settings_privacy'),
      sections: this.sections
    })
  }
}
