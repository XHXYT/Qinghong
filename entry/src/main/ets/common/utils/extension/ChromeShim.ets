/**
 * chrome.* API 兼容层（注入页面的 JS 生成器）：
 * - core（__qhExtCore）：每页面安装一次，回调注册/派发、异步 storage/sendMessage
 *   经 window.__qhNative.gmRequest 转发原生；
 * - sandbox：每 content_script 声明一个闭包，内置 chrome.* 基础 API
 *   （runtime/storage/i18n/extension），manifest 与 i18n 消息预烘焙。
 * 语义对齐：chrome.storage 为异步 API，值经原生持久化，不做页面内烘焙。
 */

import { EXT_RES_HOST, EXT_SCHEME, EXT_SCHEME_PREFIX } from './ExtensionResources';

/** ---- 原生侧解析用的 raw 模型（JSON.parse 一次转型） ---- */

export class ExtStorageGetRaw {
  extId: string = ''
  cbId: number = 0
  keysJson: string = ''
}

export class ExtStorageSetRaw {
  extId: string = ''
  cbId: number = 0
  itemsJson: string = ''
}

export class ExtStorageRemoveRaw {
  extId: string = ''
  cbId: number = 0
  keysJson: string = ''
}

export class ExtStorageClearRaw {
  extId: string = ''
  cbId: number = 0
}

export class ExtSendMsgRaw {
  extId: string = ''
  cbId: number = 0
  msgJson: string = ''
}

export class ExtRespondRaw {
  respondId: number = 0
  respJson: string = ''
}

export class ExtSendMsgBgRaw {
  extId: string = ''
  cbId: number = 0
  msgJson: string = ''
  page: string = ''
}

export class ExtTabQueryRaw {
  extId: string = ''
  cbId: number = 0
  queryJson: string = ''
}

export class ExtTabSendMsgRaw {
  extId: string = ''
  cbId: number = 0
  tabId: number = 0
  msgJson: string = ''
}

export class ExtTabCreateRaw {
  cbId: number = 0
  url: string = ''
}

export class ExtTabUpdateRaw {
  cbId: number = 0
  tabId: number = 0
  url: string = ''
  active: number = 0
}

export class ExtExecuteScriptRaw {
  extId: string = ''
  cbId: number = 0
  tabId: number = 0
  filesJson: string = ''
}

export class ExtNotifyRaw {
  text: string = ''
}

export class ExtStoreInstallRaw {
  url: string = ''
  extId: string = ''
}

export class ExtGetContextsRaw {
  extId: string = ''
  cbId: number = 0
}

/** action.setBadge* 角标更新（bg/popup → 原生，按字段增量合并） */
export class ExtSetBadgeRaw {
  extId: string = ''
  tabId: number = 0
  text: string = ''
  /** 1=setBadgeText 调用（text 字段有效，'' 代表清除）；0=纯颜色上报 */
  textOp: number = 0
  bg: string = ''
  fg: string = ''
}

/** runtime.connect 发起（popup/内容脚本/bg → 原生路由 onConnect） */
export class ExtPortConnectRaw {
  extId: string = ''
  portId: string = ''
  name: string = ''
  url: string = ''
  origin: string = ''
}

/** Port.postMessage（双向，按 portId 路由对端） */
export class ExtPortMsgRaw {
  portId: string = ''
  msgJson: string = ''
}

/** Port.disconnect（双向，对端触发 onDisconnect） */
export class ExtPortDisconnectRaw {
  portId: string = ''
}

/**
 * chrome.* 运行时 JS 生成器
 */
export class ChromeShim {

  /**
   * 页面级核心（幂等，重复安装自动跳过）
   */
  static buildCoreJs(): string {
    return `(function(){
if (window.__qhExtCore) { return; }
var seq = 0;
var cbs = {};
var msgLs = {};
var chgLs = {};
/* Port（runtime.connect 长连接）注册表：portId → { msgLs, discLs }；
   两端各持同一 portId 的本地 Port 对象，消息经原生按 portId 双向路由 */
var ports = {};
var portSeq = 0;
var portConnLs = [];
/* 多扩展派发（ArkWeb 无隔离世界，各扩展内容沙箱共用页面主世界 window.chrome）：
   旧 first-wins 合并会让后注入扩展的 webextension-polyfill（加载时经 globalThis.chrome
   捕获目标）拿到先注入扩展的 runtime —— 真机实证 AdGuard assistant 监听器被注册到
   先注入扩展名下，bg 消息派发 ls=-1 永远空响应。此处安装派发 getter：
   沙箱求值期间 window.chrome/browser 指向本扩展 API，polyfill 加载时同步捕获即
   锁定正确对象；沙箱外回落内建对象（页面自身探测 chrome 不受污染） */
var qhCurApi = null;
var qhLastApi = null;
var qhOrigChrome = window.chrome;
var qhOrigBrowser = window.browser;
function qhChromeGet() {
  return qhCurApi || qhLastApi || qhOrigChrome || {};
}
function qhBrowserGet() {
  return qhCurApi || qhLastApi || qhOrigBrowser;
}
function qhInstallGetters() {
  try {
    Object.defineProperty(window, 'chrome', { get: qhChromeGet, configurable: true });
  } catch (e) {}
  try {
    Object.defineProperty(window, 'browser', { get: qhBrowserGet, configurable: true });
  } catch (e) {}
}
qhInstallGetters();
function nat(api, obj) {
  try {
    var n = window.__qhNative;
    if (n && n.gmRequest) { n.gmRequest(api, JSON.stringify(obj)); }
    else { console.warn('[qh ext] native bridge unavailable'); }
  } catch (e) { console.warn('[qh ext] ' + api, e); }
}
function qhMakeEvApi(store) {
  return {
    addListener: function(fn) { if (typeof fn === 'function' && store.indexOf(fn) < 0) { store.push(fn); } },
    removeListener: function(fn) { var i = store.indexOf(fn); if (i >= 0) { store.splice(i, 1); } },
    hasListener: function(fn) { return store.indexOf(fn) >= 0; }
  };
}
function qhMakePort(portId, name, sender) {
  var msgLs2 = [];
  var discLs2 = [];
  /* 注册表条目持有 Port 对象本体：onMessage/onDisconnect 监听器按 Chrome 语义
     收到 (message, port) / (port)，扩展常在监听器里用第二参回复（真机实证
     Bitwarden local-backed-session-storage sendMessageTo(port)） */
  var entry = { msgLs: msgLs2, discLs: discLs2, port: null };
  ports[portId] = entry;
  var port = {
    name: name,
    sender: sender,
    onMessage: qhMakeEvApi(msgLs2),
    onDisconnect: qhMakeEvApi(discLs2),
    postMessage: function(msg) {
      if (!ports[portId]) { return; }
      var mj = 'null';
      try { mj = JSON.stringify(msg === undefined ? null : msg); } catch (e) { mj = 'null'; }
      console.warn('[qh ext] port-post ' + portId + ' len=' + mj.length);
      nat('extPortMsg', { portId: portId, msgJson: mj });
    },
    disconnect: function() {
      if (!ports[portId]) { return; }
      delete ports[portId];
      nat('extPortDisconnect', { portId: portId });
    }
  };
  entry.port = port;
  return port;
}
window.__qhExtCore = {
  reg: function(fn) { var id = ++seq; cbs[id] = fn; return id; },
  fire: function(id, err, payloadJson) {
    var fn = cbs[id];
    if (!fn) { return; }
    delete cbs[id];
    var v;
    if (payloadJson !== '' && payloadJson !== undefined && payloadJson !== null) {
      try { v = JSON.parse(payloadJson); } catch (e) { v = undefined; }
    }
    try { fn(err || null, v); } catch (e) { console.warn('[qh ext] callback', e); }
  },
  fireMessage: function(extId, msgJson, senderJson, respondId) {
    function respondOnce(resp) {
      if (respondId > 0) {
        var rj = '';
        try { if (resp !== undefined && resp !== null) { rj = JSON.stringify(resp); } } catch (e) { rj = ''; }
        nat('extRespond', { respondId: respondId, respJson: rj });
        respondId = 0;
      }
    }
    var ls = msgLs[extId];
    try { console.warn('[qh ext] fireMessage ' + extId + ' ls=' + (ls ? ls.length : -1) + ' msg=' + String(msgJson || '').substring(0, 160)); } catch (e) {}
    if (!ls || !ls.length) {
      respondOnce(undefined);
      return;
    }
    var m = null;
    try { if (msgJson) { m = JSON.parse(msgJson); } } catch (e) { m = null; }
    var sender = {};
    try { if (senderJson) { sender = JSON.parse(senderJson); } } catch (e) { sender = {}; }
    var asyncWait = false;
    for (var i = 0; i < ls.length; i++) {
      try {
        var r = ls[i](m, sender, function(resp) {
          respondOnce(resp);
        });
        if (r === true) {
          asyncWait = true;
        } else if (r && typeof r.then === 'function') {
          /* MV3（Chrome 99+）：监听器返回 Promise，决议值即响应 */
          asyncWait = true;
          r.then(function(resp) { respondOnce(resp); }, function() { respondOnce(undefined); });
        }
      } catch (e) { console.warn('[qh ext] onMessage listener', e); }
    }
    if (!asyncWait) { respondOnce(undefined); }
  },
  addMsgListener: function(extId, fn) {
    if (!msgLs[extId]) { msgLs[extId] = []; }
    msgLs[extId].push(fn);
    try { console.warn('[qh ext] addMsgListener ' + extId + ' n=' + msgLs[extId].length); } catch (e) {}
  },
  setCurExt: function(api) { qhCurApi = api; qhLastApi = api; qhInstallGetters(); },
  clearCurExt: function() { qhCurApi = null; },
  storageGet: function(extId, keysJson, cb) {
    var id = this.reg(cb);
    nat('extStorageGet', { extId: extId, cbId: id, keysJson: keysJson });
  },
  storageSet: function(extId, itemsJson, cb) {
    var id = this.reg(cb);
    nat('extStorageSet', { extId: extId, cbId: id, itemsJson: itemsJson });
  },
  storageRemove: function(extId, keysJson, cb) {
    var id = this.reg(cb);
    nat('extStorageRemove', { extId: extId, cbId: id, keysJson: keysJson });
  },
  storageClear: function(extId, cb) {
    var id = this.reg(cb);
    nat('extStorageClear', { extId: extId, cbId: id });
  },
  sendMsg: function(extId, msgJson, cb) {
    var id = cb ? this.reg(cb) : 0;
    nat('extSendMsg', { extId: extId, cbId: id, msgJson: msgJson });
  },
  natCall: function(api, obj) { nat(api, obj); },
  fireStorageChange: function(extId, changesJson, area) {
    var ls = chgLs[extId];
    if (!ls || !ls.length) { return; }
    var ch = null;
    try { ch = JSON.parse(changesJson); } catch (e) { ch = null; }
    if (ch === null) { return; }
    for (var i = 0; i < ls.length; i++) {
      try { ls[i](ch, area); } catch (e) { console.warn('[qh ext] onChanged listener', e); }
    }
  },
  addChgListener: function(extId, fn) {
    if (!chgLs[extId]) { chgLs[extId] = []; }
    chgLs[extId].push(fn);
  },
  /* 发起端：runtime.connect({name})（popup/内容脚本 → bg；bg → popup）。
     portId 由发起端生成（extId+序号+随机后缀，全局唯一），原生按 portId 路由 */
  connectPort: function(extId, name, url, origin) {
    var pid = extId + '-p' + (++portSeq) + '-' + Math.random().toString(36).slice(2, 10);
    var port = qhMakePort(pid, String(name == null ? '' : name), undefined);
    console.warn('[qh ext] port-connect ' + pid + ' name=' + name);
    nat('extPortConnect', { extId: extId, portId: pid, name: String(name == null ? '' : name),
      url: String(url == null ? '' : url), origin: String(origin == null ? '' : origin) });
    return port;
  },
  addPortConnectListener: function(fn) {
    if (typeof fn === 'function' && portConnLs.indexOf(fn) < 0) { portConnLs.push(fn); }
  },
  removePortConnectListener: function(fn) {
    var i = portConnLs.indexOf(fn);
    if (i >= 0) { portConnLs.splice(i, 1); }
  },
  /* 接收端：原生注入，构造 bg 侧 Port 并触发 runtime.onConnect；
     无监听器按 Chrome 语义立即回断（onDisconnect） */
  firePortConnect: function(portId, nameJson, senderJson) {
    var name = '';
    try { name = JSON.parse(nameJson); } catch (e) { name = ''; }
    var sender = null;
    try { sender = JSON.parse(senderJson); } catch (e) { sender = null; }
    console.warn('[qh ext] port-onConnect ' + portId + ' ls=' + portConnLs.length);
    if (!portConnLs.length) {
      delete ports[portId];
      nat('extPortDisconnect', { portId: portId });
      return;
    }
    var port = qhMakePort(portId, name, sender);
    for (var i = 0; i < portConnLs.length; i++) {
      try { portConnLs[i](port); } catch (e) { console.warn('[qh ext] onConnect listener', e); }
    }
  },
  firePortMessage: function(portId, msgJson) {
    var p = ports[portId];
    var mm = msgJson || '';
    if (mm.length > 300) { mm = mm.substring(0, 300) + '...'; }
    console.warn('[qh ext] port-msg ' + portId + ' ls=' + (p ? p.msgLs.length : -1) + ' data=' + mm);
    if (!p) { return; }
    var m = null;
    try { m = JSON.parse(msgJson); } catch (e) { m = null; }
    for (var i = 0; i < p.msgLs.length; i++) {
      /* Chrome 语义：onMessage 监听器收 (message, port) */
      try { p.msgLs[i](m, p.port); } catch (e) { console.warn('[qh ext] port onMessage', e); }
    }
  },
  firePortDisconnect: function(portId) {
    var p = ports[portId];
    console.warn('[qh ext] port-disc ' + portId);
    if (!p) { return; }
    delete ports[portId];
    for (var i = 0; i < p.discLs.length; i++) {
      /* Chrome 语义：onDisconnect 监听器收 (port) */
      try { p.discLs[i](p.port); } catch (e) { console.warn('[qh ext] port onDisconnect', e); }
    }
  }
};
})();
`;
  }

