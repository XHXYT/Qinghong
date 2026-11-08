import { CustomContentDialog } from '@kit.ArkUI';
import { NaviContainer, NaviBarButton } from '../../../components/NaviContainer';
import { QhState } from '../../../entryability/AppState';
import { buildDialogButtons } from '../../../components/dialog/AppContentDialog';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { trackerVM } from '../../../viewmodel/TrackerViewModel';
import TrackerStatInfo from '../../../common/entity/TrackerStatInfo';
import ItpStatInfo from '../../../common/entity/ItpStatInfo';
import { ItpBypassUtils } from '../../../common/utils/ItpBypassUtils';

@Builder
export function PrivacyReportBuilder() {
  PrivacyReportPage()
}

@ComponentV2
struct PrivacyReportPage {

  @Local trackers: TrackerStatInfo[] = []
  @Local totalHits: number = 0

  @Local itpRecords: ItpStatInfo[] = []
  @Local itpTotalHits: number = 0

  /** 详情弹窗当前跟踪者 */
  @Local detailCompany: string = ''
  /** 详情弹窗当前是否 ITP 拦截记录（决定是否提供「豁免此域名」） */
  @Local detailIsItp: boolean = false
  private detailInfo: TrackerStatInfo | ItpStatInfo | null = null

  private detailDialog: CustomDialogController | undefined = undefined

