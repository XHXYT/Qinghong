import { toastUtil } from '../common/utils/ToastUtils';
import { pasteboard } from '@kit.BasicServicesKit';
import { appSettings } from '../common/entity/SettingsModel';
import { TabInfo } from './TabsViewModel';
import { browserVM } from './BrowserViewModel';
import { getTranslateEngine } from '../common/utils/translate/TranslateEngine';
import { TranslateScripts } from '../common/utils/translate/TranslateScripts';

const LOG_TAG = '[TranslateVM]'

/** 支持的目标语言代码（显示名用各自语言） */
export class TranslateLang {
  static readonly CODES: string[] = ['zh-CN', 'zh-TW', 'en', 'ja', 'ko', 'ru', 'fr', 'de', 'es']

  static labelRes(code: string): ResourceStr {
    switch (code) {
      case 'zh-CN':
        return $r('app.string.translate_lang_zh_cn')
      case 'zh-TW':
        return $r('app.string.translate_lang_zh_tw')
      case 'en':
        return $r('app.string.translate_lang_en')
      case 'ja':
        return $r('app.string.translate_lang_ja')
      case 'ko':
        return $r('app.string.translate_lang_ko')
      case 'ru':
        return $r('app.string.translate_lang_ru')
      case 'fr':
        return $r('app.string.translate_lang_fr')
      case 'de':
        return $r('app.string.translate_lang_de')
      case 'es':
        return $r('app.string.translate_lang_es')
      default:
        return code
    }
  }

  /** 规范化语言标识：'en-US'→'en'，'zh'/'zh-CN'→'zh-CN'，'zh-TW'/'zh-HK'→'zh-TW' */
  static normalize(code: string): string {
    const c: string = code.trim().toLowerCase()
    if (c === '') {
      return ''
    }
    if (c.startsWith('zh')) {
      return c.includes('tw') || c.includes('hk') || c.includes('hant') ? 'zh-TW' : 'zh-CN'
    }
    const main: string = c.split('-')[0]
    return main === '' ? '' : main
  }

  /** 目标语言短名（菜单宫格等紧凑场景显示用） */
  static shortRes(code: string): Resource {
    switch (code) {
      case 'zh-CN':
        return $r('app.string.translate_lang_short_zh_cn')
      case 'zh-TW':
        return $r('app.string.translate_lang_short_zh_tw')
      case 'ja':
        return $r('app.string.translate_lang_short_ja')
      case 'ko':
        return $r('app.string.translate_lang_short_ko')
      case 'ru':
        return $r('app.string.translate_lang_short_ru')
      case 'fr':
        return $r('app.string.translate_lang_short_fr')
      case 'de':
        return $r('app.string.translate_lang_short_de')
      case 'es':
        return $r('app.string.translate_lang_short_es')
      default:
        return $r('app.string.translate_lang_short_en')
    }
  }
}

/**
 * 网页翻译视图模型：当前页翻译管线（抽取→引擎翻译→逐批回填）、
 * 翻译态管理、自动翻译判定、划词翻译
 */
@ObservedV2
export class TranslateViewModel {
  /** 正在翻译的 tab id（-1 = 空闲） */
  private busyTabId: number = -1
  /** 已翻译 tab id 集合（导航/刷新时清除） */
  private translated: Set<number> = new Set()
  /** 翻译态修订号（驱动菜单高亮/标题刷新） */
  @Trace translatedRev: number = 0

  isTranslated(tabId: number): boolean {
    return this.translatedRev >= 0 && this.translated.has(tabId)
  }

  isBusy(): boolean {
    return this.busyTabId !== -1
  }

  /** 导航/刷新时清除翻译态（TabWeb onPageBegin 调用） */
  clearTab(tabId: number): void {
    if (this.translated.delete(tabId)) {
      this.translatedRev++
    }
  }

  /** 关闭标签时清理 */
  removeTab(tabId: number): void {
    if (this.translated.delete(tabId)) {
      this.translatedRev++
    }
  }