  /** CSS 注入片段（style 元素，document_start 时 head 未建由 documentElement 兜底） */
  static cssInjectJs(css: string): string {
    return `(function(){var s=document.createElement('style');s.textContent=${JSON.stringify(css)};`
      + `(document.head||document.documentElement).appendChild(s);})();`
  }

  /**
   * chromeApi Proxy 兜底 stub 片段（宿主/内容沙箱共用）：
   * 未实现的 chrome.* 命名空间自动生成万能 stub（可调用返回 Promise、可链式取值、可 addListener），
   * 防止宿主脚本顶层 chrome.xxx.addListener 之类崩溃（如 action.onClicked/windows/webNavigation）；
   * 每个属性路径仅 console.warn 一次，作为待实现 API 的诊断清单。
   * 生成 chromeApiSafe 变量（chrome/browser 应指向它）。
   */
  private static stubProxyJs(): string {
    return `
var QH_STUB_SEEN = {};
function qhWarnOnce(p) {
  if (!QH_STUB_SEEN[p]) {
    QH_STUB_SEEN[p] = true;
    try { console.warn('[qh ext] stub chrome.' + p); } catch (e) {}
  }
}
function qhIsMetaKey(k) {
  /* 模块元属性必须返回 undefined 而非 stub：rspack/webpack 互操作探测 __esModule，
     若为 truthy 会走 module.default 分支拿到 stub 导致真 API 全丢（真机实证：
     getUILanguage 返回 Promise → uiLanguage.substring 崩 → popup 白屏） */
  return k === '__esModule' || k === 'default' || k === 'then' || k === 'catch'
    || k === 'finally' || k === 'toJSON' || k === '$$typeof';
}
/* 已实现命名空间对象递归包裹：真实属性原样透传，未知嵌套属性（如
   contextMenus.onClicked / action.onClicked / tabs.onCreated）自动 stub，
   防止 undefined.addListener 崩顶层（真机实证 AdGuard bg contextMenus.onClicked） */
var QH_WRAPS = new WeakMap();
function qhWrapObj(v, path) {
  if (v === null || typeof v !== 'object') { return v; }
  var w = QH_WRAPS.get(v);
  if (w !== undefined) { return w; }
  w = new Proxy(v, {
    get: function(t, k) {
      if (typeof k !== 'string') { return Reflect.get(t, k); }
      if (qhIsMetaKey(k)) { return undefined; }
      if (k in t) { return qhWrapObj(t[k], path + '.' + k); }
      var sub = path + '.' + k;
      qhWarnOnce(sub);
      return qhMakeStub(sub);
    }
  });
  QH_WRAPS.set(v, w);
  return w;
}
function qhMakeStub(path) {
  var base = function() {
    /* 只返回决议 undefined 的 Promise，绝不自动调用传入的函数参数：
       addListener(listener) 类注册调用若把 listener 当响应回调触发，
       会以 undefined 合成事件（undefined.menuItemId 崩，真机实证 AdGuard/GlobalSpeed bg init 链断裂） */
    return Promise.resolve(undefined);
  };
  return new Proxy(base, {
    get: function(t, k) {
      if (typeof k !== 'string') { return Reflect.get(t, k); }
      if (qhIsMetaKey(k)) { return undefined; }
      var sub = path + '.' + k;
      qhWarnOnce(sub);
      return qhMakeStub(sub);
    },
    apply: function(t, thisArg, args) { return t.apply(thisArg, args); }
  });
}
var QH_STUBS = {};
var chromeApiSafe = new Proxy(chromeApi, {
  get: function(t, k) {
    if (typeof k !== 'string') { return Reflect.get(t, k); }
    if (qhIsMetaKey(k)) { return undefined; }
    if (k in t) { return qhWrapObj(t[k], k); }
    if (!QH_STUBS[k]) {
      qhWarnOnce(k);
      QH_STUBS[k] = qhMakeStub(k);
    }
    return QH_STUBS[k];
  }
});
`;
  }

  /**
   * DNR enabled ruleset 状态 JS（content/host 两沙箱共用，插于 mkArea 与 chromeApi 之间）：
   * 持久化于扩展存储保留键 __qh_dnr_enabled_rulesets，updateEnabledRulesets 读改写、
   * getEnabledRulesets 读返回——否则恒返回空列表，AdGuard areFilterLimitsExceeded 判
   * "浏览器已修改激活的内置过滤器列表"（实际未启用任何 ruleset）误报警告
   */
  private static dnrRulesetsJs(): string {
    return `
function qhDnrRulesets() {
  return new Promise(function(res) {
    try {
      CORE.storageGet(EXTID, '"__qh_dnr_enabled_rulesets"', function(err, items) {
        var v = items && items.__qh_dnr_enabled_rulesets;
        res(Array.isArray(v) ? v : []);
      });
    } catch (e) { res([]); }
  });
}
function qhDnrUpdateRulesets(opt) {
  return qhDnrRulesets().then(function(ids) {
    var m = {};
    for (var i = 0; i < ids.length; i++) { m[ids[i]] = true; }
    var en = (opt && opt.enableRulesetIds) || [];
    var dis = (opt && opt.disableRulesetIds) || [];
    for (var j = 0; j < en.length; j++) { m[en[j]] = true; }
    for (var k = 0; k < dis.length; k++) { delete m[dis[k]]; }
    var out = Object.keys(m);
    return new Promise(function(res) {
      try {
        CORE.storageSet(EXTID, JSON.stringify({ __qh_dnr_enabled_rulesets: out }), function() { res(); });
      } catch (e) { res(); }
    });
  });
}
`;
  }

