/**
 * 源码视图词法单元：cls 着色类别（'' 无着色 / c 注释 / d doctype / p 标点 /
 * tg 标签名 / a 属性名 / v 属性值 / e 实体），txt 原文片段
 */
class SrcToken {
  readonly cls: string
  readonly txt: string

  constructor(cls: string, txt: string) {
    this.cls = cls
    this.txt = txt
  }
}

/**
 * 查看源码页面构建（双视图）：
 * - 源码：捕获的 HTML 经轻量词法着色（标签/属性/注释/实体）+ CSS 行号，仿 Chrome view-source
 * - 结构：原始 HTML 以 JSON 数据岛内嵌（'<' 转 \u003c 防 script 逃逸），
 *   页内 DOMParser 解析 + 懒加载可折叠 DOM 树（DevTools Elements 风格）
 * CSP 允许内联样式/脚本（文档由 App 构造），禁一切网络加载，深色自适应
 */
export class ViewSourceScripts {
  /** 源码视图 URL 前缀 */
  static readonly URL_PREFIX: string = 'view-source:'

  /** 构建源码展示文档（loadData 用）；showHeader=false 省略内建顶栏（外部工具栏接管切换） */
  static buildDoc(srcUrl: string, html: string, labelSrc: string, labelTree: string,
    showHeader: boolean = true, initView: string = 'src'): string {
    const header: string = `${ViewSourceScripts.URL_PREFIX}${srcUrl}`
    const colored: string = ViewSourceScripts.renderLines(ViewSourceScripts.tokenize(html))
    const island: string = JSON.stringify(html).replace(/</g, '\\u003c')
    const style: string =
      'html{-webkit-text-size-adjust:100%}' +
      'body{margin:0;font:12px/1.65 ui-monospace,Menlo,Consolas,monospace;' +
      'word-break:break-all;background:#fff;color:#333}' +
      '.qh-hd{position:sticky;top:0;z-index:1;display:flex;align-items:center;gap:10px;' +
      'padding:7px 12px;background:#f5f5f5;border-bottom:1px solid #e0e0e0}' +
      '.qh-url{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#666}' +
      '.qh-tg{flex:none;display:flex;padding:2px;background:#e4e4e4;border-radius:11px;' +
      'font:11px/1.5 system-ui,sans-serif;user-select:none;-webkit-user-select:none}' +
      '.qh-tg-btn{padding:2px 10px;border-radius:9px;color:#666}' +
      '.qh-tg-btn.on{background:#111;color:#fff}' +
      '.doc{counter-reset:l}' +
      '.ln{counter-increment:l;white-space:pre-wrap;padding-right:12px}' +
      '.ln::before{content:counter(l);display:inline-block;width:3.5em;padding-right:12px;' +
      'text-align:right;color:#b0b0b0;-webkit-user-select:none;user-select:none}' +
      '.c,.d{color:#008000}.p{color:#0000ff}.tg{color:#881280}' +
      '.a{color:#994500}.v{color:#1a1aa6}.e{color:#aa0d91}' +
      '.tree{padding:8px 12px;overflow-x:auto}' +
      '.tr{white-space:pre-wrap;word-break:break-all;padding:3px 0}' +
      '.tc{display:inline-block;width:0;height:0;border-left:5px solid #aaa;' +
      'border-top:4px solid transparent;border-bottom:4px solid transparent;' +
      'margin-right:6px;vertical-align:middle;transition:transform .12s}' +
      '.tn.open>.tr>.tc{transform:rotate(90deg)}' +
      '.tc-none{visibility:hidden}' +
      '.tk{margin-left:14px;display:none}' +
      '.tv-tag{color:#881280}.tv-p{color:#0000ff}.tv-a{color:#994500}' +
      '.tv-v{color:#1a1aa6}.tv-cm{color:#008000}.tx{color:#444}' +
      '@media(prefers-color-scheme:dark){' +
      'body{background:#1b1b1b;color:#d4d4d4}' +
      '.qh-hd{background:#252525;border-bottom-color:#333}' +
      '.qh-url{color:#999}' +
      '.qh-tg{background:#333}' +
      '.qh-tg-btn{color:#aaa}' +
      '.qh-tg-btn.on{background:#ddd;color:#111}' +
      '.ln::before{color:#5a5a5a}' +
      '.c,.d{color:#6a9955}.p{color:#808080}.tg{color:#569cd6}' +
      '.a{color:#9cdcfe}.v{color:#ce9178}.e{color:#b5cea8}' +
      '.tc{border-left-color:#777}' +
      '.tv-tag{color:#569cd6}.tv-p{color:#808080}.tv-a{color:#9cdcfe}' +
      '.tv-v{color:#ce9178}.tv-cm{color:#6a9955}.tx{color:#bbb}' +
      '}'
    const headBlock: string = showHeader
      ? '<div class="qh-hd">' +
      `<span class="qh-url">${ViewSourceScripts.escape(header)}</span>` +
      '<span class="qh-tg">' +
      `<span class="qh-tg-btn on" id="btn-src">${ViewSourceScripts.escape(labelSrc)}</span>` +
      `<span class="qh-tg-btn" id="btn-tree">${ViewSourceScripts.escape(labelTree)}</span>` +
      '</span></div>'
      : ''
    // 面板变体（无顶栏）：左侧留边 + 底部留白（滚动到末行不贴边）
    const padStyle: string = showHeader
      ? ''
      : 'body{padding-left:6px;padding-bottom:24px}'
    return '<!DOCTYPE html><html><head><meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">' +
      '<meta http-equiv="Content-Security-Policy" ' +
      'content="default-src \'none\'; style-src \'unsafe-inline\'; script-src \'unsafe-inline\'">' +
      `<style>${style}${padStyle}</style></head><body>` +
      headBlock +
      `<div id="view-src" class="doc">${colored}</div>` +
      '<div id="view-tree" class="tree" style="display:none"></div>' +
      `<script type="application/json" id="qh-src">${island}</script>` +
      `<script>${ViewSourceScripts.treeScript(initView)}</script>` +
      '</body></html>'
  }

