import { appSettings } from '../../entity/SettingsModel';
import { VIDEO_KB_SHORTCUTS, parseVideoKbOverrides } from '../../constants/KbShortcuts';

/**
 * 网页视频控制注入脚本（按设置注入，文档加载前执行，DOMContentLoaded 后绑事件）：
 * - 手势（document 捕获 touchstart，每次触摸动态定位视频，兼容各类播放器布局）：
 *   三区双击（各区分动作可配：快退/快进秒数可调、播放/暂停，CFG.dzL/dzM/dzR+sL/sM/sR）、
 *   水平滑动调进度（松开生效）、全屏左右侧上下滑（CFG.svL/svR 可配亮度/音量）、
 *   单击透传站点显隐面板（全屏接管时显隐己方控制层）、长按倍速（CFG.lpr 档位可配）；
 *   手势抑制按需生效（控制按钮、视频上下缘控制条区域始终豁免）：未接管的触摸
 *   透传站点，保留网页播放器控制面板显隐；仅己方手势实际接管时（滑动/侧滑/
 *   长按收尾、双击第二击）阻断该次 touchend 透传与 click 合成
 * - 键盘快捷键（键位可自定义，CFG.KA 为"归一化键名→动作"映射）：
 *   默认 空格 播放暂停、←/→ ±5s、J/L ±10s、↑/↓ 音量、M 静音、F 全屏（已处理键捕获抑制）
 * 手势总开关关闭时手势功能全部不注入；快捷键独立开关
 */
export class VideoScripts {