  /**
   * 生成单 content_script 沙箱代码（chrome.* 基础 API + 预烘焙 manifest/i18n + css/js）
   * @param extId 扩展 ID
   * @param manifestJson manifest.json 原文（getManifest 返回，name/description 由运行时覆盖为已解析值）
   * @param resolvedName 已解析（i18n）扩展名
   * @param resolvedDesc 已解析描述
   * @param messagesJson i18n 消息表 JSON（小写键）
   * @param uiLocale UI 语言（default_locale）
   * @param cssCode CSS 注入片段（已拼接）
   * @param jsCode 脚本代码（已拼接）
   * @param allFrames 是否允许 iframe
   */
  static buildContentSandbox(extId: string, manifestJson: string, resolvedName: string, resolvedDesc: string,
    messagesJson: string, uiLocale: string, cssCode: string, jsCode: string, allFrames: boolean,
    matches: string[]): string {
    const framesGuard: string = allFrames ? '' : 'if (window.top !== window.self) { return; }'
    const matchesJson: string = JSON.stringify(matches)
    return `(function(){
try{
var EXTID = ${JSON.stringify(extId)};
${framesGuard}
/* URL 精确守卫：scriptRules 仅粗过滤（'*.example.com' 模糊/'*' 全来源均无路径粒度），
   此处按 Chrome match pattern 语义精确匹配；非 http/https（扩展页/内部页/自建页）一律不注入 */
var QH_MATCHES = ${matchesJson};
function qhMatchPattern(pat, proto, host, path) {
  if (pat === '<all_urls>') { return proto === 'http:' || proto === 'https:'; }
  var pi = pat.indexOf('://');
  if (pi <= 0) { return false; }
  var ps = pat.substring(0, pi);
  var prest = pat.substring(pi + 3);
  var psi = prest.indexOf('/');
  var ph = psi < 0 ? prest : prest.substring(0, psi);
  var pp = psi < 0 ? '/*' : prest.substring(psi);
  if (pp === '' || pp === '/') { pp = '/*'; }
  if (ps === '*') {
    if (proto !== 'http:' && proto !== 'https:') { return false; }
  } else if (ps + ':' !== proto) { return false; }
  if (ph !== '*') {
    if (ph.indexOf('*.') === 0) {
      var base = ph.substring(2);
      if (host !== base && host.substring(host.length - base.length - 1) !== '.' + base) { return false; }
    } else if (host !== ph) { return false; }
  }
  var rx = '^';
  for (var ri = 0; ri < pp.length; ri++) {
    var rc = pp.charAt(ri);
    if (rc === '*') { rx += '[^/]*'; }
    else if ('\\\\^$.|?+()[]{}'.indexOf(rc) >= 0) { rx += '\\\\' + rc; }
    else { rx += rc; }
  }
  rx += '$';
  return new RegExp(rx).test(path);
}
var qhProto = location.protocol || '';
var qhHost = location.hostname || '';
var qhPath = location.pathname || '/';
if (qhPath === '') { qhPath = '/'; }
var qhMatched = false;
for (var qhMi = 0; qhMi < QH_MATCHES.length; qhMi++) {
  if (qhMatchPattern(QH_MATCHES[qhMi], qhProto, qhHost, qhPath)) { qhMatched = true; break; }
}
if (!qhMatched) { return; }
try { console.info('[qh ext] cs ' + EXTID + ' ' + location.href); } catch (e) {}
var CORE = window.__qhExtCore;
if (!CORE) { console.warn('[qh ext] core missing'); return; }
var MANIFEST = ${manifestJson};
try { MANIFEST.name = ${JSON.stringify(resolvedName)}; MANIFEST.description = ${JSON.stringify(resolvedDesc)}; } catch (e) {}
var MSGS = ${messagesJson};
var UILOC = ${JSON.stringify(uiLocale)};
/* 未捕获异常/Promise 拒绝带堆栈上报（内容脚本侧）：页面 console 经 ARKWEB-CONSOLE 进 hilog */
window.addEventListener('error', function (ev) {
  try {
    console.error('[qh jserr] ' + (ev.error && ev.error.stack ? ev.error.stack
      : (ev.message || '') + ' @ ' + (ev.filename || '') + ':' + (ev.lineno || 0) + ':' + (ev.colno || 0)));
  } catch (e) {}
});
window.addEventListener('unhandledrejection', function (ev) {
  try {
    var qhr = ev.reason;
    console.error('[qh jsrej] ' + (qhr && qhr.stack ? qhr.stack : String(qhr)));
  } catch (e) {}
});
var lastError = null;
var onMsgLs = [];
function getMessage(name, subs) {
  var e = MSGS[String(name == null ? '' : name).toLowerCase()];
  if (!e || typeof e.message !== 'string') { return ''; }
  var s = e.message;
  var subsArr = null;
  if (Object.prototype.toString.call(subs) === '[object Array]') { subsArr = subs; }
  else if (subs !== undefined && subs !== null) { subsArr = [subs]; }
  if (subsArr) {
    for (var si = 0; si < subsArr.length; si++) { s = s.split('$' + (si + 1) + '$').join(String(subsArr[si])); }
  }
  var ph = e.placeholders;
  if (ph) {
    for (var pk in ph) {
      var cont = ph[pk] && typeof ph[pk].content === 'string' ? ph[pk].content : '';
      var sub0 = subsArr && subsArr.length > 0 ? String(subsArr[0]) : '';
      s = s.split('$' + pk + '$').join(cont ? cont.split('$1$').join(sub0) : '');
    }
  }
  return s;
}
var runtimeApi = {
  id: EXTID,
  getManifest: function() { return JSON.parse(JSON.stringify(MANIFEST)); },
  getURL: function(p) { return '${EXT_SCHEME_PREFIX}' + EXTID + '/' + String(p == null ? '' : p).replace(/^\\/+/, ''); },
  getPlatformInfo: function(cb) {
    /* 桌面语义（os=win）：AdGuard getUserAgent 直接解构 platformInfo.os（undefined 崩）；
       同时 getIsAndroid 保持 false，popup 维持桌面布局（真机实证可用状态） */
    var info = { os: 'win', arch: 'x86-32', nacl_arch: 'x86-32', platform: 'win' };
    var p = Promise.resolve(info);
    if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
    return p;
  },
  sendMessage: function() {
    var args = Array.prototype.slice.call(arguments);
    var i = 0;
    if (typeof args[i] === 'string') { i++; }
    var msg = args[i]; i++;
    var cb = null;
    while (i < args.length) { if (typeof args[i] === 'function') { cb = args[i]; } i++; }
    var msgJson = 'null';
    try { msgJson = JSON.stringify(msg === undefined ? null : msg); } catch (e) { msgJson = 'null'; }
    var resolveP;
    var p = cb ? null : new Promise(function(res) { resolveP = res; });
    CORE.sendMsg(EXTID, msgJson, function(err, resp) {
      lastError = err ? { message: String(err) } : null;
      if (resolveP) { resolveP(resp); }
      if (cb) { try { cb(resp); } catch (e) { console.warn('[qh ext] sendMessage callback', e); } }
    });
    return p;
  },
  connect: function(opt) {
    var nm = '';
    try { nm = String((opt || {}).name == null ? '' : (opt || {}).name); } catch (e) { nm = ''; }
    return CORE.connectPort(EXTID, nm, location.href, location.origin);
  },
  onConnect: {
    addListener: function(fn) { CORE.addPortConnectListener(fn); },
    removeListener: function(fn) { CORE.removePortConnectListener(fn); },
    hasListener: function() { return false; }
  },
  onMessage: {
    addListener: function(fn) { onMsgLs.push(fn); CORE.addMsgListener(EXTID, fn); },
    removeListener: function(fn) {
      var ix = onMsgLs.indexOf(fn);
      if (ix >= 0) { onMsgLs.splice(ix, 1); }
    },
    hasListener: function(fn) { return onMsgLs.indexOf(fn) >= 0; }
  },
  onInstalled: { addListener: function() {} },
  onStartup: { addListener: function() {} },
  setLastError: function(m) { lastError = m; }
};
Object.defineProperty(runtimeApi, 'lastError', {
  get: function() { return lastError; },
  configurable: true
});
function mkArea() {
  return {
    QUOTA_BYTES: 10485760,
    get: function(keys, cb) {
      var kj = 'null';
      if (keys !== undefined && keys !== null) { try { kj = JSON.stringify(keys); } catch (e) { kj = 'null'; } }
      var p = new Promise(function(res) {
        CORE.storageGet(EXTID, kj, function(err, items) { res(items || {}); });
      });
      if (typeof cb === 'function') { p.then(function(items) { try { cb(items); } catch (e) {} }); }
      return p;
    },
    set: function(items, cb) {
      var ij = '{}';
      try { ij = JSON.stringify(items || {}); } catch (e) { ij = '{}'; }
      var p = new Promise(function(res) {
        CORE.storageSet(EXTID, ij, function() { res(); });
      });
      if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); }
      return p;
    },
    remove: function(keys, cb) {
      var kj = 'null';
      if (keys !== undefined && keys !== null) { try { kj = JSON.stringify(keys); } catch (e) { kj = 'null'; } }
      var p = new Promise(function(res) {
        CORE.storageRemove(EXTID, kj, function() { res(); });
      });
      if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); }
      return p;
    },
    clear: function(cb) {
      var p = new Promise(function(res) {
        CORE.storageClear(EXTID, function() { res(); });
      });
      if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); }
      return p;
    },
    getBytesInUse: function(keys, cb) {
      if (typeof cb === 'function') { cb(0); }
      return Promise.resolve(0);
    },
    getKeys: function(cb) {
      var p = new Promise(function(res) {
        CORE.storageGet(EXTID, 'null', function(err, items) {
          var ks = [];
          try { ks = Object.keys(items || {}); } catch (e) { ks = []; }
          res(ks);
        });
      });
      if (typeof cb === 'function') { p.then(function(ks) { try { cb(ks); } catch (e) {} }); }
      return p;
    },
    onChanged: { addListener: function(fn) { CORE.addChgListener(EXTID, fn); }, removeListener: function(fn) {} },
    /* MV3：Grammarly bg 在 allowCStoUseSessionStorage 里依赖回调式 setAccessLevel，
       缺失时 fc.create 永不 resolve → bg init 挂死（60s 超时）。必须同步回调 + 返回 Promise */
    setAccessLevel: function(o, cb) {
      if (typeof cb === 'function') { try { cb(); } catch (e) {} }
      return Promise.resolve();
    }
  };
}
${ChromeShim.dnrRulesetsJs()}
var chromeApi = {
  runtime: runtimeApi,
  i18n: {
    getMessage: getMessage,
    getUILanguage: function() { return UILOC; },
    getAcceptLanguages: function(cb) {
      if (typeof cb === 'function') { cb([UILOC]); }
      return Promise.resolve([UILOC]);
    }
  },
  cookies: {
    get: function(d, cb) { if (typeof cb === 'function') { cb(null); } return Promise.resolve(null); },
    getAll: function(d, cb) { if (typeof cb === 'function') { cb([]); } return Promise.resolve([]); },
    set: function(d, cb) { if (typeof cb === 'function') { cb(null); } return Promise.resolve(null); },
    remove: function(d, cb) { if (typeof cb === 'function') { cb(null); } return Promise.resolve(null); },
    onChanged: { addListener: function(fn) {}, removeListener: function(fn) {} }
  },
  storage: {
    local: mkArea(),
    sync: mkArea(),
    session: mkArea(),
    managed: mkArea(),
    onChanged: { addListener: function(fn) { CORE.addChgListener(EXTID, fn); }, removeListener: function(fn) {} }
  },
  extension: {
    getURL: runtimeApi.getURL,
    getManifest: runtimeApi.getManifest,
    inIncognitoContext: false
  },
  permissions: {
    contains: function(p, cb) { if (typeof cb === 'function') { cb(false); } return Promise.resolve(false); },
    request: function(p, cb) { if (typeof cb === 'function') { cb(false); } return Promise.resolve(false); },
    remove: function(p, cb) { if (typeof cb === 'function') { cb(true); } return Promise.resolve(true); }
  },
  tabs: {
    query: function(q, cb) { if (typeof cb === 'function') { cb([]); } return Promise.resolve([]); },
    sendMessage: function(tabId, msg, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    create: function(props, cb) { if (typeof cb === 'function') { cb(undefined); } return Promise.resolve(undefined); },
    getCurrent: function(cb) { if (typeof cb === 'function') { cb(undefined); } return Promise.resolve(undefined); },
    onUpdated: { addListener: function() {} },
    onRemoved: { addListener: function() {} }
  },
  notifications: {
    create: function(id, opts, cb) {
      if (typeof id === 'function') { id(); return; }
      if (typeof cb === 'function') { cb(String(id || '')); }
      return Promise.resolve(String(id || ''));
    }
  },
  webRequest: {
    onBeforeRequest: { addListener: function() {} },
    onBeforeSendHeaders: { addListener: function() {} },
    onHeadersReceived: { addListener: function() {} }
  },
  contextMenus: {
    create: function() { return 1; },
    removeAll: function(cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); }
  },
  commands: { onCommand: { addListener: function() {} } },
  action: (function() {
    /* MV3 语义：均返回 Promise（AdGuard setIcon 链式 .then，undefined 即 TypeError）。
       setBadge* 维护 JS 侧缓存（getBadgeText 同构可读）并上报原生 extSetBadge 渲染角标；
       文本按 Chrome 规范截 4 字符，tabId>0 为 per-tab 覆盖，否则为默认文本 */
    var B = { defText: '', tabText: {}, bg: '', fg: '', title: '', popup: '' };
    function normColor(c) {
      try {
        if (Object.prototype.toString.call(c) === '[object Array]' && c.length >= 3) {
          var out = '#';
          for (var ci = 0; ci < 3; ci++) {
            var v = Math.max(0, Math.min(255, Math.round(Number(c[ci]) || 0)));
            var h = v.toString(16);
            out += h.length < 2 ? '0' + h : h;
          }
          return out;
        }
        if (typeof c === 'string') {
          var s = c.trim();
          if (s.charAt(0) === '#') {
            var hx = s.substring(1);
            if (hx.length === 3) {
              return '#' + hx.charAt(0) + hx.charAt(0) + hx.charAt(1) + hx.charAt(1) + hx.charAt(2) + hx.charAt(2);
            }
            if (hx.length >= 6) { return '#' + hx.substring(0, 6).toLowerCase(); }
          }
          var pi = s.indexOf('(');
          if (pi > 0 && s.indexOf(')') > pi && s.substring(0, pi).indexOf('rgb') === 0) {
            var ps = s.substring(pi + 1, s.indexOf(')', pi + 1)).split(',');
            if (ps.length >= 3) { return normColor([Number(ps[0]), Number(ps[1]), Number(ps[2])]); }
          }
        }
      } catch (e) {}
      return '';
    }
    return {
      setTitle: function(o, cb) {
        if (o && typeof o.title === 'string') { B.title = o.title; }
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      getTitle: function(o, cb) {
        var p = Promise.resolve(B.title || '');
        if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
        return p;
      },
      setIcon: function(o, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
      setBadgeText: function(o, cb) {
        try {
          var t = o && o.text !== undefined && o.text !== null ? String(o.text) : '';
          if (t.length > 4) { t = t.substring(0, 4); }
          var tid = o && typeof o.tabId === 'number' && o.tabId > 0 ? o.tabId : 0;
          if (tid > 0) { B.tabText[tid] = t; } else { B.defText = t; }
          CORE.natCall('extSetBadge', { extId: EXTID, tabId: tid, text: t, textOp: 1 });
        } catch (e) {}
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      getBadgeText: function(o, cb) {
        var t = '';
        try {
          var tid = o && typeof o.tabId === 'number' && o.tabId > 0 ? o.tabId : 0;
          t = tid > 0 ? (B.tabText[tid] || '') : (B.defText || '');
        } catch (e) {}
        var p = Promise.resolve(t);
        if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
        return p;
      },
      setBadgeBackgroundColor: function(o, cb) {
        try {
          var col = normColor(o && o.color);
          if (col !== '') { B.bg = col; CORE.natCall('extSetBadge', { extId: EXTID, bg: col }); }
        } catch (e) {}
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      setBadgeTextColor: function(o, cb) {
        try {
          var col = normColor(o && o.color);
          if (col !== '') { B.fg = col; CORE.natCall('extSetBadge', { extId: EXTID, fg: col }); }
        } catch (e) {}
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      setPopup: function(o, cb) {
        if (o && typeof o.popup === 'string') { B.popup = o.popup; }
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      getPopup: function(o, cb) {
        var p = Promise.resolve(B.popup || '');
        if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
        return p;
      },
      onClicked: { addListener: function() {} }
    };
  })(),
  declarativeNetRequest: {
    /* 真实 Chrome 数值语义：数组/计数 API 返回空集与上限余量，
       防止 AdGuard getEnabledRulesets().map 之类 undefined 崩
       （真机实证 getExtensionStatusForPopupMV3 链断裂 → popup 卡 loader） */
    MAX_NUMBER_OF_DYNAMIC_RULES: 30000,
    MAX_NUMBER_OF_REGEX_RULES: 1000,
    MAX_NUMBER_OF_SESSION_RULES: 5000,
    MAX_NUMBER_OF_UNSAFE_SESSION_RULES: 5000,
    MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES: 5000,
    MAX_NUMBER_OF_ENABLED_STATIC_RULESETS: 50,
    SESSION_RULESET_ID: '_session',
    DYNAMIC_RULESET_ID: '_dynamic',
    RuleActionType: { BLOCK: 'block', ALLOW: 'allow', ALLOW_ALL_REQUESTS: 'allowAllRequests', MODIFY_HEADERS: 'modifyHeaders', REDIRECT: 'redirect' },
    ResourceType: { MAIN_FRAME: 'main_frame', SUB_FRAME: 'sub_frame', STYLESHEET: 'stylesheet', SCRIPT: 'script', IMAGE: 'image', FONT: 'font', OBJECT: 'object', OBJECT_SUBREQUEST: 'object_subrequest', XMLHTTPREQUEST: 'xmlhttprequest', PING: 'ping', CSP_REPORT: 'csp_report', MEDIA: 'media', WEBSOCKET: 'websocket', WEBBUNDLE: 'webbundle', WEBTRANSPORT: 'webtransport', OTHER: 'other' },
    DomainType: { FIRST_PARTY: 'firstParty', THIRD_PARTY: 'thirdParty' },
    HeaderOperation: { SET: 'set', APPEND: 'append', REMOVE: 'remove' },
    getEnabledRulesets: function(cb) { var p = qhDnrRulesets(); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getDynamicRules: function(cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getSessionRules: function(cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getAvailableStaticRuleCount: function(cb) { var p = Promise.resolve(30000); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    updateDynamicRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    updateSessionRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    updateStaticRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    isRegexSupported: function(o, cb) { var p = Promise.resolve({ isSupported: true }); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getDisabledRuleIds: function(o, cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    setDynamicRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    setSessionRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    updateEnabledRulesets: function(opt, cb) { var p = qhDnrUpdateRulesets(opt); if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); } return p; },
    onRuleMatchedDebug: { addListener: function() {} }
  }
};
${ChromeShim.stubProxyJs()}
var chrome = chromeApiSafe;
var browser = chromeApiSafe;
/* window/globalThis 暴露：内容脚本经 UMD/globalThis 取 chrome 时拿不到 IIFE 局部变量
   （ArkWeb 无隔离世界，内容沙箱跑在页面主世界）。多扩展共用主世界 window.chrome，
   旧 first-wins 合并内建对象会让后注入扩展的 polyfill（globalThis.chrome 捕获）
   拿到先注入扩展的 runtime（真机实证 AdGuard assistant 监听器注册到 5bddc 名下、
   bg 派发 ls=-1）——改经 core 派发 getter，求值期间指向本扩展 API，
   polyfill 加载时同步捕获即锁定正确对象 */
try { CORE.setCurExt(chromeApiSafe); } catch (e) {}
try {
  if (window.chrome !== chromeApiSafe) {
    /* 派发 getter 未生效（内建属性不可配置等）：退回覆盖式合并（last-wins，
       保证每个沙箱求值期 polyfill 经 globalThis.chrome 捕获到本扩展 API） */
    var wc = window.chrome;
    if (wc && typeof wc === 'object') {
      for (var wck in chromeApi) {
        try { wc[wck] = chromeApi[wck]; } catch (e3) {}
      }
    } else {
      window.chrome = chromeApiSafe;
    }
    try { window.browser = chromeApiSafe; } catch (e4) {}
  }
} catch (e2) {}
try { if (window.__qhHud) { window.__qhHud.report(EXTID, 'ext: ${ExtensionShimUtil.escapeJs(resolvedName)}', 'content'); } } catch (e) {}
${cssCode}
${jsCode}
try { console.info('[qh ext] cs done ' + EXTID); } catch (e) {}
try { CORE.clearCurExt(); } catch (e) {}
}catch(e){ try { CORE.clearCurExt(); } catch (e2) {} console.warn('[qh ext]',e)}
})();
`;
  }

