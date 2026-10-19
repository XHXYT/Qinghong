import { appSettings } from '../entity/SettingsModel';

/**
 * 网页注入脚本构建（文档加载前按设置注入，纯逻辑无 UI）
 */
export class WebScripts {

  /**
   * 隐私与增强脚本：不跟踪/不出售/禁用WebRTC/自动展开全文
   * （广告拦截由 ArkWeb 原生 AdsBlock 引擎处理，不再注入隐藏脚本）
   */
  static privacyScripts(): Array<ScriptItem> {
    const scripts: Array<ScriptItem> = []
    if (appSettings.do_not_track) {
      scripts.push({
        script: "try{Object.defineProperty(navigator,'doNotTrack',{value:'1',configurable:true});}catch(e){}",
        scriptRules: ['*']
      })
    }
    if (appSettings.do_not_sell) {
      scripts.push({
        script: "try{Object.defineProperty(navigator,'globalPrivacyControl',{value:true,configurable:true});}catch(e){}",
        scriptRules: ['*']
      })
    }
    if (appSettings.disable_webrtc) {
      scripts.push({
        script: "try{Object.defineProperty(window,'RTCPeerConnection',{value:undefined,configurable:true});" +
          "Object.defineProperty(window,'webkitRTCPeerConnection',{value:undefined,configurable:true});}catch(e){}",
        scriptRules: ['*']
      })
    }
    // 自动展开网页全文：点击「展开全文/阅读全文」类折叠按钮（每元素只点一次，排除「收起」）
    if (appSettings.auto_expand_web) {
      scripts.push({
        script: "try{(function(){" +
          "var KWS=['展开全文','展开更多','查看全文','阅读全文','显示全文','显示更多','查看更多','点击展开'," +
          "'read more','show more','view more','see more','expand full','full text'];" +
          "function qe(){" +
          "var els=document.querySelectorAll('a,button,span,div');" +
          "for(var i=0;i<els.length;i++){" +
          "var el=els[i];" +
          "if(el.__qe){continue;}" +
          "var t=(el.textContent||'').trim().toLowerCase();" +
          "if(!t||t.length>16||t.indexOf('收起')>=0){continue;}" +
          "var hit=false;" +
          "for(var j=0;j<KWS.length;j++){if(t.indexOf(KWS[j])>=0){hit=true;break;}}" +
          "if(hit){el.__qe=1;try{el.click();}catch(e){}}" +
          "}}" +
          "}" +
          "function run(){qe();setTimeout(qe,800);setTimeout(qe,2000);}" +
          "if(document.readyState==='loading'){" +
          "document.addEventListener('DOMContentLoaded',run);" +
          "}else{run();}" +
          "})()}catch(e){}",
        scriptRules: ['*']
      })
    }
    return scripts
  }

  /**
   * 剪贴板接管脚本：拦截 navigator.clipboard 文本读写（readText/writeText），
   * 经 __qhNative 代理转发原生按站点策略处理（允许/询问/阻止）；
   * rich read()/write() 不拦截，交给引擎
   */
  static clipboardScript(): ScriptItem {
    return {
      script: "try{(function(){" +
        "if(!navigator.clipboard){return;}" +
        "var seq=0,pending={};" +
        "window.__qhClipboardDone=function(id,ok,data){" +
        "var p=pending[id];if(!p){return;}delete pending[id];" +
        "if(ok){p.res(data);}else{p.rej(new DOMException('Clipboard operation was blocked.','NotAllowedError'));}" +
        "};" +
        "function req(action,text){" +
        "return new Promise(function(resolve,reject){" +
        "if(!window.__qhNative){reject(new DOMException('Clipboard unavailable.','NotAllowedError'));return;}" +
        "var id=++seq;pending[id]={res:resolve,rej:reject};" +
        "try{__qhNative.clipboardRequest(action,id,text);}" +
        "catch(e){delete pending[id];reject(new DOMException('Clipboard error.','NotAllowedError'));}" +
        "});" +
        "}" +
        "if(navigator.clipboard.readText){" +
        "navigator.clipboard.readText=function(){return req('readText','');};" +
        "}" +
        "if(navigator.clipboard.writeText){" +
        "navigator.clipboard.writeText=function(t){return req('writeText',t==null?'':String(t));};" +
        "}" +
        "})()}catch(e){}",
      scriptRules: ['*']
    }
  }

