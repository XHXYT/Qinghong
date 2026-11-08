import { buffer } from '@kit.ArkTS';
import { _QhState, QhState } from '../../../entryability/AppState';
import { appSettings } from '../../entity/SettingsModel';
import { ReadModeCssStore } from '../storage/ReadModeCssStore';
import { ReaderArticle } from '../../../viewmodel/BrowserViewModel';
import { TabInfo } from '../../../viewmodel/TabsViewModel';
import { createLogger } from '../app/Logger';

const logger = createLogger('ReaderScripts')

/**
 * Readability 提取结果原始 JSON 结构
 */
interface ReaderArticleRaw {
  title?: string
  byline?: string
  dir?: string
  lang?: string
  siteName?: string
  publishedTime?: string
  content?: string
  excerpt?: string
}

/**
 * 阅读模式核心（Mozilla Readability 方案）：
 * rawfile 内置 Readability.js，经 runJavaScript 注入页面执行预检与正文提取；
 * 提取结果以受控 HTML 模板（CSP 禁脚本）渲染，排版走 CSS 变量。
 */
export class ReaderScripts {

  private static scriptCache: Map<string, string> = new Map<string, string>()

  /** 读取 rawfile 脚本内容（内存缓存） */
  static rawScript(name: string): string {
    const cached: string | undefined = ReaderScripts.scriptCache.get(name)
    if (cached !== undefined) {
      return cached
    }
    let content: string = ''
    try {
      const data: Uint8Array = _QhState.Context.resourceManager.getRawFileContentSync(name)
      content = buffer.from(data).toString()
    } catch (e) {
      logger.error(`rawScript(${name}) 失败: ${e}`)
    }
    ReaderScripts.scriptCache.set(name, content)
    return content
  }

  /**
   * 可读性预检脚本：注入 isProbablyReaderable（幂等，挂 window.__qhIsReadable）
   */
  static readerableProbeJs(): string {
    const lib: string = ReaderScripts.rawScript('readability-readerable.js')
    return '(function(){' +
      'if(!window.__qhIsReadable){' +
      lib +
      'window.__qhIsReadable=function(){' +
      'try{return isProbablyReaderable(document);}catch(e){return false;}};' +
      '}' +
      '})();'
  }

  /**
   * 正文提取脚本：注入 Readability（幂等，挂 window.__qhParseArticle），
   * 克隆文档解析并仅保留渲染所需字段（剔除 textContent 大字段）
   */
  static readabilityProbeJs(): string {
    const lib: string = ReaderScripts.rawScript('readability.js')
    return '(function(){' +
      'if(!window.__qhParseArticle){' +
      lib +
      'window.__qhParseArticle=function(){' +
      'try{' +
      'var r=new Readability(document.cloneNode(true)).parse();' +
      'if(!r){return null;}' +
      'return {title:r.title,byline:r.byline,dir:r.dir,lang:r.lang,siteName:r.siteName,' +
      'publishedTime:r.publishedTime,content:r.content,excerpt:r.excerpt};' +
      '}catch(e){return null;}};' +
      '}' +
      '})();'
  }

  /** 从提取结果 JSON 构建 ReaderArticle（不可读/解析失败返回 null） */
  static parseArticle(json: string, tab: TabInfo): ReaderArticle | null {
    if (json === '' || json === 'null' || json === 'undefined') {
      return null
    }
    try {
      const raw = JSON.parse(json) as ReaderArticleRaw
      const content: string = typeof raw.content === 'string' ? raw.content : ''
      if (content.trim() === '') {
        return null
      }
      const article: ReaderArticle = new ReaderArticle()
      article.content = content
      article.title = ReaderScripts.pickText(raw.title, tab.title)
      article.byline = ReaderScripts.pickText(raw.byline, '')
      article.dir = raw.dir === 'rtl' ? 'rtl' : 'ltr'
      article.lang = ReaderScripts.pickText(raw.lang, '')
      article.siteName = ReaderScripts.pickText(raw.siteName, '')
      article.publishedTime = ReaderScripts.pickText(raw.publishedTime, '')
      article.excerpt = ReaderScripts.pickText(raw.excerpt, '')
      article.url = tab.url
      article.tabId = tab.id
      article.isIncognito = tab.isIncognito
      return article
    } catch (e) {
      logger.error(`parseArticle 失败: ${e}`)
      return null
    }
  }

  /**
   * 朗读网页提取脚本：复用 Readability 注入，一次提取双产物——
   * content（HTML，供阅读模式 parseArticle 进 ReaderView）与
   * text（innerText 纯文本，供朗读控件播报，块级换行保留）
   */
  static readAloudProbeJs(): string {
    return ReaderScripts.readabilityProbeJs() +
      ';(function(){try{' +
      'var r=window.__qhParseArticle();' +
      'if(!r){return "null";}' +
      'var d=document.createElement("div");d.innerHTML=r.content;' +
      'return JSON.stringify({title:r.title,byline:r.byline,dir:r.dir,lang:r.lang,' +
      'siteName:r.siteName,publishedTime:r.publishedTime,content:r.content,' +
      'text:(d.innerText||"").trim()});' +
      '}catch(e){return "null";}})()'
  }

