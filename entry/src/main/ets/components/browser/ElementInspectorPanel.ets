import { webview } from '@kit.ArkWeb';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { inspectorVM, InspectLog } from '../../viewmodel/InspectorViewModel';
import { ViewSourceScripts } from '../../common/utils/ViewSourceScripts';
import { QhState } from '../../entryability/AppState';
import { createLogger } from '../../common/utils/Logger';
import { ResourceUtils } from '../../common/utils/ResourceUtil';

const logger = createLogger('InspPanel')

/**
 * 功能选择分段按钮（元素/调试、源码/结构共用）
 */
@ComponentV2
struct InspSegBtn {
  @Require @Param label: ResourceStr
  @Require @Param active: boolean
  @Event onTap: () => void = () => {
  }

  build() {
    Text(this.label)
      .fontSize(11)
      .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.active ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
      .padding({ left: 9, right: 9, top: 4, bottom: 4 })
      .height(22)
      .borderRadius(11)
      .backgroundColor(this.active ? $r('sys.color.comp_background_primary') : Color.Transparent)
      .onClick(() => {
        this.onTap()
      })
  }
}

/**
 * 工具栏文字按钮（选/父/AD）
 */
@ComponentV2
struct InspToolBtn {
  @Require @Param label: string
  @Require @Param active: boolean
  @Require @Param dimmed: boolean
  @Event onTap: () => void = () => {
  }

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.active ? Color.White : $r('sys.color.font_primary'))
      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .height(26)
      .borderRadius(13)
      .backgroundColor(this.active ? QhState.currentThemeColor : $r('sys.color.comp_background_tertiary'))
      .opacity(this.dimmed ? 0.45 : 1)
      .onClick(() => {
        if (!this.dimmed) {
          this.onTap()
        }
      })
  }
}

/**
 * 元素审查面板（自定义底部覆盖层，非系统 sheet——页面保持可交互）：
 * 工具栏 = 元素|调试 分段 → 源码|结构 切换 → 选/父/AD → 增高 → 关闭；
 * 元素页 = 面板内嵌 Web 渲染选中元素源码/结构（ViewSourceScripts.buildDoc 无内建顶栏变体）；
 * 调试页 = 分级着色控制台日志 + JS 求值输入框
 */
@ComponentV2
export struct ElementInspectorPanel {
  /** 面板内容 Web 控制器 */
  private panelController: webview.WebviewController = new webview.WebviewController()
  /** 内容文档自愈重试标记（初始 about:blank 竞态） */
  private docRetried: boolean = false
  /** 控制台输入框内容 */
  @Local consoleInput: string = ''
  /** 控制台日志列表滚动器（新日志自动滚到底部） */
  private logScroller: Scroller = new Scroller()

  @Computed
  get docKey(): string {
    return inspectorVM.pickedHtml
  }

  @Computed
  get logCount(): number {
    return inspectorVM.currentLogs.length
  }

  @Monitor('docKey')
  onDocKeyChange(): void {
    this.docRetried = false
    this.loadElementDoc()
  }

  @Monitor('logCount')
  onLogCountChange(): void {
    if (inspectorVM.currentLogs.length > 0) {
      this.logScroller.scrollToIndex(inspectorVM.currentLogs.length - 1)
    }
  }

  /** 面板出现前的键盘避让模式（卸载时恢复） */
  private savedAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET

  /** 挂载即切 RESIZE：键盘弹出由系统压缩页面高度，面板顶不被顶出屏幕 */
  aboutToAppear(): void {
    try {
      this.savedAvoidMode = this.getUIContext().getKeyboardAvoidMode()
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    } catch (e) {
      logger.error(`切换键盘避让模式失败: ${e}`)
    }
  }

  aboutToDisappear(): void {
    inspectorVM.onPanelHidden()
    try {
      this.getUIContext().setKeyboardAvoidMode(this.savedAvoidMode)
    } catch (e) {
      logger.error(`恢复键盘避让模式失败: ${e}`)
    }
  }

