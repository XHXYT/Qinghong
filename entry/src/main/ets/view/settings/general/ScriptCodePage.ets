import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { UserScriptEngine } from '../../../common/utils/userscript/UserScriptEngine';
import { scriptVM } from '../../../viewmodel/ScriptViewModel';
import { tabsVM } from '../../../viewmodel/TabsViewModel';
import UserScriptInfo from '../../../common/entity/UserScriptInfo';
import { toastUtil } from '../../../common/utils/ui/ToastUtils';

/** 油猴官方脚本开发文档（帮助页「了解更多」跳转目标） */
const TAMPERMONKEY_DOC_URL = 'https://www.tampermonkey.net/documentation.php';

@Builder
export function ScriptCodePageBuilder() {
  ScriptCodePage()
}

/**
 * 脚本源码编辑页：TextArea 等宽编辑 + 帮助半模态 + 未保存修改拦截；
 * 新建（param 空，预填模板）与编辑两种入口
 */
@ComponentV2
struct ScriptCodePage {

  /** 脚本源码（TextArea 双向内容） */
  @Local code: string = UserScriptEngine.NEW_TEMPLATE
  @Local showHelp: boolean = false
  /** 编辑态标记（onReady 按 param 确认，驱动标题） */
  @Local isEdit: boolean = false

  /** 编辑态脚本（null = 新建） */
  private editing: UserScriptInfo | null = null
  /** 进入页面时的初始内容（用于判断是否有未保存修改） */
  private initialCode: string = ''

  build() {
    NaviContainer({
      title: this.isEdit ? $r('app.string.script_edit_source') : $r('app.string.script_add'),
      buttons: [
        new NaviBarButton({
          text: $r('app.string.help'),
          width: 48,
          backgroundColor: Color.Transparent,
          action: (): void => {
            this.showHelp = true
          }
        }),
        new NaviBarButton({
          text: $r('app.string.save'),
          width: 48,
          backgroundColor: Color.Transparent,
          action: (): void => {
            this.saveScript()
          }
        })
      ],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        const key: string = ctx.pathInfo.param as string
        if (key !== undefined && key !== '') {
          const id: number = Number(key)
          for (const s of scriptVM.scripts) {
            if (s.id === id) {
              this.editing = s
              this.code = s.code
              this.isEdit = true
              break
            }
          }
        }
        this.initialCode = this.code
      },
      onBackPressed: (): boolean => {
        // 有未保存修改时拦截返回键，弹确认框防误触丢失
        if (this.isDirty()) {
          this.confirmLeave((): void => {
            QhState.popPage()
          })
          return true
        }
        return false
      }
    })
  }

  /** 是否有未保存的修改 */
  private isDirty(): boolean {
    return this.code !== this.initialCode
  }

  /** 有未保存修改时弹拦截框，确认后才执行离开动作 */
  private confirmLeave(leave: () => void): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.script_unsaved_title'),
      message: $r('app.string.script_unsaved_message'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.script_leave'),
          fontColor: Color.Red,
          action: (): void => {
            leave()
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    })
  }

  /** 打开油猴文档新标签页并退回浏览器主页 */
  private openDocAndLeave(): void {
    tabsVM.newTab(TAMPERMONKEY_DOC_URL)
    QhState.popToRoot()
  }

  /** 保存脚本：新建安装 / 编辑更新，成功后返回 */
  private saveScript(): void {
    if (this.code.trim() === '') {
      toastUtil.showToast({ message: $r('app.string.script_code_empty') })
      return
    }
    if (this.editing !== null) {
      scriptVM.saveFromEdit(this.editing, this.code).then((): void => {
        toastUtil.showToast({ message: $r('app.string.saved') })
        QhState.popPage()
      })
      return
    }
    scriptVM.addFromCode(this.code).then((result: boolean | null): void => {
      if (result === null) {
        toastUtil.showToast({ message: $r('app.string.script_code_empty') })
        return
      }
      toastUtil.showToast({ message: result ? $r('app.string.script_added') : $r('app.string.script_replaced') })
      QhState.popPage()
    })
  }

  @Builder
  pageContent() {
    Column() {
      TextArea({ text: this.code, placeholder: $r('app.string.script_code_hint') })
        .width('100%')
        .layoutWeight(1)
        .fontSize(14)
        .fontFamily('monospace')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .padding(12)
        .onChange((v: string): void => {
          this.code = v
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 + QhState.bottomRectHeight })
    .bindSheet(this.showHelp!!, this.helpBuilder(), {
      preferType: SheetType.CENTER,
      dragBar: true,
      showClose: true,
      height: SheetSize.LARGE,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showHelp = false
      }
    })
  }

  /** 帮助：Metadata 字段与注入机制说明（对齐 Via 帮助对话框） */
  @Builder
  helpBuilder() {
    Column() {
      Scroll() {
        Column({ space: 10 }) {
          Text($r('app.string.script_help_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          Text($r('app.string.script_help_content'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .lineHeight(20)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, right: 24, top: 20, bottom: 12 })
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .layoutWeight(1)

      // 底部固定「了解更多」：跳转油猴官方脚本文档
      Text($r('app.string.script_learn_more'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(QhState.currentThemeColor)
        .padding({ top: 12, bottom: 12 + QhState.bottomRectHeight })
        .onClick(() => {
          this.showHelp = false
          // 有未保存修改时先弹拦截框，防止编辑内容丢失
          if (this.isDirty()) {
            this.confirmLeave((): void => {
              this.openDocAndLeave()
            })
            return
          }
          this.openDocAndLeave()
        })
    }
    .width('100%')
    .height('100%')
  }
}
