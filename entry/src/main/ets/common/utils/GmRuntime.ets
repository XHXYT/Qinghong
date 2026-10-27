import UserScriptInfo from '../entity/UserScriptInfo';

/**
 * GM_* API 运行时：注入页面的 JS 桥核心 + 每脚本沙箱包装生成。
 *
 * 架构：
 * - core（__qhGmCore）：每页面安装一次，回调注册/派发、经 window.__qhNative.gmRequest 转发原生；
 * - sandbox：每脚本一个闭包，内置 GM_* 全套 API、预烘焙的脚本值/资源/GM_info，try-catch 隔离。
 * - 值同步：GM_getValue 读页面内烘焙缓存（同步），GM_setValue 更新缓存 + 原生持久化 + 跨标签广播。
 */

/** GM 菜单命令（脚本 GM_registerMenuCommand 注册，浏览器菜单展示） */
export class GmMenuCommand {
  tabId: number = 0
  scriptId: number = 0
  menuId: number = 0
  name: string = ''
}

/** GM_info 序列化数据 */
export class GmInfoData {
  script: Record<string, Object> = {}
  scriptHandler: string = 'Qinghong'
  version: string = '1.0.0'
}

/** ---- 原生侧解析用的 raw 模型（JSON.parse 一次转型） ---- */
export class GmValueRaw {
  scriptId: number = 0
  key: string = ''
  valueRaw: string = ''
}

export class GmDeleteValueRaw {
  scriptId: number = 0
  key: string = ''
}

export class GmXhrRaw {
  id: number = 0
  scriptId: number = 0
  method: string = 'GET'
  url: string = ''
  headers: Record<string, string> = {}
  data: string = ''
  timeout: number = 30000
  responseType: string = 'text'
}

export class GmXhrAbortRaw {
  id: number = 0
}

export class GmOpenTabRaw {
  url: string = ''
  active: boolean = true
}

export class GmClipboardRaw {
  text: string = ''
}

export class GmNotifyRaw {
  text: string = ''
}

export class GmDownloadRaw {
  url: string = ''
}

export class GmMenuRaw {
  scriptId: number = 0
  menuId: number = 0
  name: string = ''
}

export class GmMenuIdRaw {
  scriptId: number = 0
  menuId: number = 0
}

/**
 * GM 运行时 JS 生成器
 */
export class GmRuntime {

