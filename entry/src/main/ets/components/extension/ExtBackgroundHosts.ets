import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { createLogger } from '../../common/utils/app/Logger';
import { extensionVM } from '../../viewmodel/ExtensionViewModel';
import { ExtensionResources } from '../../common/utils/extension/ExtensionResources';
import { _QhState } from '../../entryability/AppState';
import ExtensionInfo from '../../common/entity/ExtensionInfo';

const logger = createLogger('ExtBgHost')

/**
 * bg 宿主原生桥（window.__qhNative.gmRequest）：
 * 背景页 chrome.* 调用转发 ExtensionViewModel 路由
 */
class ExtBgBridge {
  private readonly handler: (api: string, json: string) => void

  constructor(handler: (api: string, json: string) => void) {
    this.handler = handler
  }

  gmRequest(api: string, json: string): void {
    this.handler(api, json)
  }
}

/**
 * 单扩展 background 隐藏宿主：
 * 隐藏 Web 加载虚拟域 __bg__.html（https origin，IDB/localStorage 可用；about:blank 的
 * opaque origin 下 AdGuard tsweb loadStaticRulesets 的 IDB open 被拒），
 * onPageEnd 注入 core + 背景沙箱 + background/service_worker 脚本，
 * 为 content_script 的 runtime.sendMessage 提供消息接收方（runtime.onMessage）
 *
 * bg 控制台堆栈展开/Symbol.toPrimitive 画像等临时诊断已随定位完成移除
 * （历史教训：Error 对象经 onConsole 只剩 message 无 stack，需在页内先行展开；
 *  toPrimitive 画像预览严禁触发任何隐式转换——stub 代理会递归爆栈）
 */
@ComponentV2
struct ExtBackgroundHost {
  @Require @Param ext: ExtensionInfo
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: ExtBgBridge = new ExtBgBridge((api: string, json: string): void => {
    extensionVM.handleBgRequest(api, json, this.ext.extId, this.controller)
  })
  private injected: boolean = false

  aboutToAppear(): void {
    extensionVM.registerBgHost(this.ext.extId, this.controller)
  }

  aboutToDisappear(): void {
    extensionVM.unregisterBgHost(this.ext.extId, this.controller)
  }

  build() {
      Web({ controller: this.controller, src: ExtensionResources.extUrl(this.ext.extId, ExtensionResources.BG_PAGE_PATH) })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: '__qhNative',
          methodList: ['gmRequest'],
          controller: this.controller
        })
        .onInterceptRequest((event: OnInterceptRequestEvent) => {
          // 宿主脚本经虚拟域 script 标签加载，须拦截服务
          const url: string = event.request.getRequestUrl()
          if (ExtensionResources.isExtRequest(url)) {
            return ExtensionResources.respond(url, `${_QhState.Context.filesDir}/extensions`)
          }
          return null
        })
        .onConsole((event: OnConsoleEvent): boolean => {
          const level: MessageLevel = event.message.getMessageLevel()
          if (level === MessageLevel.Error || level === MessageLevel.Warn) {
            logger.warn(`[bg console] ${event.message.getMessage()} @ ${event.message.getSourceId()}:${event.message.getLineNumber()}`)
          }
          return false
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          logger.warn(`bg 资源加载失败: ${event.request.getRequestUrl()} err=${event.error.getErrorInfo()}`)
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          logger.warn(`bg HTTP 错误: ${event.request.getRequestUrl()} status=${event.response.getResponseCode()}`)
        })
        .onPageEnd(() => {
          if (this.injected) {
            return
          }
          this.injected = true
          const code: string = extensionVM.backgroundCodeOf(this.ext)
          if (code === '') {
            return
          }
          this.controller.runJavaScript(code).then((): void => {
            /* 存量标签同步：会话恢复的标签无 onCreated，沙箱待宿主注册 tabs 监听器后补投 */
            extensionVM.syncTabsToBg(this.controller)
          }).catch((e: BusinessError): void => {
            logger.warn(`background 注入失败 (${this.ext.name}): ${e.message}`)
          })
        })
        .width('100%')
        .height('100%')
  }
}

/**
 * 扩展 background 宿主容器：
 * 为每个启用且声明 background/service_worker 的扩展挂一个隐藏 Web，
 * 1x1 裁剪容器铺底渲染（不参与交互、不可见）
 *
 * scriptRules 对照探针（无连字符 scheme 等）已随定论移除：
 * ArkWeb scriptRules 对自定义协议（qinghong-extension://）实测不命中，
 * 扩展页宿主沙箱统一走 '*' 全放行 + 沙箱内 location 守卫（见 ExtensionViewModel.extPageScriptItems）
 */
@ComponentV2
export struct ExtBackgroundHosts {
  build() {
    Stack() {
      ForEach(extensionVM.extensions, (ext: ExtensionInfo) => {
        if (ext.enabled && extensionVM.hasBackground(ext)) {
          Stack() {
            ExtBackgroundHost({ ext: ext })
          }
          .width(1)
          .height(1)
          .clip(true)
        }
      }, (ext: ExtensionInfo) => ext.extId)
    }
    .width(1)
    .height(1)
    .clip(true)
    .opacity(0.01)
    .hitTestBehavior(HitTestMode.None)
  }
}
