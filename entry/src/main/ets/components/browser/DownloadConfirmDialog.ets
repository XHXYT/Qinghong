import { CustomContentDialog } from '@kit.ArkUI';
import { downloadVM } from '../../viewmodel/DownloadViewModel';
import { buildDialogButtons } from '../dialog/AppContentDialog';
import { PublicDownloadDir } from '../../common/utils/download/PublicDownloadDir';
import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import { toastUtil } from '../../common/utils/ui/ToastUtils';
import { ResourceUtils } from '../../common/utils/app/ResourceUtil';
import { appSettings } from '../../common/entity/SettingsModel';

/**
 * 下载确认弹窗：接管下载事件后先确认再下载（文件名可编辑）。
 * 复用系统 CustomContentDialog（与其他弹窗同款按钮布局与风格）；
 * 组件挂载即打开弹窗，确认/取消清空 pending 后由根页卸载并关闭。
 * .crx 文件（扩展安装包）：扩展功能开启时附加「安装」按钮（直装不落盘），
 * 原下载按钮文案变「仅下载」，按钮组为 取消 / 仅下载 / 安装。
 */
@ComponentV2
export struct DownloadConfirmDialog {

  @Local name: string = ''
  private ctrl: CustomDialogController | null = null

  /** 待下载文件是否为 .crx 扩展安装包（按原始文件名判断，不受用户改名影响；扩展总开关关闭时不出安装入口） */
  private isCrxPending(): boolean {
    const p = downloadVM.pending
    return p !== null && p.fileName.toLowerCase().endsWith('.crx') && appSettings.extension_enabled
  }

  /** 安装 .crx（清空待确认状态后走扩展直装，不落盘不进下载列表） */
  private installPending(): void {
    const p = downloadVM.pending
    if (p === null) {
      return
    }
    downloadVM.cancelDownload()
    toastUtil.showToast({ message: ResourceUtils.getString($r('app.string.ext_installing')) })
    extensionVM.installFromUrl(p.url).then((ok: boolean): void => {
      const res: Resource = ok ? $r('app.string.ext_install_success') : $r('app.string.ext_install_fail')
      toastUtil.showToast({ message: ResourceUtils.getString(res) })
    })
  }

  aboutToAppear(): void {
    const p = downloadVM.pending
    this.name = p !== null ? p.fileName : ''
    const crx: boolean = this.isCrxPending()
    const labels: ResourceStr[] = crx
      ? [$r('app.string.cancel'), $r('app.string.download_only'), $r('app.string.ext_store_install_short')]
      : [$r('app.string.cancel'), $r('app.string.download_action')]
    this.ctrl = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.download_confirm_title'),
        contentBuilder: (): void => {
          this.dialogContent()
        },
        buttons: buildDialogButtons(labels, false,
          (index: number): void => {
            if (crx) {
              // 取消 / 仅下载 / 安装
              if (index === 2) {
                this.installPending()
              } else if (index === 1) {
                downloadVM.confirmDownload(this.name)
              } else {
                downloadVM.cancelDownload()
              }
            } else {
              if (index === 1) {
                downloadVM.confirmDownload(this.name)
              } else {
                downloadVM.cancelDownload()
              }
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