  /**
   * 禁用网页振动脚本：将 navigator.vibrate 置为不可写空实现
   * （全局"网页振动"关闭时注入；引擎不支持时跳过，不影响页面）
   */
  static vibrationBlockScript(): ScriptItem {
    return {
      script: "try{if(navigator.vibrate!==undefined){" +
        "Object.defineProperty(navigator,'vibrate',{value:function(){return false},writable:false,configurable:false});" +
        "}}catch(e){}",
      scriptRules: ['*']
    }
  }

  /**
   * 操作栏自动隐藏脚本（文档加载前注入，常驻）：
   * 1. 滑动模式：页面上滑（内容下滚）上报隐藏、下滑上报显示（capture 捕获内部滚动容器）；
   * 2. 点击模式：点击非交互元素（非链接/按钮/输入等）上报切换；
   * 模式是否生效由原生侧 __qhNative 回调按设置判定
   */
  static actionBarScript(): ScriptItem {
    return {
      script: "try{(function(){" +
        "if(window.__qhActionBarBound){return}window.__qhActionBarBound=true;" +
        "var lastY=window.scrollY||0;" +
        "window.addEventListener('scroll',function(ev){" +
        "var y=window.scrollY||document.documentElement.scrollTop||0;" +
        "if(y>lastY+4&&y>10){__qhNative.actionBarScroll(true)}" +
        "else if(y<lastY-4){__qhNative.actionBarScroll(false)}" +
        "lastY=y;},true);" +
        "document.addEventListener('click',function(ev){" +
        "var t=ev.target;" +
        "if(t&&t.closest&&!t.closest('a,button,input,select,textarea,label,video,audio,embed,object,svg,[onclick],[role=button],[contenteditable]')){" +
        "__qhNative.actionBarTapToggle();}},true);" +
        "})()}catch(e){}",
      scriptRules: ['*']
    }
  }