  /**
   * 生成扩展宿主页沙箱代码（background / service_worker / popup 共用）：
    * - background：运行于隐藏 Web（虚拟域 __bg__.html，https origin 使 IDB 可用）注入，onInstalled 每次宿主启动触发（安装语义）；
   * - popup：运行于扩展 popup 面板 Web，javaScriptOnDocumentStart 在页面脚本前注入；
   * runtime.onMessage 接收路由消息，chrome.storage/i18n 与 content 沙箱同源，
   * tabs 经 natCall 转发原生，alarms 为进程内 setTimeout 实现
   * @param extId 扩展 ID
   * @param manifestJson manifest.json 原文
   * @param resolvedName 已解析（i18n）扩展名
   * @param resolvedDesc 已解析描述
   * @param messagesJson i18n 消息表 JSON（小写键）
   * @param uiLocale UI 语言（default_locale）
   * @param scriptUrls 宿主脚本虚拟域 URL 列表（background 为 service_worker/scripts 文件；popup 传 []，由页面自身 HTML 加载脚本）
   * @param pageKind 'background' | 'popup'：决定 sendMessage 路由 API 与 onInstalled 触发
   */
  static buildHostSandbox(extId: string, manifestJson: string, resolvedName: string, resolvedDesc: string,
    messagesJson: string, uiLocale: string, scriptUrls: string[], pageKind: string): string {
    const sendApi: string = pageKind === 'popup' ? 'extSendMsgPopup' : 'extSendMsgBg'
    const onInstalledJs: string = pageKind === 'popup' ? '' : `
/* onInstalled/onStartup：Chrome 语义。onInstalled 仅安装时触发一次，
   以扩展自身 storage.local 的 __qhInstalled__ 标记持久化（KV 落盘）；
   之后每次宿主启动只触发 onStartup。若每次启动都发 onInstalled({reason:'install'})，
   部分扩展会反复判定新安装 → 每次冷启动都开欢迎页（真机实证）。 */
chrome.storage.local.get('__qhInstalled__', function(r) {
  if (r && r.__qhInstalled__) {
    for (var si = 0; si < onStartupLs.length; si++) {
      try { onStartupLs[si](); } catch (e) { console.warn('[qh ext] onStartup', e); }
    }
  } else {
    chrome.storage.local.set({ __qhInstalled__: 1 }, function() {});
    for (var oi = 0; oi < onInstalledLs.length; oi++) {
      try { onInstalledLs[oi]({ reason: 'install' }); } catch (e) { console.warn('[qh ext] onInstalled', e); }
    }
  }
});`
    /* importScripts shim（仅 bg）：sw.js 常为单行 importScripts('...')，
       而 script 标签上下文无 Worker 的 importScripts（真机实证 Grammarly sw.js:1
       ReferenceError → Grammarly-bg.js 从未加载 → popup↔bg RPC 全超时）。
       以同步 XHR + 间接 eval（全局作用域）等价实现；相对路径按 currentScript.src 解析 */
    const importScriptsJs: string = pageKind === 'popup' ? '' : `
window.importScripts = window.importScripts || function() {
  var base = '';
  try {
    base = (document.currentScript && document.currentScript.src) ? document.currentScript.src : location.href;
  } catch (e) { base = location.href; }
  for (var ii = 0; ii < arguments.length; ii++) {
    var u = String(arguments[ii]);
    if (u.indexOf('://') < 0) {
      if (u.indexOf('/') === 0) {
        var si = base.indexOf('://');
        if (si > 0) {
          var hs = base.indexOf('/', si + 3);
          u = (hs >= 0 ? base.substring(0, hs) : base) + u;
        }
      } else if (base) {
        var bi = base.lastIndexOf('/');
        if (bi >= 0) { u = base.substring(0, bi + 1) + u; }
      }
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', u, false);
      xhr.send(null);
      var code = xhr.responseText || '';
      if (code) { (0, eval)(code); }
    } catch (e) { console.warn('[qh ext] importScripts failed: ' + u, e); }
  }
};`
    return `(function(){
try{
var EXTID = ${JSON.stringify(extId)};
/* 扩展页宿主精确守卫：extPageScriptItems 的 scriptRules（协议前缀/模糊域）命中所有扩展页，
   仅在本扩展页面继续（scheme 页 host=extId；legacy 虚拟域子域 host=<extId>.<vhost>；
   旧路径格式 host=<vhost> 时按 pathname 前缀判定） */
var qhP = location.protocol || '';
var qhH = location.hostname || '';
var qhVsfx = '.${EXT_RES_HOST}';
if (qhP === '${EXT_SCHEME}:') {
  if (qhH !== EXTID) { return; }
} else if (qhH === '${EXT_RES_HOST}') {
  if ((location.pathname || '/').indexOf('/' + EXTID) !== 0) { return; }
} else if (qhH.substring(qhH.length - qhVsfx.length) === qhVsfx) {
  if (qhH !== EXTID + qhVsfx) { return; }
} else {
  /* 兜底：普通网页（含商店/第三方站点）不安装宿主沙箱。
     extPageScriptItems 的 scriptRules 为 '*'（scheme 规则真机实测不稳），
     普通页面若穿透会把 window.chrome/browser getter、fetch 覆盖整套装上，
     干扰页面自身脚本（真机实证 Edge Add-ons 改版后 React 客户端渲染进 #root 被干扰，
     中间空白、上下头 UHF 组件正常）。必须在此退出，仅留惰性 __qhExtCore */
  return;
}
var CORE = window.__qhExtCore;
if (!CORE) { console.warn('[qh ext] core missing'); return; }
var MANIFEST = ${manifestJson};
try { MANIFEST.name = ${JSON.stringify(resolvedName)}; MANIFEST.description = ${JSON.stringify(resolvedDesc)}; } catch (e) {}
var MSGS = ${messagesJson};
var UILOC = ${JSON.stringify(uiLocale)};
/* 未捕获异常/Promise 拒绝带堆栈上报：onConsole 只有 message 无法定位压缩代码，
   bg/popup 控制台经宿主转发到 hilog，配合扩展自带的 *.map 在 PC 侧还原源码位置 */
window.addEventListener('error', function (ev) {
  try {
    console.error('[qh jserr] ' + (ev.error && ev.error.stack ? ev.error.stack
      : (ev.message || '') + ' @ ' + (ev.filename || '') + ':' + (ev.lineno || 0) + ':' + (ev.colno || 0)));
  } catch (e) {}
});
window.addEventListener('unhandledrejection', function (ev) {
  try {
    var qhr = ev.reason;
    console.error('[qh jsrej] ' + (qhr && qhr.stack ? qhr.stack : String(qhr)));
  } catch (e) {}
});
var lastError = null;
var onMsgLs = [];
var onInstalledLs = [];
var onStartupLs = [];
var alarmLs = [];
/* tabs 事件注册表：chrome.tabs.onCreated/onUpdated/onActivated/onRemoved 监听器存储；
   原生侧经 window.__qhFireTabEvent(name, argsJson) 分发，参数为 Chrome 签名的 JSON 数组 */
var tabEv = { created: [], updated: [], activated: [], removed: [] };
function qhTabEvent(name) {
  return {
    addListener: function(fn) {
      if (typeof fn === 'function' && tabEv[name].indexOf(fn) < 0) { tabEv[name].push(fn); }
    },
    removeListener: function(fn) {
      var i = tabEv[name].indexOf(fn);
      if (i >= 0) { tabEv[name].splice(i, 1); }
    },
    hasListener: function(fn) { return tabEv[name].indexOf(fn) >= 0; }
  };
}
window.__qhFireTabEvent = function(name, argsJson) {
  var ls = tabEv[String(name)];
  if (!ls || !ls.length) { return; }
  var args = null;
  try { args = JSON.parse(argsJson); } catch (e) { args = null; }
  if (!args || !args.length) { return; }
  for (var i = 0; i < ls.length; i++) {
    try { ls[i].apply(null, args); } catch (e) { console.warn('[qh ext] tabs.' + name + ' listener', e); }
  }
};
/* 存量标签同步（会话恢复/宿主重挂的标签无 onCreated）：原生注入 __qhSyncTabs，
   轮询等待宿主脚本注册任一 tabs 事件监听器后按 onCreated 逐个补投（active 标签附 onActivated）；
   60s 仍无监听器则放弃（不使用 tabs 事件的扩展） */
var qhSyncQueue = [];
var qhSyncTimer = 0;
var qhSyncPolls = 0;
window.__qhSyncTabs = function(tabsJson) {
  try {
    var arr = JSON.parse(tabsJson);
    if (Object.prototype.toString.call(arr) === '[object Array]') {
      for (var si = 0; si < arr.length; si++) { qhSyncQueue.push(arr[si]); }
    }
  } catch (e) {}
  if (qhSyncTimer) { return; }
  qhSyncTimer = setInterval(function() {
    qhSyncPolls++;
    var hasLs = tabEv.created.length + tabEv.updated.length + tabEv.activated.length + tabEv.removed.length > 0;
    if (!hasLs && qhSyncPolls < 120) { return; }
    clearInterval(qhSyncTimer);
    qhSyncTimer = 0;
    var q = qhSyncQueue;
    qhSyncQueue = [];
    for (var qi = 0; qi < q.length; qi++) {
      window.__qhFireTabEvent('created', JSON.stringify([q[qi]]));
      if (q[qi] && q[qi].active === true) {
        window.__qhFireTabEvent('activated', JSON.stringify([{ tabId: q[qi].id, windowId: 1 }]));
      }
    }
  }, 500);
};
function getMessage(name, subs) {
  var e = MSGS[String(name == null ? '' : name).toLowerCase()];
  if (!e || typeof e.message !== 'string') { return ''; }
  var s = e.message;
  var subsArr = null;
  if (Object.prototype.toString.call(subs) === '[object Array]') { subsArr = subs; }
  else if (subs !== undefined && subs !== null) { subsArr = [subs]; }
  if (subsArr) {
    for (var si = 0; si < subsArr.length; si++) { s = s.split('$' + (si + 1) + '$').join(String(subsArr[si])); }
  }
  var ph = e.placeholders;
  if (ph) {
    for (var pk in ph) {
      var cont = ph[pk] && typeof ph[pk].content === 'string' ? ph[pk].content : '';
      var sub0 = subsArr && subsArr.length > 0 ? String(subsArr[0]) : '';
      s = s.split('$' + pk + '$').join(cont ? cont.split('$1$').join(sub0) : '');
    }
  }
  return s;
}
var runtimeApi = {
  id: EXTID,
  getManifest: function() { return JSON.parse(JSON.stringify(MANIFEST)); },
  getURL: function(p) { return '${EXT_SCHEME_PREFIX}' + EXTID + '/' + String(p == null ? '' : p).replace(/^\\/+/, ''); },
  getPlatformInfo: function(cb) {
    /* 桌面语义（os=win）：AdGuard getUserAgent 直接解构 platformInfo.os（undefined 崩）；
       同时 getIsAndroid 保持 false，popup 维持桌面布局（真机实证可用状态） */
    var info = { os: 'win', arch: 'x86-32', nacl_arch: 'x86-32', platform: 'win' };
    var p = Promise.resolve(info);
    if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
    return p;
  },
  sendMessage: function() {
    var args = Array.prototype.slice.call(arguments);
    var i = 0;
    if (typeof args[i] === 'string') { i++; }
    var msg = args[i]; i++;
    var cb = null;
    while (i < args.length) { if (typeof args[i] === 'function') { cb = args[i]; } i++; }
    var msgJson = 'null';
    try { msgJson = JSON.stringify(msg === undefined ? null : msg); } catch (e) { msgJson = 'null'; }
    var resolveP;
    var p = cb ? null : new Promise(function(res) { resolveP = res; });
    var id = CORE.reg(function(err, resp) {
      if (resolveP) { resolveP(resp); }
      if (cb) { try { cb(resp); } catch (e) { console.warn('[qh ext] sendMessage callback', e); } }
    });
    CORE.natCall('${sendApi}', { extId: EXTID, cbId: id, msgJson: msgJson, page: String(location.pathname || '') });
    return p;
  },
  onMessage: {
    addListener: function(fn) { onMsgLs.push(fn); CORE.addMsgListener(EXTID, fn); },
    removeListener: function(fn) {
      var ix = onMsgLs.indexOf(fn);
      if (ix >= 0) { onMsgLs.splice(ix, 1); }
    },
    hasListener: function(fn) { return onMsgLs.indexOf(fn) >= 0; }
  },
  onInstalled: { addListener: function(fn) { onInstalledLs.push(fn); } },
  onStartup: { addListener: function(fn) { if (typeof fn === 'function' && onStartupLs.indexOf(fn) < 0) { onStartupLs.push(fn); } } },
  connect: function(opt) {
    var nm = '';
    try { nm = String((opt || {}).name == null ? '' : (opt || {}).name); } catch (e) { nm = ''; }
    return CORE.connectPort(EXTID, nm, location.href, location.origin);
  },
  onConnect: {
    addListener: function(fn) { CORE.addPortConnectListener(fn); },
    removeListener: function(fn) { CORE.removePortConnectListener(fn); },
    hasListener: function() { return false; }
  },
  /* MV3 chrome.runtime.getContexts：返回存活的扩展上下文（BACKGROUND/POPUP）。
     不可走 stub 代理——stub 可调用但决议 undefined，Bitwarden isPopupOpen 对其
     yield 后 .some 崩 → bg 初始化链断裂 → popup 永卡 logo（真机实证） */
  getContexts: function(filter, cb) {
    var f = (filter && typeof filter === 'object') ? filter : null;
    var p = new Promise(function(res) {
      var id = CORE.reg(function(err, list) {
        res(Array.isArray(list) ? list : []);
      });
      CORE.natCall('extGetContexts', { extId: EXTID, cbId: id });
    }).then(function(list) {
      var types = (f && Array.isArray(f.contextTypes)) ? f.contextTypes : null;
      if (types && types.length) {
        return list.filter(function(c) { return c && types.indexOf(c.contextType) >= 0; });
      }
      return list;
    });
    if (typeof cb === 'function') {
      p.then(function(v) { try { cb(v); } catch (e) {} });
    }
    return p;
  },
  setLastError: function(m) { lastError = m; }
};
Object.defineProperty(runtimeApi, 'lastError', {
  get: function() { return lastError; },
  configurable: true
});
function mkArea() {
  return {
    QUOTA_BYTES: 10485760,
    get: function(keys, cb) {
      var kj = 'null';
      if (keys !== undefined && keys !== null) { try { kj = JSON.stringify(keys); } catch (e) { kj = 'null'; } }
      var p = new Promise(function(res) {
        CORE.storageGet(EXTID, kj, function(err, items) { res(items || {}); });
      });
      if (typeof cb === 'function') { p.then(function(items) { try { cb(items); } catch (e) {} }); }
      return p;
    },
    set: function(items, cb) {
      var ij = '{}';
      try { ij = JSON.stringify(items || {}); } catch (e) { ij = '{}'; }
      var p = new Promise(function(res) {
        CORE.storageSet(EXTID, ij, function() { res(); });
      });
      if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); }
      return p;
    },
    remove: function(keys, cb) {
      var kj = 'null';
      if (keys !== undefined && keys !== null) { try { kj = JSON.stringify(keys); } catch (e) { kj = 'null'; } }
      var p = new Promise(function(res) {
        CORE.storageRemove(EXTID, kj, function() { res(); });
      });
      if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); }
      return p;
    },
    clear: function(cb) {
      var p = new Promise(function(res) {
        CORE.storageClear(EXTID, function() { res(); });
      });
      if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); }
      return p;
    },
    getBytesInUse: function(keys, cb) {
      if (typeof cb === 'function') { cb(0); }
      return Promise.resolve(0);
    },
    getKeys: function(cb) {
      var p = new Promise(function(res) {
        CORE.storageGet(EXTID, 'null', function(err, items) {
          var ks = [];
          try { ks = Object.keys(items || {}); } catch (e) { ks = []; }
          res(ks);
        });
      });
      if (typeof cb === 'function') { p.then(function(ks) { try { cb(ks); } catch (e) {} }); }
      return p;
    },
    onChanged: { addListener: function(fn) { CORE.addChgListener(EXTID, fn); }, removeListener: function(fn) {} },
    /* MV3：Grammarly bg 在 allowCStoUseSessionStorage 里依赖回调式 setAccessLevel，
       缺失时 fc.create 永不 resolve → bg init 挂死（60s 超时）。必须同步回调 + 返回 Promise */
    setAccessLevel: function(o, cb) {
      if (typeof cb === 'function') { try { cb(); } catch (e) {} }
      return Promise.resolve();
    }
  };
}
${ChromeShim.dnrRulesetsJs()}
var chromeApi = {
  runtime: runtimeApi,
  i18n: {
    getMessage: getMessage,
    getUILanguage: function() { return UILOC; },
    getAcceptLanguages: function(cb) {
      if (typeof cb === 'function') { cb([UILOC]); }
      return Promise.resolve([UILOC]);
    }
  },
  cookies: {
    get: function(d, cb) { if (typeof cb === 'function') { cb(null); } return Promise.resolve(null); },
    getAll: function(d, cb) { if (typeof cb === 'function') { cb([]); } return Promise.resolve([]); },
    set: function(d, cb) { if (typeof cb === 'function') { cb(null); } return Promise.resolve(null); },
    remove: function(d, cb) { if (typeof cb === 'function') { cb(null); } return Promise.resolve(null); },
    onChanged: { addListener: function(fn) {}, removeListener: function(fn) {} }
  },
  storage: {
    local: mkArea(),
    sync: mkArea(),
    session: mkArea(),
    managed: mkArea(),
    onChanged: { addListener: function(fn) { CORE.addChgListener(EXTID, fn); }, removeListener: function(fn) {} }
  },
  extension: {
    getURL: runtimeApi.getURL,
    getManifest: runtimeApi.getManifest,
    inIncognitoContext: false
  },
  permissions: {
    contains: function(p, cb) { if (typeof cb === 'function') { cb(false); } return Promise.resolve(false); },
    request: function(p, cb) { if (typeof cb === 'function') { cb(false); } return Promise.resolve(false); },
    remove: function(p, cb) { if (typeof cb === 'function') { cb(true); } return Promise.resolve(true); }
  },
  tabs: {
    TAB_ID_NONE: -1,
    query: function(q, cb) {
      var kj = '{}';
      try { kj = JSON.stringify(q || {}); } catch (e) { kj = '{}'; }
      var p = new Promise(function(res) {
        var id = CORE.reg(function(err, tabs) { res(tabs || []); });
        CORE.natCall('extTabQuery', { extId: EXTID, cbId: id, queryJson: kj });
      });
      if (typeof cb === 'function') { p.then(function(tabs) { try { cb(tabs); } catch (e) {} }); }
      return p;
    },
    sendMessage: function(tabId) {
      var args = Array.prototype.slice.call(arguments);
      var msg = args[1];
      var cb = null;
      for (var i = 2; i < args.length; i++) { if (typeof args[i] === 'function') { cb = args[i]; } }
      var msgJson = 'null';
      try { msgJson = JSON.stringify(msg === undefined ? null : msg); } catch (e) { msgJson = 'null'; }
      var id = cb ? CORE.reg(cb) : 0;
      CORE.natCall('extTabSendMsg', { extId: EXTID, cbId: id, tabId: Number(tabId) || 0, msgJson: msgJson });
    },
    create: function(props, cb) {
      var url = '';
      try { url = String((props || {}).url || ''); } catch (e) { url = ''; }
      var id = cb ? CORE.reg(function(err, t) { try { cb(t); } catch (e) {} }) : 0;
      CORE.natCall('extTabCreate', { cbId: id, url: url });
    },
    update: function(tabId, props, cb) {
      var url = '';
      var active = 0;
      try {
        url = String((props || {}).url || '');
        active = (props || {}).active === true ? 1 : 0;
      } catch (e) { url = ''; active = 0; }
      var p = new Promise(function(res) {
        var id = CORE.reg(function(err, t) { res(t || null); });
        CORE.natCall('extTabUpdate', { cbId: id, tabId: Number(tabId) || 0, url: url, active: active });
      });
      if (typeof cb === 'function') { p.then(function(t) { try { cb(t); } catch (e) {} }); }
      return p;
    },
    get: function(tabId, cb) { if (typeof cb === 'function') { cb(undefined); } return Promise.resolve(undefined); },
    getCurrent: function(cb) { if (typeof cb === 'function') { cb(undefined); } return Promise.resolve(undefined); },
    onCreated: qhTabEvent('created'),
    onUpdated: qhTabEvent('updated'),
    onActivated: qhTabEvent('activated'),
    onRemoved: qhTabEvent('removed')
  },
  alarms: {
    create: function(name, info) {
      if (typeof name === 'object' && name !== null) { info = name; name = ''; }
      name = String(name == null ? '' : name);
      info = info || {};
      var delay = 0;
      if (info.when) { delay = info.when - Date.now(); }
      else if (info.delayInMinutes != null) { delay = info.delayInMinutes * 60000; }
      else if (info.periodInMinutes != null) { delay = info.periodInMinutes * 60000; }
      if (delay < 0) { delay = 0; }
      setTimeout(function() {
        var a = { name: name, scheduledTime: Date.now() };
        for (var i = 0; i < alarmLs.length; i++) { try { alarmLs[i](a); } catch (e) { console.warn('[qh ext] onAlarm', e); } }
      }, delay);
    },
    clear: function(name, cb) { if (typeof cb === 'function') { cb(true); } return Promise.resolve(true); },
    clearAll: function(cb) { if (typeof cb === 'function') { cb(true); } return Promise.resolve(true); },
    getAll: function(cb) { if (typeof cb === 'function') { cb([]); } return Promise.resolve([]); },
    onAlarm: { addListener: function(fn) { alarmLs.push(fn); }, removeListener: function(fn) {} }
  },
  notifications: {
    create: function(id, opts, cb) {
      if (typeof id === 'function') { id(); return; }
      var title = '';
      var msg = '';
      try { title = String((opts || {}).title || ''); msg = String((opts || {}).message || ''); } catch (e) {}
      CORE.natCall('extNotify', { text: (title ? title + ': ' : '') + msg });
      if (typeof cb === 'function') { cb(String(id || '')); }
      return Promise.resolve(String(id || ''));
    }
  },
  scripting: {
    /* 真实语义：数组 API 返回 []（AdGuard removeContentScript 对
       getRegisteredContentScripts() 结果取 .length，undefined 即 TypeError 断链） */
    getRegisteredContentScripts: function(filter, cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    registerContentScripts: function(scripts, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    unregisterContentScripts: function(filter, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    updateContentScripts: function(scripts, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    /* files 变体经 natCall 转发原生（读扩展文件注入目标标签）；
       func 变体（函数序列化，KeepAlive 保活注入）不支持，静默成功返回 [] */
    executeScript: function(inj, cb) {
      inj = inj || {};
      var files = inj.files;
      if (Object.prototype.toString.call(files) !== '[object Array]' || !files.length) {
        var p0 = Promise.resolve([]);
        if (typeof cb === 'function') { p0.then(function(v) { try { cb(v); } catch (e) {} }); }
        return p0;
      }
      var tabId = 0;
      try { tabId = Number((inj.target || {}).tabId) || 0; } catch (e) { tabId = 0; }
      var fj = '[]';
      try { fj = JSON.stringify(files); } catch (e) { fj = '[]'; }
      var resolveP;
      var p = new Promise(function(res) { resolveP = res; });
      var id = CORE.reg(function(err, results) {
        if (err) {
          try { runtimeApi.setLastError({ message: String(err) }); } catch (e2) {}
        }
        resolveP(!err && Object.prototype.toString.call(results) === '[object Array]' ? results : []);
      });
      CORE.natCall('extExecuteScript', { extId: EXTID, cbId: id, tabId: tabId, filesJson: fj });
      if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
      return p;
    },
    insertCSS: function(inj, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    removeCSS: function(inj, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); }
  },
  userScripts: {
    configure: function(opt, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    register: function(scripts, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    update: function(scripts, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    unregister: function(filter, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    resetConfig: function(cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    getScripts: function(filter, cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    execute: function(script, cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    WORLD_MAIN: 'MAIN',
    WORLD_USER_SCRIPT: 'USER_SCRIPT'
  },
  webNavigation: {
    getAllFrames: function(details, cb) { var c = typeof details === 'function' ? details : cb; var p = Promise.resolve([]); if (typeof c === 'function') { p.then(function(v) { try { c(v); } catch (e) {} }); } return p; },
    getFrame: function(details, cb) { var c = typeof details === 'function' ? details : cb; var p = Promise.resolve(undefined); if (typeof c === 'function') { p.then(function(v) { try { c(v); } catch (e) {} }); } return p; },
    onBeforeNavigate: { addListener: function() {} },
    onCommitted: { addListener: function() {} },
    onDOMContentLoaded: { addListener: function() {} },
    onCompleted: { addListener: function() {} },
    onErrorOccurred: { addListener: function() {} },
    onHistoryStateUpdated: { addListener: function() {} },
    onReferenceFragmentUpdated: { addListener: function() {} },
    onCreatedNavigationTarget: { addListener: function() {} },
    onTabReplaced: { addListener: function() {} }
  },
  windows: {
    WINDOW_ID_NONE: -1,
    WINDOW_ID_CURRENT: -2,
    getCurrent: function(q, cb) {
      var c = typeof q === 'function' ? q : cb;
      var w = { id: 1, focused: true, incognito: false, type: 'normal', state: 'normal', alwaysOnTop: false };
      if (typeof c === 'function') { try { c(w); } catch (e) {} }
      return Promise.resolve(w);
    },
    getLastFocused: function(q, cb) {
      var c = typeof q === 'function' ? q : cb;
      var w = { id: 1, focused: true, incognito: false, type: 'normal', state: 'normal', alwaysOnTop: false };
      if (typeof c === 'function') { try { c(w); } catch (e) {} }
      return Promise.resolve(w);
    },
    getAll: function(q, cb) {
      var c = typeof q === 'function' ? q : cb;
      var arr = [{ id: 1, focused: true, incognito: false, type: 'normal', state: 'normal', alwaysOnTop: false }];
      if (typeof c === 'function') { try { c(arr); } catch (e) {} }
      return Promise.resolve(arr);
    },
    onFocusChanged: { addListener: function() {} },
    onCreated: { addListener: function() {} },
    onRemoved: { addListener: function() {} }
  },
  webRequest: {
    onBeforeRequest: { addListener: function() {} },
    onBeforeSendHeaders: { addListener: function() {} },
    onHeadersReceived: { addListener: function() {} }
  },
  contextMenus: {
    create: function() { return 1; },
    removeAll: function(cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); }
  },
  commands: { onCommand: { addListener: function() {} } },
  action: (function() {
    /* MV3 语义：均返回 Promise（AdGuard setIcon 链式 .then，undefined 即 TypeError）。
       setBadge* 维护 JS 侧缓存（getBadgeText 同构可读）并上报原生 extSetBadge 渲染角标；
       文本按 Chrome 规范截 4 字符，tabId>0 为 per-tab 覆盖，否则为默认文本 */
    var B = { defText: '', tabText: {}, bg: '', fg: '', title: '', popup: '' };
    function normColor(c) {
      try {
        if (Object.prototype.toString.call(c) === '[object Array]' && c.length >= 3) {
          var out = '#';
          for (var ci = 0; ci < 3; ci++) {
            var v = Math.max(0, Math.min(255, Math.round(Number(c[ci]) || 0)));
            var h = v.toString(16);
            out += h.length < 2 ? '0' + h : h;
          }
          return out;
        }
        if (typeof c === 'string') {
          var s = c.trim();
          if (s.charAt(0) === '#') {
            var hx = s.substring(1);
            if (hx.length === 3) {
              return '#' + hx.charAt(0) + hx.charAt(0) + hx.charAt(1) + hx.charAt(1) + hx.charAt(2) + hx.charAt(2);
            }
            if (hx.length >= 6) { return '#' + hx.substring(0, 6).toLowerCase(); }
          }
          var pi = s.indexOf('(');
          if (pi > 0 && s.indexOf(')') > pi && s.substring(0, pi).indexOf('rgb') === 0) {
            var ps = s.substring(pi + 1, s.indexOf(')', pi + 1)).split(',');
            if (ps.length >= 3) { return normColor([Number(ps[0]), Number(ps[1]), Number(ps[2])]); }
          }
        }
      } catch (e) {}
      return '';
    }
    return {
      setTitle: function(o, cb) {
        if (o && typeof o.title === 'string') { B.title = o.title; }
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      getTitle: function(o, cb) {
        var p = Promise.resolve(B.title || '');
        if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
        return p;
      },
      setIcon: function(o, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
      setBadgeText: function(o, cb) {
        try {
          var t = o && o.text !== undefined && o.text !== null ? String(o.text) : '';
          if (t.length > 4) { t = t.substring(0, 4); }
          var tid = o && typeof o.tabId === 'number' && o.tabId > 0 ? o.tabId : 0;
          if (tid > 0) { B.tabText[tid] = t; } else { B.defText = t; }
          CORE.natCall('extSetBadge', { extId: EXTID, tabId: tid, text: t, textOp: 1 });
        } catch (e) {}
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      getBadgeText: function(o, cb) {
        var t = '';
        try {
          var tid = o && typeof o.tabId === 'number' && o.tabId > 0 ? o.tabId : 0;
          t = tid > 0 ? (B.tabText[tid] || '') : (B.defText || '');
        } catch (e) {}
        var p = Promise.resolve(t);
        if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
        return p;
      },
      setBadgeBackgroundColor: function(o, cb) {
        try {
          var col = normColor(o && o.color);
          if (col !== '') { B.bg = col; CORE.natCall('extSetBadge', { extId: EXTID, bg: col }); }
        } catch (e) {}
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      setBadgeTextColor: function(o, cb) {
        try {
          var col = normColor(o && o.color);
          if (col !== '') { B.fg = col; CORE.natCall('extSetBadge', { extId: EXTID, fg: col }); }
        } catch (e) {}
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      setPopup: function(o, cb) {
        if (o && typeof o.popup === 'string') { B.popup = o.popup; }
        if (typeof cb === 'function') { cb(); }
        return Promise.resolve();
      },
      getPopup: function(o, cb) {
        var p = Promise.resolve(B.popup || '');
        if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); }
        return p;
      },
      onClicked: { addListener: function() {} }
    };
  })(),
  declarativeNetRequest: {
    /* 真实 Chrome 数值语义：数组/计数 API 返回空集与上限余量，
       防止 AdGuard getEnabledRulesets().map 之类 undefined 崩
       （真机实证 getExtensionStatusForPopupMV3 链断裂 → popup 卡 loader） */
    MAX_NUMBER_OF_DYNAMIC_RULES: 30000,
    MAX_NUMBER_OF_REGEX_RULES: 1000,
    MAX_NUMBER_OF_SESSION_RULES: 5000,
    MAX_NUMBER_OF_UNSAFE_SESSION_RULES: 5000,
    MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES: 5000,
    MAX_NUMBER_OF_ENABLED_STATIC_RULESETS: 50,
    SESSION_RULESET_ID: '_session',
    DYNAMIC_RULESET_ID: '_dynamic',
    RuleActionType: { BLOCK: 'block', ALLOW: 'allow', ALLOW_ALL_REQUESTS: 'allowAllRequests', MODIFY_HEADERS: 'modifyHeaders', REDIRECT: 'redirect' },
    ResourceType: { MAIN_FRAME: 'main_frame', SUB_FRAME: 'sub_frame', STYLESHEET: 'stylesheet', SCRIPT: 'script', IMAGE: 'image', FONT: 'font', OBJECT: 'object', OBJECT_SUBREQUEST: 'object_subrequest', XMLHTTPREQUEST: 'xmlhttprequest', PING: 'ping', CSP_REPORT: 'csp_report', MEDIA: 'media', WEBSOCKET: 'websocket', WEBBUNDLE: 'webbundle', WEBTRANSPORT: 'webtransport', OTHER: 'other' },
    DomainType: { FIRST_PARTY: 'firstParty', THIRD_PARTY: 'thirdParty' },
    HeaderOperation: { SET: 'set', APPEND: 'append', REMOVE: 'remove' },
    getEnabledRulesets: function(cb) { var p = qhDnrRulesets(); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getDynamicRules: function(cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getSessionRules: function(cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getAvailableStaticRuleCount: function(cb) { var p = Promise.resolve(30000); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    updateDynamicRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    updateSessionRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    updateStaticRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    isRegexSupported: function(o, cb) { var p = Promise.resolve({ isSupported: true }); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    getDisabledRuleIds: function(o, cb) { var p = Promise.resolve([]); if (typeof cb === 'function') { p.then(function(v) { try { cb(v); } catch (e) {} }); } return p; },
    setDynamicRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    setSessionRules: function(rule, cb) { if (typeof cb === 'function') { cb(); } return Promise.resolve(); },
    updateEnabledRulesets: function(opt, cb) { var p = qhDnrUpdateRulesets(opt); if (typeof cb === 'function') { p.then(function() { try { cb(); } catch (e) {} }); } return p; },
    onRuleMatchedDebug: { addListener: function() {} }
  }
};
${ChromeShim.stubProxyJs()}
var chrome = chromeApiSafe;
var browser = chromeApiSafe;
/* 全局暴露：宿主脚本（script 标签加载，全局作用域执行）与 popup 页面脚本
   均须经 window 才可见；ArkWeb 普通页面内建 window.chrome 无 runtime 成员，
   此处 getter 覆盖（configurable 留兜底） */
try {
  Object.defineProperty(window, 'chrome', { get: function() { return chromeApiSafe; }, configurable: true });
} catch (e) { try { window.chrome = chromeApiSafe; } catch (e2) {} }
try {
  Object.defineProperty(window, 'browser', { get: function() { return chromeApiSafe; }, configurable: true });
} catch (e) { try { window.browser = chromeApiSafe; } catch (e2) {} }
/* window.close 接线（Chrome 扩展页语义）：popup 中关闭面板（handlePopupRequest）、
   扩展页标签关标签（TabWeb）；bg 宿主收到仅忽略 */
try {
  window.close = function() {
    try { CORE.natCall('extWindowClose', { extId: EXTID }); } catch (e) {}
  };
} catch (e) {}
/* fetch 超时保护（60s 无响应头即按网络错误中止）：
   bg 后端请求（filters.adtidy.org 等）在不可达网络上会无限 pending，
   阻断 AdGuard 首装链（initDefaultFilters 挂起 → postSuccessInstall 不执行 →
   app-version 不落库 → 每次启动都当首装 → 反复打开 post-install 页卡 logo）。
   超时按网络错误语义 reject，让扩展走自身回退（AdGuard 回退 CRX 内置 filter 副本）。
   虚拟域/chrome-extension://（本地资源）与已带 signal 的请求不接管；
   竞速仅覆盖"到响应头"阶段，响应头到达后正文传输不受限。 */
(function() {
  var QH_FETCH_TIMEOUT_MS = 60000;
  var origFetch = window.fetch;
  if (typeof origFetch !== 'function') { return; }
  window.fetch = function(input, init) {
    var url = '';
    try { url = typeof input === 'string' ? input : ((input && input.url) || String(input)); } catch (e) { url = ''; }
    if (url.indexOf('.${EXT_RES_HOST}/') !== -1 || url.indexOf('chrome-extension://') === 0
        || url.indexOf('${EXT_SCHEME_PREFIX}') === 0
        || (init && init.signal)) {
      return origFetch.apply(window, arguments);
    }
    var ctl = null;
    try { ctl = new AbortController(); } catch (e) { ctl = null; }
    if (ctl === null) { return origFetch.apply(window, arguments); }
    var myInit = {};
    try { for (var fk in (init || {})) { myInit[fk] = init[fk]; } } catch (e) {}
    myInit.signal = ctl.signal;
    var timer = setTimeout(function() {
      try { ctl.abort(); } catch (e) {}
      console.warn('[qh ext] fetch 超时中止: ' + url);
    }, QH_FETCH_TIMEOUT_MS);
    return origFetch.call(window, input, myInit).then(
      function(resp) { clearTimeout(timer); return resp; },
      function(err) { clearTimeout(timer); throw err; }
    );
  };
})();
/* 宿主脚本经虚拟域 script 标签加载（async=false 保证多文件按序执行，亦绕开
   runJavaScript/文件读取大小限制）；全部加载完成后触发 onInstalled（安装语义） */
${importScriptsJs}
var QH_FILES = ${JSON.stringify(scriptUrls)};
var QH_LOADED = 0;
function qhFireInstalled() {
${onInstalledJs}
}
if (QH_FILES.length === 0) {
  qhFireInstalled();
} else {
  for (var qfi = 0; qfi < QH_FILES.length; qfi++) {
    var qsc = document.createElement('script');
    qsc.async = false;
    qsc.onload = function() {
      QH_LOADED++;
      if (QH_LOADED >= QH_FILES.length) { qhFireInstalled(); }
    };
    qsc.onerror = function(e) {
      console.warn('[qh ext] host script load failed', e && e.target && e.target.src);
      QH_LOADED++;
      if (QH_LOADED >= QH_FILES.length) { qhFireInstalled(); }
    };
    qsc.src = QH_FILES[qfi];
    (document.head || document.documentElement).appendChild(qsc);
  }
}
}catch(e){console.warn('[qh ext]',e)}
})();
`;
  }

