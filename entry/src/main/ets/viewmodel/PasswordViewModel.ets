import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import PasswordInfo from '../common/entity/PasswordInfo';
import { PasswordDao } from '../common/utils/database/impl/PasswordDao';
import { PasswordNeverDao } from '../common/utils/database/impl/PasswordNeverDao';
import { _QhState } from '../entryability/AppState';

/** 保存密码提示决策 */
export enum PasswordDecision {
  /** 静默跳过（已保存一致 / 命中不保存列表） */
  SKIP = 'skip',
  /** 新增保存 */
  SAVE = 'save',
  /** 更新已保存密码 */
  UPDATE = 'update'
}

/**
 * 密码管理器：自建密码库（RDB），
 * 网页端经注入脚本检测登录表单，由 TabWeb 弹保存提示
 */
@ObservedV2
export class PasswordViewModel {

  private db: PasswordDao | null = null
  private neverDb: PasswordNeverDao | null = null

  private getDB(): PasswordDao {
    if (this.db === null) {
      this.db = new PasswordDao(_QhState.Context)
    }
    return this.db
  }

  private getNeverDB(): PasswordNeverDao {
    if (this.neverDb === null) {
      this.neverDb = new PasswordNeverDao(_QhState.Context)
    }
    return this.neverDb
  }

  /** 全部已保存密码（按更新时间倒序） */
  async listAll(): Promise<PasswordInfo[]> {
    return this.getDB().listAll()
  }

  /** 某网站最近更新的凭据（自动填充用） */
  async credentialFor(host: string): Promise<PasswordInfo | null> {
    return this.getDB().findLatestByHost(host)
  }

  async upsert(host: string, username: string, password: string): Promise<void> {
    await this.getDB().upsert(host, username, password)
  }

  async deleteById(id: number): Promise<void> {
    await this.getDB().deleteById(id)
  }

  /** 保存提示决策：跳过 / 保存 / 更新 */
  async decideSave(host: string, username: string, password: string): Promise<PasswordDecision> {
    if (await this.isNever(host)) {
      return PasswordDecision.SKIP
    }
    const existing: PasswordInfo | null = await this.getDB().findByAccount(host, username)
    if (existing === null) {
      return PasswordDecision.SAVE
    }
    if (existing.password === password) {
      return PasswordDecision.SKIP
    }
    return PasswordDecision.UPDATE
  }

  /** 是否在「不保存密码的网站」列表中 */
  async isNever(host: string): Promise<boolean> {
    return this.getNeverDB().has(host)
  }

  async addNever(host: string): Promise<void> {
    await this.getNeverDB().add(host)
  }

  async removeNever(host: string): Promise<void> {
    await this.getNeverDB().remove(host)
  }

  async listNever(): Promise<string[]> {
    return this.getNeverDB().listAll()
  }

  /**
   * 从 URI（文件选择器返回的 CSV）导入密码（Chrome 格式：name,url,username,password），返回导入条数
   */
  async importFromUri(uri: string): Promise<number> {
    const content: string = await PasswordViewModel.readTextFromUri(uri)
    return this.importFromCsv(content)
  }

  async importFromCsv(content: string): Promise<number> {
    const rows: string[][] = PasswordViewModel.parseCsv(content)
    if (rows.length === 0) {
      return 0
    }
    const first: string[] = rows[0]
    let joined: string = ''
    for (const cell of first) {
      joined += `${cell.trim().toLowerCase()},`
    }
    const hasHeader: boolean = joined.includes('username') && joined.includes('password')
    let count: number = 0
    for (let r = hasHeader ? 1 : 0; r < rows.length; r++) {
      const cells: string[] = rows[r]
      while (cells.length < 4) {
        cells.push('')
      }
      const password: string = cells[3]
      if (password === '') {
        continue
      }
      let host: string = PasswordViewModel.hostFromUrl(cells[1])
      if (host === '') {
        host = PasswordViewModel.hostFromUrl(cells[0])
      }
      if (host === '') {
        continue
      }
      await this.getDB().upsert(host, cells[2], password)
      count++
    }
    return count
  }

