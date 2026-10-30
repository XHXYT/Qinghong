/**
 * 网页翻译注入脚本（runJavaScript 按阶段执行）：
 * collectJs 抽取正文文本节点 → 引擎翻译 → applyJs 逐批回填 → restoreJs 恢复原文
 * 节点引用与原文缓存在 window.__qhTrNodes/__qhTrOrig，导航后自然失效
 */
export class TranslateScripts {

  /**
   * 抽取正文文本节点：TreeWalker 遍历，跳过脚本/样式/代码/隐藏元素与无字母文本；
   * 返回文本 JSON 数组字符串（节点引用与原文留在 window 供回填/恢复）
   */
  static collectJs(): string {
    return "(function(){" +
      "if(window.__qhTrNodes){return '[]';}" +
      "var SKIP=/^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA|SELECT|OPTION|CODE|PRE|SAMP|KBD|VAR|SVG|CANVAS|TEMPLATE|INPUT|BUTTON|TITLE|IFRAME|OBJECT)$/;" +
      "var nodes=[],texts=[];" +
      "var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode:function(n){" +
      "var p=n.parentElement;if(!p){return 2;}" +
      "if(SKIP.test(p.tagName)){return 2;}" +
      "try{if(p.closest&&(p.closest('[hidden]')||p.closest('[aria-hidden=\"true\"]'))){return 2;}}catch(e){}" +
      "var t=n.nodeValue.replace(/\\s+/g,' ').trim();" +
      "if(t.length<2){return 2;}" +
      "if(!/[a-zA-Z\\u00C0-\\u024F\\u0400-\\u04FF\\u3040-\\u30FF\\uAC00-\\uD7AF]/.test(t)){return 2;}" +
      "return 1;}});" +
      "var n;" +
      "while((n=w.nextNode())){nodes.push(n);texts.push(n.nodeValue.replace(/\\s+/g,' ').trim());}" +
      "window.__qhTrNodes=nodes;window.__qhTrOrig=texts;" +
      "return JSON.stringify(texts);" +
      "})()"
  }

  /**
   * 逐批回填译文：start 为本批首条在全文中的偏移，results 与本批文本等长；
   * bilingual=true 时译文后附原文（软换行，同块内两行显示）
   */
  static applyJs(start: number, results: string[], bilingual: boolean): string {
    return "(function(){" +
      "var start=" + start + ",arr=" + JSON.stringify(results) + ",bi=" + (bilingual ? 'true' : 'false') + ";" +
      "var nodes=window.__qhTrNodes||[],orig=window.__qhTrOrig||[];" +
      "for(var i=0;i<arr.length;i++){" +
      "var idx=start+i;var n=nodes[idx];if(!n){continue;}" +
      "var t=arr[i];if(!t){t=orig[idx]||'';}" +
      "if(bi&&t){t=t+'\\n'+(orig[idx]||'');}" +
      "try{n.nodeValue=t;}catch(e){}" +
      "}})()"
  }

  /** 恢复全部原文并清除页面翻译缓存 */
  static restoreJs(): string {
    return "(function(){" +
      "var nodes=window.__qhTrNodes||[],orig=window.__qhTrOrig||[];" +
      "for(var i=0;i<nodes.length;i++){try{nodes[i].nodeValue=orig[i];}catch(e){}}" +
      "window.__qhTrNodes=null;window.__qhTrOrig=null;" +
      "return 'ok';" +
      "})()"
  }

  /** 读取页面语言（html lang 属性），供自动翻译判定 */
  static pageLangJs(): string {
    return "(document.documentElement.getAttribute('lang')||'')"
  }
}
