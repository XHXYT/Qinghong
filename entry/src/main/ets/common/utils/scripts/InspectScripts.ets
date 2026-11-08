/**
 * 元素审查页内脚本构建（runJavaScript 注入）：
 * - enterSelectScript：选点模式——页内蓝色预选高亮框 + 标签 chip 跟手更新，
 *   点击锁定元素并经 __qhNative.inspectEvent 回传（拖动仍可滚动页面，选点期间吞掉页面点击副作用）
 * - parentScript / exitScript：切父元素 / 清理蒙版
 * - blockStyleScript：向页面注入即时隐藏样式（配合内核 AdsBlock 规则持久拦截）
 * - evalScript：控制台求值，返回 JSON.stringify({v}|{e})
 */
export class InspectScripts {

  /** 进入选点模式（重入时恢复选点态） */
  static enterSelectScript(): string {
    return '(function(){' +
      'if(window.__qhInsp){window.__qhInsp.reselect();return;}' +
      "var box=document.createElement('div');" +
      "box.style.cssText='position:fixed;display:none;pointer-events:none;z-index:2147483646;" +
      "border:2px solid #3399ff;background:rgba(51,153,255,0.14);';" +
      "var lb=document.createElement('div');" +
      "lb.style.cssText='position:fixed;display:none;pointer-events:none;z-index:2147483647;" +
      "background:#3399ff;color:#fff;font:11px/1.5 system-ui,sans-serif;padding:2px 6px;" +
      "border-radius:4px;white-space:nowrap;';" +
      '(document.body||document.documentElement).appendChild(box);' +
      '(document.body||document.documentElement).appendChild(lb);' +
      'var cur=null,sx=0,sy=0,st=0,picked=false,hist=[];' +
      'function dsc(el){' +
      "var s=el.tagName?el.tagName.toLowerCase():'node';" +
      'if(el.id){s+=\'#\'+el.id;}' +
      'if(el.getAttribute){var c=(el.getAttribute(\'class\')||\'\').trim();' +
      'if(c){s+=\'.\'+c.split(/\\s+/)[0];}}' +
      'return s;}' +
      'function rect(el){var r=el.getBoundingClientRect();' +
      "box.style.left=r.left+'px';box.style.top=r.top+'px';" +
      "box.style.width=r.width+'px';box.style.height=r.height+'px';box.style.display='block';" +
      "lb.textContent=dsc(el);lb.style.display='block';" +
      'var lty=r.top-20;if(lty<2){lty=r.top+2;}' +
      "lb.style.left=r.left+'px';lb.style.top=lty+'px';}" +
      'function nthPath(el){var parts=[],node=el,depth=0;' +
      'while(node&&node.nodeType===1&&depth<4){var idx=1,sib=node;' +
      'while((sib=sib.previousElementSibling)){idx++;}' +
      "parts.unshift(node.tagName.toLowerCase()+':nth-child('+idx+')');" +
      'node=node.parentElement;depth++;if(node===document.body){break;}}' +
      "return parts.join('>');}" +
      'function selFor(el){' +
      "if(el.id){return '#'+el.id;}" +
      "var s=el.tagName.toLowerCase();" +
      "var cls=(el.getAttribute&&el.getAttribute('class')||'').trim();" +
      'if(cls){var cs=cls.split(/\\s+/);var pick=[];' +
      'for(var i=0;i<cs.length&&i<3;i++){pick.push(cs[i]);}' +
      "s+='.'+pick.join('.');}" +
      'try{if(document.querySelectorAll(s).length===1){return s;}' +
      'return nthPath(el);}catch(e){return s;}}' +
      'function send(el,kind){var h=el.outerHTML||\'\';' +
      'if(h.length>262144){h=h.slice(0,262144);}' +
      'var payload={t:kind,html:h,sel:selFor(el),desc:dsc(el)};' +
      'try{window.__qhNative.inspectEvent(JSON.stringify(payload));}catch(e){}}' +
      'function hit(e){var el=document.elementFromPoint(e.clientX,e.clientY);' +
      'if(el&&el!==box&&el!==lb){return el;}return null;}' +
      'function tp(e){return e.changedTouches&&e.changedTouches[0]?e.changedTouches[0]:' +
      '(e.touches?e.touches[0]:null);}' +
      'function onDown(e){if(picked){return;}var t=tp(e);if(!t){return;}' +
      'sx=t.clientX;sy=t.clientY;st=Date.now();' +
      'var el=hit(t);if(el){cur=el;rect(el);}}' +
      'function onMove(e){if(picked){return;}var t=tp(e);if(!t){return;}var el=hit(t);' +
      'if(el&&el!==cur){cur=el;rect(el);}}' +
      'function onUp(e){if(picked){return;}var t=tp(e);if(!t){return;}' +
      'var dx=t.clientX-sx,dy=t.clientY-sy;' +
      'if(dx*dx+dy*dy>100||Date.now()-st>800){return;}' +
      'var el=hit(t);if(!el){return;}cur=el;rect(el);picked=true;send(el,\'pick\');' +
      'if(e.cancelable){e.preventDefault();}}' +
      'function onClk(e){e.preventDefault();e.stopPropagation();}' +
      'function onScr(){if(cur){rect(cur);}}' +
      "document.addEventListener('touchstart',onDown,{capture:true,passive:true});" +
      "document.addEventListener('touchmove',onMove,{capture:true,passive:true});" +
      "document.addEventListener('touchend',onUp,{capture:true,passive:false});" +
      "document.addEventListener('click',onClk,true);" +
      "document.addEventListener('scroll',onScr,{capture:true,passive:true});" +
      'window.__qhInsp={' +
      'reselect:function(){picked=false;cur=null;box.style.display=\'none\';lb.style.display=\'none\';},' +
      'parent:function(){if(!cur||!cur.parentElement){return;}' +
      'if(hist.length<20){hist.push(cur);}' +
      'cur=cur.parentElement;rect(cur);picked=true;send(cur,\'parent\');},' +
      'child:function(){if(!hist.length){return;}' +
      'cur=hist.pop();rect(cur);picked=true;send(cur,\'child\');},' +
      'exit:function(){' +
      "document.removeEventListener('touchstart',onDown,true);" +
      "document.removeEventListener('touchmove',onMove,true);" +
      "document.removeEventListener('touchend',onUp,true);" +
      "document.removeEventListener('click',onClk,true);" +
      "document.removeEventListener('scroll',onScr,true);" +
      'if(box.parentNode){box.parentNode.removeChild(box);}' +
      'if(lb.parentNode){lb.parentNode.removeChild(lb);}' +
      'try{delete window.__qhInsp;}catch(e){window.__qhInsp=undefined;}}};})();'
  }

