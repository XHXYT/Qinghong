import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { appSettings } from '../../entity/SettingsModel';

/**
 * 翻译引擎接口：把一批文本翻译为目标语言，返回等长译文数组（失败抛异常由调用方提示）
 */
export interface TranslateEngine {
  translateBatch(texts: string[], target: string): Promise<string[]>
}

/** GET 文本请求（带超时，非 2xx 抛异常） */
async function httpGetString(url: string, headers?: Record<string, string>): Promise<string> {
  const req: http.HttpRequest = http.createHttp()
  const noHeaders: Record<string, string> = {}
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.GET,
      header: headers ?? noHeaders,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    })
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new Error(`HTTP ${resp.responseCode}`)
    }
    return resp.result as string
  } finally {
    req.destroy()
  }
}

/** POST JSON 文本请求（带超时，非 2xx 抛异常） */
async function httpPostJson(url: string, body: string, headers: Record<string, string>): Promise<string> {
  const req: http.HttpRequest = http.createHttp()
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    })
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new Error(`HTTP ${resp.responseCode}`)
    }
    return resp.result as string
  } finally {
    req.destroy()
  }
}

/** POST 表单请求（application/x-www-form-urlencoded，非 2xx 抛异常） */
async function httpPostForm(url: string, body: string, headers?: Record<string, string>): Promise<string> {
  const req: http.HttpRequest = http.createHttp()
  try {
    const merged: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded'
    }
    if (headers !== undefined) {
      for (const k of Object.keys(headers)) {
        merged[k] = headers[k]
      }
    }
    const resp = await req.request(url, {
      method: http.RequestMethod.POST,
      header: merged,
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    })
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new Error(`HTTP ${resp.responseCode}`)
    }
    return resp.result as string
  } finally {
    req.destroy()
  }
}

/** 字节数组 → 小写十六进制 */
function bytesToHex(bytes: Uint8Array): string {
  let hex: string = ''
  for (let i = 0; i < bytes.length; i++) {
    const h: string = (bytes[i] & 0xFF).toString(16)
    hex += h.length === 1 ? '0' + h : h
  }
  return hex
}

/** MD5 摘要（百度翻译签名用） */
async function md5Hex(input: string): Promise<string> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('MD5')
  const bytes: Uint8Array = new util.TextEncoder().encodeInto(input)
  await md.update({ data: bytes } as cryptoFramework.DataBlob)
  const digest: cryptoFramework.DataBlob = await md.digest()
  return bytesToHex(digest.data)
}

/** SHA-256 摘要（有道签名用） */
async function sha256Hex(input: string): Promise<string> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256')
  const bytes: Uint8Array = new util.TextEncoder().encodeInto(input)
  await md.update({ data: bytes } as cryptoFramework.DataBlob)
  const digest: cryptoFramework.DataBlob = await md.digest()
  return bytesToHex(digest.data)
}

/** 微软 translate v3 单条请求体 */
class MsTextItem {
  Text: string = ''
}

/** Bing 网页翻译鉴权信息（IG/IID + AbusePrevention token/key） */
class BingAuth {
  ig: string = ''
  iid: string = ''
  token: string = ''
  key: string = ''
  fetchTime: number = 0
}

/** Bing 请求头（UA + 来源） */
const BING_HEADERS: Record<string, string> = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  'Referer': 'https://cn.bing.com/translator'
}

/** 正则捕获第一个分组；未匹配返回空串 */
function matchFirst(html: string, pattern: RegExp): string {
  const m: RegExpExecArray | null = pattern.exec(html)
  if (m !== null && m.length > 1 && m[1] !== undefined) {
    return m[1]
  }
  return ''
}

let bingAuth: BingAuth | null = null

