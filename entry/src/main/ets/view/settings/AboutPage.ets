import { bundleManager } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { CustomItemInfo, ItemActionType, ThirdPartyLibInfo } from '../../common/entity/CusItemInfo';
import { SettingsScaffold, SettingsSection } from '../../components/SettingsScaffold';
import { QhState, _QhState } from '../../entryability/AppState';
import { tabsVM } from '../../viewmodel/TabsViewModel';
import { toastUtil } from '../../common/utils/ToastUtils';
import { ResourceUtils } from '../../common/utils/ResourceUtil';

/** 作者主页 */
const GITHUB_OWNER_URL = 'https://github.com/XHXYT';
/** 项目仓库 */
const GITHUB_REPO_URL = 'https://github.com/XHXYT/QingHong';

@Builder
export function AboutBuilder() {
  AboutPage()
}

/**
 * 关于页：应用图标头部 + 基本信息（版本/Web 内核/项目介绍）+ 项目链接 + 开源许可（三方库清单）
 */
@ComponentV2
struct AboutPage {
  @Local sections: SettingsSection[] = []
  @Local versionName: string = '1.0.0'
  @Local engineLabel: string = ''
  /** 三方库半屏弹层显隐 */
  @Local showLibsSheet: boolean = false

  /** 三方开源库清单（半屏弹层展示） */
  private get thirdPartyLibs(): ThirdPartyLibInfo[] {
    return [
      {
        name: 'reflect-metadata',
        packageName: 'reflect-metadata',
        description: 'ES 装饰器元数据反射提案的 polyfill 实现，为数据库 ORM 实体提供类元数据读取能力。',
        license: 'Apache-2.0',
        url: 'https://github.com/rbuckton/reflect-metadata'
      },
      {
        name: 'webdav',
        packageName: '@ya520/webdav',
        description: '基础的 WebDAV 客户端工具库，为书签与设置的 WebDAV 云同步提供协议实现。',
        license: 'Apache-2.0',
        url: 'https://gitcode.com/Ya520/WebDAV'
      }
    ]
  }

  /** ArkWeb 内核版本枚举映射为可读文案 */
  private static engineLabelOf(version: webview.ArkWebEngineVersion): string {
    if (version === webview.ArkWebEngineVersion.M114) {
      return 'ArkWeb M114'
    }
    if (version === webview.ArkWebEngineVersion.M132) {
      return 'ArkWeb M132'
    }
    if (version === webview.ArkWebEngineVersion.M144) {
      return 'ArkWeb M144'
    }
    if (version === webview.ArkWebEngineVersion.ARKWEB_EVERGREEN) {
      return 'ArkWeb 常青内核'
    }
    return '系统默认'
  }