  /** 页内脚本：视图切换 + DOMParser 解析数据岛 + 懒加载可折叠 DOM 树 */
  private static treeScript(initView: string): string {
    return '(function(){' +
      "function q(i){return document.getElementById(i);}" +
      "var bS=q('btn-src'),bT=q('btn-tree'),vS=q('view-src'),vT=q('view-tree'),built=false;" +
      "function mode(m){" +
      "if(m==='tree'){vS.style.display='none';vT.style.display='block';" +
      "if(bT){bT.className='qh-tg-btn on';}if(bS){bS.className='qh-tg-btn';}" +
      'if(!built){built=true;build();}}' +
      "else{vT.style.display='none';vS.style.display='block';" +
      "if(bS){bS.className='qh-tg-btn on';}if(bT){bT.className='qh-tg-btn';}}}" +
      'window.__qhSetView=mode;' +
      "if(bS){bS.onclick=function(){mode('src');};}" +
      "if(bT){bT.onclick=function(){mode('tree');};}" +
      `mode('${initView}');` +
      "function el(t,c){var e=document.createElement(t);if(c){e.className=c;}return e;}" +
      "function sp(c,t){var e=el('span',c);e.textContent=t;return e;}" +
      'function label(n){' +
      "var lb=el('span');" +
      "lb.appendChild(sp('tv-p','\\x3c'));" +
      "lb.appendChild(sp('tv-tag',n.tagName.toLowerCase()));" +
      'var as=n.attributes;' +
      'for(var i=0;i<as.length;i++){var at=as[i];' +
      "lb.appendChild(sp('tv-a',' '+at.name));" +
      "if(at.value){var val=at.value;" +
      "if(val.indexOf('data:')===0&&val.length>96){val=val.slice(0,96)+'\\u2026';}" +
      "lb.appendChild(sp('tv-p','='));" +
      "lb.appendChild(sp('tv-v','\"'+val+'\"'));}}" +
      "lb.appendChild(sp('tv-p','\\x3e'));return lb;}" +
      'function cs(lb,name){lb.appendChild(sp(\'tv-p\',\'\\x3c/\'));' +
      "lb.appendChild(sp('tv-tag',name));lb.appendChild(sp('tv-p','\\x3e'));}" +
      'function hasKids(n){for(var i=0;i<n.childNodes.length;i++){var d=n.childNodes[i];' +
      'if(d.nodeType===1||d.nodeType===8){return true;}' +
      'if(d.nodeType===3&&d.textContent.trim()){return true;}}return false;}' +
      "function textRow(t){var tr=el('div','tr tx');var s=t.trim();" +
      "tr.textContent=s.length>2000?s.slice(0,2000)+'\\u2026':s;return tr;}" +
      "function commentRow(t){var tr=el('div','tr tx tv-cm');var s=t.trim();" +
      "tr.textContent='\\x3c!--'+(s.length>500?s.slice(0,500)+'\\u2026':s)+'--\\x3e';return tr;}" +
      'function buildKids(box,n,depth){for(var i=0;i<n.childNodes.length;i++){var d=n.childNodes[i];' +
      'if(d.nodeType===3){if(d.textContent.trim()){box.appendChild(textRow(d.textContent));}}' +
      'else if(d.nodeType===8){box.appendChild(commentRow(d.textContent));}' +
      'else if(d.nodeType===1){box.appendChild(buildNode(d,depth+1));}}}' +
      'function expand(tn){' +
      'if(!tn._b){var k=el(\'div\',\'tk\');buildKids(k,tn._n,tn._d);tn.appendChild(k);' +
      'var cr=el(\'div\',\'tr\');cs(cr,tn._n.tagName.toLowerCase());tn.appendChild(cr);' +
      'tn._k=k;tn._b=true;}' +
      "tn._k.style.display='block';tn._z.style.display='none';tn.className='tn open';}" +
      "function collapse(tn){tn._k.style.display='none';tn._z.style.display='inline';tn.className='tn';}" +
      'function buildNode(n,depth){' +
      "var tn=el('div','tn');var tr=el('div','tr');" +
      "var kids=hasKids(n);var tc=el('span','tc'+(kids?'':' tc-none'));tr.appendChild(tc);" +
      'tr.appendChild(label(n));tn.appendChild(tr);' +
      'if(kids){var z=el(\'span\',\'tx\');z.textContent=\'\\u2026\';' +
      'cs(z,n.tagName.toLowerCase());tr.appendChild(z);tn._z=z;' +
      'tn._n=n;tn._d=depth;tn._b=false;' +
      "tr.onclick=function(){if(tn.className==='tn open'){collapse(tn);}else{expand(tn);}};" +
      'if(depth<=1){expand(tn);}}return tn;}' +
      'function build(){' +
      "var raw=JSON.parse(q('qh-src').textContent);" +
      "var d=new DOMParser().parseFromString(raw,'text/html');" +
      "var low=raw.toLowerCase();" +
      // 片段（元素审查）：DOMParser 会包一层合成 html/body，须从 body 子节点建树
      "if(low.indexOf('\\x3chtml')<0&&low.indexOf('\\x3c!doctype')<0){" +
      'var bs=d.body.childNodes;' +
      'for(var i=0;i<bs.length;i++){var b=bs[i];' +
      'if(b.nodeType===1){vT.appendChild(buildNode(b,0));}' +
      'else if(b.nodeType===8){vT.appendChild(commentRow(b.textContent));}}return;}' +
      "if(low.slice(0,100).indexOf('\\x3c!doctype')>=0){" +
      "var dt=el('div','tr tx tv-cm');dt.textContent='\\x3c!DOCTYPE html\\x3e';vT.appendChild(dt);}" +
      'vT.appendChild(buildNode(d.documentElement,0));}' +
      '})();'
  }