  aboutToAppear(): void {
    this.detailDialog = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: this.detailCompany,
        contentBuilder: (): void => {
          this.detailContent()
        },
        buttons: buildDialogButtons(
          [$r('app.string.privacy_report_bypass'), $r('app.string.confirm')], false,
          (index: number): void => {
            if (index === 0 && this.detailIsItp) {
              this.bypassDetailHost()
              return
            }
            this.detailDialog?.close()
          }),
        contentAreaPadding: { top: 8, bottom: 8, left: 24, right: 24 }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 32
    })
  }

  private load(): void {
    trackerVM.listAll().then((list: TrackerStatInfo[]): void => {
      this.trackers = list
      let total: number = 0
      for (const t of list) {
        total += t.hits
      }
      this.totalHits = total
    })
    trackerVM.listItpAll().then((list: ItpStatInfo[]): void => {
      this.itpRecords = list
      let total: number = 0
      for (const t of list) {
        total += t.hits
      }
      this.itpTotalHits = total
    })
  }

  /** 类别标签（跟踪者视角文案） */
  private catLabel(category: string): ResourceStr {
    if (category === 'ads') {
      return $r('app.string.tracker_cat_ads')
    }
    if (category === 'analytics') {
      return $r('app.string.tracker_cat_analytics')
    }
    if (category === 'social') {
      return $r('app.string.tracker_cat_social')
    }
    if (category === 'fingerprint') {
      return $r('app.string.tracker_cat_fingerprint')
    }
    return $r('app.string.tracker_cat_track')
  }

  /** 公司徽标首字母（取前 1 字符，中文公司名同样适用） */
  private badgeChar(company: string): string {
    return company.length > 0 ? company.substring(0, 1) : '?'
  }

  private openDetail(info: TrackerStatInfo | ItpStatInfo, isItp: boolean): void {
    this.detailInfo = info
    this.detailIsItp = isItp
    this.detailCompany = info.company
    this.detailDialog?.open()
  }

  /** 豁免当前 ITP 详情的跟踪域名（加入应用级 bypass 列表，内核即刻生效） */
  private bypassDetailHost(): void {
    if (this.detailInfo === null) {
      return
    }
    const ok: boolean = ItpBypassUtils.addHost(this.detailInfo.host)
    toastUtil.showToast({
      message: ok ? $r('app.string.privacy_report_bypass_done') : $r('app.string.privacy_report_bypass_exists')
    })
    if (ok) {
      this.detailDialog?.close()
    }
  }

  private confirmClear(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.privacy_report_clear'),
      message: $r('app.string.privacy_report_clear_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.delete'),
          fontColor: Color.Red,
          action: (): void => {
            trackerVM.removeAll().then((): void => {
              trackerVM.removeItpAll().then((): void => {
                this.load()
              })
            })
          }
        },
        {
          value: $r('app.string.cancel'),
          style: DialogButtonStyle.DEFAULT,
          action: (): void => {
          }
        }
      ]
    }, 'clearPrivacyReport')
  }

  build() {
    NaviContainer({
      title: $r('app.string.privacy_report'),
      buttons: [
        new NaviBarButton({
          symbol: $r('sys.symbol.trash'),
          action: (): void => {
            this.confirmClear()
          }
        })
      ],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        this.load()
      },
      onShown: (): void => {
        this.load()
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  @Builder
  pageContent() {
    List({ space: 12 }) {
      // 汇总卡片（跟踪者视角）
      ListItem() {
        Column({ space: 4 }) {
          Text(ResourceUtils.getStringWithArgs($r('app.string.privacy_report_summary_hits'), [`${this.totalHits}`]))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
          Text(ResourceUtils.getStringWithArgs($r('app.string.privacy_report_summary_companies'), [`${this.trackers.length}`]))
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
          if (this.itpTotalHits > 0) {
            Text(ResourceUtils.getStringWithArgs($r('app.string.privacy_report_summary_itp_hits'), [`${this.itpTotalHits}`]))
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)

      if (this.trackers.length === 0 && this.itpRecords.length === 0) {
        ListItem() {
          Column({ space: 6 }) {
            Text($r('app.string.privacy_report_empty'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
            Text($r('app.string.privacy_report_empty_hint'))
              .fontSize(12)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 20, bottom: 20 })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
      }

      // 广告拦截跟踪者段
      if (this.trackers.length > 0) {
        ListItem() {
          Text($r('app.string.privacy_report_section_ads'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ left: 4 })
        }
        Repeat<TrackerStatInfo>(this.trackers)
          .each((ri: RepeatItem<TrackerStatInfo>) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(this.badgeChar(ri.item.company))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(QhState.currentThemeColor)
                  .width(40)
                  .height(40)
                  .borderRadius(20)
                  .textAlign(TextAlign.Center)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(ri.item.company)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.catLabel(ri.item.category))
                      .fontSize(11)
                      .fontColor($r('sys.color.font_secondary'))
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .backgroundColor($r('sys.color.comp_background_tertiary'))
                  }
                  .alignItems(VerticalAlign.Center)
                  Text(ri.item.host)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(ResourceUtils.getStringWithArgs($r('app.string.privacy_report_tracker_stats'),
                    [`${ri.item.hits}`, `${ri.item.siteCount}`]))
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 16, right: 16, top: 13, bottom: 13 })
            }
            .width('100%')
            .backgroundColor($r('app.color.background_color'))
            .borderRadius(16)
            .clip(true)
            .onClick((): void => {
              this.openDetail(ri.item, false)
            })
          })
          .key((info: TrackerStatInfo) => `${info.id ?? info.host}`)
      }

      // 智能防跟踪（ITP）拦截段
      if (this.itpRecords.length > 0) {
        ListItem() {
          Text($r('app.string.privacy_report_section_itp'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .padding({ left: 4 })
        }
        Repeat<ItpStatInfo>(this.itpRecords)
          .each((ri: RepeatItem<ItpStatInfo>) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(this.badgeChar(ri.item.company))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(QhState.currentThemeColor)
                  .width(40)
                  .height(40)
                  .borderRadius(20)
                  .textAlign(TextAlign.Center)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(ri.item.company)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.catLabel(ri.item.category))
                      .fontSize(11)
                      .fontColor($r('sys.color.font_secondary'))
                      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .backgroundColor($r('sys.color.comp_background_tertiary'))
                  }
                  .alignItems(VerticalAlign.Center)
                  Text(ri.item.host)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(ResourceUtils.getStringWithArgs($r('app.string.privacy_report_tracker_stats'),
                    [`${ri.item.hits}`, `${ri.item.siteCount}`]))
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ left: 16, right: 16, top: 13, bottom: 13 })
            }
            .width('100%')
            .backgroundColor($r('app.color.background_color'))
            .borderRadius(16)
            .clip(true)
            .onClick((): void => {
              this.openDetail(ri.item, true)
            })
          })
          .key((info: ItpStatInfo) => `${info.id ?? info.host}`)
      }
    }
    .width('100%')
    .height('100%')
    .contentEndOffset(QhState.bottomRectHeight)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ left: 16, right: 16 })
  }

  /** 详情弹窗正文：跟踪域名 / 拦截次数 / 触发网站列表 */
  @Builder
  detailContent() {
    Column({ space: 12 }) {
      if (this.detailInfo !== null) {
        Text(this.detailInfo.host)
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(ResourceUtils.getStringWithArgs($r('app.string.privacy_report_tracker_stats'),
          [`${this.detailInfo.hits}`, `${this.detailInfo.siteCount}`]))
          .fontSize(14)
        Text($r('app.string.privacy_report_sites_title'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
        Column({ space: 4 }) {
          Repeat<string>(this.detailSites())
            .each((ri: RepeatItem<string>) => {
              Text(ri.item)
                .fontSize(13)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            })
            .key((site: string) => site)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 解析详情跟踪者出现的网站列表（容错空数组） */
  private detailSites(): string[] {
    if (this.detailInfo === null || this.detailInfo.sites === '') {
      return []
    }
    try {
      return JSON.parse(this.detailInfo.sites) as string[]
    } catch (e) {
      return []
    }
  }
}