  /**
   * 翻译当前网页：抽取文本节点 → 引擎分批翻译 → 逐批回填
   */
  async translateTab(tab: TabInfo, target: string): Promise<boolean> {
    if (this.busyTabId !== -1) {
      toastUtil.showToast({ message: $r('app.string.translate_in_progress') })
      return false
    }
    if (tab.controller === null) {
      return false
    }
    const c = tab.controller
    this.busyTabId = tab.id
    try {
      const raw: string = await c.runJavaScript(TranslateScripts.collectJs())
      const texts: string[] = this.parseTexts(raw)
      if (texts.length === 0) {
        // 无可翻译内容（空页/纯中文页）：直接标记完成
        this.translated.add(tab.id)
        this.translatedRev++
        return true
      }
      toastUtil.showToast({ message: $r('app.string.translate_in_progress') })
      const engine = getTranslateEngine()
      const BATCH = 40
      for (let start = 0; start < texts.length; start += BATCH) {
        const batch: string[] = texts.slice(start, start + BATCH)
        const results: string[] = await engine.translateBatch(batch, target)
        const safe: string[] = []
        for (let i = 0; i < batch.length; i++) {
          safe.push(i < results.length && results[i] !== '' ? results[i] : batch[i])
        }
        await c.runJavaScript(TranslateScripts.applyJs(start, safe, appSettings.translate_bilingual))
      }
      this.translated.add(tab.id)
      this.translatedRev++
      toastUtil.showToast({ message: $r('app.string.translate_done') })
      return true
    } catch (e) {
      console.error(`${LOG_TAG} 翻译失败: ${e}`)
      toastUtil.showToast({ message: $r('app.string.translate_failed') })
      return false
    } finally {
      this.busyTabId = -1
    }
  }

  /** 恢复原文 */
  async restoreTab(tab: TabInfo): Promise<void> {
    if (tab.controller === null) {
      if (this.translated.delete(tab.id)) {
        this.translatedRev++
      }
      return
    }
    try {
      await tab.controller.runJavaScript(TranslateScripts.restoreJs())
    } catch (e) {
      console.error(`${LOG_TAG} 恢复原文失败: ${e}`)
    }
    if (this.translated.delete(tab.id)) {
      this.translatedRev++
    }
  }

  /**
   * 自动翻译（TabWeb onPageEnd 调用）：页面 lang 命中「总是翻译」列表且与目标语言不同时触发
   */
  autoTranslate(tab: TabInfo): void {
    if (appSettings.translate_always === '' || this.busyTabId !== -1 || this.translated.has(tab.id)) {
      return
    }
    if (tab.controller === null) {
      return
    }
    tab.controller.runJavaScript(TranslateScripts.pageLangJs())
      .then((raw: string): void => {
        let lang = ''
        try {
          lang = JSON.parse(raw) as string
        } catch (e) {
          lang = ''
        }
        const norm: string = TranslateLang.normalize(lang)
        if (norm === '') {
          return
        }
        const always: string[] = appSettings.translate_always.split(',')
        if (!always.includes(norm)) {
          return
        }
        if (TranslateLang.normalize(appSettings.translate_target_lang) === norm) {
          return
        }
        this.translateTab(tab, appSettings.translate_target_lang)
      })
      .catch((): void => {
      })
  }

  /** 划词翻译：弹窗展示译文 */
  translateSelection(text: string): void {
    const t: string = text.trim()
    if (t === '') {
      toastUtil.showToast({ message: $r('app.string.translate_no_text') })
      return
    }
    const clipped: string = t.length > 3000 ? t.substring(0, 3000) : t
    const engine = getTranslateEngine()
    engine.translateBatch([clipped], appSettings.translate_target_lang)
      .then((results: string[]): void => {
        const out: string = results.length > 0 && results[0] !== '' ? results[0] : clipped
        toastUtil.showAlertDialog({
          title: $r('app.string.translate_selection'),
          message: out,
          autoCancel: true,
          alignment: DialogAlignment.Center,
          buttons: [
            {
              value: $r('app.string.copy'),
              action: (): void => {
                this.copyText(out)
              }
            },
            {
              value: $r('app.string.confirm'),
              style: DialogButtonStyle.DEFAULT,
              action: (): void => {
              }
            }
          ]
        }, 'translateSelection')
      })
      .catch((): void => {
        toastUtil.showToast({ message: $r('app.string.translate_failed') })
      })
  }

  private copyText(text: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      pasteboard.getSystemPasteboard().setData(data)
      toastUtil.showToast({ message: $r('app.string.copied') })
    } catch (e) {
      console.error(`${LOG_TAG} 复制译文失败: ${e}`)
    }
  }

  /** runJavaScript 返回值解析：JSON 编码字符串 → 字符串数组 */
  private parseTexts(raw: string): string[] {
    try {
      const once: string = JSON.parse(raw) as string
      const arr: Object[] = JSON.parse(once) as Object[]
      const out: string[] = []
      for (const t of arr) {
        if (typeof t === 'string') {
          out.push(t)
        }
      }
      return out
    } catch (e) {
      return []
    }
  }
}

export const translateVM: TranslateViewModel = new TranslateViewModel()
