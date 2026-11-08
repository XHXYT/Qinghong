import { appSettings } from '../../entity/SettingsModel';
import { VIDEO_KB_SHORTCUTS, parseVideoKbOverrides } from '../../constants/KbShortcuts';

/**
 * 网页视频控制注入脚本（按设置注入，文档加载前执行，DOMContentLoaded 后绑事件）：
 * - 手势（document 捕获 touchstart，每次触摸动态定位视频，兼容各类播放器布局）：
 *   双击快进/快退、水平滑动调进度（松开生效）、全屏时左侧上下滑调亮度（经
 *   __qhNative.videoRequest 原生桥）/右侧调音量、单击暂停/播放、长按 3 倍速；
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
    const dtap: boolean = gesture && appSettings.video_gesture_double_tap
    const swipe: boolean = gesture && appSettings.video_gesture_swipe_seek
    const side: boolean = gesture && appSettings.video_gesture_side_slide
    const tap: boolean = gesture && appSettings.video_gesture_tap_toggle
    const lp: boolean = gesture && appSettings.video_gesture_long_press
    const cfg: string = '{"G":' + (dtap || swipe || side || tap || lp) +
      ',"dtap":' + dtap +
      ',"swipe":' + swipe +
      ',"side":' + side +
      ',"tap":' + tap +
      ',"lp":' + lp +
      ',"kb":' + kb +
      ',"KA":' + kaJson + '}'
    return {
      script: "(function(){" +
        "if(window.__qhVideoCtrl){return}" +
        "window.__qhVideoCtrl=true;" +
        "var CFG=" + cfg + ";" +
        "var SEEK=10,LPRATE=3,DBLMS=300,LPMS=600;" +
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
        // ---------- 指示器 ----------
        "function notice(v,text,keep){" +
        "var c=v.parentElement;if(!c){return}" +
        "var n=document.getElementById('__qhVNotice');" +
        "if(!n){" +
        "n=document.createElement('div');n.id='__qhVNotice';" +
        "n.style.cssText='position:absolute;z-index:2147483647;pointer-events:none;"+"" +
        "background:rgba(0,0,0,0.55);color:#fff;font:14px/1.6 sans-serif;"+"" +
        "padding:4px 12px;border-radius:6px;text-align:center;white-space:nowrap;';" +
        "}" +
        "if(n.parentElement!==c){c.appendChild(n)}" +
        "n.innerText=text;n.style.display='block';" +
        "n.style.left=Math.max(4,(c.clientWidth-n.offsetWidth)/2)+'px';" +
        "n.style.top=Math.max(4,c.clientHeight/5-n.offsetHeight/2)+'px';" +
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
        // 手势启用时抑制站点 touchstart 级手势（自带长按/按压反馈/起手计数）；
        // 单击面板显隐依赖 touchend/click，在 onEnd 中按需放行，不受影响
        "if(CFG.G){e.stopPropagation()}" +
        "var ex=sx,ey=sy;" +
        "var fs=!!document.fullscreenElement;" +
        "if(fs){" +
        "var ww=window.innerWidth,wh=window.innerHeight;" +
        "if(sx<ww*0.05||sx>ww*0.95||sy<wh*0.05||sy>wh*0.95){return}" +
        "}" +
        "var mode=0,seekD=0,leftSide=false,base=1,lpT=null,lpOn=false;" +
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
        "if(CFG.side&&fs){mode=2;leftSide=sx<window.innerWidth/2;base=leftSide?1:(v.muted?0:v.volume)}" +
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
        "if(leftSide){" +
        "try{__qhNative.videoRequest('brightness',String(k))}catch(err){}" +
        "notice(v,'亮度 '+Math.round(k*100)+'%',true)" +
        "}else{" +
        "v.volume=k;v.muted=(k===0);" +
        "notice(v,'音量 '+Math.round(k*100)+'%',true)" +
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
        "var isDbl=tap0&&CFG.dtap&&(now-last<DBLMS)&&Math.abs(sx-lx)<48;" +
        "if(tap0){v.__qhTapAt=now;v.__qhTapX=sx}" +
        // 仅己方手势实际接管时才终结透传并阻断 click 合成（滑动/侧滑/长按收尾、双击第二击）；
        // 普通单击透传站点，保留控制面板显隐，330ms 内观察站点响应后再决定是否接管暂停/播放
        "if(CFG.G&&(mode!==0||lpOn||isDbl)){e.stopPropagation();e.preventDefault();}" +
        "if(lpOn){try{v.playbackRate=1}catch(e){}lpOn=false}" +
        "if(mode===1&&seekD!==0){seekBy(v,seekD)}" +
        "if(tap0){" +
        "clearTimeout(v.__qhTapT);" +
        "if(v.__qhTapMo){v.__qhTapMo.disconnect();v.__qhTapMo=null}" +
        "if(isDbl){" +
        "seekBy(v,sx<window.innerWidth/2?-SEEK:SEEK)" +
        "}else if(CFG.tap){" +
        "if(typeof MutationObserver!=='undefined'){" +
        "v.__qhTapMo=new MutationObserver(function(){v.__qhSiteTap=1});" +
        "v.__qhTapMo.observe(document.documentElement,{subtree:true,childList:true,attributes:true});" +
        "}" +
        "var mo=v.__qhTapMo;" +
        "v.__qhTapT=setTimeout(function(){" +
        "if(mo){mo.disconnect();if(v.__qhTapMo===mo){v.__qhTapMo=null}}" +
        "if(v.paused===played&&!v.__qhSiteTap){" + // 站点未自行处理本次单击（播放态未变、无 DOM 响应）时才接管
        "if(v.paused){v.play().catch(function(){});notice(v,'播放')}" +
        "else{v.pause();notice(v,'暂停')}" +
        "}" +
        "v.__qhSiteTap=0;" +
        "},330)" +
        "}" +
        "}" +
        "}" +
        "if(CFG.lp){" +
        "lpT=setTimeout(function(){" +
        "if(!mv()){" +
        "lpOn=true;" +
        "try{v.playbackRate=LPRATE}catch(e){}" +
        "notice(v,LPRATE+'x 倍速')" +
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
        "if(CFG.side){" +
        "document.addEventListener('fullscreenchange',function(){" +
        "if(!document.fullscreenElement){" +
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
}
