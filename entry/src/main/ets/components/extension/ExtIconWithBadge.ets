import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import ExtensionInfo from '../../common/entity/ExtensionInfo';

/**
 * 扩展图标 + 角标叠加（Chrome action badge 语义）：
 * 图标文件优先（沙箱路径须 file:// 前缀），无图标声明回退拼图符号；
 * badge 文本非空时叠加在图标底部（chrome.action.setBadge* 驱动）
 */
@ComponentV2
export struct ExtIconWithBadge {
  @Require @Param ext: ExtensionInfo = new ExtensionInfo()
  /** 图标边长（vp） */
  @Param iconSize: number = 24
  /** 无图标文件时拼图符号颜色（跟随所在栏前景） */
  @Param fgColor: ResourceColor = $r('sys.color.font_secondary')

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (extensionVM.iconPathOf(this.ext) !== '') {
        Image(`file://${extensionVM.iconPathOf(this.ext)}`)
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Contain)
          .borderRadius(Math.floor(this.iconSize / 6))
      } else {
        SymbolGlyph($r('sys.symbol.puzzle'))
          .fontSize(this.iconSize)
          .fontColor([this.fgColor])
      }
      if (extensionVM.badgeOf(this.ext.extId).text !== '') {
        Text(extensionVM.badgeOf(this.ext.extId).text)
          .fontSize(Math.max(8, Math.floor(this.iconSize / 2.8)))
          .fontWeight(FontWeight.Bold)
          .fontColor(extensionVM.badgeOf(this.ext.extId).txtColor)
          .backgroundColor(extensionVM.badgeOf(this.ext.extId).bgColor)
          .borderRadius(8)
          .padding({ left: 3, right: 3, top: 1, bottom: 1 })
          .maxLines(1)
          .constraintSize({ maxWidth: this.iconSize + 12 })
      }
    }
  }
}