  /**
   * Edge 商店「设备不符/不兼容」状态行隐藏：
   * 站点经 navigator.userAgentData.brands 检测非 Edge（UA-CH 无法随 UA 串伪造），
   * 该状态行对直装流程无意义（安装走原生浮层按钮），注入样式直接隐藏
   */
  static buildEdgeBannerHideJs(): string {
    return `(function(){
if (window.__qhEdgeBannerHidden) { return; }
window.__qhEdgeBannerHidden = true;
var s = document.createElement('style');
s.textContent = '.incompatible{display:none!important}';
(document.head || document.documentElement).appendChild(s);
})();
`;
  }

  /**
   * 商店直装浮层（Chrome Web Store / Edge Add-ons）：
   * SPA 感知——轮询 location，详情页（/detail/）显示悬浮安装按钮，其余隐藏；
   * 点击经 __qhNative.gmRequest('extStoreInstall') 触发原生 CRX 下载安装；
   * 当前详情页扩展已安装（__qhNative.getInstalledExtIds 同步拉取，5 秒缓存）时浮层隐藏
   * @param label 按钮文案
   * @param showCheckJs 浮层显示条件 JS 表达式（默认 'true'；Edge 传 '!window.__qhEdgeGetOk'
   *  ——原位替换"获取"按钮成功时浮层退场，仅替换失败兜底显示）
   */
  static buildStoreInstallJs(label: string, showCheckJs: string = 'true'): string {
    return `(function(){
if (window.__qhStoreHook) { return; }
window.__qhStoreHook = true;
var LABEL = ${JSON.stringify(label)};
var BTN_ID = '__qh_store_install';
var busy = false;
var idSet = null;
var idSetAt = 0;
function isDetail() {
  return /\\/detail\\//.test(location.pathname);
}
function getIdSet() {
  var now = Date.now();
  if (idSet && now - idSetAt < 5000) { return idSet; }
  try {
    var n = window.__qhNative;
    var raw = n ? n.getInstalledExtIds() : null;
    idSet = {};
    if (raw) {
      var arr = JSON.parse(raw);
      for (var i = 0; i < arr.length; i++) { idSet[arr[i]] = 1; }
    }
    idSetAt = now;
  } catch (e) { idSet = null; idSetAt = now; }
  return idSet;
}
function extIdOf(url) {
  var m = /([a-p]{32})(?![a-p0-9])/i.exec(url || '');
  return m ? m[1].toLowerCase() : null;
}
function installedHere() {
  var set = getIdSet();
  if (!set) { return false; }
  var id = extIdOf(location.href);
  return id !== null && set[id] === 1;
}
function onInstall() {
  if (busy) { return; }
  busy = true;
  var btn = document.getElementById(BTN_ID);
  if (btn) { btn.textContent = '...'; }
  setTimeout(function() {
    busy = false;
    var b = document.getElementById(BTN_ID);
    if (b) { b.textContent = LABEL; }
  }, 4000);
  try {
    var n = window.__qhNative;
    if (n && n.gmRequest) { n.gmRequest('extStoreInstall', JSON.stringify({ url: location.href })); }
  } catch (e) { console.warn('[qh store] install', e); }
}
function tick() {
  var b = document.getElementById(BTN_ID);
  if (!isDetail()) {
    if (b) { b.style.display = 'none'; }
    return;
  }
  if (!b) {
    b = document.createElement('button');
    b.id = BTN_ID;
    b.type = 'button';
    b.textContent = LABEL;
    b.style.cssText = 'position:fixed;right:16px;bottom:96px;z-index:2147483647;'
      + 'padding:12px 20px;border:none;border-radius:24px;background:#0a7cff;color:#fff;'
      + 'font-size:14px;font-weight:600;line-height:1;box-shadow:0 4px 16px rgba(0,0,0,0.35);'
      + 'cursor:pointer;outline:none;';
    b.addEventListener('click', onInstall);
    document.documentElement.appendChild(b);
  }
  b.style.display = ((${showCheckJs}) && !installedHere()) ? 'block' : 'none';
}
setInterval(tick, 600);
tick();
})();
`;
  }

