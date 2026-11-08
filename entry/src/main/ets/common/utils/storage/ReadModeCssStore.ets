import { fileIo } from '@kit.CoreFileKit';
import { _QhState } from '../../../entryability/AppState';
import { createLogger } from '../app/Logger';

const logger = createLogger('ReadModeCssStore')

/**
 * 阅读模式自定义 CSS 存取：存应用沙箱文件（filesDir/readmode_custom.css），
 * 避免大文本写入设置首选项导致配置膨胀。
 */
export class ReadModeCssStore {

  /** 沙箱内自定义样式目录（后续其它自定义 CSS 也放这里） */
  static cssDir(): string {
    return `${_QhState.Context.filesDir}/css`
  }

  /** 沙箱内的 CSS 文件路径 */
  static filePath(): string {
    return `${ReadModeCssStore.cssDir()}/readmode_custom.css`
  }

  /** 读取 CSS 内容，文件不存在或读取失败返回空串 */
  static load(): string {
    try {
      const path: string = ReadModeCssStore.filePath()
      if (!fileIo.accessSync(path)) {
        return ''
      }
      return fileIo.readTextSync(path)
    } catch (e) {
      logger.error(`load 失败: ${e}`)
      return ''
    }
  }

  /** 保存 CSS 内容到沙箱文件（覆盖写入） */
  static save(css: string): boolean {
    try {
      const dir: string = ReadModeCssStore.cssDir()
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true)
      }
      const path: string = ReadModeCssStore.filePath()
      const file: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      try {
        fileIo.writeSync(file.fd, css)
      } finally {
        fileIo.closeSync(file)
      }
      return true
    } catch (e) {
      logger.error(`save 失败: ${e}`)
      return false
    }
  }
}
