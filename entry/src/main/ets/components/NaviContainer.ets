import UIConstants from "../common/constants/UIConstants"
import { QhState } from "../entryability/AppState"
import { KeyCode } from "@kit.InputKit"

/**
 * 自定义标题栏按钮初始化参数
 */
export interface NaviBarButtonInit {
  /** Symbol 图标资源 */
  symbol?: Resource
  /** 文字按钮文本（symbol 优先） */
  text?: ResourceStr
  /** 图标大小，默认 24vp */
  iconSize?: number
  /** 按钮宽度，默认 40vp */
  width?: number
  /** 按钮高度，默认 40vp */
  height?: number
  /** 图标/文字颜色，默认主文字色 */
  fontColor?: ResourceColor
  /** 背景色，默认官方图标按钮背景 */
  backgroundColor?: ResourceColor
  /** 点击事件 */
  action?: () => void
}

/**
 * 自定义标题栏按钮
 */
export class NaviBarButton {
  symbol: Resource | undefined = undefined
  text: ResourceStr | undefined = undefined
  iconSize: number = 24
  width: number = 40
  height: number = 40
  fontColor: ResourceColor = $r('sys.color.font_primary')
  backgroundColor: ResourceColor = $r('sys.color.comp_background_tertiary')
  action: (() => void) | undefined = undefined

  constructor(init?: NaviBarButtonInit) {
    if (init) {
      if (init.symbol !== undefined) this.symbol = init.symbol
      if (init.text !== undefined) this.text = init.text
      if (init.iconSize !== undefined) this.iconSize = init.iconSize
      if (init.width !== undefined) this.width = init.width
      if (init.height !== undefined) this.height = init.height
      if (init.fontColor !== undefined) this.fontColor = init.fontColor
      if (init.backgroundColor !== undefined) this.backgroundColor = init.backgroundColor
      if (init.action !== undefined) this.action = init.action
    }
  }
}

@ComponentV2
export struct NaviContainer {

  @Param title: ResourceStr | undefined = undefined
  @Param subTitle: ResourceStr = ''

  @Param showMenu: boolean = false
  @Param hideTitleBar: boolean = false

  @Param transitionEffect?: TransitionEffect = undefined

  @BuilderParam menusBuilder?: () => void
  @BuilderParam content: () => void;

  /** 标题栏右侧按钮（最多渲染 4 个） */
  @Param buttons: NaviBarButton[] = []

  private pageStack: NavPathStack = new NavPathStack()

  @Event onReady: (ctx: NavDestinationContext) => void
  @Event onBackPressed: () => boolean
  @Event onNaviDisAppear: () => void
  @Event onShown: () => void = () => {
  }

  private shouldShowBar(): boolean {
    return !this.hideTitleBar && !!this.title
  }

  build() {
    NavDestination() {
      if (this.menusBuilder) {
        Row().height(1).width('100%')
          .bindContextMenu(this.showMenu!!, this.menusBuilder,
            {
              placement: QhState.widthBp < 2 ? Placement.LeftBottom : Placement.BottomRight,
            })
      }
      Column() {
        if (this.shouldShowBar()) {
          this.titleBar()
        }
        Column() {
          this.content()
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.shouldShowBar() ? (QhState.topRectHeight || 12) : 0 })
    }
    .height('100%')
    .backgroundColor($r('app.color.background_color_accent'))
    .hideToolBar(true)
    .hideTitleBar(true)
    .transition(this.transitionEffect)
    .onBackPressed(() => {
      return this.onBackPressed()
    })
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down) {
        if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
          if (!this.onBackPressed()) {
            this.pageStack.pop()
          }
        }
      }
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pageStack = ctx.pathStack
      this.onReady(ctx)
    })
    .onShown(() => {
      this.onShown()
    })
    .animation({ duration: UIConstants.AnimationSpeed_300, curve: Curve.Ease })
  }

  @Builder
  titleBar() {
    Row() {
      // 返回键（官方图标按钮样式）
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onClick(() => {
        if (!this.onBackPressed()) {
          this.pageStack.pop()
        }
      })
      // 标题/副标题
      Column() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
        if (this.subTitle !== '') {
          Text(this.subTitle)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
            .textAlign(TextAlign.Start)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 右侧按钮（最多 4 个）
      if (this.buttons.length > 0) {
        Row({ space: 8 }) {
          if (this.buttons.length > 0) {
            this.barButton(0)
          }
          if (this.buttons.length > 1) {
            this.barButton(1)
          }
          if (this.buttons.length > 2) {
            this.barButton(2)
          }
          if (this.buttons.length > 3) {
            this.barButton(3)
          }
        }
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  barButton(index: number) {
    Row() {
      if (this.buttons[index].symbol !== undefined) {
        SymbolGlyph(this.buttons[index].symbol)
          .fontSize(this.buttons[index].iconSize)
          .fontColor([this.buttons[index].fontColor])
      } else if (this.buttons[index].text !== undefined) {
        Text(this.buttons[index].text)
          .fontSize(15)
          .fontColor(this.buttons[index].fontColor)
      }
    }
    .width(this.buttons[index].width)
    .height(this.buttons[index].height)
    .borderRadius(this.buttons[index].height / 2)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.buttons[index].backgroundColor)
    .onClick(() => {
      this.doAction(index)
    })
  }

  private doAction(index: number): void {
    const btn: NaviBarButton | undefined = this.buttons[index]
    if (btn !== undefined && btn.action !== undefined) {
      btn.action()
    }
  }

}
