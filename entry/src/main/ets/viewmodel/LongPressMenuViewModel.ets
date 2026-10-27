import { systemShare } from '@kit.ShareKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { tabsVM, TabInfo } from './TabsViewModel';
import { downloadVM } from './DownloadViewModel';
import { browserVM } from './BrowserViewModel';
import { toastUtil } from '../common/utils/ToastUtils';
import { adBlockEngine } from '../common/utils/AdBlockEngine';
import { _QhState } from '../entryability/AppState';

/**
 * 网页元素长按菜单（PC 窗口模式为右键菜单）动作执行
 * 条目开关由 LongPressMenuItems/appSettings.long_press_menu 控制
 */

/** 长按上下文：命中元素与页面信息快照 */
export class LongPressContext {
  linkUrl: string = ''
  imageUrl: string = ''
  linkText: string = ''
  pageUrl: string = ''
  pageTitle: string = ''
}

export class LongPressMenuViewModel {

  /**
   * 执行长按菜单动作
   * @param onOpenViewer 看图模式回调（全屏查看图片）
   */
  runAction(id: string, ctx: LongPressContext, tab: TabInfo,
    onOpenViewer: (url: string) => void): void {
    switch (id) {
      case 'open_bg':
        this.openInTab(ctx.linkUrl !== '' ? ctx.linkUrl : ctx.imageUrl, tab, true)
        break
      case 'open_new':
        this.openInTab(ctx.linkUrl !== '' ? ctx.linkUrl : ctx.imageUrl, tab, false)
        break
      case 'view_image':
        if (ctx.imageUrl !== '') {
          tabsVM.navigate(tab, ctx.imageUrl)
        }
        break
      case 'save_image':
      case 'download_image':
        downloadVM.download(ctx.imageUrl, ctx.pageUrl)
        break
      case 'share_image':
        this.share(ctx.imageUrl !== '' ? ctx.imageUrl : ctx.pageUrl)
        break
      case 'search_image':
        this.searchByImage(ctx.imageUrl, tab)
        break
      case 'image_viewer':
        if (ctx.imageUrl !== '') {
          onOpenViewer(ctx.imageUrl)
        }
        break
      case 'page_info':
        this.showPageInfo(ctx)
        break
      case 'mark_ad':
        this.markAd(ctx)
        break
      case 'copy_link_text':
        this.copyText(ctx.linkText !== '' ? ctx.linkText :
          (ctx.linkUrl !== '' ? ctx.linkUrl : ctx.imageUrl))
        break
      case 'scan_qr':
        this.scanImage(ctx.imageUrl)
        break
      case 'copy_link':
        this.copyText(ctx.linkUrl !== '' ? ctx.linkUrl : ctx.imageUrl)
        break
      case 'share':
        this.share(ctx.linkUrl !== '' ? ctx.linkUrl : ctx.pageUrl)
        break
      default:
        break
    }
  }

  /** 复制网页选中文本 */
  copySelectedText(text: string): void {
    if (text.trim() === '') {
      return
    }
    this.copyText(text)
  }

  /** 分享网页选中文本 */
  shareText(text: string): void {
    if (text.trim() === '') {
      return
    }
    try {
      const data = new systemShare.SharedData({
        utd: 'general.plain-text',
        content: text,
        title: text
      })
      const controller = new systemShare.ShareController(data)
      controller.show(_QhState.Context, {})
        .catch((error: BusinessError): void => {
          console.error(`[LongPressVM] 分享文本失败: ${error.code} ${error.message}`)
        })
    } catch (e) {
      console.error(`[LongPressVM] 分享文本异常: ${e}`)
    }
  }

  /** 用地址栏提交逻辑搜索选中文本 */
  searchText(text: string): void {
    const t = text.trim()
    if (t === '') {
      return
    }
    browserVM.submitAddress(t)
  }

  /** 新标签打开（background=true 时新建后切回原标签） */
  private openInTab(url: string, tab: TabInfo, background: boolean): void {
    if (url === '') {
      return
    }
    const current = tabsVM.activeTabId
    const created = tabsVM.newTab(url, tab.isIncognito)
    if (background && created !== null && current >= 0 && tabsVM.activeTabId !== current) {
      tabsVM.activeTabId = current
    }
  }

  /** 复制文本到剪贴板并提示 */
  private copyText(text: string): void {
    if (text === '') {
      return
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      pasteboard.getSystemPasteboard().setData(data)
        .then((): void => {
          toastUtil.showToast({ message: $r('app.string.copied') })
        })
        .catch((error: BusinessError): void => {
          console.error(`[LongPressVM] 复制失败: ${error.code} ${error.message}`)
        })
    } catch (e) {
      console.error(`[LongPressVM] 复制异常: ${e}`)
    }
  }

