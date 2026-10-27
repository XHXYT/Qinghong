import { QhState, _QhState } from '../entryability/AppState';
import { tabsVM } from './TabsViewModel';
import { browserVM } from './BrowserViewModel';
import { bookmarkVM } from './BookmarkViewModel';
import BookmarkInfo from '../common/entity/BookmarkInfo';
import { toastUtil } from '../common/utils/ToastUtils';
import { appSettings } from '../common/entity/SettingsModel';
import { MenuEntry, MenuEntries } from '../common/constants/MenuEntries';
import { PickerConfig, PickerOption, pickerSheetHeight } from '../components/SheetPicker';
import { UaUtils } from '../common/utils/UaUtils';
import { SettingsUtils } from '../common/utils/SettingsUtils';
import { ResourceUtils } from '../common/utils/ResourceUtil';
import { SiteSettingsViewModel, SitePolicy, siteSettingsVM } from './SiteSettingsViewModel';
import { CustomItemInfo, ItemActionType, RadioConfig } from '../common/entity/CusItemInfo';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError, print } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { adBlockEngine } from '../common/utils/AdBlockEngine';
import { inspectorVM } from './InspectorViewModel';
import { webview } from '@kit.ArkWeb';
import { downloadVM } from './DownloadViewModel';
import { sniffVM } from './SniffViewModel';
import { offlinePageVM } from './OfflinePageViewModel';
import { readAloudVM } from './ReadAloudViewModel';
import { shortcutVM, ShortcutViewModel } from './ShortcutViewModel';
import { PublicDownloadDir } from '../common/utils/PublicDownloadDir';
import { createLogger } from '../common/utils/Logger';

const logger = createLogger('MenuVM');

/**
 * 文件夹选择行：通用列表行数据 + 缩进层级
 */
export class FolderRowInfo {
  readonly item: CustomItemInfo
  readonly indent: number

  constructor(item: CustomItemInfo, indent: number) {
    this.item = item
    this.indent = indent
  }
}

/**
 * 主菜单（≡ 宫格菜单）视图模型：菜单分页/条目状态/点击分发/各半模态交互
 */
@ObservedV2
export class MenuViewModel {
  /** 菜单宫格是否展开 */
  @Trace showMenu: boolean = false
  /** 半模态单选选择器状态 */
  @Trace picker: PickerConfig = new PickerConfig()
  @Trace pickerHeight: number = pickerSheetHeight(3)
  /** 字号滑杆状态 */
  @Trace fontZoomValue: number = 100
  /** 工具栏半模态（选择器/字号滑杆共用一个 sheet，按 sheetKind 切换内容） */
  @Trace showSheet: boolean = false
  /** sheet 内容类型：picker=单选选择器 | font=字号滑杆 | save=保存网页（打开时设置，关闭过程中不变） */
  sheetKind: string = 'picker'
  /** 保存网页弹窗：保存名（预填页面标题，可改） */
  @Trace saveName: string = ''
  /** 保存网页弹窗：勾选保存为PDF（直接存 PDF 不进打印预览） */
  @Trace saveAsPdf: boolean = false
  /** 添加书签流程状态（编辑器局部路由共享） */
  /** 编辑器局部路由栈（全屏 cover 内 Navigation，独立于主路由） */
  editorStack: NavPathStack = new NavPathStack()
  /** 添加书签编辑器可见性 */
  @Trace showBookmarkEditor: boolean = false
  /** 编辑态：当前页已收藏，编辑存储的书签数据 */
  @Trace editorIsEdit: boolean = false
  /** 文件夹选择页服务对象：bookmark 书签位置（带添加按钮） | newFolder 新文件夹的父位置（不带） */
  @Trace folderPickerTarget: string = 'bookmark'
  @Trace bmTitle: string = ''
  @Trace bmUrl: string = ''
  @Trace bmFolder: string = ''
  @Trace bmQuick: boolean = false
  /** 书签编辑器：自定义图标沙箱路径（'' = 未自定义） */
  @Trace bmIcon: string = ''
  @Trace newFolderName: string = ''
  @Trace newFolderParent: string = ''
  /** 文件夹注册表（路径数组，顺序即显示顺序） */
  @Trace folderList: string[] = []
  /** 文件夹选择页行（根目录 + 树形缩进 + 选中态） */
  @Trace folderRows: FolderRowInfo[] = []
  /** 移动场景：文件夹选择页走主路由栈（书签页发起）；null = 编辑器局部栈 */
  private folderPickerMainStack: NavPathStack | null = null
  /** 移动场景：待移动的文件夹列表 */
  private moveFolderSources: string[] = []
  /** 移动场景：待移动的书签 id 列表 */
  private moveBookmarkIds: number[] = []
  /** 编辑器 sheet 关闭回调（书签页等自建宿主同步关闭自己的 sheet） */
  onEditorClosed: (() => void) | null = null
  /** 编辑器正在编辑的书签 id（-1 = 新增；用于保存时区分插入/更新） */
  private editingId: number = -1
  /** 文件夹编辑模式（新建文件夹页兼做编辑文件夹页） */
  @Trace folderEditMode: boolean = false
  /** 待编辑文件夹路径 */
  editFolderPath: string = ''

  // —— 主编辑页通用行 ——
  readonly nameItem: CustomItemInfo = new CustomItemInfo({
    id: 'bm_name',
    type: ItemActionType.INPUT,
    title: $r('app.string.bookmark_field_name'),
    subtitle: $r('app.string.bookmark_title_hint'),
    onChange: (v: string | boolean | number): void => {
      this.bmTitle = v as string
    }
  })
  readonly urlItem: CustomItemInfo = new CustomItemInfo({
    id: 'bm_url',
    type: ItemActionType.INPUT,
    title: $r('app.string.bookmark_field_url'),
    subtitle: $r('app.string.bookmark_url_hint'),
    onChange: (v: string | boolean | number): void => {
      this.bmUrl = v as string
    }
  })
  readonly folderItem: CustomItemInfo = new CustomItemInfo({
    id: 'bm_folder',
    type: ItemActionType.ROUTER,
    title: $r('app.string.bookmark_field_folder'),
    onChange: (): void => {
      this.openFolderPicker('bookmark')
    }
  })
  readonly quickItem: CustomItemInfo = new CustomItemInfo({
    id: 'bm_quick',
    type: ItemActionType.TOGGLE,
    title: $r('app.string.add_home_favorite'),
    onChange: (v: string | boolean | number): void => {
      this.bmQuick = v as boolean
    }
  })
  // —— 新建文件夹页通用行 ——
  readonly newFolderNameItem: CustomItemInfo = new CustomItemInfo({
    id: 'nf_name',
    type: ItemActionType.INPUT,
    title: $r('app.string.bookmark_field_name'),
    subtitle: $r('app.string.bookmark_folder_name_hint'),
    onChange: (v: string | boolean | number): void => {
      this.newFolderName = v as string
    }
  })
  readonly newFolderParentItem: CustomItemInfo = new CustomItemInfo({
    id: 'nf_parent',
    type: ItemActionType.ROUTER,
    title: $r('app.string.bookmark_field_folder'),
    onChange: (): void => {
      this.openFolderPicker('newFolder')
    }
  })

