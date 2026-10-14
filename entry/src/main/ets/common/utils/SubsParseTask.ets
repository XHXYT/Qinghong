import { fileIo } from '@kit.CoreFileKit';
import { abpRuleToRegexSrc } from './AbpRuleParse';

/** 订阅规则子线程解析结果（纯字符串数据，可跨线程序列化传输） */
export interface SubParseRaw {
  /** 网络拦截规则的正则源码 */
  blockSrcs: string[]
  /** 网络例外规则的正则源码 */
  exceptionSrcs: string[]
  /** 元素隐藏规则域名（与 hideSelectors 下标一一对应） */
  hideDomains: string[]
  hideSelectors: string[]
  /** 元素隐藏例外规则域名（与 hideExcSelectors 下标一一对应） */
  hideExcDomains: string[]
  hideExcSelectors: string[]
}

/**
 * taskpool 子线程任务：读取订阅规则文件并逐行解析为纯字符串数据。
 * RegExp 不可跨线程传输，由主线程根据源码构造。
 */
@Concurrent
export function parseSubRulesTask(path: string): SubParseRaw {
  const raw: SubParseRaw = {
    blockSrcs: [], exceptionSrcs: [],
    hideDomains: [], hideSelectors: [],
    hideExcDomains: [], hideExcSelectors: []
  }
  let text: string = ''
  try {
    if (fileIo.accessSync(path)) {
      text = fileIo.readTextSync(path)
    }
  } catch (e) {
    return raw
  }
  if (text === '') {
    return raw
  }
  const lines: string[] = text.split('\n')
  for (let line of lines) {
    line = line.trim()
    if (line.length === 0) {
      continue
    }
    const first: string = line[0]
    if (first === '!' || first === '[') {
      continue
    }
    // 元素隐藏规则（## / #@#）
    let sepIndex: number = line.indexOf('#@#')
    let isElementException: boolean = true
    if (sepIndex < 0) {
      sepIndex = line.indexOf('##')
      isElementException = false
    }
    if (sepIndex >= 0) {
      const domains: string = line.substring(0, sepIndex).trim()
      const selector: string = line.substring(sepIndex + (isElementException ? 3 : 2)).trim()
      if (selector.length > 0) {
        if (isElementException) {
          raw.hideExcDomains.push(domains)
          raw.hideExcSelectors.push(selector)
        } else {
          raw.hideDomains.push(domains)
          raw.hideSelectors.push(selector)
        }
      }
      continue
    }
    // 网络规则（@@ 例外优先）
    let isException: boolean = false
    if (line.startsWith('@@')) {
      isException = true
      line = line.substring(2).trim()
    }
    const src: string = abpRuleToRegexSrc(line)
    if (src === '') {
      continue
    }
    if (isException) {
      raw.exceptionSrcs.push(src)
    } else {
      raw.blockSrcs.push(src)
    }
  }
  return raw
}