  /** 页面级核心（幂等，重复安装自动跳过） */
  static buildCoreJs(): string {
    return `(function(){
if (window.__qhGmCore) { return; }
var seq = 0;
var xhrCbs = {};
var menuCbs = {};
var vListeners = {};
function nat(api, obj) {
  if (window.__qhHud) { try { window.__qhHud.gmCall(api, obj ? obj.scriptId : undefined); } catch (e) {} }
  try {
    var n = window.__qhNative;
    if (n && n.gmRequest) { n.gmRequest(api, JSON.stringify(obj)); }
    else { console.warn('[qh gm] native bridge unavailable'); }
  } catch (e) { console.warn('[qh gm] ' + api, e); }
}
function tryParse(s) {
  if (s === undefined || s === null) { return undefined; }
  try { return JSON.parse(s); } catch (e) { return undefined; }
}
window.__qhGmCore = {
  newId: function() { return ++seq; },
  fireLocalValueChange: function(scriptId, key, oldV, newV) {
    for (var id in vListeners) {
      var l = vListeners[id];
      if (l && l.scriptId === scriptId && l.key === key) {
        try { l.fn(key, oldV, newV, false); } catch (e) { console.warn('[qh gm] value listener', e); }
      }
    }
  },
  notifyValueChange: function(scriptId, key, oldRaw, newRaw, remote) {
    for (var id in vListeners) {
      var l = vListeners[id];
      if (l && l.scriptId === scriptId && l.key === key) {
        try { l.fn(key, tryParse(oldRaw), tryParse(newRaw), remote === true); } catch (e) { console.warn('[qh gm] value listener', e); }
      }
    }
  },
  addValueListener: function(scriptId, key, fn) {
    var id = ++seq;
    vListeners[id] = { scriptId: scriptId, key: key, fn: fn };
    return id;
  },
  removeValueListener: function(id) { delete vListeners[id]; },
  setValue: function(scriptId, key, valueRaw) { nat('setValue', { scriptId: scriptId, key: key, valueRaw: valueRaw }); },
  deleteValue: function(scriptId, key) { nat('deleteValue', { scriptId: scriptId, key: key }); },
  onXhr: function(id, cbs) { xhrCbs[id] = cbs; },
  xhr: function(id, scriptId, o) {
    nat('xhr', { id: id, scriptId: scriptId, method: o.method, url: o.url,
      headers: (o.headers && typeof o.headers === 'object') ? o.headers : {},
      data: o.data || '', timeout: o.timeout || 30000, responseType: o.responseType || 'text' });
  },
  xhrAbort: function(id) { nat('xhrAbort', { id: id }); },
  fireXhr: function(id, ok, payloadStr) {
    var cbs = xhrCbs[id];
    if (!cbs) { return; }
    delete xhrCbs[id];
    var d = {};
    try { if (payloadStr) { d = JSON.parse(payloadStr); } } catch (e) { d = {}; }
    if (!ok) {
      if (d.__timeout && cbs.ontimeout) { cbs.ontimeout(d); return; }
      if (d.__abort && cbs.onabort) { cbs.onabort(d); return; }
      if (cbs.onerror) { cbs.onerror({ error: d.error || 'network' }); }
      return;
    }
    if (cbs.responseType === 'json') {
      try { d.response = d.responseText ? JSON.parse(d.responseText) : null; } catch (e) { d.response = null; }
    }
    if (cbs.onload) { cbs.onload(d); }
  },
  registerMenu: function(scriptId, name, fn) {
    var id = ++seq;
    menuCbs[scriptId + ':' + id] = fn;
    nat('registerMenu', { scriptId: scriptId, menuId: id, name: String(name) });
    return id;
  },
  unregisterMenu: function(scriptId, menuId) {
    delete menuCbs[scriptId + ':' + menuId];
    nat('unregisterMenu', { scriptId: scriptId, menuId: menuId });
  },
  fireMenu: function(scriptId, menuId) {
    var fn = menuCbs[scriptId + ':' + menuId];
    if (fn) { try { fn(); } catch (e) { console.warn('[qh gm] menu command', e); } }
  },
  openTab: function(url, active) { nat('openTab', { url: url, active: active !== false }); },
  clipboard: function(text) { nat('clipboard', { text: text }); },
  notify: function(text) { nat('notify', { text: text }); },
  download: function(url) { nat('download', { url: url }); }
};
})();
`;
  }

