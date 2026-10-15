@Component
export struct AdReviveDialog {
  @Prop gameName: string = '';
  @Prop score: number = 0;
  @Prop visible: boolean = false;
  onRevive: () => void = () => {};
  onCancel: () => void = () => {};
  @State adCountdown: number = 5;
  @State adPlaying: boolean = false;
  @State adFinished: boolean = false;
  private adTimer: number = -1;

  build() {
    Column() {
      Column() {
        if (!this.adPlaying && !this.adFinished) {
          Text(this.gameName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2937')
            .margin({ bottom: 8 })

          Text('游戏结束')
            .fontSize(15)
            .fontColor('#6B7280')
            .margin({ bottom: 6 })

          Text('得分 ' + this.score.toString())
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor('#EA580C')
            .margin({ bottom: 18 })

          Row() {
            Button('结束')
              .height(42)
              .layoutWeight(1)
              .backgroundColor('#E5E7EB')
              .fontColor('#374151')
              .onClick(() => {
                this.onCancel();
              })

            Blank().width(12)

            Button('看广告复活')
              .height(42)
              .layoutWeight(1)
              .backgroundColor('#2563EB')
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.startAd();
              })
          }
          .width('100%')
        } else if (this.adPlaying) {
          Text('广告播放中')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2937')
            .margin({ bottom: 12 })

          Text(this.adCountdown.toString())
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor('#2563EB')
            .margin({ bottom: 8 })

          Text('秒')
            .fontSize(14)
            .fontColor('#6B7280')
        } else {
          Text('可以复活')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#16A34A')
            .margin({ bottom: 14 })

          Button('继续游戏')
            .height(42)
            .width('70%')
            .backgroundColor('#16A34A')
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.onRevive();
            })
        }
      }
      .padding(24)
      .width('86%')
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#00000066')
  }

  private startAd(): void {
    this.adPlaying = true;
    this.adFinished = false;
    this.adCountdown = 5;
    this.clearTimer();
    this.adTimer = setInterval(() => {
      this.adCountdown--;
      if (this.adCountdown <= 0) {
        this.clearTimer();
        this.adPlaying = false;
        this.adFinished = true;
      }
    }, 1000);
  }

  private clearTimer(): void {
    if (this.adTimer >= 0) {
      clearInterval(this.adTimer);
      this.adTimer = -1;
    }
  }

  aboutToDisappear(): void {
    this.clearTimer();
  }
}
