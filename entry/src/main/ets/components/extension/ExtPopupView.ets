import { webview } from '@kit.ArkWeb';
import { createLogger } from '../../common/utils/Logger';
import { appSettings } from '../../common/entity/SettingsModel';
import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import { ExtensionResources } from '../../common/utils/ExtensionResources';
import { _QhState } from '../../entryability/AppState';
import ExtensionInfo from '../../common/entity/ExtensionInfo';

const logger = createLogger('ExtPopup')

/** hex 背景亮度（0-1）：判定头部文字对比色 */
function hexLuminance(hex: string): number {
  if (hex.length !== 7 || hex[0] !== '#') {
    return 1
  }
  const r: number = parseInt(hex.substring(1, 3), 16)
  const g: number = parseInt(hex.substring(3, 5), 16)
  const b: number = parseInt(hex.substring(5, 7), 16)
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255
}

/** 通道等比加暗（force_dark_web 开启时算法加暗的近似） */
function darkenHex(hex: string, factor: number): string {
  if (hex.length !== 7 || hex[0] !== '#') {
    return hex
  }
  const channels: number[] = []
  for (let i: number = 1; i < 7; i += 2) {
    channels.push(Math.min(255, Math.round(parseInt(hex.substring(i, i + 2), 16) * factor)))
  }
  let out: string = '#'
  for (const c of channels) {
    const s: string = c.toString(16).toUpperCase()
    out += s.length < 2 ? `0${s}` : s
  }
  return out
}

/**
 * popup 原生桥（window.__qhNative.gmRequest）：
 * popup 页面 chrome.* 调用转发 ExtensionViewModel 路由
 */
class ExtPopupBridge {
  private readonly handler: (api: string, json: string) => void

  constructor(handler: (api: string, json: string) => void) {
    this.handler = handler
  }

  gmRequest(api: string, json: string): void {
    this.handler(api, json)
  }
}

/**
 * 扩展 popup 面板内容（action.default_popup）：
 * 由 Index 根节点 bindSheet（SheetType.CENTER 居中半模态）承载；
 * popup 主文档经虚拟域由 onInterceptRequest 服务，
 * core + popup 沙箱经 javaScriptOnDocumentStart 在页面脚本前注入。
 * 内容宽度自适应：加载后探测页面自然宽度（如 AdGuard --popup-width:320px），
 * 窄于面板时按自然宽度居中（模拟 Chrome 弹窗收缩尺寸）
 */
@ComponentV2
export struct ExtPopupView {
  @Require @Param ext: ExtensionInfo
  /** popup 内容自然宽度（vp）；0 = 铺满面板 */
  @Local contentWidth: number = 0
  /** 背景探测已获得非默认页色（第二次探测不再覆盖） */
  @Local bgResolved: boolean = false

  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: ExtPopupBridge = new ExtPopupBridge((api: string, json: string): void => {
    extensionVM.handlePopupRequest(api, json, this.ext.extId, this.controller)
  })

  aboutToAppear(): void {
    extensionVM.registerPopupHost(this.controller)
  }

  aboutToDisappear(): void {
    extensionVM.unregisterPopupHost(this.controller)
  }

  /** 面板背景：探测到的页面实际背景色，未探测用系统默认 */
  private panelBg(): ResourceColor {
    return extensionVM.popupBg !== '' ? extensionVM.popupBg : $r('sys.color.comp_background_primary')
  }

  /** 头部扩展名文字对比色：跟随面板背景亮度 */
  private headerFontColor(): ResourceColor {
    if (extensionVM.popupBg === '') {
      return $r('sys.color.font_primary')
    }
    return hexLuminance(extensionVM.popupBg) < 0.5 ? '#FFFFFFFF' : '#FF1A1A1A'
  }