/** 抓取 cn.bing.com/translator 页面解析 IG/IID/token/key（缓存 10 分钟） */
async function getBingAuth(): Promise<BingAuth> {
  if (bingAuth !== null && Date.now() - bingAuth.fetchTime < 10 * 60 * 1000) {
    return bingAuth
  }
  const html: string = await httpGetString('https://cn.bing.com/translator', BING_HEADERS)
  const auth: BingAuth = new BingAuth()
  auth.ig = matchFirst(html, /IG:"([^"]+)"/)
  auth.iid = matchFirst(html, /data-iid="([^"]+)"/)
  const ab: string = matchFirst(html, /params_AbusePreventionHelper\s*=\s*\[([^\]]+)\]/)
  // [key(时间戳), "token", 有效期ms]
  const parts: string[] = ab.split(',')
  if (parts.length >= 2) {
    auth.key = parts[0].trim()
    auth.token = parts[1].trim().replace(/^"|"$/g, '')
  }
  if (auth.ig === '' || auth.token === '' || auth.key === '') {
    throw new Error('Bing auth parse failed')
  }
  auth.fetchTime = Date.now()
  bingAuth = auth
  return auth
}

/** Bing 目标语言代码：zh-CN→zh-Hans、zh-TW→zh-Hant */
function bingTarget(target: string): string {
  if (target.startsWith('zh-TW')) {
    return 'zh-Hant'
  }
  if (target.startsWith('zh')) {
    return 'zh-Hans'
  }
  return target
}

/**
 * 内置免费引擎：Bing 网页翻译（cn.bing.com/ttranslatev3，免密钥，国内可达）。
 * 多条文本以 \n 合并请求（译文保留 \n 按段落数对齐拆回），对不齐的批次回退原文
 */
class BingEngine implements TranslateEngine {

  async translateBatch(texts: string[], target: string): Promise<string[]> {
    const auth: BingAuth = await getBingAuth()
    const out: string[] = []
    let i = 0
    while (i < texts.length) {
      const batch: string[] = []
      let len = 0
      while (i < texts.length && batch.length < 10 && len + texts[i].length <= 1000) {
        batch.push(texts[i].replace(/\s*\n\s*/g, ' '))
        len += texts[i].length
        i++
      }
      // 单条超长独立请求
      if (batch.length === 0) {
        const t: string = texts[i]
        batch.push(t.length > 1000 ? t.substring(0, 1000) : t.replace(/\s*\n\s*/g, ' '))
        i++
      }
      const q: string = batch.join('\n')
      const body: string = 'fromLang=auto-detect&to=' + bingTarget(target)
        + '&text=' + encodeURIComponent(q)
        + '&token=' + encodeURIComponent(auth.token)
        + '&key=' + encodeURIComponent(auth.key)
        + '&tryFetchingGenderDebiasedTranslations=true'
      const resp: string = await httpPostForm(
        'https://cn.bing.com/ttranslatev3?isVertical=1&IG=' + auth.ig + '&IID=' + auth.iid, body, BING_HEADERS)
      const data: Object[] = JSON.parse(resp) as Object[]
      let translated: string = ''
      if (data.length > 0) {
        const rec: Record<string, Object> = data[0] as Record<string, Object>
        const translations: Object[] = (rec['translations'] as Object[]) ?? []
        if (translations.length > 0) {
          const t0: Record<string, Object> = translations[0] as Record<string, Object>
          translated = (t0['text'] as string) ?? ''
        }
      }
      const segs: string[] = translated.split('\n')
      if (segs.length === batch.length) {
        for (const s of segs) {
          out.push(s)
        }
      } else {
        // 段落数对不齐：整批回退原文
        for (const b of batch) {
          out.push(b)
        }
      }
    }
    return out
  }
}

/**
 * 微软 translate v3 批量翻译（Azure 官方端点）：
 * Body [{Text}]、响应 [{translations:[{text}]}]，逐条天然对齐，每请求上限 1000 条
 */