  /** 切换到当前选中元素的父元素 */
  static parentScript(): string {
    return 'window.__qhInsp&&window.__qhInsp.parent()'
  }

  /** 返回上一个选中元素（对应父级导航的回退） */
  static childScript(): string {
    return 'window.__qhInsp&&window.__qhInsp.child()'
  }

  /** 清理页内选点蒙版与监听 */
  static exitScript(): string {
    return 'window.__qhInsp&&window.__qhInsp.exit()'
  }

  /** 注入即时隐藏样式（sel 需先经字符白名单校验） */
  static blockStyleScript(sel: string): string {
    return "(function(){var s=document.getElementById('__qh_blk');" +
      "if(!s){s=document.createElement('style');s.id='__qh_blk';" +
      '(document.head||document.documentElement).appendChild(s);}' +
      `s.textContent=s.textContent+'${sel}{display:none!important}\\n';})()`
  }

  /** 控制台求值：返回 JSON.stringify({v:结果}|{e:错误消息}) */
  static evalScript(expr: string): string {
    const enc: string = JSON.stringify(expr)
    return '(function(){try{var r=eval(' + enc + ');var s;' +
      "try{s=(r&&typeof r==='object')?JSON.stringify(r):String(r);}catch(e1){s=String(r);}" +
      'return JSON.stringify({v:s});}catch(e){' +
      'return JSON.stringify({e:String(e&&e.message||e)});}})()'
  }
}
