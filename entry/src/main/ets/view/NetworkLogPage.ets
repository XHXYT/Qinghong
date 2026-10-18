import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { QhState, _QhState } from '../entryability/AppState';
import { netLogVM, NetLogEntry, NetworkLogViewModel } from '../viewmodel/NetworkLogViewModel';
import { AdBlockEngine } from '../common/utils/AdBlockEngine';
import { toastUtil } from '../common/utils/ToastUtils';
import { tabsVM, TabInfo } from '../viewmodel/TabsViewModel';
import { downloadVM } from '../viewmodel/DownloadViewModel';

/**
 * 网络日志原生标签页（嵌入标签容器展示，非路由）：
 * 展示源标签（创建日志标签时的激活标签）的请求记录
 */
@ComponentV2
export struct NetworkLogTab {

  @Require @Param tab: TabInfo

  @Local filter: string = 'all'

  /** 日志归属的源标签 id（nativeParam） */
  private sourceTabId(): number {
    const id = Number(this.tab.nativeParam)
    return Number.isNaN(id) ? -1 : id
  }

  /** 源标签 + 过滤器下的可见条目 */
  private visibleEntries(): NetLogEntry[] {
    const tabId: number = this.sourceTabId()
    return netLogVM.entries.filter((e: NetLogEntry): boolean => {
      if (e.tabId !== tabId) {
        return false
      }
      if (this.filter === 'all') {
        return true
      }
      if (this.filter === 'blocked') {
        return e.status === 'blocked'
      }
      if (this.filter === 'other') {
        return e.kind === 'other' || e.kind === 'main'
      }
      return e.kind === this.filter
    })
  }

  /** 状态图标颜色 */
  private statusColor(status: string): ResourceColor {
    if (status === 'blocked' || status === 'error' || status === 'http') {
      return '#E84026'
    }
    return QhState.currentThemeColor
  }