  /** 加载选中元素文档（picked 为空跳过；控制器未就绪时由 onControllerAttached 兜底） */
  private loadElementDoc(): void {
    if (inspectorVM.pickedHtml === '') {
      return
    }
    const doc = ViewSourceScripts.buildDoc('', inspectorVM.pickedHtml,
      ResourceUtils.getString($r('app.string.view_source')),
      ResourceUtils.getString($r('app.string.dom_tree')),
      false, inspectorVM.treeView ? 'tree' : 'src')
    try {
      this.panelController.loadData(doc, 'text/html', 'UTF-8', ' ', ' ')
      logger.info(`loadElementDoc 已提交 docLen=${doc.length}`)
    } catch (e) {
      logger.error(`loadElementDoc 失败: ${e}`)
    }
  }

  /** 内容校验自愈（about:blank 竞态，同源码视图模式，重试一次） */
  private verifyPanelDoc(): void {
    try {
      this.panelController.runJavaScript('document.body?document.body.innerText.length:0')
        .then((raw: string): void => {
          let len = 0
          try {
            len = Number(JSON.parse(raw))
          } catch (e) {
            len = 0
          }
          if (len <= 0 && !this.docRetried) {
            this.docRetried = true
            this.loadElementDoc()
          }
        })
        .catch((): void => {
        })
    } catch (e) {
      // 控制器未就绪
    }
  }

  private toggleSelect(): void {
    if (inspectorVM.selecting) {
      inspectorVM.cancelSelect()
    } else {
      inspectorVM.startSelect()
    }
  }

  private toggleTreeView(): void {
    inspectorVM.treeView = !inspectorVM.treeView
    try {
      this.panelController.runJavaScript(`window.__qhSetView&&window.__qhSetView('${inspectorVM.treeView ? 'tree' : 'src'}')`)
        .catch((): void => {
        })
    } catch (e) {
      // Web 未挂载时忽略（重载文档时按当前 treeView 初始化）
    }
  }

  private submitConsole(): void {
    const expr = this.consoleInput.trim()
    if (expr === '') {
      return
    }
    inspectorVM.evalConsole(expr)
    this.consoleInput = ''
  }

  private logColor(level: string): string {
    if (level === 'error') {
      return '#ef5350'
    }
    if (level === 'warn') {
      return '#ffa726'
    }
    if (level === 'result') {
      return '#66bb6a'
    }
    return '#8a93a6'
  }