async function msTranslate(url: string, headers: Record<string, string>, texts: string[]): Promise<string[]> {
  const out: string[] = []
  for (let start = 0; start < texts.length; start += 100) {
    const slice: string[] = texts.slice(start, start + 100)
    const items: MsTextItem[] = []
    for (const t of slice) {
      const item: MsTextItem = new MsTextItem()
      item.Text = t.length > 3000 ? t.substring(0, 3000) : t
      items.push(item)
    }
    const resp: string = await httpPostJson(url, JSON.stringify(items), headers)
    const data: Object[] = JSON.parse(resp) as Object[]
    for (let i = 0; i < slice.length; i++) {
      let trans: string = ''
      if (i < data.length) {
        const rec: Record<string, Object> = data[i] as Record<string, Object>
        const translations: Object[] = (rec['translations'] as Object[]) ?? []
        if (translations.length > 0) {
          const t0: Record<string, Object> = translations[0] as Record<string, Object>
          trans = (t0['text'] as string) ?? ''
        }
      }
      out.push(trans)
    }
  }
  return out
}

/**
 * 微软 Azure 官方引擎：Ocp-Apim-Subscription-Key 认证，
 * 密钥可附区域（key#region，默认 global）
 */
class AzureEngine implements TranslateEngine {

  async translateBatch(texts: string[], target: string): Promise<string[]> {
    const raw: string = appSettings.translate_ms_key.trim()
    const hashIdx: number = raw.indexOf('#')
    const key: string = hashIdx >= 0 ? raw.substring(0, hashIdx).trim() : raw
    const region: string = hashIdx >= 0 ? raw.substring(hashIdx + 1).trim() : 'global'
    const headers: Record<string, string> = {
      'Ocp-Apim-Subscription-Key': key,
      'Content-Type': 'application/json'
    }
    if (region !== '') {
      headers['Ocp-Apim-Subscription-Region'] = region
    }
    const url: string = 'https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to='
      + encodeURIComponent(target)
    return msTranslate(url, headers, texts)
  }
}

/**
 * Google 翻译：Chrome 内置翻译同款 translate-pa 批量端点（免密钥，需代理）。
 * POST /v1/translateHtml，body [[texts, from, to], "te_lib"] + 内置公开 key，
 * 响应 [[译文...], [检测语言...]] 逐条天然对齐
 */
class GtxEngine implements TranslateEngine {

  async translateBatch(texts: string[], target: string): Promise<string[]> {
    const out: string[] = []
    for (let start = 0; start < texts.length; start += 50) {
      const slice: string[] = []
      for (let i = start; i < Math.min(start + 50, texts.length); i++) {
        const t: string = texts[i]
        slice.push(t.length > 3000 ? t.substring(0, 3000) : t)
      }
      const inner: Object[] = [slice, 'auto', target]
      const payload: Object[] = [inner, 'te_lib']
      const body: string = await httpPostJson(
        'https://translate-pa.googleapis.com/v1/translateHtml',
        JSON.stringify(payload),
        {
          'X-Goog-Api-Key': 'AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520',
          'Content-Type': 'application/json+protobuf'
        })
      const data: Object[] = JSON.parse(body) as Object[]
      const translations: Object[] = (data[0] as Object[]) ?? []
      for (let i = 0; i < slice.length; i++) {
        if (i < translations.length) {
          out.push((translations[i] as string) ?? '')
        } else {
          out.push(slice[i])
        }
      }
    }
    return out
  }
}

/** 百度翻译 to 代码：zh-CN→zh、zh-TW→cht */
function baiduTarget(target: string): string {
  if (target.startsWith('zh-TW')) {
    return 'cht'
  }
  if (target.startsWith('zh')) {
    return 'zh'
  }
  return target.toLowerCase()
}

/**
 * 百度翻译开放平台引擎：appid + 密钥（MD5 签名）。
 * 多条以 \n 合并（内部换行替换为空格保证对齐），trans_result 数组逐条对应
 */
class BaiduEngine implements TranslateEngine {