  /** 任一视频控制功能开启时返回注入脚本，全部关闭返回 null */
  static controlScript(): ScriptItem | null {
    const gesture: boolean = appSettings.video_gesture_enabled
    const kb: boolean = appSettings.video_keyboard_shortcuts
    if (!gesture && !kb) {
      return null
    }
    // 键位映射（归一化键名 → 动作 id），含用户自定义覆盖
    let kaJson: string = '{}'
    if (kb) {
      const ov: Record<string, string> = parseVideoKbOverrides(appSettings.video_kb_keys)
      const ka: Record<string, string> = {}
      for (const d of VIDEO_KB_SHORTCUTS) {
        let name: string = d.defKeyName
        const o: string = ov[d.id]
        if (o !== undefined && o !== '') {
          name = o
        }
        ka[name] = d.id
      }
      kaJson = JSON.stringify(ka)
    }
    // 手势子开关（G=任一触摸手势启用：抑制站点自带手势；未接管的单击仍透传，控制面板显隐不受影响）
    // 三区双击动作 dzL/dzM/dzR（rewind/forward/playpause/none）、上下滑动作 svL/svR（brightness/volume/none）、
    // 长按倍速档位 lpr（'off'|'2'|'2.5'|'3'|'4'，off=关闭）
    const swipe: boolean = gesture && appSettings.video_gesture_swipe_seek
    const dzl: string = gesture ? appSettings.video_dtap_left : 'none'
    const dzm: string = gesture ? appSettings.video_dtap_middle : 'none'
    const dzr: string = gesture ? appSettings.video_dtap_right : 'none'
    const svl: string = gesture ? appSettings.video_slide_left : 'none'
    const svr: string = gesture ? appSettings.video_slide_right : 'none'
    const lpr: string = gesture ? appSettings.video_long_press_rate : 'off'
    const dtapOn: boolean = dzl !== 'none' || dzm !== 'none' || dzr !== 'none'
    const sideOn: boolean = svl !== 'none' || svr !== 'none'
    const lpOn: boolean = lpr !== 'off'
    const cfg: string = '{"G":' + (dtapOn || swipe || sideOn || lpOn) +
      ',"dzL":"' + dzl + '"' +
      ',"dzM":"' + dzm + '"' +
      ',"dzR":"' + dzr + '"' +
      ',"sL":' + appSettings.video_dtap_left_sec +
      ',"sM":' + appSettings.video_dtap_middle_sec +
      ',"sR":' + appSettings.video_dtap_right_sec +
      ',"svL":"' + svl + '"' +
      ',"svR":"' + svr + '"' +
      ',"swipe":' + swipe +
      ',"lpr":"' + lpr + '"' +
      ',"kb":' + kb +
      ',"KA":' + kaJson + '}'
    return {
      script: "(function(){" +
        "if(window.__qhVideoCtrl){return}" +
        "window.__qhVideoCtrl=true;" +
        "var CFG=" + cfg + ";" +
        "var DBLMS=300,LPMS=600;" +
        "function run(){" +
        // ---------- 工具 ----------
        "function itag(el){try{return !!el.closest('button,input,select,textarea,a')}catch(e){return false}}" +
        "function c01(x){return Math.min(1,Math.max(0,x))}" +
        // 触摸目标 → 视频元素：自身是视频直接用；否则在尺寸相仿的祖先内查找（兼容全屏覆盖操控层的站点）
        "function fvideo(t){" +
        "if(t.tagName==='VIDEO'){return t}" +
        "if(itag(t)){return null}" +
        "var tw=t.clientWidth,th=t.clientHeight;" +
        "if(!tw||!th){return null}" +
        "var p=t,best=null,i;" +
        "for(i=0;i<12;i++){" +
        "p=p.parentElement;" +
        "if(!p||p===document.body||p===document.documentElement){break}" +
        "if(p.clientWidth>0&&p.clientWidth<tw*1.2&&p.clientHeight>0&&p.clientHeight<th*1.2){" +
        "var v=p.querySelector('video');if(v){best=v}" +
        "}" +
        "}" +
        "if(!best&&t.querySelector){" +
        "var v2=t.querySelector('video');" +
        "if(v2&&t.clientHeight<=window.innerHeight*1.5){best=v2}" +
        "}" +
        "return best" +
        "}" +
        "function fmt(s){" +
        "s=Math.round(Math.abs(s));" +
        "var m=Math.floor(s/60),r=s%60;" +
        "return (m>0?m+'分'+r+'秒':r+'秒')" +
        "}" +
        // ---------- 指示器（fixed 视口居中：父容器尺寸在全屏时不等于屏幕尺寸，绝对定位计算必偏） ----------
        "function notice(v,text,keep){" +
        "var c=document.fullscreenElement;" +
        "if(!c||c===v||c.tagName==='VIDEO'||c.tagName==='AUDIO'){c=v.parentElement}" +
        "if(!c){return}" +
        "var n=document.getElementById('__qhVNotice');" +
        "if(!n){" +
        "n=document.createElement('div');n.id='__qhVNotice';" +
        "n.style.cssText='position:fixed;left:50%;top:50%;-webkit-transform:translate(-50%,-50%);z-index:2147483647;pointer-events:none;"+"" +
        "background:rgba(0,0,0,0.5);color:#fff;font:16px/1.6 sans-serif;"+"" +
        "padding:16px 32px;border-radius:16px;text-align:center;white-space:nowrap;';" +
        "}" +
        "if(n.parentElement!==c){c.appendChild(n)}" +
        "n.innerText=text;n.style.display='block';" +
        "clearTimeout(n.__t);" +
        "if(!keep){n.__t=setTimeout(function(){n.style.display='none'},700)}" +
        "}" +
        "function seekBy(v,d){" +
        "try{" +
        "if(!isFinite(v.duration)){return}" +
        "v.currentTime=Math.min(Math.max(0,v.currentTime+d),v.duration);" +
        "notice(v,(d>0?'快进 ':'快退 ')+fmt(d))" +
        "}catch(e){}" +
        "}" +
        // ---------- 触屏手势（document 捕获） ----------
        "document.addEventListener('touchstart',function(e){" +
        "if(e.touches.length!==1){return}" +
        "var t=e.target;" +
        "if(!t||!t.tagName){return}" +
        "var v=fvideo(t);" +
        "if(!v){return}" +
        "if(isFinite(v.duration)&&v.duration>0&&v.duration<30){return}" +
        "var sx=e.touches[0].clientX,sy=e.touches[0].clientY;" +
        // 站点控制条区域（视频上/下缘条带）豁免：面板内进度条拖拽、滑块等操作完全交还站点
        "var vr=v.getBoundingClientRect();" +
        "if(vr.height>0&&(sy>vr.bottom-Math.max(64,vr.height*0.2)||sy<vr.top+Math.max(48,vr.height*0.12))){return}" +
        // 己方全屏控制层元素豁免（按钮/进度条等 pointer-events:auto 控件，触摸不接管）
        "if(t.closest&&t.closest('.__qhctl')){return}" +
        // 手势启用时抑制站点 touchstart 级手势（自带长按/按压反馈/起手计数）；
        // 单击面板显隐依赖 touchend/click，在 onEnd 中按需放行，不受影响；
        // 全屏接管期间（__qhFsTaken）恒垄断站点手势（站点控制层已被 CSS 隐藏，
        // 残留监听会造成双响应）
        "if(CFG.G||window.__qhFsTaken){e.stopPropagation()}" +
        "var ex=sx,ey=sy;" +
        "var fs=!!document.fullscreenElement;" +
        "if(fs){" +
        "var ww=window.innerWidth,wh=window.innerHeight;" +
        "if(sx<ww*0.05||sx>ww*0.95||sy<wh*0.05||sy>wh*0.95){return}" +
        "}" +
        "var mode=0,seekD=0,svAct='none',base=1,lpT=null,lpOn=false;" +
        "var played=!v.paused;" +
        "function mv(){return Math.abs(ex-sx)>12||Math.abs(ey-sy)>12}" +
        "function clp(){if(lpT){clearTimeout(lpT);lpT=null}}" +
        "function onMove(ev){" +
        "if(ev.touches.length!==1){return}" +
        "if(CFG.G){ev.stopPropagation()}" +
        "clp();" +
        "ex=ev.touches[0].clientX;ey=ev.touches[0].clientY;" +
        "var dx=ex-sx,dy=ey-sy;" +
        "if(mode===0){" +
        "if(Math.abs(dx)>12&&Math.abs(dx)>Math.abs(dy)){" +
        "if(CFG.swipe){mode=1}" +
        "}else if(Math.abs(dy)>12&&Math.abs(dy)>Math.abs(dx)){" +
        "svAct=sx<window.innerWidth/2?CFG.svL:CFG.svR;" +
        "if(svAct!=='none'&&fs){mode=2;base=svAct==='brightness'?(window.__qhBr==null?1:window.__qhBr):(v.muted?0:v.volume)}" +
        "}" +
        "if(mode===0){return}" +
        "}" +
        "if(mode===1){" +
        "ev.preventDefault();" +
        "seekD=dx*0.5;" +
        "notice(v,(seekD>0?'>> ':'<< ')+fmt(seekD),true)" +
        "}else if(mode===2){" +
        "ev.preventDefault();" +
        "var k=c01(base-dy/(window.innerHeight*0.7));" +
        "if(svAct==='brightness'){" +
        "window.__qhBr=k;" +
        "try{__qhNative.videoRequest('brightness',String(k))}catch(err){}" +
        "notice(v,'亮度 '+Math.round(k*100)+'%',true)" +
        "}else{" +
        // 全屏接管期间音量走 __qhVol（0.001 钳制防站点看门狗回写，与控制层同一链路）
        "if(window.__qhFsTaken&&window.__qhVol){window.__qhVol(k);notice(v,'音量 '+Math.round(k*100)+'%',true)}" +
        "else{v.volume=k;v.muted=(k===0);notice(v,'音量 '+Math.round(k*100)+'%',true)}" +
        "}" +
        "}" +
        "}" +
        "function onEnd(e){" +
        "clp();" +
        "document.removeEventListener('touchmove',onMove,true);" +
        "document.removeEventListener('touchend',onEnd,true);" +
        "document.removeEventListener('touchcancel',onEnd,true);" +
        "var tap0=(mode===0&&ex===sx&&ey===sy&&e.type==='touchend');" +
        "var now=Date.now();" +
        "var last=v.__qhTapAt||0,lx=v.__qhTapX||-9999;" +
        "var dz='none',dsec=10;" +
        "if(tap0&&(now-last<DBLMS)&&Math.abs(sx-lx)<48){" +
        "var zw=window.innerWidth;" +
        "if(sx<zw/3){dz=CFG.dzL;dsec=CFG.sL}" +
        "else if(sx>zw*2/3){dz=CFG.dzR;dsec=CFG.sR}" +
        "else{dz=CFG.dzM;dsec=CFG.sM}" +
        "}" +
        "var isDbl=dz!=='none';" +
        "if(tap0){v.__qhTapAt=now;v.__qhTapX=sx}" +
        // 仅己方手势实际接管时才终结透传并阻断 click 合成（滑动/侧滑/长按收尾、双击第二击）；
        // 全屏接管期单击也阻断（站点残留 click 监听防双响应，单击语义完全归己方）；
        // 普通单击完全透传站点（站点自行处理控制面板显隐）
        "if(CFG.G&&(mode!==0||lpOn||isDbl||(tap0&&window.__qhFsTaken))){e.stopPropagation();e.preventDefault();}" +
        "if(lpOn){try{v.playbackRate=1}catch(e){}lpOn=false}" +
        "if(mode===1&&seekD!==0){seekBy(v,seekD)}" +
        // 纵滑结束：居中指示浮层 400ms 后隐藏（对齐原生面板松手停留时长；修复滑音量后不消失）
        "if(mode===2){var nn=document.getElementById('__qhVNotice');if(nn){clearTimeout(nn.__t);nn.__t=setTimeout(function(){nn.style.display='none'},400)}}" +
        "if(tap0){" +
        "var pl0=v.__qhTapPl;" +
        "v.__qhTapPl=played;" +
        "clearTimeout(v.__qhTapT);" +
        // 三区双击：按区执行配置动作（rewind 快退 / forward 快进 / playpause 播放暂停）；
        // 播放暂停动作在两击间播放态已变（站点 click 已处理第一击）时不补切，保证净效果一次切换
        "if(isDbl){" +
        "if(dz==='rewind'){seekBy(v,-dsec)}" +
        "else if(dz==='forward'){seekBy(v,dsec)}" +
        "else if(dz==='playpause'&&played===pl0){" +
        "if(v.paused){v.play().catch(function(){});notice(v,'播放')}" +
        "else{v.pause();notice(v,'暂停')}" +
        "}" +
        "}else if(window.__qhFsTaken){" +
        // 全屏接管：单击延迟 DBLMS 切换己方控制层显隐（窗口内第二击到达则取消，避免双击先闪面板）
        "v.__qhTapT=setTimeout(function(){if(window.__qhCtlTap){window.__qhCtlTap()}},DBLMS);" +
        "}" +
        "}" +
        "}" +
        "if(CFG.lpr!=='off'){" +
        "lpT=setTimeout(function(){" +
        "if(!mv()){" +
        "lpOn=true;" +
        "try{v.playbackRate=Number(CFG.lpr)}catch(e){}" +
        "notice(v,CFG.lpr+'x 倍速')" +
        "}" +
        "},LPMS)" +
        "}" +
        "document.addEventListener('touchmove',onMove,{passive:false,capture:true});" +
        "document.addEventListener('touchend',onEnd,true);" +
        "document.addEventListener('touchcancel',onEnd,true);" +
        "},true);" +
        // ---------- 键盘快捷键（键位查 CFG.KA 表，忽略 Ctrl/Alt/Meta 组合） ----------
        "if(CFG.kb){" +
        "document.addEventListener('keydown',function(e){" +
        "if(e.ctrlKey||e.altKey||e.metaKey){return}" +
        "var t=e.target;" +
        "if(t&&(t.tagName==='INPUT'||t.tagName==='TEXTAREA'||t.isContentEditable)){return}" +
        "var v=document.fullscreenElement?document.fullscreenElement.querySelector('video'):null;" +
        "if(!v){" +
        "var vs=document.querySelectorAll('video');" +
        "for(var i=0;i<vs.length;i++){" +
        "var el=vs[i];" +
        "if(el.clientWidth>50&&el.clientHeight>50&&isFinite(el.duration)&&el.duration>=30){v=el;break}" +
        "}" +
        "}" +
        "if(!v){return}" +
        // e.key → 归一化键名（与设置页存储表示一致）
        "var k=e.key;" +
        "if(k===' '){k='Space'}" +
        "else if(k==='ArrowLeft'){k='←'}" +
        "else if(k==='ArrowRight'){k='→'}" +
        "else if(k==='ArrowUp'){k='↑'}" +
        "else if(k==='ArrowDown'){k='↓'}" +
        "else if(k.length===1){k=k.toUpperCase()}" +
        "var act=CFG.KA[k];" +
        "if(!act){return}" +
        "var used=true;" +
        "try{" +
        "if(act==='play'){if(v.paused){v.play().catch(function(){})}else{v.pause()}}" +
        "else if(act==='back5'){seekBy(v,-5)}" +
        "else if(act==='fwd5'){seekBy(v,5)}" +
        "else if(act==='back10'){seekBy(v,-10)}" +
        "else if(act==='fwd10'){seekBy(v,10)}" +
        "else if(act==='volup'){v.muted=false;v.volume=c01(v.volume+0.1);notice(v,'音量 '+Math.round(v.volume*100)+'%')}" +
        "else if(act==='voldown'){v.volume=c01(v.volume-0.1);v.muted=(v.volume===0);notice(v,'音量 '+Math.round(v.volume*100)+'%')}" +
        "else if(act==='mute'){v.muted=!v.muted;notice(v,v.muted?'已静音':'已取消静音')}" +
        "else if(act==='fullscreen'){if(document.fullscreenElement){document.exitFullscreen()}else if(v.requestFullscreen){v.requestFullscreen()}}" +
        "else{used=false}" +
        "}catch(err){}" +
        "if(used){e.preventDefault();e.stopPropagation()}" +
        "},true)" +
        "}" +
        // ---------- 退出全屏恢复系统亮度 ----------
        "if(CFG.svL==='brightness'||CFG.svR==='brightness'){" +
        "document.addEventListener('fullscreenchange',function(){" +
        "if(!document.fullscreenElement){" +
        "window.__qhBr=null;" +
        "try{__qhNative.videoRequest('brightnessReset','')}catch(e){}" +
        "}" +
        "});" +
        "}" +
        "}" +
        // DOM 就绪后绑定（文档加载前注入时 DOM 尚未生成）
        "if(document.readyState==='loading'){" +
        "document.addEventListener('DOMContentLoaded',run)" +
        "}else{run()}" +
        "})()",
      scriptRules: ['*']
    }
  }

