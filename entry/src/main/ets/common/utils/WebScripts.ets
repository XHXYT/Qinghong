import { appSettings } from '../entity/SettingsModel';
import { adBlockEngine } from './AdBlockEngine';

/**
 * 网页注入脚本构建（文档加载前按设置注入，纯逻辑无 UI）
 */
export class WebScripts {

  /**
   * 隐私与增强脚本：不跟踪/不出售/禁用WebRTC/自动展开全文/广告元素隐藏
   * @param adBlockOn 调用方（站点级）广告拦截是否生效，false 时不注入元素隐藏
   */
  static privacyScripts(adBlockOn: boolean = true): Array<ScriptItem> {
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
    // 广告拦截：元素隐藏注入脚本（依赖设置与自定义规则版本，变更后自动重建）
    if (adBlockOn) {
      const hide: string = adBlockEngine.hideScript()
      if (hide !== '') {
        scripts.push({
          script: hide,
          scriptRules: ['*']
        })
      }
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
}
