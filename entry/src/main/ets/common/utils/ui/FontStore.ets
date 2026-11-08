import { fileIo } from '@kit.CoreFileKit';
import { _QhState } from '../../../entryability/AppState';
import { createLogger } from '../app/Logger';

const logger = createLogger('FontStore')

/**
 * 自定义字体信息（family 注册名 + 沙箱文件路径）
 */
export class FontInfo {
  readonly family: string
  readonly path: string

  constructor(family: string, path: string) {
    this.family = family
    this.path = path
  }
}

/**
 * 外部字体存取与注册：字体文件存应用沙箱 filesDir/fonts，
 * 通过 font.registerFont 注册后即可在 fontFamily 中使用。
 */
export class FontStore {

  /** 沙箱内字体文件目录 */
  static fontsDir(): string {
    return `${_QhState.Context.filesDir}/fonts`
  }

  /** 扫描字体目录，列出全部可用字体 */
  static list(): FontInfo[] {
    const fonts: FontInfo[] = []
    try {
      const dir: string = FontStore.fontsDir()
      if (!fileIo.accessSync(dir)) {
        return fonts
      }
      const names: string[] = fileIo.listFileSync(dir)
      for (const name of names) {
        const lower: string = name.toLowerCase()
        if (lower.endsWith('.ttf') || lower.endsWith('.otf')) {
          const family: string = name.substring(0, name.lastIndexOf('.'))
          fonts.push(new FontInfo(family, `${dir}/${name}`))
        }
      }
    } catch (e) {
      logger.error(`list 失败: ${e}`)
    }
    return fonts
  }

  /** 注册单个字体（需在 UIContext 初始化后调用） */
  static register(info: FontInfo): void {
    try {
      _QhState.UIContext.getFont().registerFont({
        familyName: info.family,
        familySrc: `file://${info.path}`
      })
    } catch (e) {
      logger.error(`register 失败: ${e}`)
    }
  }

  /** 启动时注册沙箱内全部字体 */
  static registerAll(): void {
    const fonts: FontInfo[] = FontStore.list()
    for (const f of fonts) {
      FontStore.register(f)
    }
  }

  /**
   * 从文档选择器返回的 uri 导入字体：拷贝到沙箱 fonts 目录并注册。
   * @return 成功返回字体 family 名，失败返回空串
   */
  static addFromUri(uri: string): string {
    try {
      const name: string = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1))
      const lower: string = name.toLowerCase()
      if (!lower.endsWith('.ttf') && !lower.endsWith('.otf')) {
        return ''
      }
      const dir: string = FontStore.fontsDir()
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true)
      }
      const family: string = name.substring(0, name.lastIndexOf('.'))
      const destPath: string = `${dir}/${name}`
      const src: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const dest: fileIo.File = fileIo.openSync(destPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        try {
          fileIo.copyFileSync(src.fd, dest.fd)
        } finally {
          fileIo.closeSync(dest)
        }
      } finally {
        fileIo.closeSync(src)
      }
      FontStore.register(new FontInfo(family, destPath))
      return family
    } catch (e) {
      logger.error(`addFromUri 失败: ${e}`)
      return ''
    }
  }

  /** 删除沙箱内指定字体文件（选中状态重置由调用方处理） */
  static remove(family: string): boolean {
    try {
      const fonts: FontInfo[] = FontStore.list()
      const found: FontInfo | undefined = fonts.find((f: FontInfo): boolean => f.family === family)
      if (!found) {
        return false
      }
      fileIo.unlinkSync(found.path)
      return true
    } catch (e) {
      logger.error(`remove 失败: ${e}`)
      return false
    }
  }
}