  /**
   * 全屏播放脚本（恒注入，与手势/快捷键设置无关）：
   * - window.__qhVideoCmd(cmd, arg) 命令入口（原生 runJavaScript 调）：
   *   fullscreen 找播放中视频（播放中优先、可见长视频兜底）→ 尺寸相仿祖先容器
   *   requestFullscreen（站点全屏布局兼容，YouTube 等容器全屏）；找不到经
   *   __qhNative.videoRequest('fsNotFound') 上报原生 toast 提示；
   *   exitFullscreen/play/pause/seek/seekBy/volume/mute/rate/pip/cast 播控命令
   * - 接管全屏进入（fullscreenchange 且己方标记，window.__qhFsTaken 置位）：
   *   注入 CSS 隐藏站点控制层（常见播放器控件栏 + video 原生控件），
   *   构建接管控制层（Web 内原生 UI：wrap/控制条 pointer-events:none 手势直达
   *   视频，.btn 控件真实点击——pip/cast 用户手势限制天然满足），
   *   绑定 play/pause/timeupdate(节流) 等监听，状态经 rep() 同步控制层并经
   *   videoRequest('state', json) 上报原生（TabInfo.video* 字段保留）
   * - 站点播放器退出我们的容器换自己的全屏根重进全屏（B 站等常见）：
   *   全屏退出事件不立即清理，800ms 宽限期内重进全屏保持接管（重绑状态上报）；
   *   sync 命令回填状态；（重）定位视频用全屏元素查找失败时回退播放中视频查找
   * - 退出全屏（宽限超时/显式退出）：移除隐藏 CSS、移除控制层、解除整页静音
   *   （pageMute '0'）、解绑监听、复位标记
   */
  static nativeControlScript(): ScriptItem {
    return {
      script: "(function(){" +
        "if(window.__qhVideoTakeover){return}" +
        "window.__qhVideoTakeover=true;" +
        "var TAKEN=false,SV=null,HIDE_ID='__qhFsHide',EXIT_T=null,GRACE=800;" +
        // 状态上报事件集（timeupdate 单独节流）
        "var EVS=['play','pause','ended','volumechange','ratechange','durationchange','seeked','progress'];" +
        "function fvideo(){" +
        // 播放中视频取面积最大者（多视频页面避免命中预览/画中画小窗）
        "var vs=document.querySelectorAll('video'),best=null,fallback=null,bA=0,fA=0;" +
        "for(var i=0;i<vs.length;i++){" +
        "var v=vs[i],a=v.clientWidth*v.clientHeight;" +
        "if(a<2500){continue}" +
        "var d=v.duration,ok=(!isFinite(d)||d>=10);" +
        "if(ok&&a>fA){fallback=v;fA=a}" +
        "if(!v.paused&&!v.ended&&ok&&a>bA){best=v;bA=a}" +
        "}" +
        "return best||fallback" +
        "}" +
        // 全屏目标：视频本身或尺寸相仿的祖先容器（容器全屏保留站点全屏布局）
        "function fsTarget(v){" +
        "var t=v,p=v.parentElement,vw=v.clientWidth,vh=v.clientHeight;" +
        "for(var i=0;i<8&&p&&p!==document.body;i++){" +
        "if(p.clientWidth<=vw*1.15&&p.clientHeight<=vh*1.15&&p.requestFullscreen){t=p}" +
        "p=p.parentElement" +
        "}" +
        "return t" +
        "}" +
        // 接管视频：全屏元素内查找（video 自身或容器内 video），失败回退播放中视频
        "function fsv(){" +
        "var fe=document.fullscreenElement;" +
        "if(!fe){return fvideo()}" +
        "var v=(fe.tagName==='VIDEO')?fe:fe.querySelector('video');" +
        "return v||fvideo()" +
        "}" +
        // 隐藏站点控制层（含中央播放/暂停大按钮；仅接管全屏期间挂载，退出即移除）
        "function hideCss(){" +
        "var s=document.getElementById(HIDE_ID);" +
        "if(!s){" +
        "s=document.createElement('style');s.id=HIDE_ID;" +
        "s.textContent=" +
        "'video::-webkit-media-controls{display:none!important}'+" +
        "'video::-webkit-media-controls-start-playback-button{display:none!important}'+" +
        "'.ytp-chrome-bottom,.ytp-gradient-bottom,.ytp-chrome-top,.ytp-autohide{display:none!important}'+" +
        "'.ytp-big-play-button,.ytp-bezel,.ytp-bezel-icon{display:none!important}'+" +
        "'.dplayer-controller,.dplayer-controller-mask,.dplayer-bezel{display:none!important}'+" +
        "'.xgplayer-controls,.xgplayer-top,.xgplayer-start,.xgplayer-replay{display:none!important}'+" +
        "'.vjs-control-bar,.video-js .vjs-control-bar,.vjs-big-play-button{display:none!important}'+" +
        "'.shaka-controls-container,.shaka-play-button{display:none!important}'+" +
        "'.plyr__controls,.plyr__control--overlaid{display:none!important}'+" +
        "'.jw-controlbar,.jw-display-icon-display{display:none!important}'+" +
        "'.prism-controlbar,.prism-big-play-btn{display:none!important}'+" +
        "'.control-bar,.controls-bar,#controlbar,[class*=\"big-play\"]{display:none!important}';" +
        "}" +
        "if(!s.parentElement){document.documentElement.appendChild(s)}" +
        "}" +
        "function removeHide(){" +
        "var s=document.getElementById(HIDE_ID);" +
        "if(s&&s.parentElement){s.parentElement.removeChild(s)}" +
        "}" +
        "function stateJson(v){" +
        "var d=v.duration;" +
        // pip/cast：Web 标准画中画与 Remote Playback 投屏能力（内核自适应，原生按此显隐按钮）
        "return JSON.stringify({p:v.currentTime,d:isFinite(d)?d:0,pl:!v.paused&&!v.ended," +
        "vo:v.volume,mu:v.muted,r:v.playbackRate," +
        "pip:(document.pictureInPictureEnabled&&typeof v.requestPictureInPicture==='function')?1:0," +
        "cast:(v.remote&&typeof v.remote.prompt==='function')?1:0," +
        "b:(v.buffered.length>0?v.buffered.end(v.buffered.length-1):0)})" +
        "}" +
        "function rep(){" +
        "if(!SV){return}" +
        // 同步刷新 Web 内控制层（进度/图标/能力显隐；timeupdate 节流 400ms 驱动）
        "try{upCtl(SV)}catch(e){}" +
        "try{__qhNative.videoRequest('state',stateJson(SV))}catch(e){}" +
        "}" +
        // 诊断日志经原生桥转发（网页 console 不进 hilog）
        "function qlog(m){" +
        "try{__qhNative.videoRequest('log',m)}catch(e){}" +
        "}" +
        // Web PiP 进入/离开事件（成功确认 + 状态同步；rep 联动原生按钮态）
        "var PEV=function(){qlog('pip enter evt');rep()};" +
        "var PLV=function(){qlog('pip leave evt');rep()};" +
        // ===== 全屏控制层（Web 内原生 UI：与视频同 DOM 无图层冲突，点击天然真实
        // 手势——pip/cast 的 W3C 用户手势限制天然满足；wrap/控制条 pointer-events:
        // none 手势直达视频（controlScript 全局手势接管），控件 .btn 响应点击）=====
        "var CTL_ID='__qhCtlWrap',CTL_CSS='__qhCtlCss';" +
        "var PHIDE=false,CHIDE=false,PMUTE=false,HIDE_T=null,CTL_ON=true,PROG_DRAG=false,RATE_ON=false;" +
        "var CTLE={};"
 +
        "var RATES=[0.5,0.75,1,1.25,1.5,2,3];" +
        // 图标（HMSymbolVF 字形提取 SVG path，与系统 SymbolGlyph 同源同观感，
        // 尺寸对齐旧原生面板：chevron_left 28 / play·pause 24 / speaker_wave_2·
        // speaker_slash·smal_window_playback·airplayaudio 22 / checkmark 16）
        "var IC={" +
        "back:'<svg width=\"28\" height=\"28\" viewBox=\"0 0 1000 1000\"><path d=\"M384 750Q393 741 393 728Q393 715 384 706L174 495L383 283L385 281Q392 271 391.5 259Q391 247 383 239Q374 230 361 230Q348 230 339 239L119 463Q106 475 106 495Q106 511 115 523L119 527L339 750Q348 760 360 760Q372 760 384 750\" fill=\"#fff\"/></svg>'," +
        "play:'<svg width=\"24\" height=\"24\" viewBox=\"0 0 1000 1000\"><path d=\"M295 105Q267 90 238 90Q193 90 159.5 122.5Q126 155 126 203L126 797Q126 845 159.5 877Q193 909 238 909Q269 909 295 894L822 590Q856 571 868 535.5Q880 500 868 464.5Q856 429 822 410L295 105M263 840Q252 847 238 847Q219 847 203.5 833Q188 819 188 797L188 203Q188 181 203.5 167Q219 153 238 153Q251 153 263 159L790 463Q811 475 811 500Q811 524 790 536\" fill=\"#fff\"/></svg>'," +
        "pause:'<svg width=\"24\" height=\"24\" viewBox=\"0 0 1000 1000\"><path d=\"M688 146Q662 146 643.5 164Q625 182 625 208L625 792Q625 818 643.5 836Q662 854 688 854Q714 854 732 835.5Q750 817 750 792L750 208Q750 182 732 164Q714 146 688 146M313 146Q287 146 268.5 164Q250 182 250 208L250 792Q250 818 268.5 836Q287 854 313 854Q339 854 357 835.5Q375 817 375 792L375 208Q375 182 357 164Q339 146 313 146\" fill=\"#fff\"/></svg>'," +
        "vol:'<svg width=\"22\" height=\"22\" viewBox=\"0 0 1000 1000\"><path d=\"M675 378Q661 364 644.5 369.5Q628 375 622.5 391Q617 407 631 422Q662 456 662 499Q662 521 654 541Q646 561 630 577Q616 591 621.5 607.5Q627 624 643.5 629.5Q660 635 674 621Q698 596 711 564.5Q724 533 724 499Q724 465 711 433.5Q698 402 675 378M793 265Q780 251 763.5 256.5Q747 262 741 278.5Q735 295 749 308Q786 345 806.5 394.5Q827 444 827 497Q827 551 807 600Q787 649 750 686Q737 699 742.5 716Q748 733 764 738.5Q780 744 794 730Q840 684 865 624Q890 564 890 498Q890 431 865 371Q840 311 793 265M443 767Q465 783 489.5 780.5Q514 778 531 760Q548 742 548 717L548 283Q548 257 530.5 239Q513 221 488 219Q463 217 443 233L300 350L191 350Q157 350 133.5 373.5Q110 397 110 431L110 568Q110 602 133.5 626Q157 650 191 650L300 650L443 767M191 412L322 412L485 283L482 718L322 588L191 588Q183 588 177.5 582Q172 576 172 568L172 431Q172 423 178 417.5Q184 412 191 412\" fill=\"#fff\"/></svg>'," +
        "volx:'<svg width=\"22\" height=\"22\" viewBox=\"0 0 1000 1000\"><path d=\"M671 808Q671 817 668.5 822Q666 827 661 827Q656 827 648 820L428 643L251 643Q235 643 224 632Q213 621 213 605L213 395Q213 383 219.5 373.5Q226 364 237 359L192 314Q172 328 161 349Q150 370 150 395L150 605Q150 632 163.5 655Q177 678 200.5 691.5Q224 705 251 705L406 705L609 868Q625 881 647.5 884Q670 887 690 878Q712 868 725 845L671 792L671 808M872 916Q881 925 894 925Q907 925 916 916Q925 907 925 894Q925 881 916 872L128 84Q119 75 106 75Q93 75 84 84Q75 93 75 106Q75 119 84 128L872 916M734 191Q734 169 722 150.5Q710 132 690 122Q669 112 647.5 115Q626 118 609 132L413 290L457 334L648 180Q656 173 661 172.5Q666 172 668.5 176.5Q671 181 671 191L671 547L734 610\" fill=\"#fff\"/></svg>'," +
        "pip:'<svg width=\"22\" height=\"22\" viewBox=\"0 0 1000 1000\"><path d=\"M217 677Q178 677 150.5 649.5Q123 622 123 583L123 290Q123 252 150.5 224Q178 196 217 196L717 196Q756 196 783 223.5Q810 251 810 290L810 458Q810 471 819.5 480.5Q829 490 842 490Q855 490 864 480.5Q873 471 873 458L873 290Q873 248 852 212Q831 176 795 155Q759 134 717 134L217 134Q175 134 139 155Q103 176 82 212Q61 248 61 290L61 583Q61 626 82 662Q103 698 139 719Q175 740 217 740L413 740Q426 740 435.5 730.5Q445 721 445 708Q445 695 435.5 686Q426 677 413 677L217 677M594 550Q564 550 542.5 571.5Q521 593 521 623L521 793Q521 822 542.5 843.5Q564 865 594 865L866 865Q896 865 917.5 843.5Q939 822 939 793L939 623Q939 593 917.5 571.5Q896 550 866 550L594 550M877 793Q877 797 873.5 800Q870 803 866 803L594 803Q590 803 586.5 800Q583 797 583 793L583 623Q583 619 586 616Q589 613 594 613L866 613Q871 613 874 616Q877 619 877 623L877 793M431 287Q418 287 409 296Q400 305 400 318L400 427L265 292Q256 283 243 283Q230 283 221 292Q212 301 212 314Q212 327 221 336L355 470L248 470Q235 470 226 479Q217 488 217 501Q217 514 226 523Q235 532 248 532L418 532Q436 532 449 519.5Q462 507 462 489L462 318Q462 305 453 296Q444 287 431 287\" fill=\"#fff\"/></svg>'," +
        "cast:'<svg width=\"22\" height=\"22\" viewBox=\"0 0 1000 1000\"><path d=\"M811 806Q826 806 834 795Q889 733 918 656.5Q947 580 947 498Q947 377 886.5 274.5Q826 172 723.5 111.5Q621 51 500 51Q379 51 276 111.5Q173 172 112.5 274.5Q52 377 52 498Q52 580 81.5 656.5Q111 733 165 795Q174 805 187 806Q200 807 210 798Q220 789 220 776.5Q220 764 212 754Q165 700 140 634.5Q115 569 115 498Q115 394 166.5 305.5Q218 217 306.5 165Q395 113 500 113Q604 113 692.5 165Q781 217 833 305.5Q885 394 885 498Q885 569 859.5 635Q834 701 787 754Q779 764 779.5 776.5Q780 789 790 798Q800 806 811 806M690 690Q703 690 714 679Q746 642 763 595Q780 548 780 497Q780 421 742 356.5Q704 292 639.5 254Q575 216 499 216Q423 216 358.5 254Q294 292 256 356.5Q218 421 218 497Q218 547 235.5 594Q253 641 285 679Q293 689 305.5 690Q318 691 329 683Q339 675 340 662Q341 649 333 639Q308 610 294.5 573Q281 536 281 497Q281 438 310.5 388Q340 338 390.5 308.5Q441 279 500 279Q559 279 609 308.5Q659 338 688.5 388Q718 438 718 497Q718 536 705 572.5Q692 609 667 639Q659 649 659.5 662Q660 675 670 683Q678 690 690 690M554 577Q577 563 591 539.5Q605 516 605 488Q605 444 574.5 413.5Q544 383 500 383Q457 383 426 414Q395 445 395 488Q395 516 409 539.5Q423 563 446 577L352 910Q347 924 357 937Q361 943 367.5 946.5Q374 950 382 950L619 950Q634 950 644 937Q653 925 648 910L554 577M500 446Q517 446 529.5 458.5Q542 471 542 488Q542 506 529.5 518Q517 530 500 530Q482 530 469.5 517.5Q457 505 457 488Q457 471 469.5 458.5Q482 446 500 446M423 887L500 616L577 887\" fill=\"#fff\"/></svg>'," +
        "check:'<svg width=\"16\" height=\"16\" viewBox=\"0 0 1000 1000\"><path d=\"M396 758Q413 758 429 751.5Q445 745 457 733L897 295Q906 286 906 273Q906 260 897 251Q888 241 875 241Q862 241 852 251L412 689Q405 696 396 696Q387 696 380 689L147 458Q138 448 125 448.5Q112 449 103 458Q93 467 93 480Q93 493 103 502L336 733Q348 745 363.5 751.5Q379 758 396 758\" fill=\"#fff\"/></svg>'" +
        "};" +
        "function ftime(s){" +
        "if(!isFinite(s)||s<0){s=0}" +
        "s=Math.round(s);" +
        "var h=Math.floor(s/3600),m=Math.floor((s%3600)/60),r=s%60;" +
        "var p=function(n){return (n<10?'0':'')+n};" +
        "return (h>0?h+':'+p(m):m)+':'+p(r)" +
        "}" +
        "function mkdiv(cls,css){" +
        "var d=document.createElement('div');" +
        "if(cls){d.className=cls}" +
        "if(css){d.style.cssText=css}" +
        "return d" +
        "}" +
        "function removeCtl(){" +
        "var w=document.getElementById(CTL_ID);" +
        "if(w&&w.parentElement){w.parentElement.removeChild(w)}" +
        "var cs=document.getElementById(CTL_CSS);" +
        "if(cs&&cs.parentElement){cs.parentElement.removeChild(cs)}" +
        "CTLE={};clearTimeout(HIDE_T);HIDE_T=null;CTL_ON=true;RATE_ON=false;PROG_DRAG=false" +
        "}" +
        "function showCtl(){" +
        "if(CTLE.top){CTLE.top.classList.remove('hid')}" +
        "if(CTLE.bot){CTLE.bot.classList.remove('hid')}" +
        "CTL_ON=true;scheduleHide()" +
        "}" +
        "function hideCtl(){" +
        "if(CTLE.top){CTLE.top.classList.add('hid')}" +
        "if(CTLE.bot){CTLE.bot.classList.add('hid')}" +
        "CTL_ON=false;RATE_ON=false;" +
        "if(CTLE.menu){CTLE.menu.style.display='none'}" +
        "clearTimeout(HIDE_T);HIDE_T=null" +
        "}" +
        "function scheduleHide(){" +
        "clearTimeout(HIDE_T);HIDE_T=null;" +
        "if(!SV||SV.paused){return}" +
        "HIDE_T=setTimeout(hideCtl,5000)" +
        "}" +
        "window.__qhCtlTap=function(){" +
        "if(CTL_ON){hideCtl()}else{showCtl()}" +
        "};" +
        // 接管期音量（controlScript 纵滑调）：0.001 钳制防看门狗回写 + 整页静音联动
        "window.__qhVol=function(k){" +
        "if(!SV){return}" +
        "k=Number(k);if(isNaN(k)){return}" +
        "k=Math.min(1,Math.max(0,k));" +
        "if(k>0&&PMUTE){PMUTE=false;try{__qhNative.videoRequest('pageMute','0')}catch(e){}}" +
        "if(k<=0&&!PMUTE){PMUTE=true;try{__qhNative.videoRequest('pageMute','1')}catch(e){}}" +
        "VOLAT=Date.now();" +
        "var tgt=(k<=0)?0.001:k;" +
        "var ap=[];" +
        "eachMedia(SV,function(el){el.volume=tgt;ap.push(el.tagName)});" +
        "vlog(ap,tgt,(k<=0))" +
        "};" +
        "function railRatio(e){" +
        "var t=e.touches[0]||e.changedTouches[0];" +
        "if(!t||!CTLE.track){return 0}" +
        "var r=CTLE.track.getBoundingClientRect();" +
        "if(r.width<=0){return 0}" +
        "return Math.min(1,Math.max(0,(t.clientX-r.left)/r.width))" +
        "}" +
        "function setProgPreview(v,k){" +
        "var E=CTLE;" +
        "var p=(k*100)+'%';" +
        "E.inn.style.width=p;E.knob.style.left=p;" +
        "E.tc.textContent=ftime(k*(v.duration||0))" +
        "}" +
        "function renderRate(v){" +
        "var E=CTLE;" +
        "if(!E.menu){return}" +
        "E.menu.innerHTML='';" +
        "for(var i=0;i<RATES.length;i++){" +
        "(function(r){" +
        // 菜单项对齐系统 Menu（旧原生面板 RateMenuBuilder 同构）：选中项前置 checkmark 符号
        "var sel=Math.abs(v.playbackRate-r)<0.01;" +
        "var it=mkdiv('','display:-webkit-flex;-webkit-align-items:center;padding:9px 14px 9px 12px;font-size:14px;');" +
        "var ck=mkdiv('','width:20px;height:16px;display:-webkit-flex;-webkit-align-items:center;-webkit-justify-content:center;margin-right:6px;');" +
        "if(sel){ck.innerHTML=IC.check}" +
        "it.appendChild(ck);" +
        "it.appendChild(document.createTextNode(r+'X'));" +
        "it.onclick=function(e){" +
        "e.stopPropagation();" +
        "try{v.playbackRate=r}catch(e2){}" +
        "RATE_ON=false;E.menu.style.display='none';upCtl(v);scheduleHide()" +
        "};" +
        "E.menu.appendChild(it)" +
        "})(RATES[i])" +
        "}" +
        "}" +
        "function bindCtl(v){" +
        "var E=CTLE;" +
        "E.play.onclick=function(e){" +
        "e.stopPropagation();" +
        "if(v.paused){v.play().catch(function(){})}else{v.pause()}" +
        "upCtl(v);scheduleHide()" +
        "};" +
        // 静音：整页静音经原生桥（WebviewController.setAudioMuted，站点不可回写）
        "E.mute.onclick=function(e){" +
        "e.stopPropagation();" +
        "PMUTE=!PMUTE;" +
        "try{__qhNative.videoRequest('pageMute',PMUTE?'1':'0')}catch(e2){}" +
        "qlog('ctl pageMute '+PMUTE);" +
        "upCtl(v);scheduleHide()" +
        "};" +
        "E.pip.onclick=function(e){" +
        "e.stopPropagation();" +
        "if(document.pictureInPictureElement){try{var ep0=document.exitPictureInPicture();if(ep0&&ep0.catch){ep0.catch(function(e2){qlog('pip exit fail '+e2)})}}catch(e0){}return}" +
        "try{" +
        "var pr=v.requestPictureInPicture();" +
        "if(pr&&pr.then){" +
        "pr.then(function(){qlog('pip entered');rep()}).catch(function(err){qlog('pip fail '+err);PHIDE=true;E.pip.style.display='none';try{__qhNative.videoRequest('pipFail',String(err))}catch(e3){}})" +
        "}" +
        "}catch(e0){qlog('pip err '+e0);PHIDE=true;E.pip.style.display='none';try{__qhNative.videoRequest('pipFail',String(e0))}catch(e3){}}" +
        "};" +
        "E.cast.onclick=function(e){" +
        "e.stopPropagation();" +
        "try{" +
        "var pr2=v.remote.prompt();" +
        "if(pr2&&pr2.then){" +
        "pr2.then(function(){qlog('cast resolved')}).catch(function(err){qlog('cast fail '+err);CHIDE=true;E.cast.style.display='none';try{__qhNative.videoRequest('castFail',String(err))}catch(e3){}})" +
        "}" +
        "}catch(e0){qlog('cast err '+e0);CHIDE=true;E.cast.style.display='none';try{__qhNative.videoRequest('castFail',String(e0))}catch(e3){}}" +
        "};" +
        "E.rate.onclick=function(e){" +
        "e.stopPropagation();" +
        "RATE_ON=!RATE_ON;" +
        "if(RATE_ON){renderRate(v)}" +
        "E.menu.style.display=RATE_ON?'block':'none';" +
        "scheduleHide()" +
        "};" +
        // 进度拖动：拖中实时预览（不 seek），松手生效
        "var dragR=-1;" +
        "E.track.addEventListener('touchstart',function(e){e.stopPropagation();PROG_DRAG=true;dragR=railRatio(e);setProgPreview(v,dragR);clearTimeout(HIDE_T);HIDE_T=null});" +
        "E.track.addEventListener('touchmove',function(e){e.stopPropagation();e.preventDefault();dragR=railRatio(e);setProgPreview(v,dragR)});" +
        "E.track.addEventListener('touchend',function(e){" +
        "e.stopPropagation();PROG_DRAG=false;" +
        "if(dragR>=0&&isFinite(v.duration)){v.currentTime=dragR*v.duration}" +
        "dragR=-1;upCtl(v);scheduleHide()" +
        "});" +
        "E.track.addEventListener('touchcancel',function(){PROG_DRAG=false;dragR=-1;upCtl(v);scheduleHide()});" +
        "}" +
        "function upCtl(v){" +
        "var E=CTLE;" +
        "if(!E.play){return}" +
        "var live=!isFinite(v.duration)||v.duration<=0;" +
        "E.play.innerHTML=v.paused?IC.play:IC.pause;" +
        "E.mute.innerHTML=(PMUTE||v.muted||v.volume<=0.001)?IC.volx:IC.vol;" +
        "E.rate.textContent=(Math.round(v.playbackRate*100)/100)+'X';" +
        "E.title.textContent=document.title||'';" +
        "var ps=!PHIDE&&document.pictureInPictureEnabled&&typeof v.requestPictureInPicture==='function';" +
        "E.pip.style.display=ps?'-webkit-flex':'none';" +
        "var cs2=!CHIDE&&v.remote&&typeof v.remote.prompt==='function';" +
        "E.cast.style.display=cs2?'-webkit-flex':'none';" +
        "if(live){" +
        "E.bar.style.display='none';" +
        "E.live.style.display='-webkit-flex'" +
        "}else{" +
        "E.bar.style.display='-webkit-flex';" +
        "E.live.style.display='none';" +
        "if(!PROG_DRAG){" +
        "var d=v.duration||0;" +
        "var k=d>0?Math.min(1,v.currentTime/d):0;" +
        "var p=(k*100)+'%';" +
        "E.inn.style.width=p;E.knob.style.left=p;" +
        "E.tc.textContent=ftime(v.currentTime);" +
        "E.td.textContent=ftime(d);" +
        "var b=(v.buffered.length>0?v.buffered.end(v.buffered.length-1):0);" +
        "E.buf.style.width=(d>0?Math.min(100,b/d*100):0)+'%'" +
        "}" +
        "}" +
        "}" +
        "function buildCtl(v){" +
        "removeCtl();" +
        "var host=document.fullscreenElement||document.body;" +
        "if(!host){return}" +
        "var cs=document.createElement('style');" +
        "cs.id=CTL_CSS;" +
        "cs.textContent='.__qhctl{position:fixed;left:0;right:0;z-index:2147483646;pointer-events:none;color:#fff;font:14px/1.4 sans-serif;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;transition:opacity .18s}.__qhctl.hid{opacity:0}.__qhctl .btn{pointer-events:auto;display:-webkit-flex;-webkit-align-items:center;-webkit-justify-content:center;min-width:40px;height:40px}';" +
        "document.documentElement.appendChild(cs);" +
        "var w=document.createElement('div');" +
        "w.id=CTL_ID;" +
        // 上控制栏：退出 + 标题（视觉规格对齐旧原生面板：padding 16/12 + 三段渐变，
        // chevron_left 图标视觉左距 20 = 盒 ml14 + (40-28)/2）
        "var top=mkdiv('__qhctl','top:0;padding:16px 0 12px;background:linear-gradient(180deg,#000 0%,rgba(0,0,0,.5) 50%,rgba(0,0,0,0) 100%);display:-webkit-flex;-webkit-align-items:center;');" +
        "var back=mkdiv('btn','margin-left:14px;');" +
        "back.innerHTML=IC.back;" +
        "back.onclick=function(e){" +
        "e.stopPropagation();qlog('ctl exit tap');" +
        "try{__qhNative.videoRequest('exitFs','')}catch(e2){}" +
        "};" +
        "var title=mkdiv('','font-size:14px;font-weight:500;max-width:72%;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;margin-left:6px;');" +
        "title.textContent=document.title||'';" +
        "top.appendChild(back);top.appendChild(title);" +
        // 下控制栏：直播标识 / 进度行 / 控件行 / 倍速菜单（padding 10/10 + 三段渐变）
        "var bot=mkdiv('__qhctl','bottom:0;padding:10px 0 10px;background:linear-gradient(0deg,#000 0%,rgba(0,0,0,.5) 50%,rgba(0,0,0,0) 100%);');" +
        "var live=mkdiv('','display:none;-webkit-align-items:center;padding:6px 0 0;');" +
        "var lvTag=mkdiv('','font-size:12px;color:rgba(255,255,255,.85);background:rgba(255,255,255,.2);padding:2px 8px;border-radius:4px;margin-left:12px;');" +
        "lvTag.textContent='直播';" +
        "live.appendChild(lvTag);" +
        // 进度行：OutSet 风格滑轨（2px 无圆角 40% 白轨 + 白块 12px，时间码 12px 贴边 12/6）
        "var bar=mkdiv('','display:-webkit-flex;-webkit-align-items:center;padding:0;');" +
        "var tc=mkdiv('','font-size:12px;margin:0 6px 0 12px;');" +
        "var track=mkdiv('','pointer-events:auto;position:relative;-webkit-flex:1;height:30px;display:-webkit-flex;-webkit-align-items:center;');" +
        "var rail=mkdiv('','position:relative;width:100%;height:2px;background:rgba(255,255,255,.4);');" +
        "var buf=mkdiv('','position:absolute;left:0;top:0;bottom:0;width:0;background:rgba(255,255,255,.5);');" +
        "var inn=mkdiv('','position:absolute;left:0;top:0;bottom:0;width:0;background:#fff;');" +
        "var knob=mkdiv('','position:absolute;top:50%;width:12px;height:12px;border-radius:6px;background:#fff;-webkit-transform:translate(-50%,-50%);left:0;');" +
        "rail.appendChild(buf);rail.appendChild(inn);rail.appendChild(knob);track.appendChild(rail);" +
        "var td=mkdiv('','font-size:12px;margin:0 12px 0 6px;');" +
        "bar.appendChild(tc);bar.appendChild(track);bar.appendChild(td);" +
        // 控件行：play ml8 / pip·cast·mute mr9（盒边距+图标半隙=视觉 16/18），rate 文字钮 12px 白描边
        "var row=mkdiv('','display:-webkit-flex;-webkit-align-items:center;margin-top:6px;padding:0;');" +
        "var play=mkdiv('btn','margin-left:8px;');" +
        "var sp=mkdiv('','-webkit-flex:1;');" +
        "var pip=mkdiv('btn','margin-right:9px;');" +
        "pip.innerHTML=IC.pip;" +
        "var cast=mkdiv('btn','margin-right:9px;');" +
        "cast.innerHTML=IC.cast;" +
        "var mute=mkdiv('btn','margin-right:9px;');" +
        "var rate=mkdiv('btn','font-size:12px;min-width:44px;height:auto;padding:4px 8px;border:1px solid #fff;border-radius:4px;margin-right:16px;');" +
        "row.appendChild(play);row.appendChild(sp);row.appendChild(pip);row.appendChild(cast);row.appendChild(mute);row.appendChild(rate);" +
        "var menu=mkdiv('','pointer-events:auto;position:absolute;right:12px;bottom:100%;margin-bottom:8px;background:rgba(30,30,30,.95);border-radius:16px;padding:8px 0;display:none;min-width:96px;');" +
        "bot.appendChild(live);bot.appendChild(bar);bot.appendChild(row);bot.appendChild(menu);" +
        "w.appendChild(top);w.appendChild(bot);" +
        "host.appendChild(w);" +
        "CTLE={top:top,bot:bot,title:title,live:live,bar:bar,tc:tc,td:td,track:track,inn:inn,buf:buf,knob:knob,play:play,pip:pip,cast:cast,mute:mute,rate:rate,menu:menu};" +
        "bindCtl(v);" +
        "upCtl(v);" +
        "showCtl();" +
        "qlog('ctl built host='+host.tagName)" +
        "}" +
        // 音量变化监听（站点看门狗回写检测）：己方命令后 100ms 内的变化抑制（松手后的外部回写必现形）
        "var VOLAT=0;" +
        "function onVol(){" +
        "if(!SV){return}" +
        "var n=Date.now();if(n-VOLAT<100){return}" +
        "qlog('vchange vol='+SV.volume+' muted='+SV.muted)" +
        "}" +
        // 音量/静音广播目标：目标视频 + 全部播放中媒体元素（音视频分元素站点：video 播画面、独立 audio 出声）
        "function eachMedia(v,fn){" +
        "var ms=document.querySelectorAll('video,audio');" +
        "for(var i=0;i<ms.length;i++){" +
        "var el=ms[i];" +
        "if(el===v||(!el.paused&&!el.ended)){fn(el)}" +
        "}" +
        "}" +
        // 广播结果日志节流（滑动中 300ms 一条）
        "var VLT=0;" +
        "function vlog(ap,k,m){" +
        "var n=Date.now();if(n-VLT<300){return}" +
        "VLT=n;" +
        "qlog('vols k='+k+' muted='+m+' -> '+ap.join(','))" +
        "}" +
        "function attach(v){" +
        "detach();" +
        "SV=v;" +
        "for(var i=0;i<EVS.length;i++){v.addEventListener(EVS[i],rep)}" +
        "v.addEventListener('volumechange',onVol);" +
        "v.addEventListener('enterpictureinpicture',PEV);" +
        "v.addEventListener('leavepictureinpicture',PLV);" +
        "var last=0;" +
        "v.__qhTu=function(){var n=Date.now();if(n-last>400){last=n;rep()}};" +
        "v.addEventListener('timeupdate',v.__qhTu);" +
        "buildCtl(v);" +
        // 接管标记：controlScript（独立注入）据此垄断站点手势/切换单击语义/音量走 __qhVol
        "window.__qhFsTaken=true;" +
        "rep();" +
        "qlog('attach src='+String(v.currentSrc||'').slice(0,120)+' size='+v.clientWidth+'x'+v.clientHeight+' vol='+v.volume+' muted='+v.muted);" +
        // 媒体普查：页面全部媒体元素（标签+音量+静音/播放态），音视频分元素诊断
        "var ms=document.querySelectorAll('video,audio'),inf=[];" +
        "for(var i=0;i<ms.length&&inf.length<8;i++){" +
        "var el=ms[i];" +
        "if(el.currentSrc||el.src){" +
        "inf.push(el.tagName+'v'+Math.round(el.volume*100)+(el.muted?'M':'')+((!el.paused&&!el.ended)?'P':'-'))" +
        "}" +
        "}" +
        "qlog('media census '+inf.join(' '))" +
        "}" +
        "function detach(){" +
        "if(!SV){return}" +
        "try{" +
        "for(var i=0;i<EVS.length;i++){SV.removeEventListener(EVS[i],rep)}" +
        "SV.removeEventListener('volumechange',onVol);" +
        "SV.removeEventListener('enterpictureinpicture',PEV);" +
        "SV.removeEventListener('leavepictureinpicture',PLV);" +
        "if(SV.__qhTu){SV.removeEventListener('timeupdate',SV.__qhTu);SV.__qhTu=null}" +
        "}catch(e){}" +
        "SV=null" +
        "}" +
        "function cleanup(){" +
        "removeHide();" +
        "detach();" +
        "removeCtl();" +
        // 退出接管：解除整页静音（原生侧叠加标签自身静音态），清接管标记
        "if(PMUTE){PMUTE=false;try{__qhNative.videoRequest('pageMute','0')}catch(e){}}" +
        "window.__qhFsTaken=false;" +
        "TAKEN=false" +
        "}" +
        "document.addEventListener('fullscreenchange',function(){" +
        "var fe=document.fullscreenElement;" +
        "qlog('fschange fe='+(fe?String(fe.tagName):'null')+' taken='+TAKEN);" +
        "if(EXIT_T){clearTimeout(EXIT_T);EXIT_T=null}" +
        "if(fe&&TAKEN){" +
        // 接管全屏进入/换容器重进：隐藏站点控件并（重）绑定状态上报
        "hideCss();" +
        "var v=fsv();" +
        "if(v){attach(v)}" +
        "}else if(!fe&&TAKEN){" +
        // 站点播放器可能退出当前容器换自己的全屏根重进（B 站等）：
        // 宽限期内重进保持接管，超时才真正清理
        "EXIT_T=setTimeout(function(){" +
        "EXIT_T=null;" +
        "if(TAKEN&&!document.fullscreenElement){cleanup()}" +
        "},GRACE)" +
        "}" +
        "});" +
        "window.__qhVideoCmd=function(cmd,arg){" +
        "arg=arg||'';" +
        "if(cmd==='fullscreen'){" +
        "if(document.fullscreenElement){" +
        // 已在全屏中（站点先行全屏/换容器后）：原地接管现有全屏
        "TAKEN=true;" +
        "hideCss();" +
        "var v0=fsv();" +
        "if(v0){attach(v0)}" +
        "return 'ok'" +
        "}" +
        "var f=fvideo();" +
        "if(!f){try{__qhNative.videoRequest('fsNotFound','')}catch(e){}return 'none'}" +
        "var t=fsTarget(f);" +
        "TAKEN=true;" +
        "try{" +
        "var pr=t.requestFullscreen();" +
        "if(pr&&pr.catch){pr.catch(function(){if(TAKEN){TAKEN=false;try{__qhNative.videoRequest('fsNotFound','')}catch(e){}}})}" +
        "}catch(err){" +
        "TAKEN=false;" +
        "try{__qhNative.videoRequest('fsNotFound','')}catch(e){}" +
        "return 'none'" +
        "}" +
        "return 'ok'" +
        "}" +
        "if(cmd==='sync'){" +
        // 原生控制层挂载回填：（重）定位全屏视频并上报当前状态
        "qlog('sync fe='+(document.fullscreenElement?'1':'0'));" +
        "if(document.fullscreenElement){hideCss()}" +
        "var sy=fsv();" +
        "if(sy){attach(sy)}" +
        "return 'ok'" +
        "}" +
        "if(cmd==='exitFullscreen'){" +
        "if(EXIT_T){clearTimeout(EXIT_T);EXIT_T=null}" +
        "cleanup();" +
        "if(document.exitFullscreen){document.exitFullscreen()}" +
        "return 'ok'" +
        "}" +
        "var v=fsv();" +
        "if(!v){return 'none'}" +
        "if(cmd==='togglePlay'){if(v.paused){v.play().catch(function(){})}else{v.pause()}return 'ok'}" +
        "if(cmd==='play'){v.play().catch(function(){});return 'ok'}" +
        "if(cmd==='pause'){v.pause();return 'ok'}" +
        "if(cmd==='seek'){var s=Number(arg);if(!isNaN(s)&&isFinite(v.duration)){v.currentTime=Math.min(Math.max(0,s),v.duration)}return 'ok'}" +
        "if(cmd==='seekBy'){var d=Number(arg);if(!isNaN(d)&&isFinite(v.duration)){v.currentTime=Math.min(Math.max(0,v.currentTime+d),v.duration)}return 'ok'}" +
        "if(cmd==='volume'){" +
        "var k=Number(arg);" +
        "if(!isNaN(k)){" +
        "k=Math.min(1,Math.max(0,k));" +
        "VOLAT=Date.now();" +
        // 站点看门狗对 volume=0/muted=true 瞬间回写音量 1（实测 hembed）：钳到 0.001（-60dB
        // 听感静音）且绝不设 muted，规避回写触发条件；真静音由原生整页静音兜底
        "var tgt=(k<=0)?0.001:k;" +
        "var ap=[];" +
        "eachMedia(v,function(el){el.volume=tgt;ap.push(el.tagName)});" +
        "vlog(ap,tgt,(k<=0))" +
        "}" +
        "return 'ok'" +
        "}" +
        "if(cmd==='mute'){" +
        "var m=arg==='1';" +
        "VOLAT=Date.now();" +
        "var am=[];" +
        "eachMedia(v,function(el){el.muted=m;if(!m&&el.volume===0){el.volume=0.5}am.push(el.tagName)});" +
        "qlog('mute '+m+' -> '+am.join(','));" +
        "return 'ok'" +
        "}" +
        "if(cmd==='rate'){var r=Number(arg);if(!isNaN(r)&&r>0){v.playbackRate=r}return 'ok'}" +
        // Web 标准画中画（HTMLVideoElement.requestPictureInPicture，内核支持时原生按钮可见）；
        // 失败（无手势/编码不支持/MSE）异步经 pipFail 上报原生 toast 并隐藏按钮
        "if(cmd==='pip'){" +
        "if(document.pictureInPictureElement){" +
        "try{var ep=document.exitPictureInPicture();if(ep&&ep.catch){ep.catch(function(e2){qlog('pip exit fail '+e2)})}qlog('pip exit req');return 'ok'}" +
        "catch(e2){qlog('pip exit err '+e2);return 'err'}" +
        "}" +
        "if(document.pictureInPictureEnabled&&typeof v.requestPictureInPicture==='function'){" +
        "try{" +
        "var pp=v.requestPictureInPicture();" +
        "if(pp&&pp.then){" +
        "pp.then(function(){qlog('pip entered');rep()}).catch(function(err){qlog('pip fail '+err);try{__qhNative.videoRequest('pipFail',String(err))}catch(e3){}})" +
        "}else{qlog('pip no promise')}" +
        "qlog('pip req');" +
        "return 'ok'" +
        "}catch(e){qlog('pip err '+e);return 'err'}" +
        "}" +
        "qlog('pip unsupported');" +
        "return 'unsupported'" +
        "}" +
        // Web 标准 Remote Playback 投屏（HTMLMediaElement.remote.prompt）；
        // 失败异步经 castFail 上报原生 toast 并隐藏按钮
        "if(cmd==='cast'){" +
        "if(v.remote&&typeof v.remote.prompt==='function'){" +
        "try{" +
        "var pr2=v.remote.prompt();" +
        "if(pr2&&pr2.then){" +
        "pr2.then(function(){qlog('cast resolved')}).catch(function(err){qlog('cast fail '+err);try{__qhNative.videoRequest('castFail',String(err))}catch(e3){}})" +
        "}else{qlog('cast no promise')}" +
        "qlog('cast req');" +
        "return 'ok'" +
        "}catch(e){qlog('cast err '+e);return 'err'}" +
        "}" +
        "qlog('cast unsupported');" +
        "return 'unsupported'" +
        "}" +
        "if(cmd==='query'){return stateJson(v)}" +
        "return 'none'" +
        "};" +
        "})()",
      scriptRules: ['*']
    }
  }
}