  /** 状态图标 */
  private static statusSymbol(status: string): Resource {
    if (status === 'blocked') {
      return $r('sys.symbol.nosign')
    }
    if (status === 'error' || status === 'http') {
      return $r('sys.symbol.exclamationmark_circle')
    }
    return $r('sys.symbol.checkmark_circle')
  }

  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        toastUtil.showToast({ message: $r('app.string.copied') })
      })
      .catch((): void => {
      })
  }

  private toggleBlock(entry: NetLogEntry): void {
    netLogVM.toggleBlock(entry)
      .then((blocked: boolean): void => {
        toastUtil.showToast({
          message: blocked
            ? $r('app.string.ad_marked')
            : $r('app.string.net_log_unblocked')
        })
      })
      .catch((): void => {
      })
  }

  private toggleBlockDomain(entry: NetLogEntry): void {
    netLogVM.toggleBlockDomain(entry)
      .then((blocked: boolean): void => {
        toastUtil.showToast({
          message: blocked
            ? $r('app.string.ad_marked')
            : $r('app.string.net_log_unblocked')
        })
      })
      .catch((): void => {
      })
  }

  /** 新标签打开（background=true 后台打开：新建后切回日志标签） */
  private openInTab(entry: NetLogEntry, background: boolean): void {
    const current = tabsVM.activeTabId
    const created = tabsVM.newTab(entry.url, this.tab.isIncognito)
    if (background && created !== null && current >= 0 && tabsVM.activeTabId !== current) {
      tabsVM.activeTabId = current
    }
  }

  private shareUrl(url: string): void {
    try {
      const data = new systemShare.SharedData({
        utd: 'general.hyperlink',
        content: url,
        title: url
      })
      const controller = new systemShare.ShareController(data)
      controller.show(_QhState.Context, {})
        .catch((error: BusinessError): void => {
          console.error(`[NetworkLogTab] 分享失败: ${error.code} ${error.message}`)
        })
    } catch (e) {
      console.error(`[NetworkLogTab] 分享异常: ${e}`)
    }
  }

  build() {
    Column() {
      // 拦截规则存储位置（点击进入规则编辑页，长按复制路径）
      Text($r('app.string.net_log_path_prefix'))
        .fontSize(15)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 12 })
      Text(AdBlockEngine.customRulesFile())
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 4 })
        .onClick(() => {
          QhState.pushPage('settings_adblock_custom', null)
        })
        .gesture(LongPressGesture()
          .onAction(() => {
            this.copyText(AdBlockEngine.customRulesFile())
          }))
      // 操作提示
      Text($r('app.string.net_log_hint'))
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 8, bottom: 12 })
      // 过滤器
      Scroll() {
        Row({ space: 8 }) {
          ForEach(NetworkLogViewModel.filters(), (f: string) => {
            Text(NetworkLogViewModel.filterLabel(f))
              .fontSize(12)
              .fontColor(this.filter === f ? Color.White : $r('sys.color.font_secondary'))
              .padding({ left: 14, right: 14, top: 5, bottom: 5 })
              .borderRadius(14)
              .backgroundColor(this.filter === f
                ? QhState.currentThemeColor
                : $r('sys.color.comp_background_tertiary'))
              .onClick(() => {
                this.filter = f
              })
          }, (f: string): string => f)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ bottom: 4 })
      // 请求列表
      if (this.visibleEntries().length === 0) {
        Column() {
          Text($r('app.string.net_log_empty'))
            .fontSize(14)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          Repeat<NetLogEntry>(this.visibleEntries())
            .each((ri: RepeatItem<NetLogEntry>) => {
              ListItem() {
                this.entryItem(ri.item)
              }
            })
            .key((e: NetLogEntry): string => e.seq.toString())
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .padding({ bottom: 12 })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  entryItem(entry: NetLogEntry) {
    Row() {
      Column() {
        Row({ space: 6 }) {
          Text(entry.time)
            .fontSize(11)
            .fontColor($r('sys.color.font_tertiary'))
          Text(NetworkLogViewModel.kindBadge(entry.kind))
            .fontSize(9)
            .fontColor($r('sys.color.font_secondary'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
          Text(NetworkLogViewModel.hostOf(entry.url))
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        Text(entry.url)
          .fontSize(13)
          .fontColor(entry.status === 'blocked' ? $r('sys.color.font_tertiary') : $r('sys.color.font_primary'))
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph(NetworkLogTab.statusSymbol(entry.status))
        .fontSize(16)
        .fontColor([this.statusColor(entry.status)])
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .onClick(() => {
      this.openInTab(entry, false)
    })
    .bindContextMenu(this.entryMenu(entry), ResponseType.LongPress)
  }

  @Builder
  entryMenu(entry: NetLogEntry) {
    Menu() {
      MenuItem({ content: $r('app.string.net_log_open_background') })
        .onClick(() => {
          this.openInTab(entry, true)
        })
      MenuItem({ content: $r('app.string.net_log_open_new_tab') })
        .onClick(() => {
          this.openInTab(entry, false)
        })
      MenuItem({ content: netLogVM.isDomainBlocked(entry)
        ? $r('app.string.net_log_unblock_domain') : $r('app.string.net_log_block_domain') })
        .onClick(() => {
          this.toggleBlockDomain(entry)
        })
      MenuItem({ content: $r('app.string.net_log_download') })
        .onClick(() => {
          downloadVM.download(entry.url)
        })
      MenuItem({ content: $r('app.string.share') })
        .onClick(() => {
          this.shareUrl(entry.url)
        })
      MenuItem({ content: entry.status === 'blocked'
        ? $r('app.string.net_log_unblock') : $r('app.string.net_log_block') })
        .onClick(() => {
          this.toggleBlock(entry)
        })
      MenuItem({ content: $r('app.string.copy_link') })
        .onClick(() => {
          this.copyText(entry.url)
        })
    }
  }
}
