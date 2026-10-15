// ============================================================
// HomeMenu — 首页游戏菜单（按新版 UI 规范：三段式布局、主次按钮、底部辅助栏）
//
//  顶部通栏（浅蓝底）       ←  游戏菜单 + 图标组
//  核心功能区（白色）       ←  主按钮【选择游戏】+ 次按钮【游戏成就】【其他玩法】
//  底部辅助栏（浅灰底）     ←  客服 / 隐私 / 清缓存 / 版本
// ============================================================

import {
  MenuPage,
  MainMenuOption,
  MAIN_MENU_OPTIONS,
  THEME_BLUE,
  THEME_BLUE_DARK,
  THEME_BLUE_BG,
  THEME_GREY_BG,
  THEME_TEXT_PRIMARY,
  THEME_TEXT_SECOND,
  APP_VERSION
} from '../common/AppConstants';

@Component
struct PrimaryMenuButton {
  @Prop option: MainMenuOption;
  onPress: () => void = () => {};

  @State pressed: boolean = false;

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.option.title)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Text(this.option.subtitle)
            .fontSize(13)
            .fontColor('#D8FFFFFF')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('→')
          .fontSize(28)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 20, bottom: 20 })
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor(this.pressed ? THEME_BLUE_DARK : THEME_BLUE)
    .shadow({
      radius: 14,
      color: '#4775C8',
      offsetX: 0,
      offsetY: 6
    })
    .scale({ x: this.pressed ? 0.98 : 1, y: this.pressed ? 0.98 : 1 })
    .onClick(() => this.onPress())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.pressed = true;
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressed = false;
    })
  }
}

@Component
struct SecondaryMenuButton {
  @Prop option: MainMenuOption;
  onPress: () => void = () => {};

  @State pressed: boolean = false;

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.option.title)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(THEME_BLUE)
          Text(this.option.subtitle)
            .fontSize(12)
            .fontColor(THEME_TEXT_SECOND)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('→')
          .fontSize(22)
          .fontColor(THEME_BLUE)
      }
      .width('100%')
      .padding({ left: 22, right: 22, top: 18, bottom: 18 })
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(this.pressed ? THEME_BLUE_BG : '#FFFFFF')
    .border({ width: 2, color: THEME_BLUE })
    .scale({ x: this.pressed ? 0.98 : 1, y: this.pressed ? 0.98 : 1 })
    .onClick(() => this.onPress())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.pressed = true;
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressed = false;
    })
  }
}

@Component
export struct HomeMenu {
  onNavigate: (page: MenuPage) => void = () => {};

  build() {
    Column() {
      // ========== 顶部通栏导航（浅蓝底） ==========
      Column() {
        Row() {
          // 左：返回箭头
          Text('←')
            .fontSize(24)
            .fontColor(THEME_BLUE)
            .width(36)

          // 中：大号加粗标题
          Text('游戏菜单')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(THEME_TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          // 右：图标组（设置 / 帮助）
          Row() {
            Text('⚙')
              .fontSize(20)
              .fontColor(THEME_BLUE)
              .width(30)
              .textAlign(TextAlign.Center)
            Text('?')
              .fontSize(16)
              .fontColor('#FFFFFF')
              .width(24)
              .height(24)
              .textAlign(TextAlign.Center)
              .backgroundColor(THEME_BLUE)
              .borderRadius(12)
              .margin({ left: 4 })
          }
          .width(70)
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 36, bottom: 24 })
      .backgroundColor(THEME_BLUE_BG)

      // ========== 核心功能区（白色背景） ==========
      Column() {
        Blank().layoutWeight(1)

        // 三个按钮从上到下依次排布（主按钮更高、带投影）
        Column({ space: 16 }) {
          ForEach(MAIN_MENU_OPTIONS, (option: MainMenuOption) => {
            if (option.isPrimary) {
              PrimaryMenuButton({
                option: option,
                onPress: () => this.onNavigate(option.page)
              })
            } else {
              SecondaryMenuButton({
                option: option,
                onPress: () => this.onNavigate(option.page)
              })
            }
          }, (option: MainMenuOption) => option.title)
        }
        .width('100%')
        .padding({ left: 20, right: 20 })

        Blank().layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#FFFFFF')

      // ========== 底部辅助栏（浅灰底，利用原图空白） ==========
      Column() {
        Row() {
          Text('客服中心')
            .fontSize(12)
            .fontColor(THEME_TEXT_SECOND)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text('|')
            .fontSize(12)
            .fontColor('#D1D5DB')

          Text('隐私协议')
            .fontSize(12)
            .fontColor(THEME_TEXT_SECOND)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text('|')
            .fontSize(12)
            .fontColor('#D1D5DB')

          Text('清除缓存')
            .fontSize(12)
            .fontColor(THEME_TEXT_SECOND)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text('|')
            .fontSize(12)
            .fontColor('#D1D5DB')

          Text('游戏 ' + APP_VERSION)
            .fontSize(12)
            .fontColor(THEME_TEXT_SECOND)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 16, bottom: 16 })
      }
      .width('100%')
      .backgroundColor(THEME_GREY_BG)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
