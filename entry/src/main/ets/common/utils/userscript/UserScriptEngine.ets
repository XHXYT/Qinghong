import { createLogger } from '../app/Logger';

const logger = createLogger('UserScriptEngine')

/**
 * @resource 元数据（名称 + 下载地址）
 */
export class ScriptResourceMeta {
  name: string = ''
  url: string = ''
}

/**
 * Userscript metadata 解析结果
 */
export class ScriptMeta {
  name: string = ''
  namespace: string = ''
  version: string = ''
  description: string = ''
  author: string = ''
  runAt: string = 'document-end'
  matches: string[] = []
  excludes: string[] = []
  updateUrl: string = ''
  grants: string[] = []
  requires: string[] = []
  resources: ScriptResourceMeta[] = []
  connects: string[] = []
  noframes: boolean = false
}

/**
 * 用户脚本引擎：metadata 解析 + URL 匹配 + 注入代码包装
 */
export class UserScriptEngine {

  /** 新建脚本模板（对齐 Via 添加脚本预填内容） */
  static readonly NEW_TEMPLATE: string =
    '// ==UserScript==\n' +
    '// @name        New Userscript\n' +
    '// @namespace   https://qh.browser\n' +
    '// @version     0.1\n' +
    '// @description try to take over the world!\n' +
    '// @author      You\n' +
    '// @run-at      document-end\n' +
    '// @match       *://*/*\n' +
    '// @grant       none\n' +
    '// ==/UserScript==\n' +
    '\n' +
    "(function() {\n" +
    "    'use strict';\n" +
    '\n' +
    '    // Your code here...\n' +
    '})();\n'

  /**
   * 解析脚本源码中的 ==UserScript== metadata 块
   */
  static parseMeta(code: string): ScriptMeta {
    const meta: ScriptMeta = new ScriptMeta()
    const start: number = code.indexOf('==UserScript==')
    const end: number = code.indexOf('==/UserScript==')
    if (start < 0 || end < 0 || end <= start) {
      return meta
    }
    const block: string = code.substring(start, end)
    const lines: string[] = block.split('\n')
    for (const line of lines) {
      const m: RegExpMatchArray | null = line.match(/^\/\/\s*@(\S+)\s+(.*)$/)
      if (m === null || m.length < 3) {
        continue
      }
      const key: string = m[1]
      const value: string = m[2].trim()
      if (key === 'name') {
        meta.name = value
      } else if (key === 'namespace') {
        meta.namespace = value
      } else if (key === 'version') {
        meta.version = value
      } else if (key === 'description') {
        meta.description = value
      } else if (key === 'author') {
        meta.author = value
      } else if (key === 'run-at') {
        meta.runAt = value
      } else if (key === 'match' || key === 'include') {
        meta.matches.push(value)
      } else if (key === 'exclude' || key === 'exclude-match') {
        meta.excludes.push(value)
      } else if (key === 'updateURL' || key === 'downloadURL') {
        meta.updateUrl = value
      } else if (key === 'grant') {
        meta.grants.push(value)
      } else if (key === 'require') {
        meta.requires.push(value)
      } else if (key === 'connect') {
        meta.connects.push(value)
      } else if (key === 'noframes') {
        meta.noframes = true
      } else if (key === 'resource') {
        const parts: string[] = value.split(/\s+/)
        if (parts.length >= 2) {
          const r: ScriptResourceMeta = new ScriptResourceMeta()
          r.name = parts[0]
          r.url = parts[1]
          meta.resources.push(r)
        }
      }
    }
    return meta
  }

  /**
   * URL 是否命中脚本作用域：任一排除规则命中即不生效；
   * 无生效规则时全站生效，否则任一生效规则命中即可
   */
  static matchUrl(url: string, matches: string, excludes: string): boolean {
    const exLines: string[] = UserScriptEngine.splitLines(excludes)
    for (const ex of exLines) {
      if (UserScriptEngine.globMatch(ex, url)) {
        return false
      }
    }
    const inLines: string[] = UserScriptEngine.splitLines(matches)
    if (inLines.length === 0) {
      return true
    }
    for (const p of inLines) {
      if (UserScriptEngine.globMatch(p, url)) {
        return true
      }
    }
    return false
  }

  /**
   * 通配匹配：pattern 中 * 匹配任意字符序列（宽松处理 @match/@include 规则）
   */
  static globMatch(pattern: string, url: string): boolean {
    const reStr: string = UserScriptEngine.globToRegex(pattern)
    try {
      return new RegExp(reStr, 'i').test(url)
    } catch (e) {
      logger.error(`globMatch 正则构造失败: ${e}`)
      return false
    }
  }

  /**
   * 通配 pattern 转正则字符串：转义特殊字符，* 还原为 .*
   */
  private static globToRegex(pattern: string): string {
    let re: string = ''
    for (let i: number = 0; i < pattern.length; i++) {
      const c: string = pattern.charAt(i)
      if (c === '*') {
        re += '.*'
      } else if ('\\^$.|?+()[]{}'.indexOf(c) >= 0) {
        re += '\\' + c
      } else {
        re += c
      }
    }
    return re
  }

  /**
   * 多行规则文本拆分为规则数组（去空行去空白）
   */
  static splitLines(s: string): string[] {
    const out: string[] = []
    if (s === '') {
      return out
    }
    const parts: string[] = s.split('\n')
    for (const p of parts) {
      const t: string = p.trim()
      if (t !== '') {
        out.push(t)
      }
    }
    return out
  }

  /**
   * @connect 域名匹配：example.com 匹配自身与子域；*.example.com 仅匹配子域；* 放行全部
   */
  static connectMatch(pattern: string, host: string): boolean {
    if (pattern === '*' || pattern === '') {
      return true
    }
    if (pattern.startsWith('*.')) {
      return host.endsWith('.' + pattern.substring(2))
    }
    return host === pattern || host.endsWith('.' + pattern)
  }

  /**
   * 包装脚本代码：隔离作用域 + 捕获异常，避免单脚本错误影响页面
   */
  static wrapJs(code: string): string {
    return `(function(){ try{\n${code}\n}catch(e){console.warn('[qh userscript]',e)} })();`
  }
}
