import { pasteboard } from '@kit.BasicServicesKit';
import { NaviContainer } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { UserScriptEngine } from '../../../common/utils/UserScriptEngine';
import { scriptVM, ScriptViewModel } from '../../../viewmodel/ScriptViewModel';
import UserScriptInfo from '../../../common/entity/UserScriptInfo';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';

/** 运行时机选项 */
const RUN_AT_OPTIONS: string[] = ['document-start', 'document-end', 'document-idle'];

@Builder
export function ScriptEditPageBuilder() {
  ScriptEditPage()
}

/**
 * 脚本元数据编辑页（对齐 Via「编辑」页）：
 * 首行名称/版本点按弹脚本信息半模态；运行时机选择；
 * 匹配/排除逐条编辑；高级区跳源码编辑页与重置
 */
@ComponentV2
struct ScriptEditPage {

  /** 编辑中的脚本 id（live() 经 scriptVM.scripts 实时解析，避免重载后引用失效） */
  private scriptId: number = -1

  /** 当前打开的半模态：'' 关闭 / 'info' 脚本信息 / 'runtime' 运行时机 / 'pattern' 匹配排除编辑 */
  @Local sheetKind: string = ''
  /** 匹配/排除编辑 sheet（patternIndex -1 = 新增） */
  @Local patternIsMatch: boolean = true
  @Local patternIndex: number = -1
  @Local patternValue: string = ''

  private live(): UserScriptInfo | null {
    for (const s of scriptVM.scripts) {
      if (s.id === this.scriptId) {
        return s
      }
    }
    return null
  }

  private liveRunAt(): string {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? s.runAt : 'document-idle'
  }

  private liveName(): string {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? s.name : ''
  }

  private liveVersion(): string {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? s.version : ''
  }

  private liveUpdateUrl(): string {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? s.updateUrl : ''
  }

  private liveUpdatedText(): string {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? ScriptViewModel.formatStamp(s.updateTime) : '-'
  }

  private liveCreatedText(): string {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? ScriptViewModel.formatStamp(s.createTime) : '-'
  }

  private liveSizeText(): string {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? ScriptViewModel.sizeText(s.code) : '-'
  }

  /** 源码未声明 @run-at 时展示（默认） */
  private isDefaultRunAt(): boolean {
    const s: UserScriptInfo | null = this.live()
    return s === null || s.code.indexOf('@run-at') < 0
  }

  private liveMatches(): string[] {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? UserScriptEngine.splitLines(s.matches) : []
  }

  private liveExcludes(): string[] {
    const s: UserScriptInfo | null = this.live()
    return s !== null ? UserScriptEngine.splitLines(s.excludes) : []
  }

  private runAtDisplay(): string {
    const runAt: string = this.liveRunAt()
    if (!this.isDefaultRunAt()) {
      return runAt
    }
    return `${runAt}（${ResourceUtils.getString($r('app.string.script_runtime_default'))}）`
  }

