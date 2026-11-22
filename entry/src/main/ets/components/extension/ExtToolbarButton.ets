import { QhState } from '../../entryability/AppState';
import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import ExtensionInfo from '../../common/entity/ExtensionInfo';
import { ExtensionEngine } from '../../common/utils/extension/ExtensionEngine';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { ActionBarColor } from '../../common/utils/ui/ActionBarColor';
import { ResourceUtils } from '../../common/utils/app/ResourceUtil';
import { toastUtil } from '../../common/utils/ui/ToastUtils';
import { ExtIconWithBadge } from './ExtIconWithBadge';

/**
 * 工具栏扩展按钮（PC 浏览器拼图样式）：
 * 点击展开扩展面板——固定（pin）的扩展排前，行内右侧图钉可固定/取消固定，
 * 图标带 badge 角标（chrome.action.setBadge* 驱动）；
 * 点击扩展有声明的打开 popup 面板，无则提示；
 * 面板底部：Chrome 商店 / Edge 加载项 / 管理扩展
 */
@ComponentV2
export struct ExtToolbarButton {
  /** 所在栏位置：'top' 面板向下弹 / 'bottom' 面板向上弹 */
  @Param anchor: string = 'bottom'
  @Param bar: string = 'opera'
  @Local menuOpen: boolean = false

  /** 启用中的扩展列表（固定到工具栏的排前） */
  private enabledExts(): ExtensionInfo[] {
    const out: ExtensionInfo[] = []
    for (const ext of extensionVM.extensions) {
      if (ext.enabled) {
        out.push(ext)
      }
    }
    out.sort((a: ExtensionInfo, b: ExtensionInfo): number => {
      if (a.pinned === b.pinned) {
        return 0
      }
      return a.pinned ? -1 : 1
    })
    return out
  }

  /** 点击扩展：有 popup 声明打开面板，否则提示 */
  private openExt(ext: ExtensionInfo): void {
    if (extensionVM.hasPopup(ext)) {
      extensionVM.openPopup(ext)
    } else {
      toastUtil.showToast({
        message: ResourceUtils.getString($r('app.string.ext_no_popup'))
      })
    }
  }

  @Builder
  extRow(ext: ExtensionInfo) {
    Row() {
      // 左侧点击区（图标 + 名称）：与图钉按钮互不干扰（ArkUI onClick 冒泡，故用兄弟节点分离）
      Row() {
        ExtIconWithBadge({ ext: ext, iconSize: 24 })
          .margin({ right: 12 })
        Text(ext.name !== '' ? ext.name : ext.extId)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.menuOpen = false
        this.openExt(ext)
      })

      // 图钉：固定/取消固定到工具栏
      SymbolGlyph(ext.pinned ? $r('sys.symbol.pin_fill') : $r('sys.symbol.pin'))
        .fontSize(17)
        .fontColor([ext.pinned ? $r('sys.color.font_primary') : $r('sys.color.font_secondary')])
        .padding({ left: 8, right: 4, top: 10, bottom: 10 })
        .onClick(() => {
          extensionVM.togglePin(ext)
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 8, right: 6 })
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  footerRow(icon: Resource, label: string, tap: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(19)
        .fontColor([$r('sys.color.font_secondary')])
        .margin({ right: 12 })
      Text(label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 10, right: 10 })
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.menuOpen = false
      tap()
    })
  }

  @Builder
  extPanelBuilder() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.enabledExts(), (ext: ExtensionInfo) => {
            this.extRow(ext)
          }, (ext: ExtensionInfo) => `${ext.extId}#${ext.pinned ? 1 : 0}`)
        }
        .width('100%')
      }
      .width('100%')
      .align(Alignment.Start)
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 320 })

      Divider()
        .margin({ left: 10, right: 10, top: 4, bottom: 4 })

      this.footerRow($r('sys.symbol.circle_circle_2'),
        ResourceUtils.getString($r('app.string.ext_store_chrome')), (): void => {
          tabsVM.newTab(ExtensionEngine.CWS_HOME, false)
        })
      this.footerRow($r('sys.symbol.nearby_devices'),
        ResourceUtils.getString($r('app.string.ext_store_edge')), (): void => {
          tabsVM.newTab(ExtensionEngine.EDGE_ADDONS_HOME, false)
        })
      this.footerRow($r('sys.symbol.puzzle'),
        ResourceUtils.getString($r('app.string.ext_manage')), (): void => {
          QhState.pushPage('settings_extension', null)
        })
    }
    .width(290)
    .padding(8)
    .borderRadius(16)
    .backgroundColor($r('app.color.background_color'))
  }

  build() {
    SymbolGlyph($r('sys.symbol.root'))
      .fontSize(this.bar == 'opera' ? 25 : 20)
      .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), this.anchor === 'top')])
      .onClick(() => {
        this.menuOpen = true
      })
      .bindPopup(this.menuOpen, {
        builder: this.extPanelBuilder,
        placement: this.anchor === 'top' ? Placement.BottomRight : Placement.TopRight,
        enableArrow: false,
        autoCancel: true,
        popupColor: Color.Transparent,
        shadow: { radius: 0 },
        onStateChange: (e: PopupStateChangeParam): void => {
          if (!e.isVisible) {
            this.menuOpen = false
          }
        }
      })
  }
}
