// ============================================================
// PageShell — 子页面通用导航标题：返回按钮 + 标题 + 在线状态
// 用法：在页面 Column 中第一行嵌入，然后紧跟具体内容
// ============================================================

import { THEME_BLUE, THEME_SUCCESS, THEME_DANGER } from '../common/AppConstants';

@Component
export struct PageShell {
  @Prop title: string = '';
  @Prop connected: boolean = false;
  onBack: () => void = () => {};

  build() {
    Row() {
      Button('返回')
        .width(70)
        .height(36)
        .fontSize(14)
        .fontColor(THEME_BLUE)
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: THEME_BLUE })
        .borderRadius(8)
        .onClick(() => this.onBack())

      Text(this.title)
        .layoutWeight(1)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#173C82')
        .textAlign(TextAlign.Center)

      Text(this.connected ? '在线' : '离线')
        .width(70)
        .fontSize(13)
        .fontColor(this.connected ? THEME_SUCCESS : THEME_DANGER)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(44)
    .margin({ bottom: 4 })
  }
}