  /** 打开书签编辑器：已收藏则编辑存储数据，否则预填当前页 */
  openBookmarkEditor(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) return
    const existing: BookmarkInfo | null = bookmarkVM.findByUrl(tab.url)
    this.editorIsEdit = existing !== null
    this.bmTitle = existing !== null ? existing.title : tab.title
    this.bmUrl = tab.url
    this.bmFolder = existing !== null ? existing.folder : ''
    this.bmQuick = existing !== null ? existing.isQuick : false
    this.bmIcon = existing !== null ? existing.icon : ''
    this.editingId = existing !== null && existing.id !== null ? existing.id : -1
    this.folderPickerTarget = 'bookmark'
    this.nameItem.value = this.bmTitle
    this.urlItem.value = this.bmUrl
    this.folderItem.value = this.folderPathLabel(this.bmFolder)
    this.quickItem.value = this.bmQuick
    this.newFolderName = ''
    this.newFolderNameItem.value = ''
    this.newFolderParent = ''
    this.newFolderParentItem.value = this.folderPathLabel('')
    this.loadFolderRegistry()
    this.editorStack.removeByName('bookmark_select_folder')
    this.editorStack.removeByName('bookmark_new_folder')
    this.folderPickerMainStack = null
    this.moveFolderSources = []
    this.moveBookmarkIds = []
    this.folderEditMode = false
    this.editFolderPath = ''
    this.onEditorClosed = null
    this.showBookmarkEditor = true
    bookmarkVM.loadAll().then((): void => {
      this.loadFolderRegistry()
    }).catch(() => {
    })
  }

  /** 书签页发起：新建书签（默认落在当前层级） */
  prepareNewBookmark(folder: string): void {
    this.editorIsEdit = false
    this.bmTitle = ''
    this.bmUrl = ''
    this.bmFolder = folder
    this.bmQuick = false
    this.bmIcon = ''
    this.editingId = -1
    this.folderPickerTarget = 'bookmark'
    this.nameItem.value = ''
    this.urlItem.value = ''
    this.folderItem.value = this.folderPathLabel(folder)
    this.quickItem.value = false
    this.newFolderName = ''
    this.newFolderNameItem.value = ''
    this.newFolderParent = ''
    this.newFolderParentItem.value = this.folderPathLabel('')
    this.loadFolderRegistry()
    this.clearEditorStack()
    this.folderPickerMainStack = null
    this.moveFolderSources = []
    this.moveBookmarkIds = []
    this.folderEditMode = false
    this.editFolderPath = ''
  }

  /** 书签页发起：编辑已有书签（复用半模态编辑器，替代旧标题/网址对话框） */
  prepareEditBookmark(b: BookmarkInfo): void {
    this.editorIsEdit = true
    this.editingId = b.id !== null ? b.id : -1
    this.bmTitle = b.title
    this.bmUrl = b.url
    this.bmFolder = b.folder
    this.bmQuick = b.isQuick
    this.bmIcon = b.icon
    this.folderPickerTarget = 'bookmark'
    this.nameItem.value = b.title
    this.urlItem.value = b.url
    this.folderItem.value = this.folderPathLabel(b.folder)
    this.quickItem.value = b.isQuick
    this.newFolderName = ''
    this.newFolderNameItem.value = ''
    this.newFolderParent = ''
    this.newFolderParentItem.value = this.folderPathLabel('')
    this.loadFolderRegistry()
    this.clearEditorStack()
    this.folderPickerMainStack = null
    this.moveFolderSources = []
    this.moveBookmarkIds = []
    this.folderEditMode = false
    this.editFolderPath = ''
  }

  /** 书签页发起：编辑文件夹（复用新建文件夹页） */
  prepareEditFolder(path: string): void {
    this.folderEditMode = true
    this.editFolderPath = path
    this.newFolderName = this.lastSegmentOf(path)
    this.newFolderNameItem.value = this.newFolderName
    this.newFolderParent = this.parentPathOf(path)
    this.newFolderParentItem.value = this.folderPathLabel(this.newFolderParent)
    this.folderPickerTarget = 'newFolder'
    this.loadFolderRegistry()
    this.clearEditorStack()
    this.folderPickerMainStack = null
    this.moveFolderSources = []
    this.moveBookmarkIds = []
  }

  /** 新建/编辑文件夹确认（编辑模式支持改名与调整位置） */
  confirmFolderEditor(): void {
    const name: string = this.newFolderName.trim()
    if (name === '') {
      toastUtil.showToast({ message: $r('app.string.bookmark_folder_name_hint') })
      return
    }
    if (!this.folderEditMode) {
      this.createFolder()
      return
    }
    const old: string = this.editFolderPath
    const dst: string = this.newFolderParent === '' ? name : `${this.newFolderParent}/${name}`
    if (dst === old) {
      this.closeEditorSheet()
      return
    }
    if (dst.startsWith(`${old}/`)) {
      toastUtil.showToast({ message: $r('app.string.bookmark_move_invalid') })
      return
    }
    this.folderList = this.rewriteFolderPaths(this.computeFolderList(), old, dst)
    this.saveFolderRegistry()
    this.rebuildFolderRows()
    bookmarkVM.moveFolderPrefix(old, dst)
    this.closeEditorSheet()
  }

  /** 清空编辑器局部栈 */
  private clearEditorStack(): void {
    while (this.editorStack.size() > 0) {
      this.editorStack.pop(false)
    }
  }

  /** 关闭编辑器 sheet（浏览器菜单宿主 + 书签页自建宿主） */
  closeEditorSheet(): void {
    this.showBookmarkEditor = false
    const cb: (() => void) | null = this.onEditorClosed
    this.onEditorClosed = null
    if (cb !== null) {
      cb()
    }
  }

  /** 加载文件夹注册表（设置存储 + 书签中出现的路径合并，注册表顺序优先） */
  private loadFolderRegistry(): void {
    this.folderList = this.computeFolderList()
    this.rebuildFolderRows()
  }

  /** 计算文件夹注册表（不改状态） */
  private computeFolderList(): string[] {
    const list: string[] = []
    const raw: string = appSettings.bookmark_folders
    if (raw !== '') {
      try {
        const parsed = JSON.parse(raw) as string[]
        if (Array.isArray(parsed)) {
          for (const p of parsed) {
            if (typeof p === 'string' && p !== '') {
              this.ensureFolderWithAncestors(list, p)
            }
          }
        }
      } catch (e) {
        // 保持空注册表
      }
    }
    for (const b of bookmarkVM.bookmarks) {
      if (b.folder !== '') {
        this.ensureFolderWithAncestors(list, b.folder)
      }
    }
    return list
  }

  /** 注册文件夹（连同缺失的祖先层级） */
  private ensureFolderWithAncestors(list: string[], path: string): void {
    const parent: string = this.parentPathOf(path)
    if (parent !== '') {
      this.ensureFolderWithAncestors(list, parent)
    }
    if (!list.includes(path)) {
      list.push(path)
    }
  }

  /** 父级路径（'' = 根） */
  private parentPathOf(path: string): string {
    const idx: number = path.lastIndexOf('/')
    return idx < 0 ? '' : path.substring(0, idx)
  }

  /** 末级名称 */
  private lastSegmentOf(path: string): string {
    const idx: number = path.lastIndexOf('/')
    return idx < 0 ? path : path.substring(idx + 1)
  }

  /** 树形顺序：顶层按注册次序，子级跟随父级缩进排列 */
  private orderedFolderPaths(): string[] {
    return this.orderedFolderList(this.folderList)
  }

  private orderedFolderList(list: string[]): string[] {
    const out: string[] = []
    this.collectChildFolders('', list, out)
    for (const p of list) {
      if (!out.includes(p)) {
        out.push(p)
      }
    }
    return out
  }

  private collectChildFolders(parent: string, list: string[], out: string[]): void {
    for (const p of list) {
      if (this.parentPathOf(p) === parent) {
        out.push(p)
        this.collectChildFolders(p, list, out)
      }
    }
  }

  /** 指定目录的直接子文件夹（注册表顺序） */
  childFolders(parent: string): string[] {
    const list: string[] = this.computeFolderList()
    const out: string[] = []
    for (const p of list) {
      if (this.parentPathOf(p) === parent) {
        out.push(p)
      }
    }
    return out
  }

  /** 重建文件夹选择页行（根目录 + 树形缩进 + 选中态） */
  private rebuildFolderRows(): void {
    let current: string = ''
    if (this.folderPickerTarget === 'newFolder') {
      current = this.newFolderParent
    } else if (this.folderPickerTarget === 'bookmark') {
      current = this.bmFolder
    }
    const rows: FolderRowInfo[] = [new FolderRowInfo(this.makeFolderRow('', current), 0)]
    for (const p of this.orderedFolderPaths()) {
      rows.push(new FolderRowInfo(this.makeFolderRow(p, current), p.split('/').length))
    }
    this.folderRows = rows
  }

  private makeFolderRow(path: string, current: string): CustomItemInfo {
    return new CustomItemInfo({
      id: `bm_folder_${path}`,
      type: ItemActionType.RADIO,
      symbol: $r('sys.symbol.folder'),
      title: path === '' ? $r('app.string.bookmark_folder_root') : this.lastSegmentOf(path),
      radioConfig: new RadioConfig(path, 'bm_folder_pick'),
      value: current,
      onChange: (): void => {
        this.selectFolder(path)
      }
    })
  }

  /** 持久化文件夹注册表 */
  private saveFolderRegistry(): void {
    appSettings.bookmark_folders = JSON.stringify(this.folderList)
  }

  /** 打开文件夹选择二级页 */
  private openFolderPicker(target: string): void {
    this.folderPickerTarget = target
    this.rebuildFolderRows()
    this.editorStack.pushPathByName('bookmark_select_folder', null)
  }

  /** 文件夹路径显示名：根目录 → 资源文案；其余显示路径 */
  folderPathLabel(path: string): string {
    return path === ''
      ? ResourceUtils.getString($r('app.string.bookmark_folder_root'))
      : path
  }

  /** 文件夹选择：写入目标并返回上一页 */
  selectFolder(path: string): void {
    if (this.folderPickerTarget === 'move') {
      if (!this.applyMoveSelection(path)) {
        toastUtil.showToast({ message: $r('app.string.bookmark_move_invalid') })
        return
      }
      toastUtil.showToast({ message: $r('app.string.bookmark_moved') })
      this.popPicker()
      return
    }
    if (this.folderPickerTarget === 'newFolder') {
      this.newFolderParent = path
      this.newFolderParentItem.value = this.folderPathLabel(path)
      this.rebuildFolderRows()
      this.editorStack.pop()
      return
    }
    this.bmFolder = path
    this.folderItem.value = this.folderPathLabel(path)
    this.rebuildFolderRows()
    this.editorStack.pop()
  }

  /** 书签页发起的移动：文件夹选择走主路由栈 */
  openMovePicker(stack: NavPathStack, folderSources: string[], bookmarkIds: number[]): void {
    this.folderPickerTarget = 'move'
    this.folderPickerMainStack = stack
    this.moveFolderSources = folderSources
    this.moveBookmarkIds = bookmarkIds
    this.rebuildFolderRows()
    stack.pushPathByName('bookmark_select_folder', null)
  }

  /** 弹出文件夹选择页：优先主栈，其次编辑器局部栈 */
  private popPicker(): void {
    const stack: NavPathStack | null = this.folderPickerMainStack
    this.folderPickerMainStack = null
    if (stack !== null) {
      stack.pop()
      return
    }
    this.editorStack.pop()
  }

  /** 应用移动：目标不可为被移动文件夹自身或其子级；书签批量改归属，文件夹整体改路径 */
  private applyMoveSelection(target: string): boolean {
    const folders: string[] = this.moveFolderSources
    for (const src of folders) {
      if (target === src || target.startsWith(`${src}/`)) {
        return false
      }
    }
    const ids: number[] = this.moveBookmarkIds
    this.moveFolderSources = []
    this.moveBookmarkIds = []
    for (const src of folders) {
      this.applyFolderMove(src, target)
    }
    if (ids.length > 0) {
      bookmarkVM.moveBookmarksTo(ids, target)
    }
    return true
  }

  /** 移动单个文件夹到目标目录（含注册表与书签归属改写） */
  private applyFolderMove(src: string, target: string): boolean {
    if (src === '' || target === src || target.startsWith(`${src}/`)) {
      return false
    }
    const name: string = this.lastSegmentOf(src)
    const dst: string = target === '' ? name : `${target}/${name}`
    if (dst === src) {
      return true
    }
    this.folderList = this.rewriteFolderPaths(this.computeFolderList(), src, dst)
    this.saveFolderRegistry()
    this.rebuildFolderRows()
    bookmarkVM.moveFolderPrefix(src, dst)
    return true
  }

  /** 重命名文件夹（末级名称，含子级路径与书签归属同步改写） */
  renameFolder(path: string, newName: string): void {
    const name: string = newName.trim()
    if (path === '' || name === '') {
      return
    }
    const parent: string = this.parentPathOf(path)
    const dst: string = parent === '' ? name : `${parent}/${name}`
    if (dst === path) {
      return
    }
    this.folderList = this.rewriteFolderPaths(this.computeFolderList(), path, dst)
    this.saveFolderRegistry()
    this.rebuildFolderRows()
    bookmarkVM.moveFolderPrefix(path, dst)
  }

  /** 删除文件夹：注册表移除该目录及子级，内含书签移回根目录 */
  deleteFolder(path: string): void {
    if (path === '') {
      return
    }
    const list: string[] = this.computeFolderList()
    const newList: string[] = []
    for (const p of list) {
      if (p !== path && !p.startsWith(`${path}/`)) {
        newList.push(p)
      }
    }
    this.folderList = newList
    this.saveFolderRegistry()
    this.rebuildFolderRows()
    bookmarkVM.moveFolderPrefix(path, '')
  }

  /** 注册表路径前缀改写：path → dst，子级跟随 */
  private rewriteFolderPaths(list: string[], path: string, dst: string): string[] {
    const newList: string[] = []
    for (const p of list) {
      if (p === path) {
        newList.push(dst)
      } else if (p.startsWith(`${path}/`)) {
        newList.push(`${dst}${p.substring(path.length)}`)
      } else {
        newList.push(p)
      }
    }
    return newList
  }

  /** 从选择页进入新建文件夹页 */
  openNewFolderPage(): void {
    this.newFolderName = ''
    this.newFolderNameItem.value = ''
    this.newFolderParent = ''
    this.newFolderParentItem.value = this.folderPathLabel('')
    this.editorStack.pushPathByName('bookmark_new_folder', null)
  }

  /** 新建文件夹：注册并选为书签所在位置，回主编辑页 */
  createFolder(): void {
    const name: string = this.newFolderName.trim()
    if (name === '') {
      toastUtil.showToast({ message: $r('app.string.bookmark_folder_name_hint') })
      return
    }
    const path: string = this.newFolderParent === '' ? name : `${this.newFolderParent}/${name}`
    this.ensureFolderWithAncestors(this.folderList, path)
    this.saveFolderRegistry()
    this.bmFolder = path
    this.folderItem.value = this.folderPathLabel(path)
    while (this.editorStack.size() > 0) {
      this.editorStack.pop(false)
    }
  }

  /** 保存编辑后的书签 */
  saveBookmark(): void {
    const url: string = this.bmUrl.trim()
    if (url === '') {
      toastUtil.showToast({ message: $r('app.string.bookmark_url_hint') })
      return
    }
    const title: string = this.bmTitle.trim() || url
    const isUpdate: boolean = this.editorIsEdit && this.editingId >= 0
    if (isUpdate) {
      bookmarkVM.updateBookmarkWithMeta(this.editingId, title, url, this.bmFolder, this.bmQuick, this.bmIcon)
    } else {
      bookmarkVM.addBookmarkWithMeta(title, url, this.bmFolder, this.bmQuick, this.bmIcon)
    }
    this.closeEditorSheet()
    if (!isUpdate) {
      toastUtil.showToast({ message: $r('app.string.bookmark_added') })
    }
  }

  /** 书签编辑器：从相册选一张图片作为自定义图标 */
  pickBookmarkIcon(): void {
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker()
    const options: photoAccessHelper.PhotoSelectOptions = {
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1
    }
    picker.select(options)
      .then((result: photoAccessHelper.PhotoSelectResult): void => {
        if (result.photoUris.length === 0) {
          return
        }
        this.copyPickedIcon(result.photoUris[0])
      })
      .catch((error: BusinessError): void => {
        logger.error(`pickBookmarkIcon failed: ${error.code} ${error.message}`)
      })
  }

  /** 相册图片 → 解码缩放（最长边 256）→ 重编码 PNG → files/bookmark_icons/ */
  private async copyPickedIcon(uri: string): Promise<void> {
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
      if (maxSide > 256) {
        const ratio: number = 256 / maxSide
        await pixelMap.scale(ratio, ratio)
      }
      packer = image.createImagePacker()
      const buf: ArrayBuffer = await packer.packToData(pixelMap,
        { format: 'image/png', quality: 100 })
      const dir: string = `${_QhState.Context.filesDir}/bookmark_icons`
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir)
      }
      const dest: string = `${dir}/bm_icon_${Date.now()}.png`
      const bytes: Uint8Array = new Uint8Array(buf)
      const file: fileIo.File = fileIo.openSync(dest,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, bytes.buffer, { length: bytes.byteLength })
      fileIo.closeSync(file)
      this.bmIcon = dest
    } catch (error) {
      const err = error as BusinessError
      logger.error(`copyPickedIcon failed: ${err.code} ${err.message}`)
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
  /** 菜单宫格当前页索引（工具箱 = 跳第二页） */
  @Trace menuPageIndex: number = 0
  /** 菜单宫格分页数据（打开菜单前重建） */
  menuPages: MenuEntry[][] = []

  /** 只能作用于网页的条目（主页/无页面时置灰） */
  private static readonly WEB_ONLY: Set<string> = new Set<string>([
    'share', 'add_bookmark', 'mark_ad', 'translate',
    'view_source', 'inspect_element', 'fullscreen', 'resource_sniff', 'browser_id', 'network_log',
    'find_in_page', 'save', 'refresh_page', 'font_size',
    'print_pdf', 'read_aloud', 'add_to_home', 'read_mode', 'open_with',
    'game_mode', 'add_home_favorite', 'report_site'
  ])

  /** 按定制菜单布局构建分页：每页 2 行 × 5 列共 10 项 */
  buildMenuPages(): void {
    const ids = appSettings.menu_layout !== ''
      ? appSettings.menu_layout.split(',')
      : MenuEntries.DEFAULT_MENU
    const entries: MenuEntry[] = []
    for (const id of ids) {
      const e = MenuEntries.byId(id)
      if (e) {
        entries.push(e)
      }
    }
    const pages: MenuEntry[][] = []
    for (let i = 0; i < entries.length; i += 10) {
      pages.push(entries.slice(i, i + 10))
    }
    this.menuPages = pages
    // 每次打开菜单回到第一页
    this.menuPageIndex = 0
    // 刷新书签列表（驱动「已收藏」高亮）
    bookmarkVM.loadAll()
  }

  /** 是否为带状态条目（非默认状态时图标高亮） */
  isToggleEntry(id: string): boolean {
    return id === 'incognito' || id === 'ad_block' || id === 'image_mode'
      || id === 'browser_id' || id === 'screen_orientation' || id === 'font_size'
      || id === 'night_mode' || id === 'desktop_mode' || id === 'read_mode'
      || id === 'add_bookmark' || id === 'add_home_favorite'
  }

  /** 条目当前是否处于高亮状态 */
  toggleStateOf(id: string): boolean {
    if (id === 'incognito') {
      return appSettings.default_incognito
    }
    if (id === 'ad_block') {
      return appSettings.ad_block_enabled
    }
    if (id === 'image_mode') {
      return this.currentImageMode() !== 'allow'
    }
    if (id === 'browser_id') {
      return appSettings.ua_mode !== 'default'
    }
    if (id === 'screen_orientation') {
      return appSettings.screen_orientation !== 'auto'
    }
    if (id === 'font_size') {
      return this.currentFontZoom() !== 100
    }
    if (id === 'night_mode') {
      return appSettings.force_dark_web
    }
    if (id === 'desktop_mode') {
      return appSettings.desktop_mode
    }
    if (id === 'read_mode') {
      return browserVM.isReaderActive(tabsVM.activeTab ? tabsVM.activeTab.id : -1)
    }
    if (id === 'add_bookmark') {
      const tab = tabsVM.activeTab
      return tab !== null && bookmarkVM.hasBookmark(tab.url)
    }
    if (id === 'add_home_favorite') {
      const tab = tabsVM.activeTab
      return tab !== null && bookmarkVM.hasQuick(tab.url)
    }
    return false
  }

  /** 条目是否置灰不可用（网页专属功能在主页/非网页上下文置灰） */
  isEntryDisabled(id: string): boolean {
    if (!MenuViewModel.WEB_ONLY.has(id)) {
      return false
    }
    const tab = tabsVM.activeTab
    return !tab || tab.isHome
  }

  /** 全局图片显示模式：'allow' 有图 | 'block' 无图 | 'wifi' 仅WiFi有图 */
  currentImageMode(): string {
    if (appSettings.no_image_mode) {
      return 'block'
    }
    const v: string = SiteSettingsViewModel.getDefault('site_image')
    return v === 'block' || v === 'wifi' ? v : 'allow'
  }

  /** 当前网页字号缩放（%） */
  currentFontZoom(): number {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return 100
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      return 100
    }
    const p: SitePolicy | null = siteSettingsVM.livePolicyOf(host) ?? siteSettingsVM.cachedPolicy(host)
    if (p !== null) {
      return p.fontZoom
    }
    const n: number = Number(SiteSettingsViewModel.getDefault('site_font_size'))
    return Number.isNaN(n) || n <= 0 ? 100 : Math.round(n)
  }

  /** 菜单内打开半模态：先关菜单面板，待其关闭动画结束后再弹，避免双层 sheet 冲突闪屏 */
  private openSheetAfterMenuClosed(open: () => void): void {
    if (!this.showMenu) {
      open()
      return
    }
    this.showMenu = false
    setTimeout((): void => {
      open()
    }, 300)
  }

  /** 弹出半模态单选（复用设置页同款 SheetPicker） */
  private openPickerSheet(title: ResourceStr, options: PickerOption[], selected: string,
    onSelect: (v: string) => void): void {
    this.picker.title = title
    this.picker.options = options
    this.picker.selected = selected
    this.picker.onSelect = onSelect
    this.pickerHeight = pickerSheetHeight(options.length)
    this.sheetKind = 'picker'
    this.openSheetAfterMenuClosed((): void => {
      this.showSheet = true
    })
  }

  /** 解析选项显示文案（Resource 或字符串） */
  private labelOfOption(options: PickerOption[], v: string): string {
    for (const o of options) {
      if (o.value === v) {
        return typeof o.label === 'string' ? o.label : ResourceUtils.getString(o.label as Resource)
      }
    }
    return v
  }

  /** 菜单设置变更统一播报：传入菜单项与作用结果（如「电脑模式：已开启」） */
  private announceMenuChange(item: ResourceStr, result: string): void {
    const itemLabel: string = typeof item === 'string' ? item : ResourceUtils.getString(item as Resource)
    toastUtil.showToast({
      message: ResourceUtils.getStringWithArgs($r('app.string.menu_change_toast'), [itemLabel, result])
    })
  }

  /** 开关状态 → 播报文案（已开启/已关闭） */
  private toggleLabel(on: boolean): string {
    return ResourceUtils.getString(on ? $r('app.string.toast_state_on') : $r('app.string.toast_state_off'))
  }

  openUaPicker(): void {
    const options: PickerOption[] = []
    for (const p of UaUtils.PRESETS) {
      options.push(new PickerOption(p.id, p.nameRes))
    }
    for (const c of appSettings.custom_uas) {
      options.push(new PickerOption(c.id, c.name))
    }
    this.openPickerSheet($r('app.string.browser_id'), options, appSettings.ua_mode, (v: string): void => {
      appSettings.ua_mode = v
      UaUtils.applyToAll()
      // 切换标识后自动刷新当前页，使新 UA 立即生效
      browserVM.refresh()
      this.announceMenuChange($r('app.string.browser_id'), this.labelOfOption(options, v))
    })
  }

  openOrientationPicker(): void {
    const options: PickerOption[] = [
      new PickerOption('auto', $r('app.string.orientation_auto')),
      new PickerOption('portrait', $r('app.string.orientation_portrait')),
      new PickerOption('landscape', $r('app.string.orientation_landscape'))
    ]
    this.openPickerSheet($r('app.string.screen_orientation'), options,
      appSettings.screen_orientation, (v: string): void => {
        appSettings.screen_orientation = v
        SettingsUtils.applyOrientation()
        this.announceMenuChange($r('app.string.screen_orientation'), this.labelOfOption(options, v))
      })
  }

  openImageModePicker(): void {
    const options: PickerOption[] = [
      new PickerOption('allow', $r('app.string.site_opt_image_show')),
      new PickerOption('block', $r('app.string.site_opt_image_none')),
      new PickerOption('wifi', $r('app.string.site_opt_image_wifi'))
    ]
    this.openPickerSheet($r('app.string.image_mode'), options,
      this.currentImageMode(), (v: string): void => {
        SiteSettingsViewModel.setDefault('site_image', v)
        appSettings.no_image_mode = v === 'block'
        this.refreshLiveImageModes()
        this.announceMenuChange($r('app.string.image_mode'), this.labelOfOption(options, v))
      })
  }

  /**
   * 阅读模式切换：直接 Readability 提取正文（提取逻辑收敛在 browserVM.enterReader，
   * 与地址栏阅读按钮共用）；已打开时退出
   */
  toggleReadMode(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return
    }
    if (browserVM.isReaderActive(tab.id)) {
      browserVM.closeReader()
      this.announceMenuChange($r('app.string.read_mode'), this.toggleLabel(false))
      return
    }
    browserVM.enterReader()
  }

  /** 图片模式切换后，把新档位同步到已打开页面正在使用的策略实例（无需刷新页面） */
  private refreshLiveImageModes(): void {
    for (const t of tabsVM.tabs) {
      if (t.isHome) {
        continue
      }
      const host: string = SiteSettingsViewModel.hostOf(t.url)
      if (host === '') {
        continue
      }
      const live: SitePolicy | null = siteSettingsVM.livePolicyOf(host)
      if (live === null) {
        continue
      }
      siteSettingsVM.resolvePolicy(host).then((fresh: SitePolicy): void => {
        live.imageMode = fresh.imageMode
      }).catch(() => {
      })
    }
  }

  openFontSlider(): void {
    this.fontZoomValue = this.currentFontZoom()
    this.sheetKind = 'font'
    this.openSheetAfterMenuClosed((): void => {
      this.showSheet = true
    })
  }

  /** 滑动条实时应用字号到当前网页（改 TabWeb 持有的同一份策略对象，Web 属性自动刷新） */
  applyFontZoom(v: number): void {
    const zoom: number = Math.round(v / 5) * 5
    if (zoom === this.fontZoomValue) {
      return
    }
    this.fontZoomValue = zoom
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      return
    }
    const p: SitePolicy | null = siteSettingsVM.livePolicyOf(host) ?? siteSettingsVM.cachedPolicy(host)
    if (p !== null) {
      p.fontZoom = zoom
    }
  }

  /** 松手后按站点持久化字号并提示 */
  persistFontZoom(): void {
    const tab = tabsVM.activeTab
    if (!tab || tab.isHome) {
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      return
    }
    siteSettingsVM.setOverride(host, 'site_font_size', String(this.fontZoomValue)).catch(() => {
    })
    this.announceMenuChange($r('app.string.font_size'), `${this.fontZoomValue}%`)
  }

  /** 查看源码：捕获当前页 outerHTML，新标签页打开源码视图 */
  openViewSource(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null || tab.viewSourceHtml !== '') {
      return
    }
    tab.controller.runJavaScript('document.documentElement.outerHTML')
      .then((raw: string): void => {
        let html: string = raw
        try {
          const parsed = JSON.parse(raw) as string
          if (typeof parsed === 'string') {
            html = parsed
          }
        } catch (e) {
          // 保留原始返回
        }
        tabsVM.newViewSourceTab(tab.url, html,
          ResourceUtils.getString($r('app.string.view_source')), tab.isIncognito)
      })
      .catch((error: BusinessError): void => {
        console.error(`[MenuViewModel] 查看源码失败: ${error.code} ${error.message}`)
      })
  }

  /** 网站设定：网页打开时直达当前站点详情页（未建档先注册），否则进通用站点设定页 */
  private openCurrentSiteDetail(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      QhState.pushPage('settings_site', null)
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      QhState.pushPage('settings_site', null)
      return
    }
    siteSettingsVM.listSites().then((sites: string[]): void => {
      const push = (): void => {
        QhState.pushPage('settings_site_detail', host)
      }
      if (sites.indexOf(host) >= 0) {
        push()
        return
      }
      siteSettingsVM.addSite(host).then(push).catch(push)
    }).catch((): void => {
      QhState.pushPage('settings_site_detail', host)
    })
  }

  /** 添加到桌面：为当前网页创建桌面快捷方式（图标抓取失败回退首字头像） */
  private addCurrentPageToHome(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      return
    }
    shortcutVM.addToDesktop(`page_${ShortcutViewModel.urlKey(tab.url)}`,
      tab.title !== '' ? tab.title : tab.url, tab.url)
  }

  /** 其它应用打开：隐式 Want（ACTION_VIEW_DATA + 当前网页地址），系统弹出可打开应用的选择器 */
  private openWithOtherApp(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      return
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: tab.url,
      type: 'text/html'
    }
    _QhState.Context.startAbility(want)
      .catch((error: BusinessError): void => {
        logger.error(`openWithOtherApp failed: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.open_with_failed') })
      })
  }

  /** 举报网站：复制当前网址，新标签打开腾讯网址安全中心举报页（表单内粘贴举报） */
  private reportCurrentSite(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome) {
      return
    }
    browserVM.copyLink()
    tabsVM.newTab('https://urlsec.qq.com/report.html')
    toastUtil.showToast({ message: $r('app.string.report_site_copied') })
  }

  /** 菜单条目点击分发；返回 false 表示保持面板打开（开关类） */
  onMenuEntry(e: MenuEntry): boolean {
    switch (e.id) {
      case 'bookmarks':
        QhState.pushPage('bookmarks', null)
        return true
      case 'history':
        QhState.pushPage('history', null)
        return true
      case 'downloads':
        QhState.pushPage('downloads', null)
        return true
      case 'incognito': {
        // 无痕模式为全局开关：切换「默认无痕浏览」并应用到全部标签
        const target = !appSettings.default_incognito
        appSettings.default_incognito = target
        tabsVM.applyGlobalIncognito(target)
        this.announceMenuChange(e.title, this.toggleLabel(target))
        return false
      }
      case 'add_bookmark':
        this.openBookmarkEditor()
        return true
      case 'add_home_favorite': {
        // 添加主页收藏：已是主页收藏则移除（toggle）；书签不存在时顺带建档
        const tab = tabsVM.activeTab
        if (tab === null || tab.isHome) {
          return false
        }
        if (bookmarkVM.hasQuick(tab.url)) {
          bookmarkVM.setQuick(tab.url, false)
          this.announceMenuChange(e.title,
            ResourceUtils.getString($r('app.string.quick_removed')))
        } else {
          if (bookmarkVM.findByUrl(tab.url) !== null) {
            bookmarkVM.setQuick(tab.url, true)
          } else {
            bookmarkVM.addBookmark(tab.title, tab.url, true)
          }
          this.announceMenuChange(e.title,
            ResourceUtils.getString($r('app.string.quick_added')))
        }
        return false
      }
      case 'settings':
        QhState.pushPage('settings', null)
        return true
      case 'find_in_page':
        browserVM.showFindBar = true
        return true
      case 'network_log':
        tabsVM.newNetworkLogTab()
        return true
      case 'refresh_page':
        browserVM.refresh()
        return true
      case 'browser_id':
        this.openUaPicker()
        return false
      case 'view_source':
        this.openViewSource()
        return true
      case 'inspect_element':
        inspectorVM.open()
        return true
      case 'site_settings':
        this.openCurrentSiteDetail()
        return true
      case 'font_size':
        this.openFontSlider()
        return false
      case 'customize_menu':
        QhState.pushPage('settings_menu_custom', null)
        return true
      case 'desktop_mode':
        // 电脑模式开关：UA 改用「电脑模式标识」并刷新当前页使其生效
        appSettings.desktop_mode = !appSettings.desktop_mode
        UaUtils.applyToAll()
        browserVM.refresh()
        this.announceMenuChange(e.title, this.toggleLabel(appSettings.desktop_mode))
        return false
      case 'print_pdf':
        this.printPageToPdf()
        return true
      case 'save':
        this.openSaveSheet()
        return false
      case 'resource_sniff':
        // 资源嗅探：菜单关闭后采集当前页媒体资源并弹半模态面板
        this.openSniffPanel()
        return false
      case 'offline_page':
        QhState.pushPage('offline_page', null)
        return true
      case 'read_aloud':
        // 朗读网页：非阅读模式先弹窗确认，进阅读模式并拉起系统朗读面板（已在阅读模式直接朗读）
        readAloudVM.startFromTab()
        return true
      case 'add_to_home':
        // 添加到桌面：复用书签的桌面快捷方式能力，为当前网页创建图标
        this.addCurrentPageToHome()
        return true
      case 'open_with':
        // 其它应用打开：隐式 Want 拉起系统应用选择器
        this.openWithOtherApp()
        return true
      case 'game_mode':
        // 游戏模式：完全沉浸全屏（隐藏系统栏与应用栏），返回两次退出
        browserVM.enterGameMode()
        return true
      case 'report_site':
        // 举报网站：复制当前网址并打开腾讯网址安全中心举报页
        this.reportCurrentSite()
        return true
      case 'script':
        // 用户脚本管理
        QhState.pushPage('settings_script', null)
        return true
      case 'customize':
        // 主页定制：路由到设置-定制页（预览 + 分区配置）
        QhState.pushPage('settings_custom', null)
        return true
      case 'night_mode':
        // 直接切换网页强制深色（TabWeb darkMode/forceDarkAccess 随状态联动），不进设置页
        appSettings.force_dark_web = !appSettings.force_dark_web
        this.announceMenuChange(e.title, this.toggleLabel(appSettings.force_dark_web))
        return false
      case 'read_mode':
        // 阅读模式：Readability 提取正文后独立渲染，再点退出
        this.toggleReadMode()
        return false
      case 'screen_orientation':
        this.openOrientationPicker()
        return false
      case 'ad_block':
        appSettings.ad_block_enabled = !appSettings.ad_block_enabled
        this.announceMenuChange(e.title, this.toggleLabel(appSettings.ad_block_enabled))
        return false
      case 'image_mode':
        this.openImageModePicker()
        return false
      case 'scan_qr':
        this.startScan()
        return true
      case 'share':
        this.shareCurrentPage()
        return true
      case 'mark_ad':
        this.markCurrentPageAsAd()
        return true
      case 'toolbox':
        // 工具箱：菜单宫格切到第二页
        if (this.menuPages.length > 1) {
          this.menuPageIndex = 1
        }
        return false
      default:
        toastUtil.showToast({ message: $r('app.string.menu_item_wip') })
        return false
    }
  }

  /** 打印PDF：当前网页 createPdf 生成 A4 PDF，拉起系统打印预览（打印机/保存为PDF/份数/纸张/色彩/双面/页数）；
   * 菜单「打印/PDF」与键盘快捷键 Ctrl+P 共用 */
  printPageToPdf(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null) {
      return
    }
    const config: webview.PdfConfiguration = {
      width: 8.27,
      height: 11.69,
      marginTop: 0.4,
      marginBottom: 0.4,
      marginLeft: 0.4,
      marginRight: 0.4,
      scale: 1.0,
      shouldPrintBackground: true
    }
    const controller: webview.WebviewController = tab.controller
    const url: string = tab.url
    const title: string = tab.title
    controller.createPdf(config)
      .then((pdf: webview.PdfData): void => {
        this.openPrintPreview(url, title, pdf.pdfArrayBuffer())
      })
      .catch((error: BusinessError): void => {
        logger.error(`createPdf failed: ${error.code} ${error.message}`)
        toastUtil.showToast({ message: $r('app.string.pdf_save_failed') })
      })
  }

  /** 写临时 PDF 拉起系统打印预览；打印服务不可用回退保存 PDF 到公共下载目录 */
  private openPrintPreview(url: string, title: string, data: Uint8Array): void {
    const safeName: string = title.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim()
      .substring(0, 50)
    const name = `${safeName !== '' ? safeName : 'page'}_${new Date().getTime()}.pdf`
    const dir: string = `${_QhState.Context.cacheDir}/print`
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true)
    }
    const path: string = `${dir}/${name}`
    const buf: ArrayBuffer = new ArrayBuffer(data.byteLength)
    new Uint8Array(buf).set(data)
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, buf)
    } finally {
      fileIo.closeSync(file)
    }
    const files: string[] = [fileUri.getUriFromPath(path)]
    print.print(files, _QhState.Context)
      .catch((error: BusinessError): void => {
        logger.error(`print failed: ${error.code} ${error.message}`)
        downloadVM.saveLocalPdf(url, title, data)
      })
  }

  /** 打开保存网页弹窗：预填页面标题，可勾选保存为PDF */
  openSaveSheet(): void {
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null) {
      return
    }
    this.saveName = tab.title !== '' ? tab.title : tab.url
    this.saveAsPdf = false
    this.sheetKind = 'save'
    this.openSheetAfterMenuClosed((): void => {
      this.showSheet = true
    })
  }

  /** 打开资源嗅探面板：菜单收起后采集当前页媒体资源（网络日志 + 页面 JS 扫描）并弹半模态 */
  openSniffPanel(): void {
    this.openSheetAfterMenuClosed((): void => {
      sniffVM.open()
    })
  }

  /** 确认保存：勾选PDF直接存公共PDF目录（不进打印预览）；未勾选存离线网页到公共 Offline 目录 */
  confirmSave(): void {
    this.showSheet = false
    const tab = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null) {
      return
    }
    const controller: webview.WebviewController = tab.controller
    const url: string = tab.url
    if (this.saveAsPdf) {
      const config: webview.PdfConfiguration = {
        width: 8.27,
        height: 11.69,
        marginTop: 0.4,
        marginBottom: 0.4,
        marginLeft: 0.4,
        marginRight: 0.4,
        scale: 1.0,
        shouldPrintBackground: true
      }
      controller.createPdf(config)
        .then((pdf: webview.PdfData): void => {
          downloadVM.saveLocalPdf(url, this.saveName, pdf.pdfArrayBuffer())
        })
        .catch((error: BusinessError): void => {
          logger.error(`save as pdf failed: ${error.code} ${error.message}`)
          toastUtil.showToast({ message: $r('app.string.pdf_save_failed') })
        })
      return
    }
    this.saveOfflinePage(controller, url)
  }

  /** 存离线网页：storeWebArchive 落沙箱中转，复制到公共 Download/包名/Offline 后落库 */
  private saveOfflinePage(controller: webview.WebviewController, url: string): void {
    const safeName: string = this.saveName.replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim()
      .substring(0, 50)
    const baseName: string = safeName !== '' ? safeName : 'page'
    PublicDownloadDir.ensureDir('Offline')
      .then((dir: string): void => {
        let fileName: string = `${baseName}.mhtml`
        // 同名防覆盖：已存在则追加时间戳
        if (fileIo.accessSync(`${dir}/${fileName}`)) {
          fileName = `${baseName}_${new Date().getTime()}.mhtml`
        }
        const tmpDir: string = `${_QhState.Context.cacheDir}/offline`
        if (!fileIo.accessSync(tmpDir)) {
          fileIo.mkdirSync(tmpDir, true)
        }
        const tmpPath: string = `${tmpDir}/${fileName}`
        controller.storeWebArchive(tmpPath, false)
          .then((stored: string): void => {
            if (stored === '') {
              toastUtil.showToast({ message: $r('app.string.offline_save_failed') })
              return
            }
            // 兼容返回全路径或纯文件名
            const src: string = stored.indexOf('/') >= 0 ? stored : `${tmpDir}/${stored}`
            const stat: fileIo.Stat = fileIo.statSync(src)
            const file: fileIo.File = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY)
            let data: Uint8Array = new Uint8Array(0)
            try {
              const buf: ArrayBuffer = new ArrayBuffer(stat.size)
              fileIo.readSync(file.fd, buf)
              data = new Uint8Array(buf)
            } finally {
              fileIo.closeSync(file)
            }
            PublicDownloadDir.writeBytes(dir, fileName, data)
            try {
              fileIo.unlinkSync(src)
            } catch (e) {
              // 中转文件清理失败忽略
            }
            offlinePageVM.saveRecord(url, this.saveName, `${dir}/${fileName}`)
          })
          .catch((error: BusinessError): void => {
            logger.error(`storeWebArchive failed: ${error.code} ${error.message}`)
            toastUtil.showToast({ message: $r('app.string.offline_save_failed') })
          })
      })
      .catch((): void => {
        toastUtil.showToast({ message: $r('app.string.offline_save_failed') })
      })
  }

  /** 扫码：调起系统默认扫码界面，结果按地址栏提交逻辑在当前标签打开 */
  startScan(): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: true
    }
    scanBarcode.startScanForResult(_QhState.Context, options)
      .then((result: scanBarcode.ScanResult) => {
        const text: string = result.originalValue.trim()
        if (text !== '') {
          browserVM.submitAddress(text)
        }
      })
      .catch((error: BusinessError): void => {
        // 用户取消等场景静默处理
        logger.error(`startScan failed: ${error.code} ${error.message}`)
      })
  }

  /** 分享当前页面：调系统分享面板（链接 + 标题） */
  private shareCurrentPage(): void {
    const tab = tabsVM.activeTab
    const url = tab !== null ? tab.url : ''
    const title = tab !== null ? tab.title : ''
    if (url === '') {
      return
    }
    try {
      const data = new systemShare.SharedData({
        utd: 'general.hyperlink',
        content: url,
        title: title !== '' ? title : url
      })
      const controller = new systemShare.ShareController(data)
      controller.show(_QhState.Context, {})
        .catch((error: BusinessError): void => {
          logger.error(`share failed: ${error.code} ${error.message}`)
        })
    } catch (e) {
      logger.error(`share exception: ${e}`)
    }
  }

  /** 标记广告：当前页地址加入广告拦截自定义规则并同步内核 */
  private markCurrentPageAsAd(): void {
    const tab = tabsVM.activeTab
    const url = tab !== null ? tab.url : ''
    if (url === '') {
      return
    }
    const current = adBlockEngine.loadCustomRulesSync()
    if (current.split('\n').some((line: string): boolean => line.trim() === url)) {
      toastUtil.showToast({ message: $r('app.string.ad_marked') })
      return
    }
    const next = current.trim() !== '' ? `${current.replace(/\s+$/, '')}\n${url}\n` : `${url}\n`
    adBlockEngine.saveCustomRules(next)
      .then((): void => {
        toastUtil.showToast({ message: $r('app.string.ad_marked') })
      })
      .catch((): void => {
      })
  }

  /** 条目图标颜色：置灰/高亮/默认 */
  entryIconColor(id: string): ResourceColor {
    if (this.isEntryDisabled(id)) {
      return $r('sys.color.font_tertiary')
    }
    return this.isToggleEntry(id) && this.toggleStateOf(id)
      ? QhState.currentThemeColor
      : $r('sys.color.font_primary')
  }

  /** 条目标题颜色：置灰/高亮/默认 */
  entryTitleColor(id: string): ResourceColor {
    if (this.isEntryDisabled(id)) {
      return $r('sys.color.font_tertiary')
    }
    return this.isToggleEntry(id) && this.toggleStateOf(id)
      ? QhState.currentThemeColor
      : $r('sys.color.font_secondary')
  }

  /** 条目标题：图片模式按当前档位动态显示（有图/无图/仅WIFI有图）；已收藏书签显示已收藏；已主页收藏显示已添加 */
  entryTitle(e: MenuEntry): ResourceStr {
    if (e.id === 'image_mode') {
      const mode: string = this.currentImageMode()
      if (mode === 'block') {
        return $r('app.string.no_image_mode')
      }
      if (mode === 'wifi') {
        return $r('app.string.site_opt_image_wifi')
      }
    }
    if (e.id === 'add_bookmark' && this.toggleStateOf('add_bookmark')) {
      return $r('app.string.bookmark_state_added')
    }
    if (e.id === 'add_home_favorite' && this.toggleStateOf('add_home_favorite')) {
      return $r('app.string.quick_added')
    }
    return e.title
  }
}

export const menuVM = new MenuViewModel()