  private loadVersionName(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return info.versionName
    } catch (e) {
      console.error(`[AboutPage] getBundleInfoForSelfSync failed: ${e}`)
      return _QhState.appVersion
    }
  }

  /** 当前 ArkWeb 内核版本可读文案（读取失败返回空串） */
  private loadEngineLabel(): string {
    try {
      return AboutPage.engineLabelOf(webview.WebviewController.getActiveWebEngineVersion())
    } catch (e) {
      console.error(`[AboutPage] getActiveWebEngineVersion failed: ${e}`)
      return ''
    }
  }

  /** Web 内核详情弹窗：当前版本 + 内核档位说明 */
  private showEngineDetail(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.web_engine'),
      message: ResourceUtils.getStringWithArgs($r('app.string.web_engine_desc'), [this.engineLabel]),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.confirm'),
          action: (): void => {
          }
        }
      ]
    }, 'aboutEngineDetail')
  }

  /** GPL-3.0 开源协议弹窗 */
  private showLicenseDetail(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.open_source_license'),
      message: ResourceUtils.getString($r('app.string.open_source_license_desc')),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.confirm'),
          action: (): void => {
          }
        }
      ]
    }, 'aboutLicenseDetail')
  }

  /** 项目介绍弹窗 */
  private showProjectIntro(): void {
    toastUtil.showAlertDialog({
      title: $r('app.string.app_name'),
      message: ResourceUtils.getString($r('app.string.about_desc')),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.confirm'),
          action: (): void => {
          }
        }
      ]
    }, 'aboutProjectIntro')
  }

  aboutToAppear(): void {
    this.versionName = this.loadVersionName()
    this.engineLabel = this.loadEngineLabel()

    const infoSection = new SettingsSection('info', $r('app.string.basic_info'))
    infoSection.items = [
      new CustomItemInfo({
        symbol: $r('sys.symbol.info_circle'),
        title: $r('app.string.app_version'),
        type: ItemActionType.TEXT,
        id: 'app_version',
        value: `v${this.versionName}`
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.gearshape'),
        title: $r('app.string.web_engine'),
        type: ItemActionType.TEXT,
        id: 'web_engine',
        value: this.engineLabel,
        onChange: (): void => {
          this.showEngineDetail()
        }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.doc_text'),
        title: $r('app.string.project_intro'),
        type: ItemActionType.ROUTER,
        id: 'project_intro',
        onChange: (): void => {
          this.showProjectIntro()
        }
      })
    ]

    const linkSection = new SettingsSection('links', $r('app.string.project_links'))
    linkSection.items = [
      new CustomItemInfo({
        symbol: $r('sys.symbol.person'),
        title: $r('app.string.author_home'),
        type: ItemActionType.ROUTER,
        id: 'author_home',
        onChange: (): void => {
          tabsVM.newTab(GITHUB_OWNER_URL)
        }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.star_circle'),
        title: $r('app.string.project_repo'),
        type: ItemActionType.ROUTER,
        id: 'project_repo',
        onChange: (): void => {
          tabsVM.newTab(GITHUB_REPO_URL)
        }
      })
    ]

    const licenseSection = new SettingsSection('license', $r('app.string.open_source'))
    licenseSection.items = [
      new CustomItemInfo({
        symbol: $r('sys.symbol.doc_text_fill'),
        title: $r('app.string.open_source_license'),
        subtitle: 'GPL-3.0',
        type: ItemActionType.ROUTER,
        id: 'open_source_license',
        onChange: (): void => {
          this.showLicenseDetail()
        }
      }),
      new CustomItemInfo({
        symbol: $r('sys.symbol.person_2'),
        title: $r('app.string.third_party_libs'),
        type: ItemActionType.ROUTER,
        id: 'third_party_libs',
        onChange: (): void => {
          this.showLibsSheet = true
        }
      })
    ]

    this.sections = [infoSection, linkSection, licenseSection]
  }

  build() {
    Column() {
      SettingsScaffold({
        title: $r('app.string.about'),
        sections: this.sections,
        header: (): void => {
          this.pageHeader()
        },
        onReady: (ctx: NavDestinationContext): void => {
        },
        onBackPressed: (): boolean => {
          return false
        }
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet(this.showLibsSheet, this.LibSheet(), {
      preferType: SheetType.CENTER,
      height: '60%',
      dragBar: true,
      showClose: false,
      onDisappear: (): void => {
        this.showLibsSheet = false
      }
    })
  }

  /** 顶部应用图标 + 名称 + 版本 */
  @Builder
  pageHeader() {
    Column({ space: 10 }) {
      Stack() {
        Image($r('app.media.background'))
          .width(80)
          .height(80)
        Image($r('app.media.foreground'))
          .width(80)
          .height(80)
      }
      .width(80)
      .height(80)
      .borderRadius(20)
      .clip(true)
      .margin({ top: 24 })

      Text($r('app.string.app_name'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))

      Text(`v${this.versionName}`)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 8, bottom: 4 })
  }

  /** 三方开源库半屏弹层 */
  @Builder
  LibSheet() {
    Column() {
      Row() {
        Text($r('app.string.third_party_libs'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .fontColor($r('sys.color.font_primary'))
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showLibsSheet = false
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.thirdPartyLibs, (lib: ThirdPartyLibInfo, index: number) => {
            this.LibCard(lib, index)
          }, (lib: ThirdPartyLibInfo) => lib.packageName)
          Text($r('app.string.third_party_libs_footer'))
            .fontSize(12)
            .fontColor($r('sys.color.font_fourth'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 8, bottom: 16 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: QhState.bottomRectHeight + 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }

  /** 单个三方库卡片：库名 + 协议标签 + 包名 + 简介 + 仓库按钮 */
  @Builder
  LibCard(lib: ThirdPartyLibInfo, index: number) {
    Column({ space: 8 }) {
      Row() {
        Text(lib.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
        Text(lib.license)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor($r('sys.color.ohos_id_color_hover'))
          .margin({ left: 8 })
        Blank()
        Text(`${index + 1}`)
          .fontSize(12)
          .fontColor($r('sys.color.font_fourth'))
      }
      .width('100%')

      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.archivebox_fill'))
          .fontSize(13)
          .fontColor([$r('sys.color.font_tertiary')])
        Text(lib.packageName)
          .fontSize(13)
          .fontColor($r('sys.color.font_tertiary'))
          .fontFamily('monospace')
      }
      .width('100%')

      Text(lib.description)
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      Row() {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.link'))
              .fontSize(13)
              .fontColor([Color.White])
            Text($r('app.string.view_repo'))
              .fontSize(13)
              .fontColor(Color.White)
          }
        }
        .height(32)
        .borderRadius(16)
        .padding({ left: 16, right: 16 })
        .backgroundColor(QhState.currentThemeColor)
        .onClick(() => {
          tabsVM.newTab(lib.url)
        })
        Blank()
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.background_color'))
  }
}
