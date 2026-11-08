import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { createLogger } from '../app/Logger';

const logger = createLogger('HomeImageUtil')

/**
 * 主页定制图片工具：相册选图 → 解码缩放 → 重编码 PNG 写入沙箱
 */
export class HomeImageUtil {

  /** 拉起相册选图（单张），返回 photo uri（空串=取消） */
  static pickImage(): Promise<string> {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
    const options: photoAccessHelper.PhotoSelectOptions = {
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1
    }
    return picker.select(options)
      .then((result: photoAccessHelper.PhotoSelectResult): string => {
        return result.photoUris.length > 0 ? result.photoUris[0] : ''
      })
      .catch((error: BusinessError): string => {
        logger.error(`pickImage failed: ${error.code} ${error.message}`)
        return ''
      })
  }

  /**
   * 相册 uri → 解码（最长边超 maxEdge 时等比缩小）→ PNG 写入 destPath
   * @returns 是否成功
   */
  static async savePicked(uri: string, destPath: string, maxEdge: number, quality: number): Promise<boolean> {
    let srcFile: fileIo.File | null = null
    let source: image.ImageSource | null = null
    let pixelMap: image.PixelMap | null = null
    let packer: image.ImagePacker | null = null
    try {
      srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      source = image.createImageSource(srcFile.fd)
      pixelMap = await source.createPixelMap()
      const info: image.ImageInfo = await pixelMap.getImageInfo()
      const maxSide: number = Math.max(info.size.width, info.size.height)
      if (maxEdge > 0 && maxSide > maxEdge) {
        const ratio: number = maxEdge / maxSide
        await pixelMap.scale(ratio, ratio)
      }
      packer = image.createImagePacker()
      const buf: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/png', quality: quality })
      const bytes: Uint8Array = new Uint8Array(buf)
      const file: fileIo.File = fileIo.openSync(destPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
      fileIo.closeSync(file)
      return true
    } catch (error) {
      const err = error as BusinessError
      logger.error(`savePicked failed: ${err.code} ${err.message}`)
      return false
    } finally {
      if (packer !== null) {
        packer.release()
      }
      if (pixelMap !== null) {
        pixelMap.release()
      }
      if (source !== null) {
        source.release()
      }
      if (srcFile !== null) {
        fileIo.closeSync(srcFile)
      }
    }
  }

  /** 确保目录存在并返回其路径 */
  static ensureDir(dir: string): string {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir)
    }
    return dir
  }
}
