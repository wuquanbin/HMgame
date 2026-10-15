// ============================================================
// AchievementPage — 成就页面
//   顶部：游戏切换 Tab
//   下方：当前游戏的成就列表
// ============================================================

import { PageShell } from './PageShell';
import {
  THEME_BLUE,
  THEME_CARD,
  THEME_TEXT_SECOND,
  THEME_SUCCESS
} from '../common/AppConstants';
import {
  Achievement,
  GameOption,
  GameType,
  GAME_OPTIONS,
  achievementUnlocked,
  achievementsForGame
} from '../common/GameDataModel';

// -------- 获取当前游戏 Option --------
function optionForGame(gameId: GameType): GameOption | null {
  for (let i = 0; i < GAME_OPTIONS.length; i++) {
    if (GAME_OPTIONS[i].id === gameId) return GAME_OPTIONS[i];
  }
  return null;
}

// -------- 游戏 Tab 切换 --------
@Component
struct GameTabs {
  @Prop selectedGame: GameType = GameType.SNAKE;
  onSelected: (game: GameType) => void = () => {};

  @State pressedGame: GameType | null = null;

  build() {
    Row() {
      ForEach(GAME_OPTIONS, (game: GameOption) => {
        Column() {
          Text(game.label)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedGame === game.id ? '#FFFFFF' : THEME_BLUE)
        }
        .height(40)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.selectedGame === game.id ? THEME_BLUE : '#FFFFFF')
        .border({
          width: 1,
          color: this.selectedGame === game.id ? THEME_BLUE : '#D7E1F7'
        })
        .borderRadius(8)
        .scale({
          x: this.pressedGame === game.id ? 0.96 : 1,
          y: this.pressedGame === game.id ? 0.96 : 1
        })
        .onClick(() => this.onSelected(game.id))
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) this.pressedGame = game.id;
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressedGame = null;
        })
      }, (game: GameOption) => game.name)
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 2, bottom: 2 })
  }
}

// -------- 游戏主题 banner（展示游戏背景图） --------
@Component
struct GameThemeBanner {
  @Prop selectedGame: GameType = GameType.SNAKE;
  @Prop unlockedIds: number[] = [];

  private currentLabel(): string {
    const opt = optionForGame(this.selectedGame);
    return (opt !== null && opt !== undefined) ? opt.label : '游戏';
  }

  private unlockedCount(): number {
    const list = achievementsForGame(this.selectedGame);
    let count = 0;
    for (let i = 0; i < list.length; i++) {
      if (achievementUnlocked(this.unlockedIds, list[i].id)) count++;
    }
    return count;
  }

  @Builder
  buildBackgroundImage() {
    if (this.selectedGame === GameType.SNAKE) {
      Image($r('app.media.bg_snake'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.selectedGame === GameType.TETRIS) {
      Image($r('app.media.bg_tetris'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.selectedGame === GameType.DINO) {
      Image($r('app.media.bg_dino'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.selectedGame === GameType.PLANE) {
      Image($r('app.media.bg_plane'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else {
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#222222')
    }
  }

  build() {
    Stack() {
      this.buildBackgroundImage()

      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.45)')

      Column() {
        Text(this.currentLabel())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textShadow({
            radius: 6,
            color: 'rgba(0,0,0,0.65)',
            offsetX: 0,
            offsetY: 2
          })
        Text('成就进度：' + this.unlockedCount().toString() + '/' + achievementsForGame(this.selectedGame).length.toString())
          .fontSize(13)
          .fontColor('#FFFFFF')
          .margin({ top: 6 })
          .textShadow({
            radius: 4,
            color: 'rgba(0,0,0,0.7)',
            offsetX: 0,
            offsetY: 1
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 16, right: 16, top: 18 })
    }
    .width('100%')
    .height(170)
    .clip(true)
  }
}

// -------- 成就列表 --------
@Component
struct AchievementBoard {
  @Prop selectedGame: GameType = GameType.SNAKE;
  @Prop unlockedIds: number[] = [];

  build() {
    Column() {
      ForEach(achievementsForGame(this.selectedGame), (item: Achievement) => {
        Row() {
          Column() {
            Text(item.name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#111827')
            Text(item.description)
              .fontSize(12)
              .fontColor(THEME_TEXT_SECOND)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          if (achievementUnlocked(this.unlockedIds, item.id)) {
            Text('✓ 已解锁')
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor(THEME_SUCCESS)
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          } else {
            Text(item.threshold.toString() + '分')
              .fontSize(12)
              .fontColor(THEME_TEXT_SECOND)
              .backgroundColor('#F1F3F7')
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          }
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 4, right: 4 })
        .borderWidth({ bottom: 1 })
        .borderColor('#E5E7EB')
      }, (item: Achievement) => item.id.toString())
    }
    .padding({ left: 16, right: 16, top: 2, bottom: 16 })
    .width('100%')
  }
}

// -------- 成就页整体 --------
@Component
export struct AchievementPage {
  @Prop connected: boolean = false;
  @Prop selectedGame: GameType = GameType.SNAKE;
  @Prop unlockedIds: number[] = [];
  onBack: () => void = () => {};
  onGameSelected: (game: GameType) => void = () => {};

  build() {
    Column() {
      PageShell({
        title: '游戏成就',
        connected: this.connected,
        onBack: () => this.onBack()
      })

      Column() {
        GameThemeBanner({
          selectedGame: this.selectedGame,
          unlockedIds: this.unlockedIds
        })

        GameTabs({
          selectedGame: this.selectedGame,
          onSelected: (g: GameType) => this.onGameSelected(g)
        })

        AchievementBoard({
          selectedGame: this.selectedGame,
          unlockedIds: this.unlockedIds
        })
      }
      .width('100%')
      .backgroundColor(THEME_CARD)
      .borderRadius(12)
      .clip(true)

      Blank().layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 14 })
    .backgroundColor('#EFF3F9')
  }
}