  /**
   * 调试悬浮窗（幂等）：右下角 GM 徽标，点按展开注入脚本列表与 GM 调用计数；
   * sandbox 注入时 report(sid, name, runAt)，core nat() 转 gmCall(api, sid)
   */
  static buildHudJs(): string {
    return `(function(){
if (window.__qhHud) { return; }
var calls = 0;
var apiCounts = {};
var bySid = {};
var list = [];
var root = document.createElement('div');
root.style.cssText = 'position:fixed;right:10px;bottom:10px;z-index:2147483647;font:12px/1.5 monospace;';
var badge = document.createElement('div');
badge.textContent = 'GM 0';
badge.style.cssText = 'display:inline-block;padding:5px 12px;border-radius:16px;' +
  'background:rgba(20,20,20,0.85);color:#69f0ae;box-shadow:0 2px 8px rgba(0,0,0,.3);cursor:pointer;user-select:none;';
var panel = document.createElement('div');
panel.style.cssText = 'display:none;margin-top:6px;max-width:260px;max-height:220px;overflow:auto;' +
  'padding:10px 12px;border-radius:12px;background:rgba(20,20,20,0.92);color:#eee;';
function esc(s) {
  return String(s).replace(/[&<>"]/g, function(c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
  });
}
function render() {
  badge.textContent = 'GM ' + calls + (list.length ? ' · ' + list.length + 's' : '');
  var h = '';
  if (!list.length) { h += '<div style="color:#888">no userscript injected</div>'; }
  for (var i = 0; i < list.length; i++) {
    h += '<div><b style="color:#69f0ae">' + esc(list[i].name) + '</b>' +
      ' <span style="color:#999">' + esc(list[i].runAt) + '</span>' +
      ' <span style="color:#ffd54f">×' + list[i].n + '</span></div>';
  }
  var apis = Object.keys(apiCounts);
  if (apis.length) {
    h += '<div style="margin-top:6px;color:#888">GM calls</div>';
    for (var j = 0; j < apis.length; j++) {
      h += '<div>' + esc(apis[j]) + ' ×' + apiCounts[apis[j]] + '</div>';
    }
  }
  panel.innerHTML = h;
}
function mount() {
  var p = document.body || document.documentElement;
  if (p && root.parentNode !== p) { p.appendChild(root); }
}
badge.addEventListener('click', function(e) {
  e.stopPropagation();
  panel.style.display = panel.style.display === 'none' ? 'block' : 'none';
});
root.appendChild(badge);
root.appendChild(panel);
window.__qhHud = {
  report: function(sid, name, runAt) {
    var e = bySid[sid];
    if (!e) {
      e = { name: String(name), runAt: String(runAt), n: 0 };
      bySid[sid] = e;
      list.push(e);
    }
    render();
  },
  gmCall: function(api, sid) {
    calls++;
    apiCounts[api] = (apiCounts[api] || 0) + 1;
    var e = bySid[sid];
    if (e) { e.n++; }
    render();
  }
};
render();
mount();
document.addEventListener('DOMContentLoaded', mount);
setTimeout(mount, 500);
})();
`;
  }

