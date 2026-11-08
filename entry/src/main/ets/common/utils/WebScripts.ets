import { appSettings } from '../entity/SettingsModel';

/**
 * 网页注入脚本构建（文档加载前按设置注入，纯逻辑无 UI）
 */
export class WebScripts {

  /**
   * 隐私与增强脚本：不跟踪/不出售/禁用WebRTC/自动展开全文
   * （广告拦截由 ArkWeb 原生 AdsBlock 引擎处理）
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
   *    每次显隐切换后 400ms 静默窗（覆盖 250ms 动画）：吸收高度变化引发的滚动锚定反向调整，
   *    防止合成滚动事件形成显隐振荡（sticky 头部重页面滚动回弹的根因）；
   * 2. 点击模式：点击非交互元素（非链接/按钮/输入等）上报切换；
   * 模式是否生效由原生侧 __qhNative 回调按设置判定
   */
  static actionBarScript(): ScriptItem {
    return {
      script: "try{(function(){" +
        "if(window.__qhActionBarBound){return}window.__qhActionBarBound=true;" +
        "var lastY=window.scrollY||0;" +
        "var muteUntil=0;" +
        "window.addEventListener('scroll',function(ev){" +
        "var y=window.scrollY||document.documentElement.scrollTop||0;" +
        "if(Date.now()<muteUntil){lastY=y;return}" +
        "if(y>lastY+4&&y>10){__qhNative.actionBarScroll(true);muteUntil=Date.now()+400}" +
        "else if(y<lastY-4){__qhNative.actionBarScroll(false);muteUntil=Date.now()+400}" +
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

  /**
   * 采集「正在播放」的视频信息（助手菜单打开时 runJavaScript 执行，非侵入不改页面状态）：
   * 严格判定播放中（!paused && !ended && readyState>=2）且地址为 http(s) 直链
   * （blob:/MSE 媒体排除），顶层 document 扫不到时递归同源 iframe（跨域静默跳过）；
   * 返回 JSON 字符串 {u:地址,p:当前秒,d:总秒,m:静音,r:就绪态,w:播放中}，无则空串
   */
  static playingVideoInfoJs(): string {
    return "try{(function(){" +
      "function info(v){try{" +
      "var s=v.currentSrc||v.src||'';" +
      "if(!s){return '';}" +
      "try{s=new URL(s,v.ownerDocument.baseURI).href;}catch(e){return '';}" +
      "if(!/^https?:/i.test(s)){return '';}" +
      "return JSON.stringify({u:s,p:v.currentTime||0,d:isFinite(v.duration)?v.duration:0," +
      "m:!!v.muted,r:v.readyState,w:!v.paused&&!v.ended});" +
      "}catch(e){return '';}}" +
      "function find(doc){try{" +
      "var vs=doc.querySelectorAll('video');" +
      "var j='',area=-1;" +
      "for(var i=0;i<vs.length;i++){var v=vs[i];" +
      "if(v.paused||v.ended||v.readyState<2){continue;}" +
      "var a=(v.videoWidth||v.clientWidth||0)*(v.videoHeight||v.clientHeight||0);" +
      "if(a<=area){continue;}" +
      "var jj=info(v);if(jj){j=jj;area=a;}}" +
      "return j;" +
      "}catch(e){return '';}}" +
      "var r=find(document);" +
      "if(!r){var fs=document.querySelectorAll('iframe');" +
      "for(var k=0;k<fs.length&&!r;k++){" +
      "try{r=find(fs[k].contentDocument);}catch(e){}}}" +
      "return r;" +
      "})()}catch(e){return ''}"
  }

  /**
   * 接管探测（快速托管路径，runJavaScript 执行；非侵入，不改页面状态）：
   * 播放中的视频优先，无则回退任意 readyState>=2 的视频（含暂停态）；
   * MSE/blob 视频保留（u 返回空串，由原生侧用网络日志嗅探的 m3u8/mp4 补位）；
   * 返回 JSON 字符串 {u:直链或空,p:当前秒,d:总秒,m:静音,r:就绪态,w:是否播放中}，无视频返回空串
   */
  static takeoverProbeJs(): string {
    return "try{(function(){" +
      "function info(v){try{" +
      "var s=v.currentSrc||v.src||'';" +
      "var u='';" +
      "if(s){" +
      "try{u=new URL(s,v.ownerDocument.baseURI).href;}catch(e){u=s;}" +
      "if(!/^https?:/i.test(u)){u='';}" +
      "}" +
      "return JSON.stringify({u:u,p:v.currentTime||0,d:isFinite(v.duration)?v.duration:0," +
      "m:!!v.muted,r:v.readyState,w:!v.paused&&!v.ended});" +
      "}catch(e){return '';}}" +
      "function find(doc){try{" +
      "var vs=doc.querySelectorAll('video');" +
      "var v=null,i,area=-1;" +
      "for(i=0;i<vs.length;i++){var c=vs[i];" +
      "if(c.paused||c.ended||c.readyState<2){continue;}" +
      "var a=(c.videoWidth||c.clientWidth||0)*(c.videoHeight||c.clientHeight||0);" +
      "if(a>area){area=a;v=c;}}" +
      "if(v){return v;}" +
      "area=-1;" +
      "for(i=0;i<vs.length;i++){var c2=vs[i];" +
      "if(c2.readyState<2){continue;}" +
      "var a2=(c2.videoWidth||c2.clientWidth||0)*(c2.videoHeight||c2.clientHeight||0);" +
      "if(a2>area){area=a2;v=c2;}}" +
      "return v;" +
      "}catch(e){return null;}}" +
      "var v=find(document);" +
      "if(!v){var fs=document.querySelectorAll('iframe');" +
      "for(var k=0;k<fs.length&&!v;k++){" +
      "try{v=find(fs[k].contentDocument);}catch(e){}}" +
      "return v?info(v):'';" +
      "})()}catch(e){return ''}"
  }

  /**
   * 暂停网页播放中视频并打 __qhHosted 标记（原生侧确认拿到可播地址后调用；
   * 归还时 restoreVideoJs 凭标记定位视频恢复续播）
   */
   static pauseVideoJs(): string {
     return "try{(function(){" +
       "function find(doc){try{" +
       "var vs=doc.querySelectorAll('video');" +
       "var v=null,i,area=-1;" +
       "for(i=0;i<vs.length;i++){var c=vs[i];" +
       "if(c.paused||c.ended||c.readyState<2){continue;}" +
       "var a=(c.videoWidth||c.clientWidth||0)*(c.videoHeight||c.clientHeight||0);" +
       "if(a>area){area=a;v=c;}}" +
       "if(v){return v;}" +
       "area=-1;" +
       "for(i=0;i<vs.length;i++){var c2=vs[i];" +
       "if(c2.readyState<2){continue;}" +
       "var a2=(c2.videoWidth||c2.clientWidth||0)*(c2.videoHeight||c2.clientHeight||0);" +
       "if(a2>area){area=a2;v=c2;}}" +
       "return v;" +
       "}catch(e){return null;}}" +
      "var v=find(document);" +
      "if(!v){var fs=document.querySelectorAll('iframe');" +
      "for(var k=0;k<fs.length&&!v;k++){" +
      "try{v=find(fs[k].contentDocument);}catch(e){}}}" +
      "if(!v){return;}" +
      "try{v.pause();}catch(e){}" +
      "try{v.__qhHosted=1;}catch(e){}" +
      "})()}catch(e){}"
  }

  /**
   * 归还网页视频（独立托管结束恢复用，runJavaScript 执行）：
   * 优先查找 __qhHosted 标记的视频（顶层 + 同源 iframe），标记丢失时回退
   * 面积最大选片（与接管探测同目标），清除标记并定位到 pos，
   * wasPlaying 时恢复播放（不刷新页面，网页视频无感续播）
   */
  static restoreVideoJs(pos: number, wasPlaying: boolean): string {
    const p: string = pos.toFixed(2)
    const w: string = wasPlaying ? '1' : '0'
    return "try{(function(){" +
      "function mark(doc){try{" +
      "var vs=doc.querySelectorAll('video');" +
      "for(var i=0;i<vs.length;i++){if(vs[i].__qhHosted){return vs[i];}}" +
      "}catch(e){}return null;}" +
      "function pick(doc){try{" +
      "var vs=doc.querySelectorAll('video');" +
      "var v=null,area=-1;" +
      "for(var i=0;i<vs.length;i++){var c=vs[i];" +
      "if(c.readyState<2){continue;}" +
      "var a=(c.videoWidth||c.clientWidth||0)*(c.videoHeight||c.clientHeight||0);" +
      "if(a>area){area=a;v=c;}}" +
      "if(!v){for(var j=0;j<vs.length;j++){v=vs[j];break;}}" +
      "return v;" +
      "}catch(e){}return null;}" +
      "var v=mark(document);" +
      "if(!v){var fs=document.querySelectorAll('iframe');" +
      "for(var k=0;k<fs.length&&!v;k++){" +
      "try{v=mark(fs[k].contentDocument);}catch(e){}}}" +
      "if(!v){v=pick(document);" +
      "if(!v){var fs2=document.querySelectorAll('iframe');" +
      "for(var k2=0;k2<fs2.length&&!v;k2++){" +
      "try{v=pick(fs2[k2].contentDocument);}catch(e){}}}}" +
      "if(!v){return;}" +
      "try{v.__qhHosted=0;}catch(e){}" +
      "try{if(isFinite(v.duration)&&" + p + ">0){v.currentTime=Math.min(" + p + ",v.duration);}}" +
      "catch(e){}" +
      "if(" + w + "){try{v.play().catch(function(){});}catch(e){}}" +
      "})()}catch(e){}"
  }

  /**
   * 资源嗅探按需采集（打开嗅探面板时 runJavaScript 执行一次）：
   * DOM 媒体元素（img/video/audio/source/embed/poster）+ performance 资源条目
   * + 整页 HTML 正则扫描内嵌媒体 URL（可抓到未播放、仅写在页面/脚本配置里的地址），
   * 按扩展名分类为 video/audio/image，返回 JSON 数组 [{u:URL,k:类型}]。
   * 与网络日志互补：可抓到 <video> 元素 src、页面静态媒体等未走当前记录的地址
   */
  static sniffCollectJs(): string {
    return "try{(function(){" +
      "var VE=/\\.(mp4|m3u8|webm|flv|mkv|mov|ts|avi|m4v)(\\?|#|$)/i;" +
      "var AE=/\\.(mp3|m4a|aac|flac|wav|ogg|opus|amr)(\\?|#|$)/i;" +
      "var IE=/\\.(jpg|jpeg|png|webp|gif|bmp|svg|ico|avif)(\\?|#|$)/i;" +
      "var ME='m3u8|mp4|webm|flv|mkv|mov|m4v|avi|mp3|m4a|aac|flac|wav|ogg|opus|amr';" +
      "var seen={},out=[];" +
      "function kind(u){var s=String(u).split('?')[0];" +
      "if(VE.test(s)){return 'video';}" +
      "if(AE.test(s)){return 'audio';}" +
      "if(IE.test(s)){return 'image';}" +
      "return '';}" +
      "function add(u,k){if(!u){return;}u=String(u);" +
      "try{u=new URL(u,location.href).href;}catch(e){return;}" +
      "if(seen[u]){return;}var kk=k||kind(u);if(!kk){return;}" +
      "seen[u]=1;out.push({u:u,k:kk});}" +
      "var els=document.querySelectorAll('img,video,audio,source,embed');" +
      "for(var i=0;i<els.length;i++){var el=els[i],tag=el.tagName;" +
      "var def=tag==='IMG'?'image':(tag==='VIDEO'?'video':(tag==='AUDIO'?'audio':''));" +
      "add(el.currentSrc||el.src||el.getAttribute('data-src')||'',def);" +
      "if(tag==='VIDEO'||tag==='AUDIO'){add(el.getAttribute('poster')||'','image');}}" +
      "if(window.performance&&performance.getEntriesByType){" +
      "var rs=performance.getEntriesByType('resource');" +
      "for(var j=0;j<rs.length;j++){add(rs[j].name,'');}}" +
      "try{" +
      "var html=document.documentElement.innerHTML||'';" +
      "var RE=new RegExp('https?:\\\\/\\\\/[^\\\\s\\\"\\'<>\\\\\\\\)]+?\\\\.(?:'+ME+')(?:\\\\?[^\\\\s\\\"\\'<>\\\\\\\\)]*)?|[\\\"\\'(]\\\\/\\\\/[^\\\\s\\\"\\'<>\\\\\\\\)]+?\\\\.(?:'+ME+')(?:\\\\?[^\\\\s\\\"\\'<>\\\\\\\\)]*)?','gi');" +
      "var hm;while((hm=RE.exec(html))!==null){" +
      "var s=hm[0],c=s.charAt(0);" +
      "if(c==='\\\"'||c===\"\\'\"||c==='('){s=s.substring(1);}" +
      "add(s,'');}" +
      "}catch(e){}" +
      "return JSON.stringify(out);" +
      "})()}catch(e){return '[]'}"
  }

  /**
   * 媒体嗅探钩子脚本（文档加载前注入，常驻）：
   * 1. 包装 HTMLMediaElement.src 赋值、XMLHttpRequest.open、fetch 三个入口，命中媒体扩展名即上报；
   * 2. DOM 就绪后自动扫描整页 HTML 内嵌媒体 URL + video/audio/source 元素（可抓到只写在
   *    页面/脚本配置里、从未经 JS 赋值或 XHR 请求的地址，对齐华为浏览器载入即捕获的行为）；
   * 3. __qhNative 代理不可用（iframe）时经 postMessage 向父帧中继，主帧脚本转发原生。
   * 上报经 __qhNative.sniffMedia 记入网络日志，悬浮按钮实时出现
   */
  static sniffMediaScript(): ScriptItem {
    return {
      script: "try{(function(){" +
        "if(window.__qhSniffBound){return;}window.__qhSniffBound=1;" +
        "var ME='m3u8|mp4|webm|flv|mkv|mov|m4v|avi|mp3|m4a|aac|flac|wav|ogg|opus|amr';" +
        "var VE=/\\.(m3u8|mp4|webm|flv|mkv|mov|m4v|avi)([?#]|$)/i;" +
        "var AE=/\\.(mp3|m4a|aac|flac|wav|ogg|opus|amr)([?#]|$)/i;" +
        "var seen={};" +
        "function abs(u){try{return new URL(u,location.href).href;}catch(e){return '';}}" +
        "function rep(u,k){" +
        "try{" +
        "if(!u){return;}" +
        "u=abs(String(u));" +
        "if(!/^https?:/i.test(u)){return;}" +
        "k=k||'';" +
        "if(!k){if(VE.test(u)){k='video';}else if(AE.test(u)){k='audio';}}" +
        "if(!k){return;}" +
        "if(seen[u]){return;}" +
        "seen[u]=1;" +
        "if(window.__qhNative&&__qhNative.sniffMedia){__qhNative.sniffMedia(u,k);}" +
        "else if(window.parent!==window){try{window.parent.postMessage({__qhSniff:{u:u,k:k}},'*');}catch(e){}}" +
        "}catch(e){}" +
        "}" +
        "window.addEventListener('message',function(ev){" +
        "try{var d=ev.data;" +
        "if(d&&typeof d==='object'&&d.__qhSniff&&d.__qhSniff.u){rep(d.__qhSniff.u,d.__qhSniff.k||'');}" +
        "}catch(e){}" +
        "},false);" +
        "function scan(){" +
        "try{" +
        "var RE=new RegExp('https?:\\\\/\\\\/[^\\\\s\\\"\\'<>\\\\\\\\)]+?\\\\.(?:'+ME+')(?:\\\\?[^\\\\s\\\"\\'<>\\\\\\\\)]*)?|[\\\"\\'(]\\\\/\\\\/[^\\\\s\\\"\\'<>\\\\\\\\)]+?\\\\.(?:'+ME+')(?:\\\\?[^\\\\s\\\"\\'<>\\\\\\\\)]*)?','gi');" +
        "var html=document.documentElement.innerHTML||'';" +
        "var m;while((m=RE.exec(html))!==null){" +
        "var s=m[0],c=s.charAt(0);" +
        "if(c==='\\\"'||c===\"\\'\"||c==='('){s=s.substring(1);}" +
        "rep(s,'');}" +
        "}catch(e){}" +
        "try{" +
        "var els=document.querySelectorAll('video,audio,source');" +
        "for(var i=0;i<els.length;i++){rep(els[i].currentSrc||els[i].src||'','');}" +
        "}catch(e){}" +
        "}" +
        "function sched(){scan();setTimeout(scan,1500);setTimeout(scan,4000);}" +
        "if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',sched);}" +
        "else{sched();}" +
        "try{" +
        "var d=Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype,'src');" +
        "if(d&&d.set){" +
        "Object.defineProperty(HTMLMediaElement.prototype,'src',{configurable:true,enumerable:d.enumerable," +
        "get:function(){return d.get.call(this);}," +
        "set:function(v){rep(v,'');return d.set.call(this,v);}});" +
        "}" +
        "}catch(e){}" +
        "try{" +
        "var oo=XMLHttpRequest.prototype.open;" +
        "XMLHttpRequest.prototype.open=function(m,u){rep(u,'');return oo.apply(this,arguments);};" +
        "}catch(e){}" +
        "try{" +
        "var of=window.fetch;" +
        "if(of){window.fetch=function(i,o){try{rep(i&&i.url!==undefined?i.url:i,'');}catch(e){}return of.apply(this,arguments);};" +
        "}" +
        "}catch(e){}" +
        "})()}catch(e){}",
      scriptRules: ['*']
    }
  }
}