  build() {
    NaviContainer({
      title: $r('app.string.script_edit'),
      buttons: [],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        const key: string = ctx.pathInfo.param as string
        if (key !== undefined && key !== '') {
          this.scriptId = Number(key)
        }
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List() {
      // 首行：名称 + 版本（点按弹脚本信息）
      ListItem() {
        Column({ space: 3 }) {
          Text(this.liveName())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
            .maxLines(2)
          Text(this.liveVersion())
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => {
          this.sheetKind = 'info'
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)

      // 运行时机
      ListItem() {
        Column({ space: 3 }) {
          Text($r('app.string.script_runtime'))
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
          Text(this.runAtDisplay())
            .fontSize(13)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .onClick(() => {
          this.sheetKind = 'runtime'
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 12 })

      // 匹配
      ListItem() {
        Text($r('app.string.script_section_match'))
          .fontSize(13)
          .fontColor(QhState.currentThemeColor)
          .width('100%')
          .padding({ left: 16, top: 14, bottom: 4 })
      }
      .width('100%')

      ForEach(this.liveMatches(), (m: string, idx: number) => {
        ListItem() {
          this.ruleRow(m)
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: 8 })
        .onClick(() => {
          this.openPatternEditor(true, idx, m)
        })
      }, (m: string, idx: number): string => `m_${idx}_${m}`)

      ListItem() {
        this.addRow($r('app.string.script_add_match'))
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 8 })
      .onClick(() => {
        this.openPatternEditor(true, -1, '')
      })

      // 排除
      ListItem() {
        Text($r('app.string.script_section_exclude'))
          .fontSize(13)
          .fontColor(QhState.currentThemeColor)
          .width('100%')
          .padding({ left: 16, top: 14, bottom: 4 })
      }
      .width('100%')

      ForEach(this.liveExcludes(), (e: string, idx: number) => {
        ListItem() {
          this.ruleRow(e)
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: 8 })
        .onClick(() => {
          this.openPatternEditor(false, idx, e)
        })
      }, (e: string, idx: number): string => `e_${idx}_${e}`)

      ListItem() {
        this.addRow($r('app.string.script_add_exclude'))
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 8 })
      .onClick(() => {
        this.openPatternEditor(false, -1, '')
      })

      // 高级
      ListItem() {
        Text($r('app.string.script_section_advanced'))
          .fontSize(13)
          .fontColor(QhState.currentThemeColor)
          .width('100%')
          .padding({ left: 16, top: 14, bottom: 4 })
      }
      .width('100%')

      ListItem() {
        Text($r('app.string.script_edit_source'))
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 15, bottom: 15 })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 8 })
      .onClick(() => {
        QhState.pushPage('settings_script_code', `${this.scriptId}`)
      })

      ListItem() {
        Text($r('app.string.script_reset'))
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 15, bottom: 15 })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 8 })
      .onClick(() => {
        this.confirmReset()
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(QhState.bottomRectHeight)
    .padding({ left: 16, right: 16, top: 10 })
    .bindSheet(this.sheetKind !== ''!!, this.sheetContentBuilder(), {
      preferType: SheetType.CENTER,
      height: this.sheetKind === 'info' ? 400 : (this.sheetKind === 'runtime' ? 250 : 240),
      dragBar: false,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.sheetKind = ''
      }
    })
  }

  /** 半模态内容分发：单 bindSheet 按 sheetKind 切换内容与高度 */
  @Builder
  sheetContentBuilder() {
    if (this.sheetKind === 'info') {
      this.infoSheetBuilder()
    } else if (this.sheetKind === 'runtime') {
      this.runtimeSheetBuilder()
    } else {
      this.patternSheetBuilder()
    }
  }

  @Builder
  ruleRow(v: string) {
    Text(v)
      .fontSize(15)
      .fontColor($r('sys.color.font_primary'))
      .width('100%')
      .maxLines(2)
      .padding({ left: 16, right: 16, top: 15, bottom: 15 })
  }

  @Builder
  addRow(label: ResourceStr) {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_primary')])
      Text(label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 15, bottom: 15 })
  }

  // ==================== 脚本信息半模态 ====================

  @Builder
  infoRow(label: ResourceStr, value: string, copyable: boolean) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .width(84)
      Text(value !== '' ? value : '-')
        .fontSize(14)
        .fontColor(copyable ? QhState.currentThemeColor : $r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(copyable ? 1 : 2)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 9, bottom: 9 })
    .onClick(() => {
      if (copyable && value !== '') {
        this.copyText(value)
      }
    })
  }

  @Builder
  infoSheetBuilder() {
    Column() {
      Text($r('app.string.script_info_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .height(48)
      Scroll() {
        Column() {
          this.infoRow($r('app.string.script_info_name'), this.liveName(), false)
          this.infoRow($r('app.string.version'), this.liveVersion(), false)
          this.infoRow($r('app.string.script_info_url'), this.liveUpdateUrl(), true)
          this.infoRow($r('app.string.script_info_updated'), this.liveUpdatedText(), false)
          this.infoRow($r('app.string.script_info_created'), this.liveCreatedText(), false)
          this.infoRow($r('app.string.script_info_size'), this.liveSizeText(), false)
        }
        .width('100%')
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: QhState.bottomRectHeight })
  }

  private copyText(text: string): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        toastUtil.showToast({ message: $r('app.string.script_copied') })
      })
      .catch((): void => {
      })
  }

  // ==================== 运行时机选择半模态 ====================

  @Builder
  runtimeSheetBuilder() {
    Column() {
      Text($r('app.string.script_runtime'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .height(48)
      ForEach(RUN_AT_OPTIONS, (opt: string) => {
        Row() {
          Text(opt)
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
          if (opt === this.liveRunAt()) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(18)
              .fontColor([QhState.currentThemeColor])
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 13, bottom: 13 })
        .onClick(() => {
          const s: UserScriptInfo | null = this.live()
          if (s !== null && s.runAt !== opt) {
            scriptVM.updateRuntime(s, opt)
          }
          this.sheetKind = ''
        })
      }, (opt: string): string => opt)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: QhState.bottomRectHeight })
  }

  // ==================== 匹配/排除编辑半模态 ====================

  private openPatternEditor(isMatch: boolean, idx: number, value: string): void {
    this.patternIsMatch = isMatch
    this.patternIndex = idx
    this.patternValue = value
    this.sheetKind = 'pattern'
  }

  /** 保存当前编辑的规则（新增追加 / 修改原地覆盖），空规则提示 */
  private savePattern(): void {
    const v: string = this.patternValue.trim()
    if (v === '') {
      toastUtil.showToast({ message: $r('app.string.script_pattern_invalid') })
      return
    }
    const s: UserScriptInfo | null = this.live()
    if (s === null) {
      this.sheetKind = ''
      return
    }
    const matches: string[] = this.liveMatches()
    const excludes: string[] = this.liveExcludes()
    if (this.patternIsMatch) {
      if (this.patternIndex < 0) {
        matches.push(v)
      } else if (this.patternIndex < matches.length) {
        matches[this.patternIndex] = v
      }
    } else {
      if (this.patternIndex < 0) {
        excludes.push(v)
      } else if (this.patternIndex < excludes.length) {
        excludes[this.patternIndex] = v
      }
    }
    scriptVM.updatePatterns(s, matches.join('\n'), excludes.join('\n'))
    this.sheetKind = ''
  }

  /** 删除当前编辑的规则 */
  private deletePattern(): void {
    const s: UserScriptInfo | null = this.live()
    if (s !== null && this.patternIndex >= 0) {
      const matches: string[] = this.liveMatches()
      const excludes: string[] = this.liveExcludes()
      if (this.patternIsMatch) {
        if (this.patternIndex < matches.length) {
          matches.splice(this.patternIndex, 1)
        }
      } else {
        if (this.patternIndex < excludes.length) {
          excludes.splice(this.patternIndex, 1)
        }
      }
      scriptVM.updatePatterns(s, matches.join('\n'), excludes.join('\n'))
    }
    this.sheetKind = ''
  }

  @Builder
  patternSheetBuilder() {
    Column({ space: 14 }) {
      Text(this.patternIsMatch
        ? (this.patternIndex < 0 ? $r('app.string.script_add_match') : $r('app.string.script_section_match'))
        : (this.patternIndex < 0 ? $r('app.string.script_add_exclude') : $r('app.string.script_section_exclude')))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
      TextInput({ text: this.patternValue, placeholder: $r('app.string.script_pattern_hint') })
        .fontSize(15)
        .height(44)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .onChange((v: string): void => {
          this.patternValue = v
        })
      Row({ space: 12 }) {
        if (this.patternIndex >= 0) {
          Button($r('app.string.delete'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.Red)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              this.deletePattern()
            })
        }
        Button($r('app.string.save'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(QhState.currentThemeColor)
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.savePattern()
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 18, bottom: 18 + QhState.bottomRectHeight })
  }

  // ==================== 重置 ====================

  private confirmReset(): void {
    const s: UserScriptInfo | null = this.live()
    if (s === null) {
      return
    }
    if (s.updateUrl === '') {
      toastUtil.showToast({ message: $r('app.string.script_no_update_url') })
      return
    }
    toastUtil.showAlertDialog({
      title: $r('app.string.script_reset'),
      message: $r('app.string.script_reset_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.script_reset'),
          fontColor: Color.Red,
          action: (): void => {
            scriptVM.resetFromUrl(s).then((ok: boolean): void => {
              toastUtil.showToast({
                message: ok ? $r('app.string.saved') : $r('app.string.script_update_failed')
              })
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
    }, 'resetScript')
  }
}
