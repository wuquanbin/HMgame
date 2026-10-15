// ============================================================
// MatrixPage — 8x8 矩阵灯 / 其他玩法页面
//   顶部：矩阵灯标题 + 连接状态
//   中部：8x8 可点击点阵网格 + 快速生成图案按钮 + 清空/点亮
//   底部：MQTT 连接/发送面板
// ============================================================

import { PageShell } from './PageShell';
import {
  THEME_BLUE,
  THEME_CARD,
  THEME_TEXT_PRIMARY,
  THEME_TEXT_SECOND,
  THEME_SUCCESS,
  THEME_DANGER,
  MATRIX_SIZE,
  MATRIX_GRID_TEMPLATE,
  MATRIX_INDEXES,
  MatrixPattern,
  MATRIX_PATTERNS
} from '../common/AppConstants';

// -------- 单个点阵格 --------
@Component
struct MatrixCell {
  @Prop on: boolean = false;
  onTap: () => void = () => {};

  @State pressed: boolean = false;

  build() {
    Button('')
      .width('100%')
      .height('100%')
      .backgroundColor(this.on ? '#22C55E' : '#111827')
      .border({
        width: 1,
        color: this.on ? '#A7F3D0' : '#334155'
      })
      .borderRadius(6)
      .scale({ x: this.pressed ? 0.9 : 1, y: this.pressed ? 0.9 : 1 })
      .onClick(() => this.onTap())
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) this.pressed = true;
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressed = false;
      })
  }
}

// -------- 矩阵灯网格卡片 --------
@Component
struct MatrixBoardCard {
  @Prop patternName: string = '';
  @Prop connected: boolean = false;
  @Prop rows: number[] = [];
  onCellTap: (cellIndex: number) => void = () => {};

  private cellOn(cellIndex: number): boolean {
    const row = Math.floor(cellIndex / MATRIX_SIZE);
    const col = cellIndex % MATRIX_SIZE;
    if (row < 0 || row >= MATRIX_SIZE) return false;
    const mask = 1 << col;
    return (this.rows[row] & mask) !== 0;
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('8x8 矩阵灯')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(THEME_TEXT_PRIMARY)
          Text(this.patternName)
            .fontSize(12)
            .fontColor(THEME_TEXT_SECOND)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.connected ? '已连接' : '未连接')
          .fontSize(12)
          .fontColor(this.connected ? THEME_SUCCESS : THEME_DANGER)
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .backgroundColor(this.connected ? '#EAF7EF' : '#FEE2E2')
          .borderRadius(6)
      }
      .width('100%')
      .margin({ bottom: 12 })

      Grid() {
        ForEach(MATRIX_INDEXES, (cellIndex: number) => {
          GridItem() {
            MatrixCell({
              on: this.cellOn(cellIndex),
              onTap: () => this.onCellTap(cellIndex)
            })
          }
          .aspectRatio(1)
        }, (cellIndex: number) => cellIndex.toString())
      }
      .columnsTemplate(MATRIX_GRID_TEMPLATE)
      .rowsTemplate(MATRIX_GRID_TEMPLATE)
      .columnsGap(5)
      .rowsGap(5)
      .width('100%')
      .aspectRatio(1)
      .padding(10)
      .backgroundColor('#0F172A')
      .borderRadius(10)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(THEME_CARD)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }
}

// -------- 预设图案面板 --------
@Component
struct PatternPanel {
  @Prop patternName: string = '';
  onApplyPattern: (pattern: MatrixPattern) => void = () => {};
  onRandom: () => void = () => {};
  onClear: () => void = () => {};
  onFill: () => void = () => {};

  @State pressed: string = '';

