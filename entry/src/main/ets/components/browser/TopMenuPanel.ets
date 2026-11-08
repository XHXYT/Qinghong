import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';
import cert from '@ohos.security.cert';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { QhState, _QhState } from '../../entryability/AppState';
import { browserVM } from '../../viewmodel/BrowserViewModel';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { bookmarkVM } from '../../viewmodel/BookmarkViewModel';
import { scriptVM } from '../../viewmodel/ScriptViewModel';
import { siteSettingsVM, SiteSettingsViewModel } from '../../viewmodel/SiteSettingsViewModel';
import { UserScriptEngine } from '../../common/utils/userscript/UserScriptEngine';
import { toastUtil } from '../../common/utils/ui/ToastUtils';
import BookmarkInfo from '../../common/entity/BookmarkInfo';
import UserScriptInfo from '../../common/entity/UserScriptInfo';
import UIConstants from '../../common/constants/UIConstants';
import { UrlUtils } from '../../common/constants/SearchEngines';

/** Cookie 行（fetchCookieSync 拆解） */
class CookieRow {
  name: string
  value: string

  constructor(name: string, value: string) {
    this.name = name
    this.value = value
  }
}

/** 证书解析结果 */
class CertInfo {
  subjectCn: string = ''
  subjectO: string = ''
  subjectOu: string = ''
  issuerCn: string = ''
  issuerO: string = ''
  notBefore: string = ''
  notAfter: string = ''
  shaCert: string = ''
  shaPubKey: string = ''
}

/** 字节数组 → 冒号分组小写十六进制（每 16 字节换行） */
function hexGroups(bytes: Uint8Array): string {
  let s: string = ''
  for (let i = 0; i < bytes.length; i++) {
    if (i > 0) {
      s += (i % 16 === 0) ? '\n' : ':'
    }
    s += bytes[i].toString(16).padStart(2, '0')
  }
  return s
}