  async translateBatch(texts: string[], target: string): Promise<string[]> {
    const appid: string = appSettings.translate_baidu_appid.trim()
    const key: string = appSettings.translate_baidu_key.trim()
    const out: string[] = []
    let i = 0
    while (i < texts.length) {
      const batch: string[] = []
      let len = 0
      while (i < texts.length && batch.length < 20 && len + texts[i].length <= 1200) {
        batch.push(texts[i].replace(/\s*\n\s*/g, ' '))
        len += texts[i].length
        i++
      }
      // 单条超长独立请求（q 上限 6000 字节，保守截 1500 字符）
      if (batch.length === 0) {
        batch.push(texts[i].length > 1500 ? texts[i].substring(0, 1500) : texts[i])
        i++
      }
      const q: string = batch.join('\n')
      const salt: string = Date.now().toString()
      const sign: string = await md5Hex(appid + q + salt + key)
      const body: string = 'q=' + encodeURIComponent(q) + '&from=auto&to=' + baiduTarget(target)
        + '&appid=' + encodeURIComponent(appid) + '&salt=' + salt + '&sign=' + sign
      const resp: string = await httpPostForm('https://fanyi-api.baidu.com/api/trans/vip/translate', body)
      const data: Record<string, Object> = JSON.parse(resp) as Record<string, Object>
      if (data['error_code'] !== undefined) {
        throw new Error(`Baidu ${data['error_code']}`)
      }
      const results: Object[] = (data['trans_result'] as Object[]) ?? []
      if (results.length !== batch.length) {
        // 条数不齐（合并翻译被拆行等）：整批回退原文
        for (const b of batch) {
          out.push(b)
        }
        continue
      }
      for (let j = 0; j < batch.length; j++) {
        const rec: Record<string, Object> = results[j] as Record<string, Object>
        out.push((rec['dst'] as string) ?? '')
      }
    }
    return out
  }
}

/** 有道智云 to 代码：zh-CN→zh-CHS、zh-TW→zh-CHT */
function youdaoTarget(target: string): string {
  if (target.startsWith('zh-TW')) {
    return 'zh-CHT'
  }
  if (target.startsWith('zh')) {
    return 'zh-CHS'
  }
  return target
}

/**
 * 有道智云文本翻译 v3 引擎：appKey + 应用密钥（SHA-256 签名）。
 * q 限 1000 字符，逐条请求
 */
class YoudaoEngine implements TranslateEngine {

  async translateBatch(texts: string[], target: string): Promise<string[]> {
    const appKey: string = appSettings.translate_youdao_appid.trim()
    const secret: string = appSettings.translate_youdao_secret.trim()
    const out: string[] = []
    for (const t of texts) {
      const q: string = t.length > 900 ? t.substring(0, 900) : t
      const salt: string = Date.now().toString()
      const curtime: string = Math.floor(Date.now() / 1000).toString()
      // input 规则：q≤20 原样；否则前 10 + 长度 + 后 10
      const input: string = q.length <= 20
        ? q
        : q.substring(0, 10) + q.length.toString() + q.substring(q.length - 10)
      const sign: string = await sha256Hex(appKey + input + salt + curtime + secret)
      const body: string = 'q=' + encodeURIComponent(q) + '&from=auto&to=' + youdaoTarget(target)
        + '&appKey=' + encodeURIComponent(appKey) + '&salt=' + salt
        + '&signType=v3&curtime=' + curtime + '&sign=' + sign
      const resp: string = await httpPostForm('https://openapi.youdao.com/api', body)
      const data: Record<string, Object> = JSON.parse(resp) as Record<string, Object>
      const errCode: string = (data['errorCode'] as string) ?? '1'
      const translations: Object[] = (data['translation'] as Object[]) ?? []
      if (errCode === '0' && translations.length > 0) {
        out.push((translations[0] as string) ?? '')
      } else {
        out.push('')
      }
    }
    return out
  }
}

/** LibreTranslate /translate 请求体 */
class LibreRequestBody {
  q: string = ''
  source: string = 'auto'
  target: string = ''
  format: string = 'text'
  api_key: string = ''
}

/**
 * LibreTranslate 引擎（自建/第三方服务）：逐条请求 /translate，
 * 响应 {translatedText}；target 归一（zh-CN→zh）
 */
class LibreEngine implements TranslateEngine {