  /**
   * crxsoso.com「安装到浏览器」按钮接管（无自注入按钮，复用页面原生按钮）：
   * 站点是 Chrome/Edge 扩展聚合索引（Nuxt 2 SPA），详情页原生「安装到浏览器」按钮
   * （href = api.crxsoso.com /edge/dlink 返回的 CRX 下载链）点击本会触发浏览器下载——
   * 改为拦截接管，转原生直装（extStoreInstall → installFromUrl）：
   * - document 捕获阶段全局监听（常驻，SPA 路由切换无需重挂），命中主安装按钮
   *   （a[href][download] 且类名 download-action-online 或按钮文字「安装到浏览器」——
   *   桌面版锚点类名 download-action-online，移动版锚点仅 flex-fill-block 靠文字识别）
   *   即 preventDefault（阻断下载）+ stopPropagation（先于站点 Vue 根节点合成点击）；
   * - 双重守卫：hostname 须为 crxsoso.com（document-start 全站注入时自守卫）+
   *   详情页路由 /addon/detail/（Edge）、/webstore/detail/（Chrome）；
   *   /firefox/detail/（XPI 不支持）放行原生行为；
   * - 其他下载锚点（离线包/历史版本弹窗内 crx/zip 链接）不接管：放行原生下载
   *   → 下载确认弹窗（.crx 自带「安装」选项，两条路径都可达安装）；
   * - 安装 URL 恒用锚点自身 href（站点 dlink，国内可达镜像；官方商店链路
   *   clients2.google.com 国内不可直连，不可用作首选）；路径 32 位扩展 ID 作
   *   extId 提示一并传递（扩展 ID 稳定、可覆盖安装；slug 无 ID 由 CRX/ZIP 内容决定）；
   * - href 未就绪不拦截；4 秒 busy 防重复触发；
   * - 注入时机：document-start（PC 布局广告资源重，onPageEnd/window.load 可能晚于
   *   dlink 就绪与用户点击，须监听先于按钮可用；onPageEnd 注入经 __qhCrxsosoHook 幂等兜底）
   */
  static buildCrxsosoInstallJs(): string {
    return `(function(){
if (window.__qhCrxsosoHook) { return; }
window.__qhCrxsosoHook = true;
function supported() {
  if (!/(^|\\.)crxsoso\\.com$/i.test(location.hostname)) { return false; }
  return /^\\/(addon|webstore)\\/detail\\//.test(location.pathname);
}
function crxIdOfPath() {
  var segs = location.pathname.split('/');
  for (var i = segs.length - 1; i >= 0; i--) {
    if (/^[a-p]{32}$/i.test(segs[i])) { return segs[i].toLowerCase(); }
  }
  return '';
}
function isOnlineBtn(a) {
  if ((a.className || '').indexOf('download-action-online') >= 0) { return true; }
  return (a.textContent || '').replace(/\\s+/g, '').indexOf('安装到浏览器') >= 0;
}
function onCapture(ev) {
  if (!supported()) { return; }
  var t = ev.target;
  var a = (t && t.closest) ? t.closest('a[href][download]') : null;
  if (!a || !a.getAttribute('href')) { return; }
  if (!isOnlineBtn(a)) { return; }
  ev.preventDefault();
  ev.stopPropagation();
  if (a.__qhBusy) { return; }
  var url = a.href || '';
  if (!url) { return; }
  a.__qhBusy = true;
  setTimeout(function() { a.__qhBusy = false; }, 4000);
  try {
    var n = window.__qhNative;
    if (n && n.gmRequest) {
      n.gmRequest('extStoreInstall', JSON.stringify({ url: url, extId: crxIdOfPath() }));
    }
  } catch (e) { console.warn('[qh crxsoso] install', e); }
}
document.addEventListener('click', onCapture, true);
})();
`;
  }

