/**
 * ABP 规则纯解析工具（主线程与 taskpool 子线程共用，无 RegExp 构造）
 */

/**
 * ABP 规则 → 正则源码字符串
 * `/正则/` 规则返回内部内容；`||` `|` `^` `*` `$` 选项按 ABP 语义转译；无效规则返回 ''
 */
export function abpRuleToRegexSrc(rule: string): string {
  let pattern: string = rule
  // 忽略 $ 选项（script/image/third-party 等，ArkWeb 无法区分资源类型）
  const dollar: number = pattern.indexOf('$')
  if (dollar >= 0) {
    pattern = pattern.substring(0, dollar)
  }
  if (pattern.length === 0) {
    return ''
  }
  // 正则规则 /…/
  if (pattern.length > 2 && pattern.startsWith('/') && pattern.endsWith('/')) {
    return pattern.substring(1, pattern.length - 1)
  }
  let anchorStart: boolean = false
  let anchorEnd: boolean = false
  if (pattern.startsWith('||')) {
    anchorStart = true
    pattern = pattern.substring(2)
  } else if (pattern.startsWith('|')) {
    anchorStart = true
    pattern = pattern.substring(1)
  }
  if (pattern.endsWith('|')) {
    anchorEnd = true
    pattern = pattern.substring(0, pattern.length - 1)
  }
  if (pattern.length === 0) {
    return ''
  }
  let src: string = ''
  if (anchorStart) {
    // 域名锚：scheme:// + 可选子域 + 模式
    src += '^[a-z][a-z0-9+.\\-]*:\\/\\/(?:[^\\/]*\\.)?'
  }
  for (let i = 0; i < pattern.length; i++) {
    const ch: string = pattern[i]
    if (ch === '*') {
      src += '.*'
    } else if (ch === '^') {
      // 分隔符：字母/数字/_ . - % 以外的字符或结尾
      src += '(?:[^a-z0-9_.\\-%]|$)'
    } else {
      src += abpEscapeRegex(ch)
    }
  }
  if (anchorEnd) {
    src += '$'
  }
  return src
}

function abpEscapeRegex(ch: string): string {
  if ('\\^$.|?*+()[]{}'.includes(ch)) {
    return `\\${ch}`
  }
  return ch
}