  /**
   * 导出为 Chrome CSV 格式文本；无密码时返回空串
   */
  async exportToCsv(): Promise<string> {
    const all: PasswordInfo[] = await this.listAll()
    if (all.length === 0) {
      return ''
    }
    const lines: string[] = ['name,url,username,password']
    for (const p of all) {
      lines.push(
        `${PasswordViewModel.csvCell(p.host)},${PasswordViewModel.csvCell(`https://${p.host}/`)},` +
        `${PasswordViewModel.csvCell(p.username)},${PasswordViewModel.csvCell(p.password)}`)
    }
    return lines.join('\n')
  }

  private static async readTextFromUri(uri: string): Promise<string> {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd)
      const buf: ArrayBuffer = new ArrayBuffer(stat.size)
      let total: number = 0
      while (total < stat.size) {
        const n: number = fileIo.readSync(file.fd, buf, { offset: total })
        if (n <= 0) {
          break
        }
        total += n
      }
      return buffer.from(buf).toString('utf-8')
    } finally {
      fileIo.closeSync(file)
    }
  }

  /** 从 URL 提取 host（无 scheme 时视为纯域名） */
  static hostFromUrl(url: string): string {
    let u: string = url.trim().toLowerCase()
    if (u === '') {
      return ''
    }
    const schemeIdx: number = u.indexOf('://')
    if (schemeIdx >= 0) {
      u = u.substring(schemeIdx + 3)
    }
    let end: number = u.length
    const slash: number = u.indexOf('/')
    if (slash >= 0 && slash < end) {
      end = slash
    }
    const question: number = u.indexOf('?')
    if (question >= 0 && question < end) {
      end = question
    }
    const hash: number = u.indexOf('#')
    if (hash >= 0 && hash < end) {
      end = hash
    }
    let host: string = u.substring(0, end)
    const at: number = host.indexOf('@')
    if (at >= 0) {
      host = host.substring(at + 1)
    }
    const colon: number = host.indexOf(':')
    if (colon >= 0) {
      host = host.substring(0, colon)
    }
    return host
  }

  /** CSV 单元格转义（含逗号/引号/换行时加引号） */
  static csvCell(v: string): string {
    if (v.indexOf(',') >= 0 || v.indexOf('"') >= 0 || v.indexOf('\n') >= 0 || v.indexOf('\r') >= 0) {
      return `"${v.replace(/"/g, '""')}"`
    }
    return v
  }

  /** 解析 CSV 文本（处理引号内逗号/换行/转义引号，去除 BOM） */
  static parseCsv(content: string): string[][] {
    let text: string = content
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
      text = text.substring(1)
    }
    const rows: string[][] = []
    let row: string[] = []
    let cell: string = ''
    let inQuotes: boolean = false
    let i: number = 0
    while (i < text.length) {
      const ch: string = text.charAt(i)
      if (inQuotes) {
        if (ch === '"') {
          if (i + 1 < text.length && text.charAt(i + 1) === '"') {
            cell += '"'
            i += 2
            continue
          }
          inQuotes = false
          i++
          continue
        }
        cell += ch
        i++
        continue
      }
      if (ch === '"') {
        inQuotes = true
        i++
        continue
      }
      if (ch === ',') {
        row.push(cell)
        cell = ''
        i++
        continue
      }
      if (ch === '\r') {
        i++
        continue
      }
      if (ch === '\n') {
        row.push(cell)
        rows.push(row)
        row = []
        cell = ''
        i++
        continue
      }
      cell += ch
      i++
    }
    if (cell !== '' || row.length > 0) {
      row.push(cell)
      rows.push(row)
    }
    return rows
  }
}

export const passwordVM = new PasswordViewModel()
