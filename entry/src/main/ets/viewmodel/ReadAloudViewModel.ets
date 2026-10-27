import { TextReader } from '@kit.SpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TabInfo, tabsVM } from './TabsViewModel';
import { browserVM } from './BrowserViewModel';
import { ReaderScripts } from '../common/utils/ReaderScripts';
import { toastUtil } from '../common/utils/ToastUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { _QhState } from '../entryability/AppState';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('ReadAloudViewModel')

/**
 * 朗读提取结果受控结构（Readability + innerText 一次提取）
 */
interface ReadAloudArticleRaw {
  title?: string
  byline?: string
  text?: string
}

/**
 * 「朗读网页」视图模型（Speech Kit TextReader 朗读控件）：
 * 非阅读模式点击先弹窗提示「即将进入阅读模式并开始朗读」，确认后提取正文、
 * 进入阅读模式（ReaderView）并拉起系统朗读面板；已在阅读模式点击直接重新朗读。
 * 系统面板自带播放/暂停/倍速/上一句下一句/Minibar 悬浮条。
 */
class ReadAloudViewModel {

  /** TextReader.init 缓存（成功后复用；失败置回 null 允许重试） */
  private initPromise: Promise<void> | null = null

  /** 朗读入口：非阅读模式先弹窗确认，已在阅读模式直接朗读 */
  startFromTab(): void {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null) {
      return
    }
    if (browserVM.isReaderActive(tab.id)) {
      this.extractAndSpeak(tab, true)
      return
    }
    toastUtil.showAlertDialog({
      title: $r('app.string.read_aloud'),
      message: ResourceUtils.getString($r('app.string.read_aloud_confirm_message')),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        },
        {
          value: $r('app.string.reader_enter'),
          action: (): void => {
            this.extractAndSpeak(tab, false)
          }
        }
      ]
    }, 'readAloudConfirm')
  }

  /** 提取正文：进阅读模式（首次）+ 启动系统朗读面板 */
  private extractAndSpeak(tab: TabInfo, readerActive: boolean): void {
    const controller = tab.controller
    if (controller === null) {
      return
    }
    controller.runJavaScript(ReaderScripts.readAloudProbeJs())
      .then((raw: string): void => {
        const json: string = ReadAloudViewModel.unwrapJsString(raw)
        const article: ReadAloudArticleRaw | null = ReadAloudViewModel.parseRaw(json)
        if (article === null) {
          toastUtil.showToast({ message: $r('app.string.reader_not_supported') })
          return
        }
        if (!readerActive) {
          const readerArticle = ReaderScripts.parseArticle(json, tab)
          if (readerArticle === null) {
            toastUtil.showToast({ message: $r('app.string.reader_not_supported') })
            return
          }
          browserVM.openReader(readerArticle)
        }
        const text: string = article.text ?? ''
        if (text === '') {
          toastUtil.showToast({ message: $r('app.string.read_aloud_failed') })
          return
        }
        const title: string = article.title ?? tab.title
        const byline: string = article.byline ?? ''
        this.ensureInited()
          .then((): Promise<void> => this.start(title, byline, text, tab.url))
          .catch((error: BusinessError): void => {
            logger.error(`朗读启动失败: ${error.code} ${error.message}`)
            toastUtil.showToast({ message: $r('app.string.read_aloud_failed') })
          })
      })
      .catch((error: BusinessError): void => {
        logger.error(`朗读正文提取失败: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.reader_not_supported') })
      })
  }

  /** TextReader 懒初始化（幂等；失败可重试） */
  private ensureInited(): Promise<void> {
    if (this.initPromise !== null) {
      return this.initPromise
    }
    const param: TextReader.ReaderParam = {
      isVoiceBrandVisible: true,
      businessBrandInfo: {
        panelName: ResourceUtils.getString($r('app.string.EntryAbility_label'))
      },
      isMinibarNeeded: true
    }
    const promise: Promise<void> = TextReader.init(_QhState.Context, param)
    // 失败重置缓存允许重试；原始 promise 的拒绝由调用方捕获提示
    promise.catch((error: BusinessError): void => {
      this.initPromise = null
      logger.error(`TextReader init 失败: ${error.code} ${error.message}`)
    })
    this.initPromise = promise
    return promise
  }

  /** 拉起系统朗读面板并起播（id 用页面 URL，同页重复朗读指向同一篇） */
  private start(title: string, byline: string, text: string, url: string): Promise<void> {
    const info: TextReader.ReadInfo = {
      id: url,
      title: { text: title, isClickable: false },
      bodyInfo: text
    }
    if (byline !== '') {
      info.author = { text: byline, isClickable: false }
    }
    return TextReader.start([info])
  }

  /** runJavaScript 回参解包：string 结果经 JSON 编码（带引号），按需反序列化一次 */
  private static unwrapJsString(raw: string): string {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        return JSON.parse(raw) as string
      } catch (e) {
        return raw
      }
    }
    return raw
  }

  /** 朗读提取结果解析（'null'/空/非法 JSON 返回 null） */
  private static parseRaw(json: string): ReadAloudArticleRaw | null {
    if (json === '' || json === 'null' || json === 'undefined') {
      return null
    }
    try {
      const raw = JSON.parse(json) as ReadAloudArticleRaw
      if (raw === null || typeof raw !== 'object') {
        return null
      }
      return raw
    } catch (e) {
      return null
    }
  }
}

export const readAloudVM = new ReadAloudViewModel()
