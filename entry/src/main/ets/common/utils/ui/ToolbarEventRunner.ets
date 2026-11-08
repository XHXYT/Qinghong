import { BusinessError } from '@kit.BasicServicesKit';
import { getToolbarEventAction } from '../../entity/ToolbarEvent';
import { tabsVM, TabInfo } from '../../../viewmodel/TabsViewModel';
import { browserVM } from '../../../viewmodel/BrowserViewModel';
import { menuVM } from '../../../viewmodel/MenuViewModel';
import { readAloudVM } from '../../../viewmodel/ReadAloudViewModel';
import { downloadVM } from '../../../viewmodel/DownloadViewModel';
import { bookmarkVM } from '../../../viewmodel/BookmarkViewModel';
import { QhState } from '../../../entryability/AppState';
import { PickerOption, pickerSheetHeight } from '../../../components/SheetPicker';

/**
 * 工具栏事件执行器（设置-工具栏-工具栏事件）：
 * 5 按钮长按 + 工具栏左滑/右滑 → 读绑定动作并执行；
 * 翻译转 menuVM.openTranslate；打开AI面板暂未接线（静默不处理）
 */
class ToolbarEventRunner {

  /** 执行事件绑定动作；返回 false 表示绑定「无操作」或未接线动作 */
  run(eventId: string): boolean {
    const action: string = getToolbarEventAction(eventId)
    if (action === '' || action === 'none') {
      return false
    }
    if (action === 'translate') {
      menuVM.openTranslate()
      return true
    }
    if (action === 'ai_panel') {
      return false
    }
    this.runAction(action)
    return true
  }

  private runAction(id: string): void {
    switch (id) {
      case 'new_tab':
        tabsVM.newTab('', null, false)
        break
      case 'prev_tab':
        this.switchTabStep(-1)
        break
      case 'next_tab':
        this.switchTabStep(1)
        break
      case 'go_back':
        browserVM.goBack()
        break
      case 'go_forward':
        browserVM.goForward()
        break
      case 'close_tab': {
        const tab: TabInfo | null = tabsVM.tabById(tabsVM.activeTabId)
        if (tab !== null) {
          tabsVM.closeTab(tab.id)
        }
        break
      }
      case 'close_all_tabs':
        tabsVM.closeAll()
        break
      case 'duplicate_tab':
        this.duplicateTab()
        break
      case 'bookmarks':
        QhState.pushPage('bookmarks', null)
        break
      case 'bookmark_dialog':
        this.openBookmarkDialog()
        break
      case 'history':
        QhState.pushPage('history', null)
        break
      case 'downloads':
        QhState.pushPage('downloads', null)
        break
      case 'settings':
        QhState.pushPage('settings', null)
        break
      case 'find_in_page':
        browserVM.showFindBar = true
        break
      case 'read_mode':
        menuVM.toggleReadMode()
        break
      case 'read_aloud':
        readAloudVM.startFromTab()
        break
      case 'enter_url':
        browserVM.isEditingAddress = true
        break
      case 'save_page':
        this.savePage()
        break
      case 'refresh':
        browserVM.refresh()
        break
      case 'view_source':
        menuVM.openViewSource()
        break
      case 'add_bookmark':
        menuVM.openBookmarkEditor()
        break
      case 'page_down':
        this.scrollPage(false)
        break
      case 'page_up':
        this.scrollPage(true)
        break
      case 'scroll_top':
        this.scrollTo(true)
        break
      case 'scroll_bottom':
        this.scrollTo(false)
        break
      default:
        break
    }
  }

  /** 相对当前标签步进切换（循环） */
  private switchTabStep(step: number): void {
    const count: number = tabsVM.tabs.length
    if (count <= 1) {
      return
    }
    const idx: number = tabsVM.tabs.findIndex((t: TabInfo): boolean => t.id === tabsVM.activeTabId)
    if (idx < 0) {
      return
    }
    const next: number = (idx + step + count) % count
    tabsVM.switchTab(tabsVM.tabs[next].id)
  }

  /** 复制标签：同地址同无痕态新开标签 */
  private duplicateTab(): void {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null) {
      return
    }
    if (tab.isHome || tab.viewSourceHtml !== '') {
      tabsVM.newTab('', tab.isIncognito, false)
      return
    }
    tabsVM.newTab(tab.url, tab.isIncognito, false)
  }

  /** 书签对话框：半模态书签列表，点选在当前标签打开 */
  private openBookmarkDialog(): void {
    bookmarkVM.loadAll().then((): void => {
      if (bookmarkVM.bookmarks.length === 0) {
        QhState.pushPage('bookmarks', null)
        return
      }
      const options: PickerOption[] = []
      for (const b of bookmarkVM.bookmarks) {
        options.push(new PickerOption(b.url, b.title !== '' ? b.title : b.url))
      }
      menuVM.picker.title = $r('app.string.bookmarks')
      menuVM.picker.options = options
      menuVM.picker.selected = ''
      menuVM.picker.onSelect = (v: string): void => {
        browserVM.submitAddress(v)
      }
      menuVM.pickerHeight = pickerSheetHeight(options.length)
      menuVM.sheetKind = 'picker'
      menuVM.showSheet = true
    }).catch((): void => {
      QhState.pushPage('bookmarks', null)
    })
  }

  /** 保存网页：捕获 outerHTML 存下载目录 */
  private savePage(): void {
    const tab: TabInfo | null = tabsVM.activeTab
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
        downloadVM.saveLocalHtml(tab.url, tab.title, html)
      })
      .catch((error: BusinessError): void => {
        console.error(`[ToolbarEvent] 保存网页失败: ${error.code} ${error.message}`)
      })
  }

  /** 滚动当前网页一屏（up=true 向上） */
  private scrollPage(up: boolean): void {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null
      || browserVM.isReaderActive(tab.id) || tab.viewSourceHtml !== '') {
      return
    }
    const dir: number = up ? -1 : 1
    tab.controller.runJavaScript(`window.scrollBy(0, ${dir} * window.innerHeight * 0.9)`)
      .catch((error: BusinessError): void => {
        console.error(`[ToolbarEvent] 翻页失败: ${error.code} ${error.message}`)
      })
  }

  /** 滚动到顶部/底部（top=true 顶部） */
  private scrollTo(top: boolean): void {
    const tab: TabInfo | null = tabsVM.activeTab
    if (tab === null || tab.isHome || tab.controller === null
      || browserVM.isReaderActive(tab.id) || tab.viewSourceHtml !== '') {
      return
    }
    const js: string = top ? 'window.scrollTo(0, 0)' : 'window.scrollTo(0, document.body.scrollHeight)'
    tab.controller.runJavaScript(js)
      .catch((error: BusinessError): void => {
        console.error(`[ToolbarEvent] 滚动失败: ${error.code} ${error.message}`)
      })
  }
}

export const toolbarEventRunner: ToolbarEventRunner = new ToolbarEventRunner()
