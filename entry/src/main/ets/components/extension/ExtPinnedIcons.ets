import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import ExtensionInfo from '../../common/entity/ExtensionInfo';
import { ActionBarColor } from '../../common/utils/ui/ActionBarColor';
import { ResourceUtils } from '../../common/utils/app/ResourceUtil';
import { toastUtil } from '../../common/utils/ui/ToastUtils';
import { ExtIconWithBadge } from './ExtIconWithBadge';

/**
 * 工具栏固定扩展图标列（PC 浏览器 pin 语义）：
 * 渲染 pinned + enabled 的扩展图标（带 badge 角标）；
 * 点击：有 popup 声明打开面板，无则提示；长按：取消固定并提示
 */
@ComponentV2
export struct ExtPinnedIcons {
  /** 所在栏位置：决定图标大小与拼图回退前景色 */
  @Param anchor: string = 'bottom'
  @Param bar: string = 'opera'

  /** 固定且启用中的扩展列表 */
  private pinnedExts(): ExtensionInfo[] {
    const out: ExtensionInfo[] = []
    for (const ext of extensionVM.extensions) {
      if (ext.enabled && ext.pinned) {
        out.push(ext)
      }
    }
    return out
  }

  build() {
    if (this.pinnedExts().length > 0) {
      Row({ space: 4 }) {
        ForEach(this.pinnedExts(), (ext: ExtensionInfo) => {
          ExtIconWithBadge({
            ext: ext,
            iconSize: this.bar == 'opera' ? 25 : 20,
            fgColor: ActionBarColor.fg($r('sys.color.font_secondary'), this.anchor === 'top')
          })
            .onClick(() => {
              if (extensionVM.hasPopup(ext)) {
                extensionVM.openPopup(ext)
              } else {
                toastUtil.showToast({
                  message: ResourceUtils.getString($r('app.string.ext_no_popup'))
                })
              }
            })
            .gesture(
              LongPressGesture({ repeat: false, duration: 500 })
                .onAction((): void => {
                  extensionVM.togglePin(ext)
                  toastUtil.showToast({
                    message: ResourceUtils.getString($r('app.string.ext_unpin'))
                  })
                })
            )
        }, (ext: ExtensionInfo) => ext.extId)
      }
    }
  }
}