/** ASN.1 时间（UTCTime/GeneralizedTime）→ 可读格式 */
function fmtAsn1Time(t: string): string {
  const m: RegExpMatchArray | null = t.match(/^(\d{2}|\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z?$/)
  if (m === null || m.length < 7) {
    return t
  }
  let y: string = m[1]
  if (y.length === 2) {
    y = (Number(y) >= 50 ? '19' : '20') + y
  }
  return `${y}-${m[2]}-${m[3]} ${m[4]}:${m[5]}:${m[6]} UTC`
}

/** 从 DN 串（CN=...,O=...）提取指定键值 */
function dnValue(dn: string, key: string): string {
  const parts: string[] = dn.split(',')
  for (const part of parts) {
    const idx: number = part.indexOf('=')
    if (idx > 0 && part.substring(0, idx).trim() === key) {
      return part.substring(idx + 1).trim()
    }
  }
  return ''
}

/**
 * 地址栏左图标全宽顶弹面板（Index 内层 Stack 顶部兄弟节点）：
 * 主页态 = 路由入口（站点设定 + 快捷书签）；网页态 = 页面信息
 * （网站标题/网址/历史/二维码 + 证书 + Cookies + 网站设定 + 脚本）。
 * 透明 scrim 点击关闭；详情经 bindSheet 半模态展示。
 */
@ComponentV2
export struct TopMenuPanel {
  /** 面板弹出边：'top'=自顶向下（顶部栏布局）、'bottom'=自底向上（底部栏布局），跟随搜索框所在栏 */
  @Param edge: string = 'top'
  /** 面板距弹出边偏移（顶部布局=顶栏实测总高，底部布局=底栏实测总高） */
  @Param edgeOffset: number = 46

  @Local showSheet: boolean = false
  @Local sheetKind: string = ''
  @Local qrPixmap: image.PixelMap | undefined = undefined
  @Local qrLoading: boolean = false
  @Local certInfo: CertInfo | null = null
  @Local certLoading: boolean = false
  @Local cookieRows: CookieRow[] = []

  private isHomeMode(): boolean {
    const tab = tabsVM.activeTab
    return tab === null || tab.isHome
  }

  private close(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, (): void => {
      browserVM.showPageMenu = false
    })
  }

  private copyText(text: string): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      toastUtil.showToast({ message: $r('app.string.copied') })
    })
  }

  // ---------- 详情半模态 ----------

  private sheetHeight(): number {
    if (this.sheetKind === 'qr') {
      return 380
    }
    if (this.sheetKind === 'cert') {
      return 560
    }
    if (this.sheetKind === 'cookies') {
      return 470
    }
    // 脚本：按关联脚本数动态撑高，超过 6 条固定高度由 List 内滚动
    const n: number = this.matchingScripts().length
    if (n === 0) {
      return 240
    }
    const rows: number = Math.min(n, 6)
    return 120 + rows * 56
  }

  private openSheet(kind: string): void {
    this.sheetKind = kind
    if (kind === 'qr') {
      this.loadQr()
    } else if (kind === 'cert') {
      this.loadCert()
    } else if (kind === 'cookies') {
      this.loadCookies()
    } else if (kind === 'scripts') {
      scriptVM.loadAll()
    }
    this.showSheet = true
  }

  // ---------- 二维码 ----------

  private currentUrl(): string {
    const tab = tabsVM.activeTab
    return tab !== null ? tab.url : ''
  }

  private loadQr(): void {
    const url: string = this.currentUrl()
    this.qrLoading = true
    const opts: generateBarcode.CreateOptions = {
      scanType: scanCore.ScanType.QR_CODE,
      height: 600,
      width: 600
    }
    generateBarcode.createBarcode(url, opts).then((pm: image.PixelMap): void => {
      this.qrPixmap = pm
      this.qrLoading = false
    }).catch((): void => {
      this.qrPixmap = undefined
      this.qrLoading = false
    })
  }

  /** 保存二维码到图库（SaveButton 安组件授权） */
  private async saveQr(): Promise<void> {
    if (this.qrPixmap === undefined) {
      return
    }
    try {
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(_QhState.Context)
      // SaveButton 安组件授权流程：createAsset 两参重载返回资产 uri
      const uri: string =
        await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png')
      const file: fileIo.File = fileIo.openSync(uri,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      const packer: image.ImagePacker = image.createImagePacker()
      const data: ArrayBuffer = await packer.packing(this.qrPixmap, { format: 'image/png', quality: 100 })
      fileIo.writeSync(file.fd, data)
      fileIo.closeSync(file)
      packer.release()
      toastUtil.showToast({ message: $r('app.string.qr_saved') })
    } catch (e) {
      toastUtil.showToast({ message: $r('app.string.save_failed') })
    }
  }

  // ---------- 证书 ----------

  private async sha256Hex(data: Uint8Array): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256')
    await md.update({ data: data } as cryptoFramework.DataBlob)
    const digest: cryptoFramework.DataBlob = await md.digest()
    return hexGroups(digest.data)
  }

  private async loadCert(): Promise<void> {
    this.certInfo = null
    this.certLoading = true
    try {
      const tab = tabsVM.activeTab
      if (tab === null || tab.controller === null) {
        this.certLoading = false
        return
      }
      const controller: webview.WebviewController = tab.controller
      const certs: Array<cert.X509Cert> = await controller.getCertificate()
      if (certs.length === 0) {
        this.certLoading = false
        return
      }
      const x: cert.X509Cert = certs[0]
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8')
      const subjectBytes: Uint8Array = x.getSubjectName(cert.EncodingType.ENCODING_UTF8).data
      const subject: string = decoder.decodeToString(subjectBytes)
      const issuer: string = x.getIssuerName(cert.EncodingType.ENCODING_UTF8)
      const info: CertInfo = new CertInfo()
      info.subjectCn = dnValue(subject, 'CN')
      info.subjectO = dnValue(subject, 'O')
      info.subjectOu = dnValue(subject, 'OU')
      info.issuerCn = dnValue(issuer, 'CN')
      info.issuerO = dnValue(issuer, 'O')
      info.notBefore = fmtAsn1Time(x.getNotBeforeTime())
      info.notAfter = fmtAsn1Time(x.getNotAfterTime())
      const encoded: cert.EncodingBlob = await x.getEncoded()
      info.shaCert = await this.sha256Hex(encoded.data)
      info.shaPubKey = await this.sha256Hex(x.getPublicKey().getEncoded().data)
      this.certInfo = info
    } catch (e) {
      this.certInfo = null
    }
    this.certLoading = false
  }

  // ---------- Cookies ----------

  private loadCookies(): void {
    const tab = tabsVM.activeTab
    if (tab === null) {
      this.cookieRows = []
      return
    }
    try {
      const raw: string = webview.WebCookieManager.fetchCookieSync(tab.url, tab.isIncognito)
      const rows: CookieRow[] = []
      if (raw !== '') {
        const parts: string[] = raw.split(';')
        for (const part of parts) {
          const p: string = part.trim()
          if (p === '') {
            continue
          }
          const eq: number = p.indexOf('=')
          if (eq > 0) {
            rows.push(new CookieRow(p.substring(0, eq), p.substring(eq + 1)))
          }
        }
      }
      this.cookieRows = rows
    } catch (e) {
      this.cookieRows = []
    }
  }

  /** 删除单条 Cookie：以过期 Set-Cookie 覆盖 */
  private deleteCookie(row: CookieRow): void {
    const tab = tabsVM.activeTab
    if (tab === null) {
      return
    }
    try {
      webview.WebCookieManager.configCookieSync(tab.url,
        `${row.name}=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/`, tab.isIncognito)
      this.loadCookies()
    } catch (e) {
      toastUtil.showToast({ message: $r('app.string.save_failed') })
    }
  }

  private copyAllCookies(): void {
    const parts: string[] = []
    for (const r of this.cookieRows) {
      parts.push(`${r.name}=${r.value}`)
    }
    this.copyText(parts.join('; '))
  }

  // ---------- 脚本 ----------

  private scriptMatches(s: UserScriptInfo): boolean {
    const tab = tabsVM.activeTab
    if (tab === null) {
      return false
    }
    return UserScriptEngine.matchUrl(tab.url, s.matches, s.excludes)
  }

  /** 与当前网站关联（会作用于当前页）的脚本 */
  private matchingScripts(): UserScriptInfo[] {
    const list: UserScriptInfo[] = []
    for (const s of scriptVM.scripts) {
      if (this.scriptMatches(s)) {
        list.push(s)
      }
    }
    return list
  }

  // ---------- 网站设定 ----------

  /** 跳转当前站点设定详情：优先最长后缀匹配的已存站点，无记录则建档当前 host */
  private async goSiteSettings(): Promise<void> {
    const tab = tabsVM.activeTab
    if (tab === null) {
      return
    }
    const host: string = SiteSettingsViewModel.hostOf(tab.url)
    if (host === '') {
      return
    }
    let target: string = ''
    try {
      const sites: string[] = await siteSettingsVM.listSites()
      for (const s of sites) {
        if (SiteSettingsViewModel.hostMatches(host, s) && s.length > target.length) {
          target = s
        }
      }
      if (target === '') {
        // 无设定记录：建档但默认不启用，详情页开关为关、列表置灰
        await siteSettingsVM.setSiteEnabled(host, false)
        target = host
      }
    } catch (e) {
      target = host
    }
    browserVM.showPageMenu = false
    QhState.pushPage('settings_site_detail', target)
  }

  private goHistory(): void {
    browserVM.showPageMenu = false
    QhState.pushPage('history', null)
  }

  // ---------- 构建器 ----------

  /** 圆形图标按钮（站点信息行右侧） */
  @Builder
  circleBtn(icon: Resource, action: () => void) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([$r('sys.color.font_secondary')])
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .onClick(() => action())
  }

  /** 小图标按钮（Cookie 行复制/删除） */
  @Builder
  miniBtn(icon: Resource, action: () => void) {
    SymbolGlyph(icon)
      .fontSize(15)
      .fontColor([$r('sys.color.font_secondary')])
      .padding(6)
      .onClick(() => action())
  }

  /** 功能行：图标 + 标题 + 右箭头 */
  @Builder
  infoRow(icon: Resource, label: ResourceStr, action: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([$r('sys.color.font_secondary')])
      Text(label)
        .fontSize(15)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(UIConstants.CHEVRON_SIZE)
        .fontColor([$r('sys.color.font_tertiary')])
    }
    .height(46)
    .padding({ left: 16, right: 14 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => action())
  }

  /** 主页态面板：站点设定 + 快捷书签 */
  @Builder
  homePanel() {
    Column() {
      this.infoRow($r('sys.symbol.electric_install'), $r('app.string.site_settings'), (): void => {
        this.close()
        QhState.pushPage('settings_site', null)
      })
      Divider()
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })
      if (bookmarkVM.quickLinks.length === 0) {
        Text($r('app.string.no_quick_links'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 18, bottom: 18 })
      } else {
        Scroll() {
          Column() {
            ForEach(bookmarkVM.quickLinks, (b: BookmarkInfo) => {
              this.infoRow($r('sys.symbol.star'), b.title !== '' ? b.title : b.url, (): void => {
                this.close()
                browserVM.openUrl(b.url)
              })
            }, (b: BookmarkInfo): string => b.id !== null ? `${b.id}` : b.url)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .constraintSize({ maxHeight: 300 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 网页态面板：站点信息 + 证书/Cookies/站点设定/脚本 */
  @Builder
  pagePanel() {
    Column() {
      // 行 1：站点信息（标题 + 完整网址 + 安全标识 + 历史/二维码按钮）
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(this.siteTitle())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.currentUrl())
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.connectionState() !== 'unknown') {
            Row({ space: 4 }) {
              SymbolGlyph(this.securityIcon())
                .fontSize(13)
                .fontColor([this.securityColor()])
              Text(this.connectionState() === 'secure'
                ? $r('app.string.site_connection_secure')
                : $r('app.string.site_connection_insecure'))
                .fontSize(12)
                .fontColor(this.securityColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(VerticalAlign.Center)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.circleBtn($r('sys.symbol.clock'), (): void => {
          this.goHistory()
        })
        this.circleBtn($r('sys.symbol.qrcode'), (): void => {
          this.openSheet('qr')
        })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      this.infoRow(this.securityIcon(), $r('app.string.view_certificate'), (): void => {
        this.openSheet('cert')
      })
      this.infoRow($r('sys.symbol.tracking_cookie_interception'), $r('app.string.view_cookies'), (): void => {
        this.openSheet('cookies')
      })
      this.infoRow($r('sys.symbol.electric_install'), $r('app.string.site_settings'), (): void => {
        this.goSiteSettings()
      })
      this.infoRow($r('sys.symbol.code_square'), $r('app.string.view_scripts'), (): void => {
        this.openSheet('scripts')
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private siteTitle(): string {
    const tab = tabsVM.activeTab
    if (tab === null) {
      return ''
    }
    if (tab.title !== '') {
      return tab.title
    }
    return SiteSettingsViewModel.hostOf(tab.url)
  }

  /** 当前站点连接安全状态（https=secure / http=insecure / 其他=unknown） */
  private connectionState(): string {
    return UrlUtils.secureStateOf(this.currentUrl())
  }

  /** 安全标识图标：安全=勾盾 / 不安全=警示盾 / 其他 scheme=锁盾 */
  private securityIcon(): Resource {
    const state: string = this.connectionState()
    if (state === 'insecure') {
      return $r('sys.symbol.exclamationmark_shield_fill')
    }
    if (state === 'secure') {
      return $r('sys.symbol.checkmark_shield')
    }
    return $r('sys.symbol.lock_shield')
  }

  /** 安全标识颜色：安全=绿 / 不安全=警示红 */
  private securityColor(): ResourceColor {
    return this.connectionState() === 'secure' ? '#66BB6A' : '#E84026'
  }

  /** 二维码半模态：码图 + 网址 + 保存按钮 */
  @Builder
  qrSheet() {
    Column({ space: 16 }) {
      if (this.qrPixmap !== undefined) {
        Image(this.qrPixmap)
          .width(230)
          .height(230)
          .borderRadius(12)
          .backgroundColor(Color.White)
          .padding(10)
      } else if (this.qrLoading) {
        LoadingProgress()
          .width(36)
          .height(36)
      } else {
        Text($r('app.string.save_failed'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
      }
      Text(this.currentUrl())
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textAlign(TextAlign.Center)
        .padding({ left: 28, right: 28 })
      SaveButton({
        text: SaveDescription.SAVE_IMAGE,
        icon: SaveIconStyle.FULL_FILLED,
        buttonType: ButtonType.Capsule
      })
        .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
          if (result === SaveButtonOnClickResult.SUCCESS) {
            this.saveQr()
          }
        })
    }
    .width('100%')
    .padding({ top: 20, bottom: 20, left: 20, right: 20 })
    .alignItems(HorizontalAlign.Center)
  }

  /** 证书信息行：标签 + 值（可选复制） */
  @Builder
  certValueRow(label: ResourceStr, value: string, copyable: boolean) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .width(86)
      Text(value === '' ? '-' : value)
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(copyable ? 4 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (copyable && value !== '') {
        this.miniBtn($r('sys.symbol.doc_text_on_doc_text'), (): void => {
          this.copyText(value)
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  certSectionLabel(label: ResourceStr) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .width('100%')
      .padding({ left: 16, top: 14, bottom: 4 })
  }

  /** 证书半模态 */
  @Builder
  certSheet() {
    Scroll() {
      Column() {
        if (this.certLoading) {
          LoadingProgress()
            .width(36)
            .height(36)
            .margin({ top: 40 })
        } else if (this.certInfo === null) {
          Text($r('app.string.cert_unavailable'))
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 40 })
        } else {
          this.certSectionLabel($r('app.string.cert_issued_to'))
          this.certValueRow($r('app.string.cert_common_name'), this.certInfo.subjectCn, true)
          this.certValueRow($r('app.string.cert_organization'), this.certInfo.subjectO, true)
          this.certValueRow($r('app.string.cert_org_unit'), this.certInfo.subjectOu, true)
          this.certSectionLabel($r('app.string.cert_issuer'))
          this.certValueRow($r('app.string.cert_common_name'), this.certInfo.issuerCn, true)
          this.certValueRow($r('app.string.cert_organization'), this.certInfo.issuerO, true)
          this.certSectionLabel($r('app.string.cert_validity'))
          this.certValueRow($r('app.string.cert_issued_on'), this.certInfo.notBefore, true)
          this.certValueRow($r('app.string.cert_expires_on'), this.certInfo.notAfter, true)
          this.certSectionLabel($r('app.string.cert_sha256'))
          this.certValueRow($r('app.string.cert_fp_certificate'), this.certInfo.shaCert, true)
          this.certValueRow($r('app.string.cert_fp_public_key'), this.certInfo.shaPubKey, true)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.TopStart)
  }

  /** Cookies 半模态 */
  @Builder
  cookiesSheet() {
    Column() {
      Row() {
        Text($r('app.string.view_cookies'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        if (this.cookieRows.length > 0) {
          this.miniBtn($r('sys.symbol.doc_text_on_doc_text'), (): void => {
            this.copyAllCookies()
          })
        }
      }
      .width('100%')
      .height(46)
      .padding({ left: 16, right: 10 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      if (this.cookieRows.length === 0) {
        Text($r('app.string.cookies_empty'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 36 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.cookieRows, (row: CookieRow) => {
              Row({ space: 4 }) {
                Column({ space: 3 }) {
                  Text(row.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(row.value)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                this.miniBtn($r('sys.symbol.doc_text_on_doc_text'), (): void => {
                  this.copyText(`${row.name}=${row.value}`)
                })
                this.miniBtn($r('sys.symbol.trash'), (): void => {
                  this.deleteCookie(row)
                })
              }
              .width('100%')
              .padding({ left: 16, right: 6, top: 8, bottom: 8 })
              .alignItems(VerticalAlign.Top)
            }, (row: CookieRow): string => row.name)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 脚本半模态：仅显示与当前网站关联的脚本 + 启用开关；超出固定高度由 List 滚动 */
  @Builder
  scriptsSheet() {
    Column() {
      if (this.matchingScripts().length === 0) {
        Text($r('app.string.no_scripts'))
          .fontSize(13)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 36 })
      } else {
        List() {
          ForEach(this.matchingScripts(), (s: UserScriptInfo) => {
            ListItem() {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(s.name !== '' ? s.name : `#${s.id}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 5 }) {
                    Circle()
                      .width(6)
                      .height(6)
                      .fill(QhState.currentThemeColor)
                    Text($r('app.string.script_runs_here'))
                      .fontSize(11)
                      .fontColor($r('sys.color.font_secondary'))
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: s.enabled })
                  .onChange((isOn: boolean) => {
                    scriptVM.toggle(s, isOn)
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 14, top: 9, bottom: 9 })
              .alignItems(VerticalAlign.Center)
            }
          }, (s: UserScriptInfo): string => s.id !== null ? `${s.id}_${s.enabled}` : s.name)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  detailSheetBuilder() {
    if (this.sheetKind === 'qr') {
      this.qrSheet()
    } else if (this.sheetKind === 'cert') {
      this.certSheet()
    } else if (this.sheetKind === 'cookies') {
      this.cookiesSheet()
    } else {
      this.scriptsSheet()
    }
  }

  build() {
    Stack({ alignContent: this.edge === 'bottom' ? Alignment.Bottom : Alignment.Top }) {
      // 透明 scrim：点击空白关闭
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.close()
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))

      // 全宽面板：顶部栏布局自顶向下弹出、底部栏布局自底向上弹出（跟随搜索框所在栏）
      Column() {
        if (this.isHomeMode()) {
          this.homePanel()
        } else {
          this.pagePanel()
        }
      }
      .width('100%')
      .margin(this.edge === 'bottom' ? { bottom: this.edgeOffset } : { top: this.edgeOffset })
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(this.isHomeMode()
        ? { topLeft: 22, topRight: 22, bottomLeft: 22, bottomRight: 22 }
        : (this.edge === 'bottom'
          ? { topLeft: 22, topRight: 22 } : { bottomLeft: 22, bottomRight: 22 }))
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)', offsetY: this.edge === 'bottom' ? -4 : 4 })
      .clip(true)
      .transition(TransitionEffect.translate({ y: this.edge === 'bottom' ? 220 : -220 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: 220, curve: Curve.Friction }))
    }
    .width('100%')
    .height('100%')
    .bindSheet(this.showSheet!!, this.detailSheetBuilder(), {
      height: this.sheetHeight(),
      dragBar: true,
      showClose: false,
      backgroundColor: $r('sys.color.comp_background_primary'),
      onDisappear: (): void => {
        this.showSheet = false
      }
    })
  }
}