  /**
   * Chrome Web Store「添加至Chrome」按钮原位接管（替代右下角浮层）：
   * 新版 CWS（chromewebstore.google.com，WizJS SPA）详情页原生安装按钮在非 Chrome 浏览器
   * 点击无响应——捕获阶段拦截 + 文案改写为「安装」，转原生直装（extStoreInstall →
   * installFromUrl，官方 clients2.google.com CRX 链路）。关键点：
   * - 文案匹配（去空白小写、长度 ≤40 前缀匹配）：添加至Chrome/添加到Chrome/Add to Chrome；
   * - 扫描命中后改写最深层匹配文本（descendant 优先、容器兜底）为安装文案，
   *   记 __qhCwsBtn 引用并置 __qhCwsOk=true 收起右下角浮层（buildStoreInstallJs 显隐条件）；
   *   800ms 轮询重应用（WizJS 重渲染还原文案后重写；SPA 换页节点失联后重新扫描）；
   * - 点击拦截：命中改写节点（引用等价或包含关系）或原文案匹配（未改写兜底）时
   *   preventDefault + stopPropagation（先于 WizJS 根节点合成事件派发），4 秒 busy 防重复；
   * - 双重守卫：hostname（chromewebstore.google.com / chrome.google.com 旧域）+ 详情页路由 /detail/；
   * - 安装 URL 用 location.href（含 32 位扩展 ID）；未扫到按钮时浮层兜底，点击拦截仍生效；
   * - document 捕获监听常驻，SPA 路由切换无需重挂
   * @param label 按钮改写文案（安装）
   */
  static buildCwsInstallJs(label: string): string {
    return `(function(){
if (window.__qhCwsHook) { return; }
window.__qhCwsHook = true;
var LABEL = ${JSON.stringify(label)};
function supported() {
  if (!/(^|\\.)chromewebstore\\.google\\.com$/i.test(location.hostname)
    && !/(^|\\.)chrome\\.google\\.com$/i.test(location.hostname)) { return false; }
  return /\\/detail\\//.test(location.pathname);
}
function norm(s) {
  s = s || '';
  if (s.length > 40) { return ''; }
  return s.replace(/\\s+/g, '').toLowerCase();
}
function matchLabel(n) {
  return n !== '' && (n.indexOf('添加至chrome') === 0
    || n.indexOf('添加到chrome') === 0
    || n.indexOf('addtochrome') === 0);
}
function matchEl(el) {
  return matchLabel(norm(el.getAttribute('aria-label'))) || matchLabel(norm(el.textContent));
}
function deepestMatch(el) {
  var kids = el.querySelectorAll('*');
  for (var i = 0; i < kids.length; i++) {
    var t = kids[i].textContent || '';
    if (t.length <= 40 && matchLabel(norm(t))) { return kids[i]; }
  }
  var tt = el.textContent || '';
  return (tt.length <= 40 && matchLabel(norm(tt))) ? el : null;
}
function applyBtn(el) {
  var t = deepestMatch(el);
  if (t === null) { return; }
  if (t.textContent !== LABEL) { t.textContent = LABEL; }
  window.__qhCwsBtn = t;
  window.__qhCwsOk = true;
}
function onCapture(ev) {
  if (!supported()) { return; }
  var t = ev.target;
  var el = (t && t.closest) ? t.closest('button,[role="button"]') : null;
  if (el === null) { return; }
  var ref = window.__qhCwsBtn;
  var hit = matchEl(el) || (ref !== undefined && ref !== null
    && (ref === el || ref.contains(el) || el.contains(ref)));
  if (!hit) { return; }
  ev.preventDefault();
  ev.stopPropagation();
  if (el.__qhBusy) { return; }
  el.__qhBusy = true;
  setTimeout(function() { el.__qhBusy = false; }, 4000);
  try {
    var n = window.__qhNative;
    if (n && n.gmRequest) {
      n.gmRequest('extStoreInstall', JSON.stringify({ url: location.href }));
    }
  } catch (e) { console.warn('[qh cws] install', e); }
}
var timer = setInterval(function() {
  if (!supported()) { return; }
  var ref = window.__qhCwsBtn;
  if (ref !== undefined && ref !== null && ref.isConnected) {
    if (ref.textContent !== LABEL) { ref.textContent = LABEL; }
    window.__qhCwsOk = true;
    return;
  }
  var els = document.querySelectorAll('button,[role="button"]');
  for (var i = 0; i < els.length; i++) {
    if (matchEl(els[i])) { applyBtn(els[i]); return; }
  }
}, 800);
document.addEventListener('click', onCapture, true);
})();
`;
  }

