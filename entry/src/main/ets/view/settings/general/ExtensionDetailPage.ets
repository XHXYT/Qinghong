import { pasteboard } from '@kit.BasicServicesKit';
import { NaviContainer } from '../../../components/NaviContainer';
import { CustomListItem } from '../../../components/CusItemBuilder';
import { CustomItemInfo, ItemActionType } from '../../../common/entity/CusItemInfo';
import { QhState } from '../../../entryability/AppState';
import { extensionVM } from '../../../viewmodel/ExtensionViewModel';
import ExtensionInfo from '../../../common/entity/ExtensionInfo';
import { ExtManifestRaw } from '../../../common/utils/ExtensionEngine';
import { ExtensionResources } from '../../../common/utils/ExtensionResources';
import { ScriptViewModel } from '../../../viewmodel/ScriptViewModel';
import { toastUtil } from '../../../common/utils/ToastUtils';
import { ResourceUtils } from '../../../common/utils/ResourceUtil';
import { tabsVM } from '../../../viewmodel/TabsViewModel';

@Builder
export function ExtensionDetailPageBuilder() {
  ExtensionDetailPage()
}

/**
 * 扩展详细信息页（对齐 Chrome 扩展详情页）：
 * 头部图标/名称/版本/描述 + 启用开关；扩展 ID（点击复制）、安装来源/时间；
 * manifest 权限与主机权限展示；选项页入口；底部移除按钮
 */
@ComponentV2
struct ExtensionDetailPage {

  /** 当前扩展 id（live() 经 extensionVM.extensions 实时解析） */
  private extId: string = ''

  /** manifest 原文解析缓存（安装后不可变） */
  private rawCache: ExtManifestRaw | null = null

  private live(): ExtensionInfo | null {
    for (const e of extensionVM.extensions) {
      if (e.extId === this.extId) {
        return e
      }
    }
    return null
  }

  private liveInfo(): ExtensionInfo {
    const e: ExtensionInfo | null = this.live()
    return e !== null ? e : new ExtensionInfo()
  }

  /** manifest 原文解析（一次转型 + 缺失字段归一化，失败回退空模型） */
  private rawOf(): ExtManifestRaw {
    if (this.rawCache === null) {
      let raw: ExtManifestRaw = new ExtManifestRaw()
      try {
        raw = JSON.parse(this.liveInfo().manifest) as ExtManifestRaw
        if (!(raw.permissions instanceof Array)) {
          raw.permissions = []
        }
        if (!(raw.host_permissions instanceof Array)) {
          raw.host_permissions = []
        }
        if (typeof raw.options_page !== 'string') {
          raw.options_page = ''
        }
        if (raw.options_ui !== undefined && raw.options_ui !== null && typeof raw.options_ui === 'object') {
          if (typeof raw.options_ui.page !== 'string') {
            raw.options_ui.page = ''
          }
        } else {
          raw.options_ui = null
        }
      } catch (e) {
        raw = new ExtManifestRaw()
      }
      this.rawCache = raw
    }
    return this.rawCache
  }

  /** manifest 声明的选项页相对路径（options_ui.page 优先） */
  private optionsPath(): string {
    const raw: ExtManifestRaw = this.rawOf()
    if (raw.options_ui !== null && raw.options_ui.page !== '') {
      return raw.options_ui.page
    }
    return raw.options_page
  }

  private liveEnabled(): boolean {
    return this.liveInfo().enabled
  }

  private installSource(): string {
    const e: ExtensionInfo = this.liveInfo()
    if (e.updateUrl !== '') {
      return e.updateUrl
    }
    return ResourceUtils.getString($r('app.string.ext_local_import'))
  }

  private createdText(): string {
    return ScriptViewModel.formatStamp(this.liveInfo().createTime)
  }

  private updatedText(): string {
    return ScriptViewModel.formatStamp(this.liveInfo().updateTime)
  }