  /** runJavaScript 结果归一化为 hex；'' = 无有效颜色（透明/未设置） */
  private normalizeProbeHex(raw: string): string {
    let s: string = raw
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1)
    }
    if (s.length !== 7 || s[0] !== '#') {
      return ''
    }
    const upper: string = s.toUpperCase()
    if (!/^#[0-9A-F]{6}$/.test(upper)) {
      return ''
    }
    return appSettings.force_dark_web ? darkenHex(upper, 0.3) : upper
  }

  /** 页面默认底色（Chrome popup 无背景时为白；force_dark 时为加暗近似） */
  private defaultProbeHex(): string {
    return appSettings.force_dark_web ? darkenHex('#FFFFFF', 0.3) : '#FFFFFF'
  }

  /**
   * 探测页面实际背景色（body → documentElement → 首个子元素，首个不透明色），
   * 同步到 VM 驱动 sheet/面板背景自适应；
   * onlyIfUnresolved：首次探测已获得非默认页色时跳过（避免覆盖用户已见效果）
   */
  private probePanelBg(onlyIfUnresolved: boolean): void {
    const expr: string = '(function(){'
      + 'function px(v){v=Math.max(0,Math.min(255,Math.round(v)));var s=v.toString(16);return s.length<2?"0"+s:s;}'
      + 'function solid(el){'
      + 'if(!el)return "";'
      + 'try{'
      + 'var s=window.getComputedStyle(el).backgroundColor;'
      + 'var m=s&&s.match(/^rgba?\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*(?:,\\s*([\\d.]+)\\s*)?\\)$/);'
      + 'if(!m)return "";'
      + 'if(m[4]!==undefined&&parseFloat(m[4])<0.5)return "";'
      + 'return "#"+px(+m[1])+px(+m[2])+px(+m[3]);'
      + '}catch(e){return ""}'
      + '}'
      + 'var b=document.body,h=document.documentElement;'
      + 'return solid(b)||solid(h)||solid(b&&b.firstElementChild)||"";})()'
    this.controller.runJavaScript(expr)
      .then((r: string) => {
        if (onlyIfUnresolved && this.bgResolved) {
          return
        }
        const hex: string = this.normalizeProbeHex(r)
        if (hex === '') {
          return
        }
        if (hex !== this.defaultProbeHex()) {
          this.bgResolved = true
        }
        extensionVM.popupBg = hex
        logger.info(`popup 面板背景=${hex}`)
      })
      .catch((): void => {
      })
  }

  /** 延迟探测内容自然宽度：仅当显著窄于视口时收窄居中（AdGuard body 固定 --popup-width:320px） */
  private probeContentWidth(): void {
    setTimeout((): void => {
      const expr: string = '(function(){'
        + 'var w=document.body?Math.round(document.body.getBoundingClientRect().width):0;'
        + 'var vw=window.innerWidth;'
        + 'return (w>=200&&w<vw-8)?w:0;})()'
      this.controller.runJavaScript(expr)
        .then((r: string) => {
          const n: number = Number(r)
          if (Number.isFinite(n) && n > 0) {
            this.contentWidth = n
            logger.info(`popup 内容宽度=${n}`)
          }
        })
        .catch((): void => {
        })
    }, 500)
  }

  build() {
    Column() {
      // 头部：扩展名（关闭走半模态自带关闭按钮 showClose）
      Row({ space: 8 }) {
        Text(this.ext.name !== '' ? this.ext.name : this.ext.extId)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.headerFontColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(48)
      .padding({ left: 20, right: 40 })
      .alignItems(VerticalAlign.Center)

      // popup 文档（虚拟域主文档，扩展资源由拦截服务）
      Web({ controller: this.controller, src: extensionVM.popupUrlOf(this.ext) })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .darkMode(appSettings.force_dark_web ? WebDarkMode.On : WebDarkMode.Auto)
        .forceDarkAccess(appSettings.force_dark_web)
        .javaScriptOnDocumentStart([{
          script: extensionVM.popupCodeOf(this.ext),
          scriptRules: ['*']
        }])
        .javaScriptProxy({
          object: this.bridge,
          name: '__qhNative',
          methodList: ['gmRequest'],
          controller: this.controller
        })
        .onInterceptRequest((event: OnInterceptRequestEvent) => {
          const url: string = event.request.getRequestUrl()
          if (ExtensionResources.isExtRequest(url)) {
            return ExtensionResources.respond(url, `${_QhState.Context.filesDir}/extensions`)
          }
          return null
        })
        .onConsole((event: OnConsoleEvent): boolean => {
          const level: MessageLevel = event.message.getMessageLevel()
          if (level === MessageLevel.Error || level === MessageLevel.Warn) {
            logger.warn(`[popup console] ${event.message.getMessage()} @ ${event.message.getSourceId()}:${event.message.getLineNumber()}`)
          }
          return false
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          logger.warn(`popup 资源加载失败: ${event.request.getRequestUrl()} err=${event.error.getErrorInfo()}`)
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          logger.warn(`popup HTTP 错误: ${event.request.getRequestUrl()} status=${event.response.getResponseCode()}`)
        })
        .onPageEnd(() => {
          logger.info(`popup 加载完成: ${this.ext.name}`)
          /* 诊断：主文档 DOM 规模（其它扩展空白页定位保留） */
          this.controller.runJavaScript('document.documentElement.outerHTML.length')
            .then((len: string) => {
              logger.info(`popup DOM 长度=${len}`)
            })
            .catch((): void => {
            })
          /* 诊断：3s 后 dump 渲染状态（React 是否挂载/样式是否加载） */
          setTimeout((): void => {
            const expr: string = '(function(){'
              + 'var b=document.body||document.documentElement;'
              + 'var ss=0;try{ss=document.styleSheets.length;}catch(e){}'
              + 'var txt=(b.innerText||"").replace(/\\s+/g," ").substring(0,200);'
              + 'var el=b.querySelectorAll("*").length;'
              + 'var rc=b.firstElementChild?b.firstElementChild.innerHTML.length:-1;'
              + 'return JSON.stringify({ss:ss,el:el,rc:rc,txt:txt});})()'
            this.controller.runJavaScript(expr)
              .then((r: string) => {
                logger.info(`popup 渲染状态=${r}`)
              })
              .catch((): void => {
              })
          }, 3000)
          this.probeContentWidth()
          /* 背景色自适应：700ms 首探；3s 补探（仅首次未获非默认页色时生效，覆盖异步渲染后才有背景的页面） */
          setTimeout((): void => {
            this.probePanelBg(false)
          }, 700)
          setTimeout((): void => {
            this.probePanelBg(true)
          }, 3000)
        })
        .width(this.contentWidth > 0 ? this.contentWidth : '100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.panelBg())
  }
}