  /**
   * 生成单脚本沙箱代码（GM_* 全套 API + 预烘焙值/资源 + @require 库 + 用户代码）
   * @param scriptId 脚本 id（值存储/回调派发的关联键）
   * @param info 脚本实体（code/noframes）
   * @param valuesJson 预烘焙值（原生 JSON 对象字面量，如 {"k":"v"}）
   * @param resourcesJson 资源映射（如 {"name":{"mime":"image/png","b64":"..."}}）
   * @param infoJson GM_info JSON
   * @param requiresCode @require 库代码（已按序拼接）
   */
  static buildSandbox(scriptId: number, info: UserScriptInfo, valuesJson: string,
    resourcesJson: string, infoJson: string, requiresCode: string): string {
    const noframes: string = info.noframes ? 'true' : 'false'
    return `(function(){
try{
var SID = ${scriptId};
if (${noframes} && window.top !== window.self) { return; }
var __qhg = window.__qhGmCore;
if (!__qhg) { console.warn('[qh userscript] GM core missing'); return; }
var __qhValues = ${valuesJson};
var __qhRes = ${resourcesJson};
var unsafeWindow = window;
var GM_info = ${infoJson};
try { console.info('[qh userscript] run: ' + GM_info.script.name); if (window.__qhHud) { window.__qhHud.report(SID, GM_info.script.name, ${JSON.stringify(info.runAt)}); } } catch (e) {}
function GM_getValue(key, def) {
  return Object.prototype.hasOwnProperty.call(__qhValues, key) ? __qhValues[key] : def;
}
function GM_setValue(key, value) {
  var old = __qhValues[key];
  __qhValues[key] = value;
  __qhg.fireLocalValueChange(SID, key, old, value);
  __qhg.setValue(SID, key, JSON.stringify(value));
}
function GM_deleteValue(key) {
  if (!Object.prototype.hasOwnProperty.call(__qhValues, key)) { return false; }
  var old = __qhValues[key];
  delete __qhValues[key];
  __qhg.fireLocalValueChange(SID, key, old, undefined);
  __qhg.deleteValue(SID, key);
  return true;
}
function GM_listValues() { return Object.keys(__qhValues); }
function GM_addValueChangeListener(key, fn) {
  return __qhg.addValueListener(SID, key, function(k, oldV, newV, remote) { fn(k, oldV, newV, remote); });
}
function GM_removeValueChangeListener(id) { __qhg.removeValueListener(id); }
function GM_addStyle(css) {
  var s = document.createElement('style');
  s.textContent = String(css == null ? '' : css);
  (document.head || document.documentElement).appendChild(s);
  return s;
}
function GM_addElement(a, b, c) {
  var parent, tag, attrs;
  if (typeof a === 'string') { tag = a; attrs = b || {}; parent = c || document.head || document.documentElement; }
  else { parent = a; tag = b; attrs = c || {}; }
  if (!tag) { return null; }
  var el = document.createElement(tag);
  for (var k in attrs) { try { el.setAttribute(k, attrs[k]); } catch (e) {} }
  parent.appendChild(el);
  return el;
}
function GM_getResourceText(name) {
  var r = __qhRes[name];
  if (!r) { return undefined; }
  try { return decodeURIComponent(escape(atob(r.b64))); } catch (e) { return undefined; }
}
function GM_getResourceURL(name) {
  var r = __qhRes[name];
  if (!r) { return undefined; }
  return 'data:' + (r.mime || 'text/plain') + ';base64,' + r.b64;
}
function GM_xmlhttpRequest(details) {
  if (!details || !details.url) {
    if (details && details.onerror) { details.onerror({ error: 'no url' }); }
    return { abort: function() {} };
  }
  var id = __qhg.newId();
  __qhg.onXhr(id, {
    responseType: details.responseType || 'text',
    onload: details.onload, onerror: details.onerror,
    ontimeout: details.ontimeout, onabort: details.onabort
  });
  var data = '';
  if (typeof details.data === 'string') { data = details.data; }
  else if (details.data != null) { try { data = JSON.stringify(details.data); } catch (e) { data = ''; } }
  var headers = {};
  if (details.headers && typeof details.headers === 'object') { headers = details.headers; }
  __qhg.xhr(id, SID, {
    method: (details.method || 'GET').toUpperCase(),
    url: String(details.url),
    headers: headers,
    data: data,
    timeout: details.timeout > 0 ? details.timeout : 30000,
    responseType: details.responseType || 'text'
  });
  return { abort: function() { __qhg.xhrAbort(id); } };
}
function GM_setClipboard(data) { __qhg.clipboard(String(data == null ? '' : data)); }
function GM_openInTab(url, options) {
  var active = true;
  if (options && typeof options === 'object' && options.active === false) { active = false; }
  __qhg.openTab(String(url || 'about:blank'), active);
  return { close: function() {}, closed: false };
}
function GM_download(details) {
  var url = typeof details === 'string' ? details : (details && details.url ? String(details.url) : '');
  if (!url) {
    if (details && details.onerror) { details.onerror({ error: 'no url' }); }
    return;
  }
  __qhg.download(url);
}
function GM_notification(details, ondone) {
  var text = typeof details === 'string' ? details : (details && (details.text || details.title) ? (details.text || details.title) : '');
  __qhg.notify(String(text));
  if (typeof ondone === 'function') { try { ondone(undefined, undefined); } catch (e) {} }
}
function GM_registerMenuCommand(name, fn) {
  return __qhg.registerMenu(SID, String(name), function() { fn(); });
}
function GM_unregisterMenuCommand(id) { __qhg.unregisterMenu(SID, id); }
var GM = {
  info: GM_info,
  getValue: function(k) { return new Promise(function(res) { res(GM_getValue(k)); }); },
  setValue: function(k, v) { return new Promise(function(res) { GM_setValue(k, v); res(); }); },
  deleteValue: function(k) { return new Promise(function(res) { res(GM_deleteValue(k)); }); },
  listValues: function() { return new Promise(function(res) { res(GM_listValues()); }); },
  xmlHttpRequest: GM_xmlhttpRequest,
  addStyle: GM_addStyle,
  addElement: GM_addElement,
  getResourceText: GM_getResourceText,
  getResourceURL: GM_getResourceURL,
  setClipboard: GM_setClipboard,
  openInTab: GM_openInTab,
  download: GM_download,
  notification: GM_notification,
  registerMenuCommand: GM_registerMenuCommand,
  unregisterMenuCommand: GM_unregisterMenuCommand
};
${requiresCode}
${info.code}
}catch(e){console.warn('[qh userscript]',e)}
})();
`;
  }
}
