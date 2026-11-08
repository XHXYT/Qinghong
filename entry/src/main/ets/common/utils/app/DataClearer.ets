import { webview } from '@kit.ArkWeb';
import { fileIo } from '@kit.CoreFileKit';
import { _QhState } from '../../../entryability/AppState';
import { appSettings } from '../../entity/SettingsModel';
import { tabsVM } from '../../../viewmodel/TabsViewModel';
import { historyVM } from '../../../viewmodel/HistoryViewModel';
import { searchHistoryVM } from '../../../viewmodel/SearchViewModel';
import { faviconCache } from '../../../viewmodel/FaviconCache';
import { createLogger } from './Logger';

const logger = createLogger('DataClearer')

/**
 * 数据清理统一入口：设置页「清除数据」与「退出时清除数据」共用。
 * 表单数据无 ArkWeb 公开清除 API，不提供该项（旧设置串中的 form key 解析时自然忽略）。
 */
export class DataClearer {

  /** 清理项 key（与设置页勾选项一一对应） */
  static readonly KEYS: string[] = ['cache', 'history', 'search_history', 'closed_tabs',
    'web_storage', 'cookies', 'app_cache'];

  /** 网页内核缓存（任一标签的 WebviewController.removeCache 为引擎级清理） */
  static clearCache(): void {
    for (const tab of tabsVM.tabs) {
      if (tab.controller) {
        try {
          (tab.controller as webview.WebviewController).removeCache(true);
          return
        } catch (e) {
          logger.error('clearCache', `${e}`)
        }
      }
    }
  }

  /** 历史记录 */
  static clearHistory(): void {
    historyVM.clearAll()
  }

  /** 搜索历史 */
  static clearSearchHistory(): void {
    searchHistoryVM.clearAll()
  }

  /** 已关闭标签（撤销关闭记录） */
  static clearClosedTabs(): void {
    tabsVM.clearUndoTip()
  }

  /** 网页存储（DOM Storage） */
  static clearWebStorage(): void {
    try {
      webview.WebStorage.deleteAllData()
    } catch (e) {
      logger.error('clearWebStorage', `${e}`)
    }
  }

  /** Cookie 及登录信息（Cookie + HTTP 认证凭据） */
  static clearCookies(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync()
    } catch (e) {
      logger.error('clearCookies', `${e}`)
    }
    try {
      webview.WebDataBase.deleteHttpAuthCredentials()
    } catch (e) {
      logger.error('clearAuthCredentials', `${e}`)
    }
  }

  /** 应用缓存：favicon 缓存 + 打印/长按扫描临时文件（不动下载临时与离线页内容） */
  static clearAppCache(): void {
    faviconCache.clearAll()
    try {
      const cacheDir: string = _QhState.Context.cacheDir
      const names: string[] = fileIo.listFileSync(cacheDir)
      for (const name of names) {
        const path: string = `${cacheDir}/${name}`
        try {
          if (name.startsWith('lp_scan_') && name.endsWith('.img')) {
            fileIo.unlinkSync(path)
          } else if (name === 'print') {
            // rmdirSync 仅支持空目录：先清空内部文件再删
            const inner: string[] = fileIo.listFileSync(path)
            for (const f of inner) {
              fileIo.unlinkSync(`${path}/${f}`)
            }
            fileIo.rmdirSync(path)
          }
        } catch (e) {
          logger.error('clearAppCache', `${name}: ${e}`)
        }
      }
    } catch (e) {
      logger.error('clearAppCache', `${e}`)
    }
  }

  /** 按 key 列表批量清理 */
  static clearByKeys(keys: string[]): void {
    for (const key of keys) {
      switch (key) {
        case 'cache':
          DataClearer.clearCache()
          break
        case 'history':
          DataClearer.clearHistory()
          break
        case 'search_history':
          DataClearer.clearSearchHistory()
          break
        case 'closed_tabs':
          DataClearer.clearClosedTabs()
          break
        case 'web_storage':
          DataClearer.clearWebStorage()
          break
        case 'cookies':
          DataClearer.clearCookies()
          break
        case 'app_cache':
          DataClearer.clearAppCache()
          break
        default:
          break
      }
    }
  }

  /** 应用退出时清理（按「退出时清除数据」设置执行） */
  static clearExitData(): void {
    const setting: string = appSettings.exit_clear_data
    if (!setting) {
      return
    }
    const keys: string[] = setting.split(',').filter((k: string): boolean => DataClearer.KEYS.includes(k.trim()))
    if (keys.length > 0) {
      logger.info('clearExitData', `退出清理: ${keys.join(',')}`)
      DataClearer.clearByKeys(keys)
    }
  }
}