  /** 系统分享面板（分享链接） */
  private share(url: string): void {
    if (url === '') {
      return
    }
    try {
      const data = new systemShare.SharedData({
        utd: 'general.hyperlink',
        content: url,
        title: url
      })
      const controller = new systemShare.ShareController(data)
      controller.show(_QhState.Context, {})
        .catch((error: BusinessError): void => {
          console.error(`[LongPressVM] 分享失败: ${error.code} ${error.message}`)
        })
    } catch (e) {
      console.error(`[LongPressVM] 分享异常: ${e}`)
    }
  }

  /** 以图搜图：百度识图按图片地址搜索 */
  private searchByImage(imageUrl: string, tab: TabInfo): void {
    if (imageUrl === '') {
      return
    }
    const target = `https://graph.baidu.com/pcpage/index?tpl_from=pc&image_url=${encodeURIComponent(imageUrl)}`
    this.openInTab(target, tab, false)
  }

  /** 页面/元素信息弹窗 */
  private showPageInfo(ctx: LongPressContext): void {
    const lines: string[] = []
    if (ctx.pageTitle !== '') {
      lines.push(ctx.pageTitle)
    }
    if (ctx.pageUrl !== '') {
      lines.push(ctx.pageUrl)
    }
    if (ctx.linkUrl !== '' && ctx.linkUrl !== ctx.pageUrl) {
      lines.push(ctx.linkUrl)
    }
    if (ctx.imageUrl !== '' && ctx.imageUrl !== ctx.linkUrl && ctx.imageUrl !== ctx.pageUrl) {
      lines.push(ctx.imageUrl)
    }
    AlertDialog.show({
      title: $r('app.string.long_press_page_info'),
      message: lines.join('\n'),
      confirm: {
        value: $r('app.string.confirm'),
        action: (): void => {
        }
      }
    })
  }

  /** 标记广告：命中元素地址加入广告拦截自定义规则 */
  private markAd(ctx: LongPressContext): void {
    const target = ctx.imageUrl !== '' ? ctx.imageUrl :
      (ctx.linkUrl !== '' ? ctx.linkUrl : ctx.pageUrl)
    if (target === '') {
      return
    }
    const current = adBlockEngine.loadCustomRulesSync()
    const next = current.trim() !== '' ? `${current.replace(/\s+$/, '')}\n${target}\n` : `${target}\n`
    adBlockEngine.saveCustomRules(next)
      .then((): void => {
        toastUtil.showToast({ message: $r('app.string.ad_marked') })
      })
      .catch((): void => {
      })
  }

  /** 识别图片二维码：下载到缓存后调 ScanKit 图码识别，结果按地址栏提交逻辑打开 */
  private scanImage(imageUrl: string): void {
    if (imageUrl === '') {
      return
    }
    const req = http.createHttp()
    req.request(imageUrl, {
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 10000,
      readTimeout: 15000
    })
      .then((resp: http.HttpResponse): void => {
        req.destroy()
        const buf = resp.result
        if (!(buf instanceof ArrayBuffer)) {
          toastUtil.showToast({ message: $r('app.string.qr_not_found') })
          return
        }
        const filePath = `${_QhState.Context.cacheDir}/lp_scan_${Date.now()}.img`
        try {
          const file = fileIo.openSync(filePath,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
          fileIo.writeSync(file.fd, buf)
          fileIo.closeSync(file)
        } catch (e) {
          console.error(`[LongPressVM] 二维码缓存写入失败: ${e}`)
          toastUtil.showToast({ message: $r('app.string.qr_not_found') })
          return
        }
        this.detectQrFile(filePath)
      })
      .catch((error: BusinessError): void => {
        req.destroy()
        console.error(`[LongPressVM] 二维码图片下载失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.qr_not_found') })
      })
  }

  /** 对本地图片文件做图码识别 */
  private detectQrFile(filePath: string): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: false
    }
    try {
      detectBarcode.decode({ uri: `file://${filePath}` }, options,
        (error: BusinessError, results: Array<scanBarcode.ScanResult>): void => {
          try {
            fileIo.unlinkSync(filePath)
          } catch (e) {
          }
          let text = ''
          try {
            if (results !== undefined && results.length > 0) {
              text = results[0].originalValue.trim()
            }
          } catch (e) {
            text = ''
          }
          if (error !== undefined && error !== null && error.code !== 0) {
            console.error(`[LongPressVM] 图码识别失败: ${error.code} ${error.message}`)
          }
          if (text !== '') {
            browserVM.submitAddress(text)
          } else {
            toastUtil.showToast({ message: $r('app.string.qr_not_found') })
          }
        })
    } catch (e) {
      try {
        fileIo.unlinkSync(filePath)
      } catch (err) {
      }
      console.error(`[LongPressVM] 图码识别异常: ${e}`)
      toastUtil.showToast({ message: $r('app.string.qr_not_found') })
    }
  }
}

export const longPressVM = new LongPressMenuViewModel()