  async translateBatch(texts: string[], target: string): Promise<string[]> {
    const base: string = appSettings.translate_libre_url.trim().replace(/\/+$/, '')
    const url: string = base + '/translate'
    const out: string[] = []
    for (const t of texts) {
      const clipped: string = t.length > 3000 ? t.substring(0, 3000) : t
      const bodyObj: LibreRequestBody = new LibreRequestBody()
      bodyObj.q = clipped
      bodyObj.target = target.startsWith('zh-CN') ? 'zh' : (target.startsWith('zh-TW') ? 'zh-TW' : target)
      bodyObj.api_key = appSettings.translate_libre_key.trim()
      const resp: string = await httpPostJson(url, JSON.stringify(bodyObj),
        { 'Content-Type': 'application/json' })
      const data: Record<string, Object> = JSON.parse(resp) as Record<string, Object>
      out.push((data['translatedText'] as string) ?? '')
    }
    return out
  }
}

/** DeepL target_lang 代码映射 */
function deeplTarget(target: string): string {
  if (target.startsWith('zh-TW')) {
    return 'ZH-HANT'
  }
  if (target.startsWith('zh')) {
    return 'ZH-HANS'
  }
  if (target.startsWith('en')) {
    return 'EN-US'
  }
  return target.toUpperCase()
}

/** DeepL /v2/translate 请求体 */
class DeepLRequestBody {
  text: string[] = []
  target_lang: string = ''
}

/**
 * DeepL 引擎：free key（:fx 结尾）走 api-free，pro key 走 api.deepl.com；
 * 原生支持 text 数组批量
 */
class DeepLEngine implements TranslateEngine {

  async translateBatch(texts: string[], target: string): Promise<string[]> {
    const key: string = appSettings.translate_deepl_key.trim()
    const endpoint: string = key.endsWith(':fx')
      ? 'https://api-free.deepl.com/v2/translate'
      : 'https://api.deepl.com/v2/translate'
    const clipped: string[] = []
    for (const t of texts) {
      clipped.push(t.length > 3000 ? t.substring(0, 3000) : t)
    }
    const bodyObj: DeepLRequestBody = new DeepLRequestBody()
    bodyObj.text = clipped
    bodyObj.target_lang = deeplTarget(target)
    const resp: string = await httpPostJson(endpoint, JSON.stringify(bodyObj),
      { 'Authorization': 'DeepL-Auth-Key ' + key, 'Content-Type': 'application/json' })
    const data: Record<string, Object> = JSON.parse(resp) as Record<string, Object>
    const translations: Object[] = (data['translations'] as Object[]) ?? []
    const out: string[] = []
    for (let i = 0; i < clipped.length; i++) {
      if (i < translations.length) {
        const rec: Record<string, Object> = translations[i] as Record<string, Object>
        out.push((rec['text'] as string) ?? '')
      } else {
        out.push('')
      }
    }
    return out
  }
}

/**
 * 引擎工厂：按设置返回可用引擎；
 * 微软 Azure/百度/有道/DeepL/LibreTranslate 未配齐密钥时回退内置免费引擎
 */
export function getTranslateEngine(): TranslateEngine {
  const engine: string = appSettings.translate_engine
  if (engine === 'google') {
    return new GtxEngine()
  }
  if (engine === 'microsoft' && appSettings.translate_ms_key.trim() !== '') {
    return new AzureEngine()
  }
  if (engine === 'baidu' && appSettings.translate_baidu_appid.trim() !== ''
    && appSettings.translate_baidu_key.trim() !== '') {
    return new BaiduEngine()
  }
  if (engine === 'youdao' && appSettings.translate_youdao_appid.trim() !== ''
    && appSettings.translate_youdao_secret.trim() !== '') {
    return new YoudaoEngine()
  }
  if (engine === 'deepl' && appSettings.translate_deepl_key.trim() !== '') {
    return new DeepLEngine()
  }
  if (engine === 'libre' && appSettings.translate_libre_url.trim() !== '') {
    return new LibreEngine()
  }
  return new BingEngine()
}