  build() {
    // 面板本体直接作为 Stack 子节点底对齐（不套全屏容器——全屏容器会拦截网页触摸）
    Column() {
      this.toolbarBuilder()
      if (inspectorVM.selecting) {
        Row() {
          Text($r('app.string.inspect_selecting_hint'))
            .fontSize(13)
            .fontColor('#3399ff')
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
      } else if (inspectorVM.mode === 'element') {
        if (inspectorVM.pickedHtml === '') {
          Column() {
            Text($r('app.string.inspect_empty_hint'))
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Web({ src: 'about:blank', controller: this.panelController })
            .javaScriptAccess(true)
            .domStorageAccess(false)
            .darkMode(WebDarkMode.Auto)
            .width('100%')
            .layoutWeight(1)
            .onControllerAttached(() => {
              this.loadElementDoc()
            })
            .onPageEnd(() => {
              this.verifyPanelDoc()
            })
        }
      } else {
        this.consoleBuilder()
      }
    }
    .width('100%')
    .height(inspectorVM.selecting ? 84 : (inspectorVM.fullHeight ? '94%' : '45%'))
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius({ topLeft: 18, topRight: 18 })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)', offsetY: -4 })
  }

  @Builder
  toolbarBuilder() {
    Row({ space: 6 }) {
      // 已选中元素时收成下拉选择省空间，未选中保持分段按钮
      if (inspectorVM.pickedHtml !== '') {
        Select([
          { value: ResourceUtils.getString($r('app.string.inspect_tab_element')) },
          { value: ResourceUtils.getString($r('app.string.inspect_tab_console')) }
        ])
          .selected(inspectorVM.mode === 'console' ? 1 : 0)
          .value(inspectorVM.mode === 'console'
            ? ResourceUtils.getString($r('app.string.inspect_tab_console'))
            : ResourceUtils.getString($r('app.string.inspect_tab_element')))
          .onSelect((index: number) => {
            inspectorVM.mode = index === 1 ? 'console' : 'element'
          })
          .font({ size: 11 })
          .fontColor($r('sys.color.font_primary'))
          .optionFont({ size: 11 })
          .optionFontColor($r('sys.color.font_primary'))
          .selectedOptionFont({ size: 11 })
          .selectedOptionFontColor($r('sys.color.font_primary'))
          .selectedOptionBgColor($r('sys.color.comp_background_tertiary'))
          .controlSize(ControlSize.SMALL)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(13)
          .height(26)
      } else {
        Row({ space: 2 }) {
          InspSegBtn({
            label: $r('app.string.inspect_tab_element'),
            active: inspectorVM.mode === 'element',
            onTap: (): void => {
              inspectorVM.mode = 'element'
            }
          })
          InspSegBtn({
            label: $r('app.string.inspect_tab_console'),
            active: inspectorVM.mode === 'console',
            onTap: (): void => {
              inspectorVM.mode = 'console'
            }
          })
        }
        .padding(2)
        .borderRadius(14)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
      }

      if (inspectorVM.mode === 'element') {
        if (inspectorVM.pickedHtml !== '' && !inspectorVM.selecting) {
          Row({ space: 2 }) {
            InspSegBtn({
              label: $r('app.string.view_source'),
              active: !inspectorVM.treeView,
              onTap: (): void => {
                if (inspectorVM.treeView) {
                  this.toggleTreeView()
                }
              }
            })
            InspSegBtn({
              label: $r('app.string.dom_tree'),
              active: inspectorVM.treeView,
              onTap: (): void => {
                if (!inspectorVM.treeView) {
                  this.toggleTreeView()
                }
              }
            })
          }
          .padding(2)
          .borderRadius(14)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
        }
        InspToolBtn({
          label: ResourceUtils.getString($r('app.string.inspect_btn_select')),
          active: inspectorVM.selecting || inspectorVM.pickedSelector !== '',
          dimmed: false,
          onTap: (): void => {
            this.toggleSelect()
          }
        })
        InspToolBtn({
          label: ResourceUtils.getString($r('app.string.inspect_btn_parent')),
          active: false,
          dimmed: inspectorVM.pickedSelector === '',
          onTap: (): void => {
            inspectorVM.pickParent()
          }
        })
        InspToolBtn({
          label: ResourceUtils.getString($r('app.string.inspect_btn_child')),
          active: false,
          dimmed: inspectorVM.childDepth <= 0,
          onTap: (): void => {
            inspectorVM.pickChild()
          }
        })
        InspToolBtn({
          label: 'AD',
          active: false,
          dimmed: inspectorVM.pickedSelector === '',
          onTap: (): void => {
            inspectorVM.blockPicked()
          }
        })
      } else {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
          .padding({ left: 6, right: 6 })
          .onClick(() => {
            inspectorVM.clearLogs()
          })
      }

      Blank()

      SymbolGlyph(inspectorVM.fullHeight ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
        .padding({ left: 4, right: 4 })
        .onClick(() => {
          inspectorVM.fullHeight = !inspectorVM.fullHeight
        })
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
        .padding({ left: 4, right: 4 })
        .onClick(() => {
          inspectorVM.close()
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 10, right: 6 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: $r('sys.color.comp_background_tertiary') })
  }

  @Builder
  consoleBuilder() {
    Column() {
      if (inspectorVM.currentLogs.length === 0) {
        Column() {
          Text($r('app.string.inspect_console_empty'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.logScroller }) {
          ForEach(inspectorVM.currentLogs, (lg: InspectLog) => {
            ListItem() {
              Column({ space: 2 }) {
                Text(lg.msg)
                  .fontSize(12)
                  .fontColor(this.logColor(lg.level))
                  .width('100%')
                if (lg.src !== '') {
                  Text(`${lg.time}  ${lg.src}:${lg.line}`)
                    .fontSize(10)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width('100%')
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            }
          }, (lg: InspectLog) => lg.seq.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({
          strokeWidth: 1,
          color: $r('sys.color.comp_background_tertiary'),
          startMargin: 14,
          endMargin: 14
        })
      }

      Row({ space: 8 }) {
        TextInput({
          placeholder: ResourceUtils.getString($r('app.string.inspect_console_hint')),
          text: this.consoleInput
        })
          .layoutWeight(1)
          .fontSize(12)
          .height(36)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.consoleInput = v
          })
          .onSubmit(() => {
            this.submitConsole()
          })
        Text($r('app.string.inspect_console_run'))
          .fontSize(13)
          .fontColor(QhState.currentThemeColor)
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .onClick(() => {
            this.submitConsole()
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6,
        bottom: Math.max(QhState.bottomRectHeight, 10) })
    }
    .width('100%')
    .layoutWeight(1)
  }
}
