import { NaviContainer, NaviBarButton } from '../components/NaviContainer';
import { QhState, _QhState } from '../entryability/AppState';
import { CustomContentDialog } from '@kit.ArkUI';
import { browserVM } from '../viewmodel/BrowserViewModel';
import { bookmarkVM } from '../viewmodel/BookmarkViewModel';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import { menuVM } from '../viewmodel/MenuViewModel';
import { tabsVM } from '../viewmodel/TabsViewModel';
import { CustomListItem } from '../components/CusItemBuilder';
import { CustomItemInfo, ItemActionType, ContextMenuItem } from '../common/entity/CusItemInfo';
import { buildDialogButtons } from '../components/dialog/AppContentDialog';
import { toastUtil } from '../common/utils/ToastUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { systemShare } from '@kit.ShareKit';
import { productViewManager } from '@kit.AppGalleryKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { ColorUtils } from '../common/utils/ColorUtils';
import { BookmarkEditor } from '../components/browser/BookmarkEditor';

const SHORTCUT_UA: string = 'Mozilla/5.0 (Linux; Android 14) Mobile Safari/537.36'

/** https://host[:port]/path → https://host[:port] */
function originOf(url: string): string {
  const idx: number = url.indexOf('://')
  if (idx < 0) {
    return ''
  }
  const rest: string = url.substring(idx + 3)
  const slash: number = rest.indexOf('/')
  return slash < 0 ? url : url.substring(0, idx + 3 + slash)
}

/** 相对 href → 绝对地址（其余格式放弃） */
function absoluteUrl(href: string, origin: string): string {
  if (href.startsWith('http://') || href.startsWith('https://')) {
    return href
  }
  if (href.startsWith('//')) {
    return `https:${href}`
  }
  if (href.startsWith('/')) {
    return `${origin}${href}`
  }
  return ''
}

/** 解析 HTML 内 link 图标候选（apple-touch-icon 优先） */
function parseIconLinks(html: string, origin: string): string[] {
  const apple: string[] = []
  const icons: string[] = []
  const tags: string[] | null = html.match(/<link[^>]+>/gi)
  if (tags === null) {
    return []
  }
  for (const tag of tags) {
    const relM: RegExpMatchArray | null = tag.match(/rel\s*=\s*["'][^"']*["']/i)
    if (relM === null || !/icon/i.test(relM[0])) {
      continue
    }
    const hrefM: RegExpMatchArray | null = tag.match(/href\s*=\s*["']([^"']+)["']/i)
    if (hrefM === null) {
      continue
    }
    const abs: string = absoluteUrl(hrefM[1], origin)
    if (abs === '') {
      continue
    }
    if (/apple-touch-icon/i.test(relM[0])) {
      apple.push(abs)
    } else {
      icons.push(abs)
    }
  }
  const out: string[] = []
  for (const a of apple) {
    out.push(a)
  }
  for (const i of icons) {
    out.push(i)
  }
  return out
}

function isPng(bytes: Uint8Array): boolean {
  return bytes.length > 24 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47
}

function isWebp(bytes: Uint8Array): boolean {
  return bytes.length > 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
}

/** PNG IHDR 宽度（像素） */
function pngWidth(bytes: Uint8Array): number {
  return (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19]
}

