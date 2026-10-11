import { ButtonOptions } from "@ohos.arkui.advanced.Dialog"

/**
 * 弹窗按钮构建工具。
 * CustomContentDialog 是 @CustomDialog struct（@ohos.arkui.advanced.Dialog，
 * 经 @kit.ArkUI 导出），不能被普通组件二次包装，
 * 必须作为 new CustomDialogController({ builder: CustomContentDialog({...}) }) 的直接 builder 使用。
 * 业务方按 Pixark 同款模式：import { CustomContentDialog } from '@kit.ArkUI' 后直接 new 使用。
 */

/**
 * 构建弹窗按钮组
 * @param labels 按钮文案
 * @param danger 最后一个按钮是否为危险红色
 * @param onClick 点击回调（index 从 0 开始）
 */
export function buildDialogButtons(labels: ResourceStr[], danger: boolean,
  onClick: (index: number) => void): ButtonOptions[] {
  return labels.map((label: ResourceStr, index: number): ButtonOptions => {
    return {
      value: label,
      buttonStyle: ButtonStyleMode.TEXTUAL,
      fontColor: danger && index === labels.length - 1 ? Color.Red : $r('sys.color.icon_emphasize'),
      action: (): void => {
        onClick(index)
      }
    }
  })
}