  /**
   * 构建阅读页 HTML：模板 + 正文 + 排版 CSS 变量 + 自定义 CSS；
   * CSP 禁脚本（提取内容直出，Readability 已剔除脚本，此处纵深防御）
   */
  static buildReaderHtml(article: ReaderArticle): string {
    const bg: string = appSettings.readModeBgHex()
    const dark: boolean = ReaderScripts.isDarkHex(bg)
    const text: string = dark ? '#EAEAEA' : '#3A3A3A'
    const link: string = dark ? '#7FB2FF' : '#1A5FB4'
    const fontFamily: string = ReaderScripts.fontFamilyOf(appSettings.read_mode_serif)
    const meta: string = ReaderScripts.buildMeta(article)
    const custom: string = ReadModeCssStore.load().trim()
    // 阅读页全屏沉浸：正文起点避让状态栏与顶栏（vp 与 CSS px 1:1）
    const topInset: number = Math.round(QhState.topRectHeight) + 48 + 24
    return '<!DOCTYPE html><html><head>' +
      '<meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<meta http-equiv="Content-Security-Policy" content="default-src \'none\';' +
      'img-src http: https: data: blob:;media-src http: https: data: blob:;' +
      'style-src \'unsafe-inline\';script-src \'none\'">' +
      '<style>' +
      ':root{--qh-bg:' + bg + ';--qh-text:' + text + ';--qh-link:' + link + ';' +
      '--qh-size:' + appSettings.read_mode_font_size + 'px;--qh-font:' + fontFamily + ';}' +
      '*{box-sizing:border-box;}' +
      'html{-webkit-text-size-adjust:100%;}' +
      'body{margin:0;background:var(--qh-bg);color:var(--qh-text);' +
      'font-family:var(--qh-font);font-size:var(--qh-size);line-height:1.85;}' +
      '.qh-wrap{max-width:720px;margin:0 auto;padding:' + topInset + 'px 20px 64px;}' +
      '.qh-title{font-size:1.55em;line-height:1.45;margin:0 0 10px;}' +
      '.qh-meta{font-size:0.78em;opacity:0.6;margin:0 0 26px;}' +
      '.qh-meta span{margin-right:12px;}' +
      'article img,article video{max-width:100%;height:auto;}' +
      'article figure{margin:1.2em 0;}' +
      'article figcaption{font-size:0.8em;opacity:0.6;}' +
      'article a{color:var(--qh-link);text-decoration:none;}' +
      'article p{margin:1em 0;}' +
      'article h2,article h3,article h4{line-height:1.5;margin:1.6em 0 0.8em;}' +
      'article blockquote{margin:1.2em 0;padding:0.1em 1em;border-left:3px solid var(--qh-link);opacity:0.85;}' +
      'article pre{white-space:pre-wrap;word-break:break-word;background:rgba(128,128,128,0.12);' +
      'padding:12px;border-radius:8px;overflow-x:auto;}' +
      'article code{font-family:monospace;}' +
      'article table{border-collapse:collapse;display:block;max-width:100%;overflow-x:auto;}' +
      'article td,article th{border:1px solid rgba(128,128,128,0.35);padding:6px 10px;}' +
      'article ul,article ol{padding-left:1.5em;}' +
      '</style>' +
      (custom === '' ? '' : '<style>' + custom + '</style>') +
      '</head><body><div class="qh-wrap">' +
      '<h1 class="qh-title">' + ReaderScripts.escapeHtml(article.title) + '</h1>' +
      (meta === '' ? '' : '<p class="qh-meta">' + meta + '</p>') +
      '<article dir="' + article.dir + '">' + article.content + '</article>' +
      '</div></body></html>'
  }

  /**
   * 阅读页滚动监听挂钩（幂等）：方向变化或回顶时经 __qhReaderBridge 通知原生，
   * 供阅读顶栏随滚动自动隐藏/显示
   */
  static readerScrollHookJs(): string {
    return '(function(){' +
      'if(window.__qhScrollBound)return;window.__qhScrollBound=true;' +
      'var last=window.scrollY||0,lastSent=0;' +
      'window.addEventListener("scroll",function(){' +
      'var y=window.scrollY||0,d=y-last;last=y;' +
      'if(Math.abs(d)<10)return;' +
      'var s=d>0?1:-1,atTop=y<=0;' +
      'if(s===lastSent&&!atTop)return;' +
      'lastSent=s;' +
      'if(window.__qhReaderBridge){try{window.__qhReaderBridge.onScroll(s,atTop);}catch(e){}}' +
      '},{passive:true});' +
      '})()'
  }

  /** 衬线/无衬线字体栈 */
  static fontFamilyOf(serif: boolean): string {
    return serif
      ? 'Georgia,"Times New Roman","Songti SC",SimSun,serif'
      : 'system-ui,-apple-system,"HarmonyOS Sans SC","PingFang SC","Noto Sans CJK SC","Microsoft YaHei",sans-serif'
  }

  /** 署名/站点/发布时间元信息行 */
  private static buildMeta(article: ReaderArticle): string {
    const parts: string[] = []
    if (article.byline !== '') {
      parts.push(ReaderScripts.escapeHtml(article.byline))
    }
    if (article.siteName !== '') {
      parts.push(ReaderScripts.escapeHtml(article.siteName))
    }
    if (article.publishedTime !== '') {
      parts.push(ReaderScripts.escapeHtml(article.publishedTime))
    }
    const html: string[] = []
    for (const p of parts) {
      html.push('<span>' + p + '</span>')
    }
    return html.join('')
  }

  private static pickText(v: string | undefined, fallback: string): string {
    return typeof v === 'string' && v.trim() !== '' ? v.trim() : fallback
  }

  /** HTML 文本转义（标题/署名等纯文本字段） */
  static escapeHtml(s: string): string {
    return s
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
  }

  /** 背景色亮度判断（暗色底配浅色文字） */
  static isDarkHex(hex: string): boolean {
    const r: number = parseInt(hex.substring(1, 3), 16)
    const g: number = parseInt(hex.substring(3, 5), 16)
    const b: number = parseInt(hex.substring(5, 7), 16)
    return (r * 0.299 + g * 0.587 + b * 0.114) < 140
  }
}
