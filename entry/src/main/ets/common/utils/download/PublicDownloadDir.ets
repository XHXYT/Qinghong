import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { bundleManager } from '@kit.AbilityKit';
import { _QhState } from '../../../entryability/AppState';
import { createLogger } from '../app/Logger';

const logger = createLogger('PublicDownloadDir')

/**
 * 公共下载目录 Download/<本应用包名> 统一访问工具：
 * 备份/PDF/下载三处保存共用。包名目录未创建（首次无访问权限）时，
 * 走系统 DOWNLOAD 保存流程：无界面，由系统自动创建 Download/<包名> 并授予访问权限。
 */
export class PublicDownloadDir {
  /** 子目录真实路径（不确保存在）：Download/<本应用包名>/<sub> */
  static dirOf(sub: string): string {
    const uri: string =
      `file://docs/storage/Users/currentUser/Download/${PublicDownloadDir.bundleName()}/${sub}`
    return new fileUri.FileUri(uri).path
  }

  /** 子目录显示路径（设置页展示用） */
  static labelOf(sub: string): string {
    return `Download/${PublicDownloadDir.bundleName()}/${sub}`
  }

  /** 确保子目录存在且有权限；无权限时走 DOWNLOAD 系统授权流程后重试 */
  static async ensureDir(sub: string): Promise<string> {
    const dir: string = PublicDownloadDir.dirOf(sub)
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true)
      }
      return dir
    } catch (e) {
      logger.info('ensureDir', '直接创建失败，走 DOWNLOAD 系统授权流程')
    }
    const svPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(_QhState.Context)
    const options: picker.DocumentSaveOptions = {
      pickerMode: picker.DocumentPickerMode.DOWNLOAD
    }
    const uris: string[] = await svPicker.save(options)
    if (uris.length === 0) {
      throw new Error('DOWNLOAD 保存流程未返回文件 URI')
    }
    // 系统会预创建空文件，删除避免残留
    try {
      fileIo.unlinkSync(new fileUri.FileUri(uris[0]).path)
    } catch (e) {
      logger.error('ensureDir', `删除预创建文件失败: ${e}`)
    }
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true)
    }
    return dir
  }

  /** 写文本文件（目录不存在则创建） */
  static writeText(dir: string, fileName: string, text: string): void {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true)
    }
    const file: fileIo.File = fileIo.openSync(`${dir}/${fileName}`,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, text)
    } finally {
      fileIo.closeSync(file)
    }
  }

  /** 写二进制文件（目录不存在则创建） */
  static writeBytes(dir: string, fileName: string, data: Uint8Array): void {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true)
    }
    const buf: ArrayBuffer = new ArrayBuffer(data.byteLength)
    new Uint8Array(buf).set(data)
    const file: fileIo.File = fileIo.openSync(`${dir}/${fileName}`,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, buf)
    } finally {
      fileIo.closeSync(file)
    }
  }

  private static bundleName(): string {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
    return info.name
  }
}