  /** HTML 源码词法切分：注释/doctype/标签（含属性）/实体/文本 */
  private static tokenize(src: string): SrcToken[] {
    const toks: SrcToken[] = []
    const n = src.length
    let i = 0
    while (i < n) {
      const ch = src.charAt(i)
      if (ch === '<') {
        if (src.startsWith('<!--', i)) {
          const end = src.indexOf('-->', i + 4)
          const stop = end < 0 ? n : end + 3
          toks.push(new SrcToken('c', src.substring(i, stop)))
          i = stop
          continue
        }
        if (i + 1 < n && src.charAt(i + 1) === '!') {
          const end = src.indexOf('>', i)
          const stop = end < 0 ? n : end + 1
          toks.push(new SrcToken('d', src.substring(i, stop)))
          i = stop
          continue
        }
        const isClose = i + 1 < n && src.charAt(i + 1) === '/'
        const nameStart = isClose ? i + 2 : i + 1
        if (nameStart < n && ViewSourceScripts.isTagChar(src.charAt(nameStart))) {
          i = ViewSourceScripts.emitTag(src, i, toks)
          continue
        }
      }
      if (ch === '&') {
        let j = i + 1
        if (j < n && src.charAt(j) === '#') {
          j++
        }
        const jStart = j
        while (j < n && ViewSourceScripts.isAlnum(src.charAt(j)) && j - i < 12) {
          j++
        }
        if (j > jStart && j < n && src.charAt(j) === ';') {
          toks.push(new SrcToken('e', src.substring(i, j + 1)))
          i = j + 1
          continue
        }
      }
      let k = i
      while (k < n && src.charAt(k) !== '<' && src.charAt(k) !== '&') {
        k++
      }
      if (k === i) {
        k = i + 1
      }
      toks.push(new SrcToken('', src.substring(i, k)))
      i = k
    }
    return toks
  }