  private copyText(text: string): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        toastUtil.showToast({ message: $r('app.string.copied') })
      })
      .catch((): void => {
      })
  }

  /** 确认移除：删除后 Toast 并返回上一页 */
  private confirmRemove(): void {
    const e: ExtensionInfo | null = this.live()
    if (e === null) {
      QhState.pageStack.pop()
      return
    }
    toastUtil.showAlertDialog({
      title: e.name,
      message: $r('app.string.ext_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.ext_remove'),
          fontColor: Color.Red,
          action: (): void => {
            extensionVM.deleteExt(e).then((): void => {
              toastUtil.showToast({ message: $r('app.string.ext_removed') })
              QhState.pageStack.pop()
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
    }, 'removeExtension')
  }

  build() {
    NaviContainer({
      title: $r('app.string.ext_detail'),
      buttons: [],
      content: (): void => {
        this.pageContent()
      },
      onReady: (ctx: NavDestinationContext): void => {
        const key: string = ctx.pathInfo.param as string
        if (key !== undefined && key !== '') {
          this.extId = key
        }
      },
      onBackPressed: (): boolean => {
        return false
      }
    })
  }

  /** 信息键值行 */
  @Builder
  infoRow(label: Resource, value: string, copyable: boolean) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1)
        .maxLines(1)
      Text(value === '' ? '-' : value)
        .fontSize(13)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '58%' })
    }
    .width('100%')
    .height(44)
    .onClick(() => {
      if (copyable && value !== '') {
        this.copyText(value)
      }
    })
  }

  /** 权限胶囊 */
  @Builder
  permChip(perm: string) {
    Text(perm)
      .fontSize(12)
      .fontColor($r('sys.color.font_secondary'))
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(10)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .margin({ right: 6, bottom: 6 })
  }

  @Builder
  pageContent() {
    List() {
      // 头部：图标 + 名称/版本 + 描述 + 启用开关
      ListItem() {
        Column() {
          Row({ space: 12 }) {
            if (extensionVM.iconPathOf(this.liveInfo()) !== '') {
              Image(`file://${extensionVM.iconPathOf(this.liveInfo())}`)
                .width(48)
                .height(48)
                .borderRadius(12)
                .objectFit(ImageFit.Contain)
            } else {
              SymbolGlyph($r('sys.symbol.puzzle'))
                .fontSize(40)
                .fontColor([$r('sys.color.font_secondary')])
            }
            Column({ space: 2 }) {
              Text(this.liveInfo().name)
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(2)
              Text(`v${this.liveInfo().version} · MV${this.liveInfo().manifestVersion}`)
                .fontSize(12)
                .fontColor($r('sys.color.font_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          if (this.liveInfo().description !== '') {
            Text(this.liveInfo().description)
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
              .margin({ top: 10 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(16)
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)

      // 启用开关（通用行组件）
      ListItem() {
        CustomListItem({
          item: new CustomItemInfo({
            id: 'detail_toggle',
            title: $r('app.string.ext_enable'),
            type: ItemActionType.TOGGLE,
            value: this.liveEnabled(),
            onChange: (v: string | boolean | number): void => {
              const e: ExtensionInfo | null = this.live()
              if (e !== null) {
                extensionVM.toggle(e, v as boolean)
              }
            }
          }),
          itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 信息：ID / 来源 / 时间
      ListItem() {
        Column() {
          this.infoRow($r('app.string.ext_id'), this.liveInfo().extId, true)
          Divider()
            .color($r('sys.color.comp_divider'))
            .margin({ left: 0, right: 0 })
          this.infoRow($r('app.string.ext_install_source'), this.installSource(), false)
          Divider()
            .color($r('sys.color.comp_divider'))
          this.infoRow($r('app.string.ext_install_time'), this.createdText(), false)
          Divider()
            .color($r('sys.color.comp_divider'))
          this.infoRow($r('app.string.ext_update_time'), this.updatedText(), false)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })

      // 权限
      if (this.rawOf().permissions.length > 0 || this.rawOf().host_permissions.length > 0) {
        ListItem() {
          Column() {
            if (this.rawOf().permissions.length > 0) {
              Text($r('app.string.ext_permissions'))
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .padding({ top: 14, bottom: 8 })
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.rawOf().permissions, (p: string) => {
                  this.permChip(p)
                }, (p: string) => p)
              }
              .width('100%')
            }
            if (this.rawOf().host_permissions.length > 0) {
              Text($r('app.string.ext_host_permissions'))
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.rawOf().host_permissions, (p: string) => {
                  this.permChip(p)
                }, (p: string) => p)
              }
              .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 10 })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: 10 })
      }

      // 选项页入口（通用行组件；清空页面栈退回主界面再开标签）
      if (this.optionsPath() !== '') {
        ListItem() {
          CustomListItem({
            item: new CustomItemInfo({
              id: 'detail_options',
              title: $r('app.string.ext_options_page'),
              type: ItemActionType.ROUTER,
              value: '',
              onChange: (v: string | boolean | number): void => {
                QhState.pageStack.clear()
                tabsVM.newTab(ExtensionResources.extUrl(this.extId, this.optionsPath()), false)
              }
            }),
            itemPadding: { left: 16, right: 16, top: 13, bottom: 13 }
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.background_color'))
        .borderRadius(16)
        .clip(true)
        .margin({ top: 10 })
      }

      // 移除
      ListItem() {
        Text($r('app.string.ext_remove'))
          .fontSize(15)
          .fontColor(Color.Red)
          .width('100%')
          .height(48)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.confirmRemove()
          })
      }
      .width('100%')
      .backgroundColor($r('app.color.background_color'))
      .borderRadius(16)
      .clip(true)
      .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .contentEndOffset(QhState.bottomRectHeight)
    .padding({ left: 16, right: 16 })
  }
}
