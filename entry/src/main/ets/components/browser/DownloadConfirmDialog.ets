import { CustomContentDialog } from '@kit.ArkUI';
import { downloadVM } from '../../viewmodel/DownloadViewModel';
import { buildDialogButtons } from '../dialog/AppContentDialog';
import { PublicDownloadDir } from '../../common/utils/PublicDownloadDir';

/**
 * 下载确认弹窗：接管下载事件后先确认再下载（文件名可编辑）。
 * 复用系统 CustomContentDialog（与其他弹窗同款按钮布局与风格）；
 * 组件挂载即打开弹窗，确认/取消清空 pending 后由根页卸载并关闭。
 */
@ComponentV2
export struct DownloadConfirmDialog {

  @Local name: string = ''
  private ctrl: CustomDialogController | null = null

  aboutToAppear(): void {
    const p = downloadVM.pending
    this.name = p !== null ? p.fileName : ''
    this.ctrl = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.download_confirm_title'),
        contentBuilder: (): void => {
          this.dialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.download_action')], false,
          (index: number): void => {
            if (index === 1) {
              downloadVM.confirmDownload(this.name)
            } else {
              downloadVM.cancelDownload()
            }
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      cancel: (): void => {
        // 点遮罩/返回键关闭：同步清空待确认状态
        downloadVM.cancelDownload()
      }
    })
    // aboutToAppear 阶段控制器尚未就绪，下一帧打开
    setTimeout((): void => {
      this.ctrl?.open()
    }, 0)
  }

  aboutToDisappear(): void {
    this.ctrl?.close()
    this.ctrl = null
  }

  /** 弹窗正文：来源链接 + 文件名输入（可编辑）+ 保存位置 */
  @Builder
  dialogContent() {
    Column({ space: 12 }) {
      if (downloadVM.pending !== null) {
        Text(downloadVM.pending.url)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      TextInput({ text: this.name, placeholder: downloadVM.pending?.fileName ?? '' })
        .fontSize(15)
        .height(48)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .onChange((v: string): void => {
          this.name = v
        })
      Text(PublicDownloadDir.labelOf('Download'))
        .fontSize(12)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
  }

  build() {
    Column()
      .width(0)
      .height(0)
  }
}