/** 下载图标候选：校验 PNG/WEBP 魔数、尺寸下限与 100KB 上限后写入沙箱 */
async function downloadIcon(url: string, savePath: string): Promise<boolean> {
  const client: http.HttpRequest = http.createHttp()
  try {
    const headers: Record<string, string> = { 'User-Agent': SHORTCUT_UA }
    const resp: http.HttpResponse = await client.request(url, {
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false,
      connectTimeout: 5000,
      readTimeout: 5000,
      header: headers
    })
    const result: string | Object | ArrayBuffer | undefined = resp.result
    if (!(result instanceof ArrayBuffer)) {
      return false
    }
    const bytes: Uint8Array = new Uint8Array(result)
    if (bytes.byteLength < 64 || bytes.byteLength > 100 * 1024) {
      return false
    }
    if (isPng(bytes)) {
      if (pngWidth(bytes) < 64) {
        return false
      }
    } else if (!isWebp(bytes)) {
      return false
    }
    const file: fileIo.File = fileIo.openSync(savePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
    fileIo.closeSync(file)
    return true
  } catch (e) {
    return false
  } finally {
    client.destroy()
  }
}

/** 尝试抓取网站自身图标（站点 HTML link 解析 + PNG/WEBP 校验） */
async function fetchSiteIcon(pageUrl: string, savePath: string): Promise<boolean> {
  const origin: string = originOf(pageUrl)
  if (origin === '') {
    return false
  }
  let html: string = ''
  const client: http.HttpRequest = http.createHttp()
  try {
    const headers: Record<string, string> = { 'User-Agent': SHORTCUT_UA }
    const resp: http.HttpResponse = await client.request(origin, {
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: 5000,
      readTimeout: 8000,
      header: headers
    })
    if (typeof resp.result === 'string') {
      html = resp.result
    }
  } catch (e) {
    html = ''
  } finally {
    client.destroy()
  }
  if (html === '') {
    return false
  }
  const candidates: string[] = parseIconLinks(html, origin)
  let count: number = 0
  for (const c of candidates) {
    if (count >= 4) {
      break
    }
    count++
    if (await downloadIcon(c, savePath)) {
      return true
    }
  }
  return false
}

/** 生成书签首字头像图标（主题色底 + 白色首字），兜底方案 */
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

@Builder
export function BookmarkBuilder() {
  BookmarkPage()
}

@ComponentV2
struct BookmarkPage {
  private pageStack: NavPathStack = new NavPathStack()
  /** 当前层级文件夹路径（'' = 根） */
  @Local currentFolder: string = ''
  /** 编辑（多选）模式 */
  @Local selectMode: boolean = false
  /** 已选中项：b_<id> | f_<path> */
  @Local selectedKeys: string[] = []
  /** 编辑栏「更多」菜单可见性 */
  @Local showMoreMenu: boolean = false
  /** 书签页自建编辑器 sheet（添加书签 / 编辑文件夹复用） */
  @Local showEditorSheet: boolean = false
  /** 编辑书签对话框 */
  @Local editBookmarkId: number = -1
  @Local editTitleInput: string = ''
  @Local editUrlInput: string = ''
  private editBookmarkDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    bookmarkVM.loadAll()
    this.editBookmarkDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.bookmark_edit_title'),
        contentBuilder: (): void => {
          this.editBookmarkDialogContent()
        },
        buttons: buildDialogButtons([$r('app.string.cancel'), $r('app.string.save')], false,
          (index: number): void => {
            if (index === 1) {
              this.doEditBookmark()
            }
            this.editBookmarkDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 },
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  private doEditBookmark(): void {
    const url = this.editUrlInput.trim()
    if (url === '') {
      toastUtil.showToast({ message: $r('app.string.bookmark_url_hint') })
      return
    }
    bookmarkVM.updateBookmark(this.editBookmarkId, this.editTitleInput.trim() || url, url)
    if (this.selectMode) {
      this.exitSelectMode()
    }
  }

  private displayName(path: string): string {
    const segs: string[] = path.split('/')
    return segs.length > 0 ? segs[segs.length - 1] : path
  }

  private bookmarksIn(folder: string): BookmarkInfo[] {
    const out: BookmarkInfo[] = []
    for (const b of bookmarkVM.bookmarks) {
      if (b.folder === folder) {
        out.push(b)
      }
    }
    return out
  }

  private findBookmarkById(id: number): BookmarkInfo | null {
    for (const b of bookmarkVM.bookmarks) {
      if (b.id === id) {
        return b
      }
    }
    return null
  }

  private openBookmark(b: BookmarkInfo): void {
    browserVM.openUrl(b.url)
    // 弹出全部书签路由页（含各级文件夹页），回到浏览器
    while (this.pageStack.size() > 0) {
      this.pageStack.pop(false)
    }
  }

  // —— 编辑（多选）模式 ——

  private enterSelect(key: string): void {
    this.selectMode = true
    this.selectedKeys = [key]
  }

  private exitSelectMode(): void {
    this.selectMode = false
    this.selectedKeys = []
  }

  private isSelected(key: string): boolean {
    return this.selectedKeys.includes(key)
  }

  private toggleKey(key: string): void {
    if (this.isSelected(key)) {
      const next: string[] = []
      for (const k of this.selectedKeys) {
        if (k !== key) {
          next.push(k)
        }
      }
      this.selectedKeys = next
      return
    }
    const next: string[] = this.selectedKeys.slice(0)
    next.push(key)
    this.selectedKeys = next
  }

  private selectedFolderPaths(): string[] {
    const out: string[] = []
    for (const k of this.selectedKeys) {
      if (k.startsWith('f_')) {
        out.push(k.substring(2))
      }
    }
    return out
  }

  private selectedBookmarkIds(): number[] {
    const out: number[] = []
    for (const k of this.selectedKeys) {
      if (k.startsWith('b_')) {
        const n: number = Number(k.substring(2))
        if (!Number.isNaN(n)) {
          out.push(n)
        }
      }
    }
    return out
  }

  private allKeysAtLevel(): string[] {
    const keys: string[] = []
    for (const p of menuVM.childFolders(this.currentFolder)) {
      keys.push(`f_${p}`)
    }
    for (const b of this.bookmarksIn(this.currentFolder)) {
      keys.push(`b_${b.id}`)
    }
    return keys
  }

  private toggleSelectAll(): void {
    const all: string[] = this.allKeysAtLevel()
    const everySelected: boolean = all.length > 0 &&
      all.every((k: string): boolean => this.isSelected(k))
    this.selectedKeys = everySelected ? [] : all
  }

  /** 更多菜单可用：单文件夹 或 任意数量书签（混合/多文件夹置灰） */
  private moreMenuAvailable(): boolean {
    const f: number = this.selectedFolderPaths().length
    const b: number = this.selectedBookmarkIds().length
    return (f === 1 && b === 0) || (f === 0 && b >= 1)
  }

  private moveSelection(): void {
    const paths: string[] = this.selectedFolderPaths()
    const ids: number[] = this.selectedBookmarkIds()
    if (paths.length === 0 && ids.length === 0) {
      return
    }
    this.exitSelectMode()
    menuVM.openMovePicker(this.pageStack, paths, ids)
  }

  private deleteSelection(): void {
    const ids: number[] = this.selectedBookmarkIds()
    const paths: string[] = this.selectedFolderPaths()
    for (const id of ids) {
      bookmarkVM.deleteBookmark(id)
    }
    for (const p of paths) {
      menuVM.deleteFolder(p)
    }
    this.exitSelectMode()
    toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
  }

  private openSelectionInNewTabs(): void {
    for (const id of this.selectedBookmarkIds()) {
      const b: BookmarkInfo | null = this.findBookmarkById(id)
      if (b !== null) {
        tabsVM.newTab(b.url)
      }
    }
    this.exitSelectMode()
  }

  private shareSelection(): void {
    const b: BookmarkInfo | null = this.findBookmarkById(this.selectedBookmarkIds()[0])
    if (b !== null) {
      this.shareBookmark(b)
    }
  }

  // —— 单项操作 ——

  private shareBookmark(b: BookmarkInfo): void {
    try {
      const data = new systemShare.SharedData({
        utd: 'general.hyperlink',
        content: b.url,
        title: b.title
      })
      const controller = new systemShare.ShareController(data)
      controller.show(_QhState.Context, {})
        .catch((error: BusinessError): void => {
          console.error(`[BookmarkPage] 分享失败: ${error.code} ${error.message}`)
        })
    } catch (e) {
      console.error(`[BookmarkPage] 分享异常: ${e}`)
    }
  }

  private openInNewTab(b: BookmarkInfo): void {
    tabsVM.newTab(b.url)
  }

  private async addToDesktop(b: BookmarkInfo): Promise<void> {
    try {
      const savePath: string = `${_QhState.Context.filesDir}/bookmark_shortcut_${b.id}.png`
      let iconReady: boolean = await fetchSiteIcon(b.url, savePath)
      if (!iconReady) {
        iconReady = makeAvatarIcon(b.title, savePath)
      }
      if (!iconReady) {
        toastUtil.showToast({ message: $r('app.string.bookmark_desktop_failed') })
        return
      }
      const want: Want = {
        bundleName: 'com.ya.qinghong',
        moduleName: 'entry',
        abilityName: 'EntryAbility',
        parameters: { 'url': b.url }
      }
      const result: productViewManager.CheckShortcutResult =
        await productViewManager.checkPinShortcutPermitted(_QhState.Context, `bm_${b.id}`, want,
          b.title, savePath, '')
      await productViewManager.requestNewPinShortcut(_QhState.Context, result.tid ?? '')
      toastUtil.showToast({ message: $r('app.string.bookmark_desktop_added') })
    } catch (e) {
      console.error(`[BookmarkPage] 添加至桌面失败: ${e}`)
      toastUtil.showToast({ message: $r('app.string.bookmark_desktop_failed') })
    }
  }

  private openBookmarkEdit(id: number): void {
    const b: BookmarkInfo | null = this.findBookmarkById(id)
    if (b === null) {
      return
    }
    this.editBookmarkId = id
    this.editTitleInput = b.title
    this.editUrlInput = b.url
    this.editBookmarkDialog?.open()
  }

  private openFolderEdit(path: string): void {
    if (this.selectMode) {
      this.exitSelectMode()
    }
    menuVM.prepareEditFolder(path)
    menuVM.onEditorClosed = (): void => {
      this.showEditorSheet = false
    }
    this.showEditorSheet = true
  }

  /** 右上角添加书签：半模态编辑器（默认落在当前层级） */
  private openAddEditor(): void {
    menuVM.prepareNewBookmark(this.currentFolder)
    menuVM.onEditorClosed = (): void => {
      this.showEditorSheet = false
    }
    this.showEditorSheet = true
  }

  private folderCtxMenu(path: string): ContextMenuItem[] {
    const items: ContextMenuItem[] = []
    items.push(new ContextMenuItem($r('app.string.bookmark_multi_select'), (): void => {
      this.enterSelect(`f_${path}`)
    }, $r('sys.symbol.checkmark_circle')))
    items.push(new ContextMenuItem($r('app.string.bookmark_edit_folder'), (): void => {
      this.openFolderEdit(path)
    }, $r('sys.symbol.square_and_pencil')))
    items.push(new ContextMenuItem($r('app.string.bookmark_move_to'), (): void => {
      menuVM.openMovePicker(this.pageStack, [path], [])
    }, $r('sys.symbol.arrow_right_circle')))
    items.push(new ContextMenuItem($r('app.string.delete'), (): void => {
      menuVM.deleteFolder(path)
      toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
    }, $r('sys.symbol.trash'), true))
    return items
  }

  private bookmarkCtxMenu(b: BookmarkInfo): ContextMenuItem[] {
    const items: ContextMenuItem[] = []
    items.push(new ContextMenuItem($r('app.string.bookmark_multi_select'), (): void => {
      this.enterSelect(`b_${b.id}`)
    }, $r('sys.symbol.checkmark_circle')))
    items.push(new ContextMenuItem($r('app.string.share'), (): void => {
      this.shareBookmark(b)
    }, $r('sys.symbol.share')))
    items.push(new ContextMenuItem($r('app.string.bookmark_edit_title'), (): void => {
      if (b.id !== null) {
        this.openBookmarkEdit(b.id)
      }
    }, $r('sys.symbol.square_and_pencil')))
    items.push(new ContextMenuItem($r('app.string.bookmark_add_desktop'), (): void => {
      this.addToDesktop(b)
    }, $r('sys.symbol.house')))
    items.push(new ContextMenuItem($r('app.string.bookmark_open_new_tab'), (): void => {
      this.openInNewTab(b)
    }, $r('sys.symbol.arrow_up_right')))
    items.push(new ContextMenuItem($r('app.string.delete'), (): void => {
      if (b.id !== null) {
        bookmarkVM.deleteBookmark(b.id)
        toastUtil.showToast({ message: $r('app.string.bookmark_deleted') })
      }
    }, $r('sys.symbol.trash'), true))
    return items
  }

  private folderItem(path: string): CustomItemInfo {
    const key: string = `f_${path}`
    if (this.selectMode) {
      return new CustomItemInfo({
        id: key,
        symbol: $r('sys.symbol.folder'),
        title: this.displayName(path),
        type: ItemActionType.CHECK,
        value: this.isSelected(key),
        onChange: (): void => {
          this.toggleKey(key)
        }
      })
    }
    return new CustomItemInfo({
      id: key,
      symbol: $r('sys.symbol.folder'),
      title: this.displayName(path),
      type: ItemActionType.ROUTER,
      value: '',
      contextMenuItems: this.folderCtxMenu(path),
      onChange: (): void => {
        this.pageStack.pushPathByName('bookmarks', path)
      }
    })
  }

  private bookmarkItem(b: BookmarkInfo): CustomItemInfo {
    const key: string = `b_${b.id}`
    if (this.selectMode) {
      return new CustomItemInfo({
        id: key,
        title: b.title,
        subtitle: b.url,
        type: ItemActionType.CHECK,
        value: this.isSelected(key),
        onChange: (): void => {
          this.toggleKey(key)
        }
      })
    }
    return new CustomItemInfo({
      id: key,
      title: b.title,
      subtitle: b.url,
      type: ItemActionType.ROUTER_BLANK,
      value: '',
      contextMenuItems: this.bookmarkCtxMenu(b),
      onChange: (): void => {
        this.openBookmark(b)
      }
    })
  }

  private pageTitle(): ResourceStr {
    if (this.selectMode) {
      return ResourceUtils.getStringWithArgs($r('app.string.bookmark_selected_count'),
        [this.selectedKeys.length])
    }
    return this.currentFolder === '' ? $r('app.string.bookmarks') : this.displayName(this.currentFolder)
  }

  private navButtons(): NaviBarButton[] {
    if (this.selectMode) {
      return [
        new NaviBarButton({
          symbol: $r('sys.symbol.xmark'),
          action: (): void => {
            this.exitSelectMode()
          }
        })
      ]
    }
    return [
      new NaviBarButton({
        symbol: $r('sys.symbol.plus'),
        action: (): void => {
          this.openAddEditor()
        }
      })
    ]
  }

  @Builder
  editBookmarkDialogContent() {
    Column({ space: 12 }) {
      TextInput({ text: this.editTitleInput, placeholder: $r('app.string.bookmark_title_hint') })
        .height(44)
        .fontSize(15)
        .onChange((v: string) => {
          this.editTitleInput = v
        })
      TextInput({ text: this.editUrlInput, placeholder: $r('app.string.bookmark_url_hint') })
        .height(44)
        .fontSize(15)
        .type(InputType.URL)
        .onChange((v: string) => {
          this.editUrlInput = v
        })
    }
    .width('100%')
  }

  @Builder
  avatar(b: BookmarkInfo) {
    Text(b.title.length > 0 ? b.title.substring(0, 1) : '?')
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .width(36)
      .height(36)
      .textAlign(TextAlign.Center)
      .borderRadius(18)
      .backgroundColor(QhState.currentThemeColor)
  }

  @Builder
  barItem(label: ResourceStr, symbol: Resource, color: ResourceColor, onTap: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([color])
      Text(label)
        .fontSize(11)
        .fontColor(color)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(onTap)
  }

  @Builder
  editBar() {
    Column() {
      Row() {
        this.barItem($r('app.string.bookmark_move_to'), $r('sys.symbol.arrow_right_circle'),
          this.selectedKeys.length > 0 ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'),
          (): void => {
            if (this.selectedKeys.length > 0) {
              this.moveSelection()
            }
          })
        this.barItem($r('app.string.delete'), $r('sys.symbol.trash'),
          this.selectedKeys.length > 0 ? Color.Red : $r('sys.color.font_tertiary'),
          (): void => {
            if (this.selectedKeys.length > 0) {
              this.deleteSelection()
            }
          })
        this.barItem($r('app.string.select_all'), $r('sys.symbol.checkmark_circle'),
          $r('sys.color.font_primary'),
          (): void => {
            this.toggleSelectAll()
          })
        this.moreBarItem()
      }
      .width('100%')
      .height(56)
    }
    .width('100%')
    .backgroundColor($r('app.color.background_color'))
    .padding({ bottom: QhState.bottomRectHeight })
  }

  /** 更多按钮：菜单直接锚定在本按钮上方 */
  @Builder
  moreBarItem() {
    Column({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontSize(22)
        .fontColor([this.moreMenuAvailable() ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')])
      Text($r('app.string.more'))
        .fontSize(11)
        .fontColor(this.moreMenuAvailable() ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary'))
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (this.moreMenuAvailable()) {
        this.showMoreMenu = true
      }
    })
    .bindMenu(this.showMoreMenu, this.moreMenu, {
      placement: Placement.Top,
      onDisappear: (): void => {
        this.showMoreMenu = false
      }
    })
  }

  @Builder
  moreMenu() {
    Menu() {
      if (this.selectedFolderPaths().length === 1 && this.selectedBookmarkIds().length === 0) {
        MenuItem({ content: $r('app.string.edit') })
          .onClick(() => {
            this.openFolderEdit(this.selectedFolderPaths()[0])
          })
      } else {
        MenuItem({ content: $r('app.string.bookmark_open_new_tab') })
          .onClick(() => {
            this.openSelectionInNewTabs()
          })
        if (this.selectedBookmarkIds().length === 1) {
          MenuItem({ content: $r('app.string.edit') })
            .onClick(() => {
              this.openBookmarkEdit(this.selectedBookmarkIds()[0])
            })
          MenuItem({ content: $r('app.string.share') })
            .onClick(() => {
              this.shareSelection()
            })
        }
      }
    }
    .backgroundColor($r('app.color.start_window_background'))
    .borderRadius(20)
  }

  @Builder
  pageContent() {
    Column() {
      if (!this.selectMode && menuVM.childFolders(this.currentFolder).length === 0 &&
        this.bookmarksIn(this.currentFolder).length === 0) {
        Column() {
          Text($r('app.string.empty_bookmarks'))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Column() {
              ForEach(menuVM.childFolders(this.currentFolder), (path: string) => {
                CustomListItem({
                  item: this.folderItem(path),
                  itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                })
              }, (path: string) => `f_${path}`)
              ForEach(this.bookmarksIn(this.currentFolder), (b: BookmarkInfo) => {
                CustomListItem({
                  item: this.bookmarkItem(b),
                  icon: (): void => {
                    this.avatar(b)
                  },
                  itemPadding: { left: 16, right: 16, top: 12, bottom: 12 }
                })
              }, (b: BookmarkInfo) => `b_${b.id}`)
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor($r('app.color.background_color'))
            .clip(true)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      if (this.selectMode) {
        this.editBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_color_accent'))
  }

  /** 书签页自建编辑器 sheet（与浏览器菜单同款半模态） */
  @Builder
  editorSheetBuilder() {
    BookmarkEditor()
  }

  build() {
    NaviContainer({
      title: this.pageTitle(),
      buttons: this.navButtons(),
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.pageStack = ctx.pathStack
        const p: Object | undefined = ctx.pathInfo.param
        if (p !== undefined && typeof p === 'string') {
          this.currentFolder = p
        }
      },
      onBackPressed: (): boolean => {
        if (this.selectMode) {
          this.exitSelectMode()
          return true
        }
        return false
      }
    })
    .bindSheet(this.showEditorSheet, this.editorSheetBuilder(), {
      height: 560,
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showEditorSheet = false
      }
    })
  }
}
