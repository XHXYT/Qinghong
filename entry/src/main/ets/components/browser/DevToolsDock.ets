import { webview } from '@kit.ArkWeb';
import { devtoolsVM } from '../../common/utils/DevTools';

/** 前端 __qhDevTools 桥对象：DevTools 前端 ⋮ 菜单停靠侧图标、模拟器开关与 ✕ 关闭按钮经此驱动原生 */
class DevToolsFrontendProxy {
  setLayout(side: string): boolean {
    return devtoolsVM.setLayout(side)
  }

  setDeviceMode(on: boolean): boolean {
    return devtoolsVM.setDeviceMode(on)
  }

  setDeviceFrame(x: number, y: number, w: number, h: number,
    emuW: number, emuH: number, zoom: number): boolean {
    return devtoolsVM.setDeviceFrame(x, y, w, h, emuW, emuH, zoom)
  }

  /** 内核默认 UA：前端关闭设备模拟时用以恢复被 override 的页面 UA（ArkWeb 对空串 UA 不清除） */
  defaultUA(): string {
    return webview.WebviewController.getDefaultUserAgent()
  }

  close(): void {
    devtoolsVM.close()
  }
}

/**
 * DevTools 停靠面板：inspector Web 全高填充。
 * 停靠侧切换/弹出/关闭由前端自身 UI（⋮ 菜单停靠行、✕ 按钮）经 __qhDevTools proxy 驱动。
 * 由 Index 分屏容器按 effectiveSide 分配区域（左/下/右停靠）。
 */
@ComponentV2
export struct DevToolsDock {
  private readonly proxyConfig: JavaScriptProxy = {
    object: new DevToolsFrontendProxy(),
    name: '__qhDevTools',
    methodList: ['setLayout', 'setDeviceMode', 'setDeviceFrame', 'defaultUA', 'close'],
    controller: devtoolsVM.controller
  }

  build() {
    Column() {
      Web({ controller: devtoolsVM.controller, src: devtoolsVM.inspectorUrl })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        // localStorage（DevTools 前端语言/主题/面板设置）由 domStorageAccess 控制；
        // databaseAccess 只管 IndexedDB/WebSQL
        .domStorageAccess(true)
        .databaseAccess(true)
        .javaScriptProxy(this.proxyConfig)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color'))
  }
}
