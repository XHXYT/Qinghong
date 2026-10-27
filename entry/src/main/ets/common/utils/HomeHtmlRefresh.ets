/**
 * HTML 主页刷新注册表（外部单例无法 @Monitor，用回调驱动重推配置）
 * 独立工具类：供 HomeHtmlView（注册）、BookmarkViewModel（书签变化触发）等双向引用，避免循环依赖
 */
export class HomeHtmlRefresh {
  private listeners: Array<() => void> = []

  register(fn: () => void): void {
    if (this.listeners.indexOf(fn) < 0) {
      this.listeners.push(fn)
    }
  }

  unregister(fn: () => void): void {
    const i = this.listeners.indexOf(fn)
    if (i >= 0) {
      this.listeners.splice(i, 1)
    }
  }

  /** 通知所有挂载中的 HTML 主页重新拉取配置渲染 */
  request(): void {
    for (const fn of this.listeners) {
      fn()
    }
  }
}

export const homeHtmlRefresh: HomeHtmlRefresh = new HomeHtmlRefresh()
