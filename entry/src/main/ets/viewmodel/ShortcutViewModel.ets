import { productViewManager } from '@kit.AppGalleryKit';
import { Want } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { QhState, _QhState } from '../entryability/AppState';
import { ColorUtils } from '../common/utils/ui/ColorUtils';
import { toastUtil } from '../common/utils/ui/ToastUtils';
import { faviconCache, FaviconCache } from './FaviconCache';

/** 生成首字头像图标（主题色底 + 白色首字），兜底方案 */
function makeAvatarIcon(title: string, savePath: string): boolean {
  try {
    const size: number = 256
    const canvas: OffscreenCanvas = new OffscreenCanvas(size, size)
    const ctx: OffscreenCanvasRenderingContext2D = canvas.getContext('2d', new RenderingContextSettings(true))
    const argb: number = ColorUtils.getColorWithAlpha(QhState.currentThemeColor, 255)
    const themeHex: string = `#${(argb & 0x00FFFFFF).toString(16).padStart(6, '0')}`
    ctx.fillStyle = themeHex
    ctx.fillRect(0, 0, size, size)
    ctx.fillStyle = '#FFFFFF'
    ctx.font = 'bold 120px sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(title.length > 0 ? title.substring(0, 1) : '?', size / 2, size / 2)
    const dataUrl: string = ctx.toDataURL('image/png')
    const b64: string = dataUrl.substring(dataUrl.indexOf(',') + 1)
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(b64)
    const file: fileIo.File = fileIo.openSync(savePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
    fileIo.closeSync(file)
    return true
  } catch (e) {
    return false
  }
}

/**
 * 桌面快捷方式：书签右键与菜单「添加到桌面」共用
 * （favicon 缓存 → 站点图标抓取 → 首字头像兜底 → checkPinShortcutPermitted + requestNewPinShortcut）
 */
export class ShortcutViewModel {

  /** URL → 稳定短 key（djb2 哈希），同一页面重复添加复用同一快捷方式 id */
  static urlKey(url: string): string {
    let h: number = 5381
    for (let i = 0; i < url.length; i++) {
      h = ((h << 5) + h + url.charCodeAt(i)) >>> 0
    }
    return h.toString(36)
  }

  /** 快捷方式图标目录（专门文件夹，避免图标散放在 files 根目录） */
  static iconDir(): string {
    const dir: string = `${_QhState.Context.filesDir}/shortcut_icons`
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir)
    }
    return dir
  }

  /** 旧版图标曾散放在 files 根目录：启动时迁入专门文件夹 */
  static migrateLegacyIcons(): void {
    try {
      const filesDir: string = _QhState.Context.filesDir
      const dir: string = ShortcutViewModel.iconDir()
      const names: string[] = fileIo.listFileSync(filesDir)
      for (const name of names) {
        if (name.startsWith('shortcut_icon_') && name.endsWith('.png')) {
          fileIo.moveFileSync(`${filesDir}/${name}`, `${dir}/${name}`)
        }
      }
    } catch (e) {
      console.error(`[ShortcutViewModel] 旧图标迁移失败: ${e}`)
    }
  }

  /** 添加快捷方式进行中标记：防止启动清理误删正在创建的图标 */
  private static adding: boolean = false

  /**
   * 清理孤儿图标：对照桌面已固定快捷方式列表，
   * 删除 shortcut_icons 目录中不再被引用的图标（如用户已从桌面移除的网页快捷方式残留）
   */
  static async cleanOrphanIcons(): Promise<void> {
    if (ShortcutViewModel.adding) {
      return
    }
    try {
      const dir: string = ShortcutViewModel.iconDir()
      const names: string[] = fileIo.listFileSync(dir)
      if (names.length === 0) {
        return
      }
      const pinned: Set<string> = new Set<string>()
      // API 24+；低版本设备抛 801（不支持）直接跳过清理
      const infos: productViewManager.PinShortcutInfo[] = await productViewManager.getPinShortcutInfos()
      for (const info of infos) {
        pinned.add(info.shortcutId)
      }
      for (const name of names) {
        if (!name.startsWith('shortcut_icon_') || !name.endsWith('.png')) {
          continue
        }
        const key: string = name.substring('shortcut_icon_'.length, name.length - '.png'.length)
        if (!pinned.has(key)) {
          fileIo.unlinkSync(`${dir}/${name}`)
        }
      }
    } catch (e) {
      console.error(`[ShortcutViewModel] 孤儿图标清理失败: ${e}`)
    }
  }

  async addToDesktop(shortcutKey: string, title: string, url: string): Promise<void> {
    ShortcutViewModel.adding = true
    try {
      const savePath: string = `${ShortcutViewModel.iconDir()}/shortcut_icon_${shortcutKey}.png`
      const host: string = FaviconCache.hostOf(url)
      // 优先复用 favicon 缓存（页面加载/懒加载已抓取），无缓存再按 URL 抓取站点图标
      let iconReady: boolean = faviconCache.copyTo(host, savePath)
      if (!iconReady) {
        iconReady = await faviconCache.fetchAsync(url) && faviconCache.copyTo(host, savePath)
      }
      if (!iconReady) {
        iconReady = makeAvatarIcon(title, savePath)
      }
      if (!iconReady) {
        toastUtil.showToast({ message: $r('app.string.bookmark_desktop_failed') })
        return
      }
      const want: Want = {
        bundleName: 'com.ya.qinghong',
        moduleName: 'entry',
        abilityName: 'EntryAbility',
        parameters: { 'url': url }
      }
      const result: productViewManager.CheckShortcutResult =
        await productViewManager.checkPinShortcutPermitted(_QhState.Context, shortcutKey, want,
          title, savePath, '')
      await productViewManager.requestNewPinShortcut(_QhState.Context, result.tid ?? '')
      toastUtil.showToast({ message: $r('app.string.bookmark_desktop_added') })
    } catch (e) {
      console.error(`[ShortcutViewModel] 添加至桌面失败: ${e}`)
      toastUtil.showToast({ message: $r('app.string.bookmark_desktop_failed') })
    } finally {
      ShortcutViewModel.adding = false
    }
  }
}

export const shortcutVM: ShortcutViewModel = new ShortcutViewModel()
