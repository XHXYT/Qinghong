import { CustomContentDialog } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { NaviContainer } from '../../../../components/NaviContainer';
import { QhState } from '../../../../entryability/AppState';
import { CustomItemInfo, ItemActionType } from '../../../../common/entity/CusItemInfo';
import { CustomListItem } from '../../../../components/CusItemBuilder';
import { buildDialogButtons } from '../../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../../common/utils/ToastUtils';
import { passwordVM } from '../../../../viewmodel/PasswordViewModel';
import PasswordInfo from '../../../../common/entity/PasswordInfo';

@Builder
export function SettingsPasswordSavedBuilder() {
  SavedPasswordsPage()
}

@ComponentV2
struct SavedPasswordsPage {

  @Local passwords: PasswordInfo[] = []

  /** 详情弹窗当前凭据 */
  private detailId: number = -1
  @Local detailHost: string = ''
  @Local detailUsername: string = ''
  private detailPassword: string = ''
  @Local detailShowPassword: boolean = false

  private detailDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.detailDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: this.detailHost,
        contentBuilder: (): void => {
          this.detailContent()
        },
        buttons: buildDialogButtons([$r('app.string.password_copy_action'), $r('app.string.delete')], true,
          (index: number): void => {
            if (index === 0) {
              this.copyPassword()
            } else if (index === 1) {
              this.confirmDelete()
            }
            this.detailDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32,
      onWillAppear: (): void => {
        this.detailShowPassword = false
      }
    })
  }

  private load(): void {
    passwordVM.listAll().then((list: PasswordInfo[]): void => {
      this.passwords = list
    })
  }

  private item(info: PasswordInfo): CustomItemInfo {
    return new CustomItemInfo({
      id: `${info.id}`,
      title: info.host,
      type: ItemActionType.TEXT,
      value: info.username,
      onChange: (v: string | boolean | number): void => {
        this.detailId = info.id ?? -1
        this.detailHost = info.host
        this.detailUsername = info.username
        this.detailPassword = info.password
        this.detailDialog?.open()
      }
    })
  }

  /** 复制密码到系统剪贴板 */
  private copyPassword(): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.detailPassword)
      pasteboard.getSystemPasteboard().setData(data).then((): void => {
        toastUtil.showToast({ message: $r('app.string.copied') })
      })
    } catch (error) {
      console.error(`[SavedPasswords] 复制密码失败: ${error}`)
    }
  }

  private confirmDelete(): void {
    toastUtil.showAlertDialog({
      title: this.detailHost,
      message: $r('app.string.password_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            passwordVM.deleteById(this.detailId).then((): void => {
              this.load()
            })
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'deletePassword')
  }

  build() {
    NaviContainer({
      title: $r('app.string.saved_passwords'),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.load()
      },
      onShown: (): void => {
        this.load()
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      if (this.passwords.length > 0) {
        Repeat<PasswordInfo>(this.passwords)
          .each((ri: RepeatItem<PasswordInfo>) => {
            ListItem() {
              CustomListItem({
                item: this.item(ri.item),
                itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.background_color'))
            .borderRadius(16)
            .clip(true)
            .margin({ top: ri.index === 0 ? 10 : 12 })
          })
          .key((info: PasswordInfo) => `${info.id}`)
      } else {
        ListItem() {
          Text($r('app.string.saved_passwords_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  detailContent() {
    Column({ space: 12 }) {
      Row() {
        Text($r('app.string.label_username'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width(64)
        Text(this.detailUsername === '' ? '-' : this.detailUsername)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      Row() {
        Text($r('app.string.label_password'))
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .width(64)
        Text(this.detailShowPassword ? this.detailPassword : '••••••••')
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph(this.detailShowPassword ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
          .fontSize(20)
          .fontColor([$r('sys.color.font_secondary')])
          .onClick(() => {
            this.detailShowPassword = !this.detailShowPassword
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