  /** 解析一个完整标签（< 名 属性=值 ... >），返回结束下标 */
  private static emitTag(src: string, start: number, toks: SrcToken[]): number {
    const n = src.length
    let i = start
    toks.push(new SrcToken('p', src.substring(i, i + 1)))
    i++
    if (i < n && src.charAt(i) === '/') {
      toks.push(new SrcToken('p', '/'))
      i++
    }
    let j = i
    while (j < n && ViewSourceScripts.isTagChar(src.charAt(j))) {
      j++
    }
    if (j > i) {
      toks.push(new SrcToken('tg', src.substring(i, j)))
      i = j
    }
    while (i < n) {
      const c = src.charAt(i)
      if (c === '>') {
        toks.push(new SrcToken('p', '>'))
        return i + 1
      }
      if (c === '/' && i + 1 < n && src.charAt(i + 1) === '>') {
        toks.push(new SrcToken('p', '/>'))
        return i + 2
      }
      if (ViewSourceScripts.isSpace(c)) {
        let w = i
        while (w < n && ViewSourceScripts.isSpace(src.charAt(w))) {
          w++
        }
        toks.push(new SrcToken('', src.substring(i, w)))
        i = w
        continue
      }
      let k = i
      while (k < n) {
        const cc = src.charAt(k)
        if (ViewSourceScripts.isSpace(cc) || cc === '=' || cc === '>') {
          break
        }
        if (cc === '/' && k + 1 < n && src.charAt(k + 1) === '>') {
          break
        }
        k++
      }
      if (k === i) {
        k = i + 1
      }
      toks.push(new SrcToken('a', src.substring(i, k)))
      i = k
      let w = i
      while (w < n && ViewSourceScripts.isSpace(src.charAt(w))) {
        w++
      }
      if (w < n && src.charAt(w) === '=') {
        if (w > i) {
          toks.push(new SrcToken('', src.substring(i, w)))
        }
        toks.push(new SrcToken('p', '='))
        i = w + 1
        let w2 = i
        while (w2 < n && ViewSourceScripts.isSpace(src.charAt(w2))) {
          w2++
        }
        if (w2 > i) {
          toks.push(new SrcToken('', src.substring(i, w2)))
        }
        i = w2
        if (i < n) {
          const q = src.charAt(i)
          if (q === '"' || q === '\'') {
            const end = src.indexOf(q, i + 1)
            const stop = end < 0 ? n : end + 1
            toks.push(new SrcToken('v', src.substring(i, stop)))
            i = stop
          } else {
            let k2 = i
            while (k2 < n) {
              const cc = src.charAt(k2)
              if (ViewSourceScripts.isSpace(cc) || cc === '>') {
                break
              }
              if (cc === '/' && k2 + 1 < n && src.charAt(k2 + 1) === '>') {
                break
              }
              k2++
            }
            if (k2 === i) {
              k2 = i + 1
            }
            toks.push(new SrcToken('v', src.substring(i, k2)))
            i = k2
          }
        }
      }
    }
    return n
  }

  /** 按行组装着色 HTML：跨行 span 拆行重开，CSS 计数器行号 */
  private static renderLines(toks: SrcToken[]): string {
    const lines: string[] = ['']
    let li = 0
    let curCls = ''
    for (const tok of toks) {
      const parts: string[] = tok.txt.split('\n')
      for (let p = 0; p < parts.length; p++) {
        if (p > 0) {
          if (curCls !== '') {
            lines[li] += '</span>'
            curCls = ''
          }
          li++
          lines.push('')
        }
        if (curCls !== tok.cls) {
          if (curCls !== '') {
            lines[li] += '</span>'
          }
          if (tok.cls !== '') {
            lines[li] += `<span class="${tok.cls}">`
          }
          curCls = tok.cls
        }
        lines[li] += ViewSourceScripts.escape(parts[p])
      }
    }
    if (curCls !== '') {
      lines[li] += '</span>'
    }
    let out = ''
    for (const l of lines) {
      out += `<div class="ln">${l}</div>`
    }
    return out
  }

  private static escape(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  }

  private static isSpace(c: string): boolean {
    return c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\f'
  }

  private static isTagChar(c: string): boolean {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
      c === '-' || c === '_' || c === ':' || c === '.'
  }

  private static isAlnum(c: string): boolean {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  }
}