  build() {
    Column() {
      Row() {
        Text('快速生成')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(THEME_TEXT_PRIMARY)
          .layoutWeight(1)

        Text('随机')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor('#EA580C')
          .borderRadius(8)
          .scale({ x: this.pressed === 'random' ? 0.95 : 1, y: this.pressed === 'random' ? 0.95 : 1 })
          .onClick(() => this.onRandom())
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) this.pressed = 'random';
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressed = '';
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(MATRIX_PATTERNS, (pattern: MatrixPattern) => {
          Column() {
            Text(pattern.name)
              .fontSize(13)
              .fontColor(this.patternName === pattern.name ? '#FFFFFF' : THEME_BLUE)
          }
          .width('31%')
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ bottom: 10 })
          .backgroundColor(this.patternName === pattern.name ? THEME_BLUE : '#FFFFFF')
          .border({ width: 1, color: THEME_BLUE })
          .borderRadius(8)
          .onClick(() => this.onApplyPattern(pattern))
        }, (pattern: MatrixPattern) => pattern.name)
      }
      .width('100%')

      Row() {
        Text('清空')
          .fontSize(13)
          .fontColor(THEME_DANGER)
          .layoutWeight(1)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#FCA5A5' })
          .borderRadius(8)
          .onClick(() => this.onClear())

        Blank().width(10)

        Text('全部点亮')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .height(40)
          .textAlign(TextAlign.Center)
          .backgroundColor('#16A34A')
          .borderRadius(8)
          .onClick(() => this.onFill())
      }
      .width('100%')
    }
    .padding(16)
    .width('100%')
    .backgroundColor(THEME_CARD)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }
}

// -------- MQTT 连接与发送面板 --------
@Component
struct MatrixConnectionPanel {
  @Prop connected: boolean = false;
  @Prop statusText: string = '';
  @Prop message: string = '';
  onConnect: () => void = () => {};
  onSend: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.connected ? '重新连接 MQTT' : '连接 MQTT')
          .fontSize(13)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .height(42)
          .textAlign(TextAlign.Center)
          .backgroundColor(THEME_BLUE)
          .borderRadius(8)
          .onClick(() => this.onConnect())

        Blank().width(10)

        Text('发送当前画面')
          .fontSize(13)
          .fontColor(THEME_BLUE)
          .layoutWeight(1)
          .height(42)
          .textAlign(TextAlign.Center)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: THEME_BLUE })
          .borderRadius(8)
          .onClick(() => this.onSend())
      }
      .width('100%')

      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(12)
          .fontColor(THEME_TEXT_SECOND)
          .margin({ top: 10 })
          .width('100%')
      }

      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(11)
          .fontColor(this.connected ? THEME_SUCCESS : THEME_DANGER)
          .margin({ top: 6 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .padding(16)
    .width('100%')
    .backgroundColor(THEME_CARD)
    .borderRadius(12)
  }
}

// -------- 其他玩法页整体 --------
@Component
export struct MatrixPage {
  @Prop connected: boolean = false;
  @Prop statusText: string = '';
  @Prop matrixPatternName: string = '';
  @Prop matrixMessage: string = '';
  @Prop matrixRows: number[] = [];
  onBack: () => void = () => {};
  onCellTap: (cellIndex: number) => void = () => {};
  onApplyPattern: (pattern: MatrixPattern) => void = () => {};
  onRandomPattern: () => void = () => {};
  onClear: () => void = () => {};
  onFill: () => void = () => {};
  onConnect: () => void = () => {};
  onSendFrame: () => void = () => {};

  build() {
    Column() {
      PageShell({
        title: '其他玩法',
        connected: this.connected,
        onBack: () => this.onBack()
      })

      Scroll() {
        Column() {
          MatrixBoardCard({
            patternName: this.matrixPatternName,
            connected: this.connected,
            rows: this.matrixRows,
            onCellTap: (idx: number) => this.onCellTap(idx)
          })

          PatternPanel({
            patternName: this.matrixPatternName,
            onApplyPattern: (p: MatrixPattern) => this.onApplyPattern(p),
            onRandom: () => this.onRandomPattern(),
            onClear: () => this.onClear(),
            onFill: () => this.onFill()
          })

          MatrixConnectionPanel({
            connected: this.connected,
            statusText: this.statusText,
            message: this.matrixMessage,
            onConnect: () => this.onConnect(),
            onSend: () => this.onSendFrame()
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 14 })
    .backgroundColor('#EFF3F9')
  }
}