  /**
   * 密码管理器脚本（文档加载前注入）：
   * 1. 挂 window.__qhFillPassword(user,pass) 供原生自动填充（含 SPA 表单延迟重试）；
   * 2. 监听表单提交与按钮点击，捕获登录凭据经 __qhNative.passwordSubmit 上报原生弹保存提示
   */
  static passwordScript(): ScriptItem {
    return {
      script: "try{(function(){" +
        "if(window.__qhPwInit){return;}window.__qhPwInit=1;" +
        "function pwds(){return Array.prototype.slice.call(document.querySelectorAll('input[type=password]'));}" +
        "function score(el){" +
        "var s=0;var ac=(el.getAttribute('autocomplete')||'').toLowerCase();" +
        "var nm=((el.name||'')+' '+(el.id||'')).toLowerCase();" +
        "if(ac.indexOf('username')>=0||ac.indexOf('email')>=0){s+=10;}" +
        "if(nm.indexOf('user')>=0||nm.indexOf('email')>=0||nm.indexOf('account')>=0||nm.indexOf('phone')>=0||nm.indexOf('mobile')>=0){s+=5;}" +
        "if((el.type||'').toLowerCase()==='email'){s+=3;}" +
        "return s;" +
        "}" +
        "function userOf(p){" +
        "var scope=p.form||document;" +
        "var list=scope.querySelectorAll(\"input:not([type=password]):not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=submit]):not([type=button]):not([type=file]):not([type=image])\");" +
        "var best=null,bestScore=-1;" +
        "for(var i=0;i<list.length;i++){" +
        "var el=list[i];var t=(el.type||'').toLowerCase();" +
        "if(t!=='email'&&t!=='text'&&t!=='tel'){continue;}" +
        "if(p.form===null&&!(el.compareDocumentPosition(p)&Node.DOCUMENT_POSITION_FOLLOWING)){continue;}" +
        "var s=score(el);if(s>=bestScore){bestScore=s;best=el;}" +
        "}" +
        "return best;" +
        "}" +
        "function setV(el,v){" +
        "try{" +
        "var proto=(el.tagName==='TEXTAREA')?window.HTMLTextAreaElement.prototype:window.HTMLInputElement.prototype;" +
        "var d=Object.getOwnPropertyDescriptor(proto,'value');" +
        "if(d&&d.set){d.set.call(el,v);}else{el.value=v;}" +
        "el.dispatchEvent(new Event('input',{bubbles:true}));" +
        "el.dispatchEvent(new Event('change',{bubbles:true}));" +
        "}catch(e){try{el.value=v;}catch(e2){}}" +
        "}" +
        "function tryFill(){" +
        "try{" +
        "var c=window.__qhPwCred;if(!c){return;}" +
        "var list=pwds();if(!list.length){return;}" +
        "var f=list[0];" +
        "if(!f.value){setV(f,c.p);}" +
        "var u=userOf(f);" +
        "if(u&&c.u&&!u.value){setV(u,c.u);}" +
        "}catch(e){}" +
        "}" +
        "window.__qhFillPassword=function(user,pass){" +
        "window.__qhPwCred={u:user,p:pass};" +
        "tryFill();" +
        "if(!window.__qhPwObs){" +
        "window.__qhPwObs=1;var n=0;" +
        "var timer=setInterval(function(){n++;tryFill();if(n>20){clearInterval(timer);}},500);" +
        "document.addEventListener('DOMContentLoaded',function(){tryFill();});" +
        "}" +
        "};" +
        "function report(){" +
        "try{" +
        "var list=pwds();var filled=null;" +
        "for(var i=list.length-1;i>=0;i--){if(list[i].value){filled=list[i];break;}}" +
        "if(!filled){return;}" +
        "var pass=filled.value;if(!pass){return;}" +
        "var u=userOf(filled);var user=(u&&u.value)||'';" +
        "var key=user+'\\n'+pass;" +
        "if(!window.__qhPwSeen){window.__qhPwSeen={};}" +
        "if(window.__qhPwSeen[key]){return;}" +
        "window.__qhPwSeen[key]=1;" +
        "if(window.__qhNative&&__qhNative.passwordSubmit){__qhNative.passwordSubmit(user,pass);}" +
        "}catch(e){}" +
        "}" +
        "document.addEventListener('submit',function(){setTimeout(report,80);},true);" +
        "document.addEventListener('click',function(e){" +
        "try{" +
        "var t=e.target;if(!t||!t.closest){return;}" +
        "if(t.closest('button,[role=button],input[type=submit],input[type=button],a')){setTimeout(report,600);}" +
        "}catch(e2){}" +
        "},true);" +
        "})()}catch(e){}",
      scriptRules: ['*']
    }
  }

  /**
   * 长按/右键菜单辅助脚本：contextmenu 触发时记录命中链接的文本，
   * 供原生 onContextMenuShow 之后 runJavaScript 读取（复制链接文本用）
   */
  static contextMenuScript(): ScriptItem {
    return {
      script: "try{(function(){" +
        "if(window.__qhCtxInit){return;}window.__qhCtxInit=1;window.__qhCtxText='';" +
        "document.addEventListener('contextmenu',function(e){" +
        "window.__qhCtxText='';" +
        "try{" +
        "var t=e.target;" +
        "var a=t&&t.closest?t.closest('a'):null;" +
        "if(a){window.__qhCtxText=(a.textContent||'').replace(/\\s+/g,' ').trim().slice(0,300);}" +
        "}catch(x){}" +
        "},true);" +
        "})()}catch(e){}",
      scriptRules: ['*']
    }
  }
}