  /**
   * Edge Add-ons"获取"按钮原位替换：
   * 页面原生灰色"获取/Get"按钮（非 Edge 浏览器下 disabled/pointer-events:none 不可点）
   * 改写为安装按钮——样式对齐商店直装浮层、点击经 extStoreInstall 走原生安装。关键点：
   * - disabled 表单控件不派发 click 事件（捕获监听也收不到）：每 tick 强制启用，React 重渲染会还原须重应用；
   * - 文案改写后按原文案（获取/Get）搜索不到按钮：详情页节点引用跟踪（__qhEdgeGetBtn）+
   *   列表页注册表（__qhEdgeGetBtns，isConnected + 可见性过滤）；
   * - 列表页（首页/分类等）卡片各有"获取"按钮：逐个转换，安装 URL 解析自所在卡片内
   *   a[href*="/detail/"]（向上最多 10 层、不越过 body），解析不到则跳过该按钮；
   * - 详情页保持单按钮 + location.href（卡片无自引用链接，向上查找易误中推荐位链接）；
   * - 已安装状态：__qhNative.getInstalledExtIds 同步拉取已装商店 ID 集合（5 秒缓存），
   *   按钮安装 URL 提取 32 位商店 ID 匹配——已安装显示灰色"已安装"不可点，未安装显示"安装"；
   * - click 之外附 pointerdown/up 兜底触发（每按钮 __qhGetBusy/__qhArmed 防双触发）；
   * - React 重挂/重渲染由 600ms 轮询重应用（行内样式 + 文案 + 捕获点击）；
   * - 详情页替换成功置 window.__qhEdgeGetOk=true，配合 buildStoreInstallJs 显隐条件收起右下角浮层
   *   （列表页浮层本就只在详情页显示，ok 恒 false 无影响）；
   * - 捕获阶段 stopPropagation 先于 React 根节点合成事件派发，阻断原跳转行为
   * @param label 详情页按钮文案
   * @param listLabel 列表页卡片按钮文案（卡片空间小用短文案）
   * @param installedLabel 已安装状态文案
   */
  static buildEdgeGetReplaceJs(label: string, listLabel: string, installedLabel: string): string {
    return `(function(){
if (window.__qhEdgeGetHook) { return; }
window.__qhEdgeGetHook = true;
var LABEL = ${JSON.stringify(label)};
var LIST_LABEL = ${JSON.stringify(listLabel)};
var INSTALLED_LABEL = ${JSON.stringify(installedLabel)};
function isDetail() {
  return /\\/detail\\//.test(location.pathname);
}
/* 已安装商店 ID 集合：__qhNative.getInstalledExtIds 同步拉取，5 秒缓存（跨 bridge 调用降频） */
var idSet = null;
var idSetAt = 0;
function getIdSet() {
  var now = Date.now();
  if (idSet && now - idSetAt < 5000) { return idSet; }
  try {
    var n = window.__qhNative;
    var raw = n ? n.getInstalledExtIds() : null;
    idSet = {};
    if (raw) {
      var arr = JSON.parse(raw);
      for (var i = 0; i < arr.length; i++) { idSet[arr[i]] = 1; }
    }
    idSetAt = now;
  } catch (e) { idSet = null; idSetAt = now; }
  return idSet;
}
function extIdOf(url) {
  var m = /([a-p]{32})(?![a-p0-9])/i.exec(url || '');
  return m ? m[1].toLowerCase() : null;
}
function gmInstall(btn, url) {
  if (btn.__qhGetBusy || btn.__qhGetInstalled) { return; }
  btn.__qhGetBusy = true;
  btn.textContent = '...';
  setTimeout(function() {
    btn.__qhGetBusy = false;
    if (btn.isConnected) { applyBtn(btn, btn.__qhGetList === true); }
  }, 4000);
  try {
    var n = window.__qhNative;
    if (n && n.gmRequest) { n.gmRequest('extStoreInstall', JSON.stringify({ url: url })); }
  } catch (e) { console.warn('[qh store] edge get install', e); }
}
function onInstall(ev) {
  if (ev) { ev.preventDefault(); ev.stopPropagation(); }
  gmInstall(this, this.__qhGetUrl || location.href);
}
function armDown() { this.__qhArmed = true; }
function armUp(ev) {
  if (!this.__qhArmed) { return; }
  this.__qhArmed = false;
  onInstall.call(this, ev);
}
/* 按安装状态统一应用样式与文案（busy 期间只刷状态不覆盖文案） */
function applyBtn(b, isList) {
  if (!b.__qhGetId) { b.__qhGetId = extIdOf(b.__qhGetUrl || location.href); }
  var set = getIdSet();
  var inst = b.__qhGetId !== null && set !== null && set[b.__qhGetId] === 1;
  b.__qhGetInstalled = inst;
  var base = 'border:none;font-weight:600;line-height:1;outline:none;pointer-events:auto;'
    + (inst ? 'cursor:default;background:#e5e7eb;color:#6b7280;' : 'cursor:pointer;background:#0a7cff;color:#fff;');
  if (isList) {
    /* 列表卡片空间小：不覆盖 padding 保持原尺寸，仅改色 */
    b.style.cssText = 'border-radius:16px;font-size:inherit;' + base;
  } else {
    b.style.cssText = 'padding:12px 32px;border-radius:20px;box-shadow:0 4px 16px rgba(0,0,0,0.35);'
      + 'font-size:15px;' + base;
  }
  if (!b.__qhGetBusy) {
    var want = inst ? INSTALLED_LABEL : (isList ? LIST_LABEL : LABEL);
    if (b.textContent !== want) { b.textContent = want; }
  }
}
function isVisible(el) {
  return el.getClientRects().length > 0;
}
function hookBtn(b) {
  if (b.__qhGetConv) { return; }
  b.__qhGetConv = true;
  try { b.type = 'button'; } catch (e) {}
  b.addEventListener('click', onInstall, true);
  b.addEventListener('pointerdown', armDown, true);
  b.addEventListener('pointerup', armUp, true);
}
function forceEnabled(b) {
  try { b.disabled = false; } catch (e) {}
  try { b.removeAttribute('disabled'); } catch (e) {}
  try { b.removeAttribute('aria-disabled'); } catch (e) {}
}
function findDetailUrl(btn) {
  if (btn.tagName === 'A') {
    var oh = btn.getAttribute('href') || '';
    if (oh.indexOf('/detail/') >= 0) { return btn.href; }
  }
  var node = btn.parentElement;
  for (var i = 0; i < 10 && node && node !== document.body; i++) {
    var a = node.querySelector('a[href*="/detail/"]');
    if (a) { return a.href; }
    node = node.parentElement;
  }
  return null;
}
/* 详情页：单按钮跟踪（文案改写后按原文案搜不到，靠节点引用持续管理） */
function findGetBtn() {
  var prev = window.__qhEdgeGetBtn;
  if (prev && prev.isConnected && isVisible(prev)) { return prev; }
  window.__qhEdgeGetBtn = null;
  var els = document.querySelectorAll('button, [role="button"], a');
  for (var i = 0; i < els.length; i++) {
    if (!isVisible(els[i])) { continue; }
    var t = (els[i].textContent || '').replace(/\\s+/g, ' ').trim();
    if (t === '获取' || t === 'Get') { window.__qhEdgeGetBtn = els[i]; return els[i]; }
  }
  return null;
}
/* 列表页：卡片"获取"按钮逐个转换，注册表跟踪 + 每轮重应用 */
function tickList() {
  var reg = window.__qhEdgeGetBtns || [];
  var live = [];
  for (var i = 0; i < reg.length; i++) {
    var r = reg[i];
    if (r.isConnected && isVisible(r)) {
      live.push(r);
      hookBtn(r);
      forceEnabled(r);
      applyBtn(r, true);
    }
  }
  var els = document.querySelectorAll('button, [role="button"], a');
  for (var j = 0; j < els.length; j++) {
    var b = els[j];
    if (!isVisible(b) || b.__qhGetConv) { continue; }
    var t = (b.textContent || '').replace(/\\s+/g, ' ').trim();
    if (t !== '获取' && t !== 'Get') { continue; }
    var url = findDetailUrl(b);
    if (!url) { continue; }
    b.__qhGetUrl = url;
    b.__qhGetList = true;
    hookBtn(b);
    forceEnabled(b);
    applyBtn(b, true);
    live.push(b);
  }
  window.__qhEdgeGetBtns = live;
}
function tick() {
  var ok = false;
  if (isDetail()) {
    var b = findGetBtn();
    if (b) {
      b.__qhGetUrl = location.href;
      b.__qhGetList = false;
      hookBtn(b);
      forceEnabled(b);
      applyBtn(b, false);
      ok = true;
    }
  } else {
    tickList();
  }
  window.__qhEdgeGetOk = ok;
}
setInterval(tick, 600);
tick();
})();
`;
  }
}

/** 生成 JS 中的字符串安全嵌入工具（单引号/换行转义） */
class ExtensionShimUtil {
  static escapeJs(s: string): string {
    return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, ' ')
  }
}
