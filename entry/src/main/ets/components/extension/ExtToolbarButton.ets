import { SymbolGlyphModifier } from '@kit.ArkUI';
import { QhState } from '../../entryability/AppState';
import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import ExtensionInfo from '../../common/entity/ExtensionInfo';
import { ExtensionEngine } from '../../common/utils/extension/ExtensionEngine';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { ActionBarColor } from '../../common/utils/ui/ActionBarColor';
import { ResourceUtils } from '../../common/utils/app/ResourceUtil';
import { toastUtil } from '../../common/utils/ui/ToastUtils';

/**
 * 工具栏扩展按钮（PC 浏览器拼图样式）：
 * 点击展开扩展列表菜单——有声明的扩展打开 popup 面板，无则提示；
 * 菜单底部「管理扩展」跳转扩展管理设置页
 */
@ComponentV2
export struct ExtToolbarButton {
  /** 所在栏位置：'top' 菜单向下弹 / 'bottom' 菜单向上弹 */
  @Param anchor: string = 'bottom'
  @Param bar: string = 'opera'
  @Local menuOpen: boolean = false

  /** 启用中的扩展列表 */
  private enabledExts(): ExtensionInfo[] {
    const out: ExtensionInfo[] = []
    for (const ext of extensionVM.extensions) {
      if (ext.enabled) {
        out.push(ext)
      }
    }
    return out
  }

  /** 菜单项参数：图标文件优先（沙箱路径须 file:// 前缀），无图标声明回退拼图符号 */
  private menuOpts(ext: ExtensionInfo): MenuItemOptions {
    const opts: MenuItemOptions = { content: ext.name !== '' ? ext.name : ext.extId }
    const icon: string = extensionVM.iconPathOf(ext)
    if (icon !== '') {
      opts.startIcon = `file://${icon}`
    } else {
      opts.symbolStartIcon = new SymbolGlyphModifier($r('sys.symbol.puzzle'))
    }
    return opts
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
  extMenuBuilder() {
    Menu() {
      ForEach(this.enabledExts(), (ext: ExtensionInfo) => {
        MenuItem(this.menuOpts(ext))
          .onClick(() => {
            this.menuOpen = false
            this.openExt(ext)
          })
      }, (ext: ExtensionInfo) => ext.extId)
      MenuItem({
        content: ResourceUtils.getString($r('app.string.ext_store_chrome')),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.circle_circle_2'))
      })
        .onClick(() => {
          this.menuOpen = false
          tabsVM.newTab(ExtensionEngine.CWS_HOME, false)
        })
      MenuItem({
        content: ResourceUtils.getString($r('app.string.ext_store_edge')),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.nearby_devices'))
      })
        .onClick(() => {
          this.menuOpen = false
          tabsVM.newTab(ExtensionEngine.EDGE_ADDONS_HOME, false)
        })
      MenuItem({
        content: ResourceUtils.getString($r('app.string.ext_manage')),
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.puzzle'))
      })
        .onClick(() => {
          this.menuOpen = false
          QhState.pushPage('settings_extension', null)
        })
    }
    .backgroundColor($r('app.color.start_window_background'))
    .borderRadius(16)
  }

  build() {
    SymbolGlyph($r('sys.symbol.root'))
      .fontSize(this.bar == 'opera' ? 25 : 20)
      .fontColor([ActionBarColor.fg($r('sys.color.font_secondary'), this.anchor === 'top')])
      .onClick(() => {
        this.menuOpen = true
      })
      .bindMenu(this.menuOpen, this.extMenuBuilder(), {
        placement: this.anchor === 'top' ? Placement.BottomRight : Placement.TopRight,
        onDisappear: (): void => {
          this.menuOpen = false
        }
      })
  }
}
