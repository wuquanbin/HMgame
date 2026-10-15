// ============================================================
// SelectGamePage — 选择游戏页面
//   顶部：Swiper 左右滑动游戏卡片选择器
//   中部：最新对局卡片（大号分数）
//   底部：排行榜（随当前选中游戏联动）
// ============================================================

import { PageShell } from './PageShell';
import {
  THEME_BLUE,
  THEME_CARD,
  THEME_TEXT_PRIMARY,
  THEME_TEXT_SECOND,
  THEME_ACCENT
} from '../common/AppConstants';
import {
  GameOption,
  GameType,
  ScoreRecord,
  GAME_OPTIONS,
  achievementUnlocked,
  achievementsForGame,
  formatTime,
  gameLabelFromName,
  gameNameFromType
} from '../common/GameDataModel';

// -------- 顶部固定游戏背景卡 --------
@Component
struct GameHeroCard {
  @Prop game: GameOption;
  @Prop selected: boolean = false;
  @Prop unlockedIds: number[] = [];
  onTap: () => void = () => {};

  private unlockedCount(): number {
    const list = achievementsForGame(this.game.id);
    let count = 0;
    for (let i = 0; i < list.length; i++) {
      if (achievementUnlocked(this.unlockedIds, list[i].id)) count++;
    }
    return count;
  }

  @Builder
  private buildBackgroundImage() {
    if (this.game.id === GameType.SNAKE) {
      Image($r('app.media.bg_snake'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.game.id === GameType.TETRIS) {
      Image($r('app.media.bg_tetris'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.game.id === GameType.DINO) {
      Image($r('app.media.bg_dino'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else if (this.game.id === GameType.PLANE) {
      Image($r('app.media.bg_plane'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#111827')
    }
  }

  build() {
    Stack() {
      this.buildBackgroundImage()

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.28)')

      Column() {
        Text(this.game.label)
          .fontSize(25)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textShadow({
            radius: 8,
            color: 'rgba(0,0,0,0.75)',
            offsetX: 0,
            offsetY: 2
          })

        Text('成就 ' + this.unlockedCount().toString() + '/' + achievementsForGame(this.game.id).length.toString())
          .fontSize(14)
          .fontColor('#FFFFFF')
          .margin({ top: 8 })
          .textShadow({
            radius: 5,
            color: 'rgba(0,0,0,0.7)',
            offsetX: 0,
            offsetY: 1
          })

        Text(this.selected ? '✓ 已选择' : '点击选择')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#4A5D23')
          .margin({ top: 16 })
          .padding({ left: 22, right: 22, top: 7, bottom: 7 })
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#FACC15' })
          .borderRadius(18)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 18, right: 18 })
    }
    .width('100%')
    .height(190)
    .border({ width: 3, color: this.selected ? '#FACC15' : '#D7E1F7' })
    .borderRadius(14)
    .clip(true)
    .onClick(() => {
      this.onTap();
    })
  }
}

// -------- 顶部固定高度滑动选择器 --------
@Component
struct GameSwipingSelector {
  @Prop selectedGame: GameType = GameType.SNAKE;
  @Prop unlockedIds: number[] = [];
  onSelectedChange: (game: GameType) => void = () => {};

  private selectedIndex(): number {
    for (let i = 0; i < GAME_OPTIONS.length; i++) {
      if (GAME_OPTIONS[i].id === this.selectedGame) {
        return i;
      }
    }
    return 0;
  }

  build() {
    Swiper() {
      ForEach(GAME_OPTIONS, (game: GameOption) => {
        GameHeroCard({
          game: game,
          selected: this.selectedGame === game.id,
          unlockedIds: this.unlockedIds,
          onTap: () => {
            this.onSelectedChange(game.id);
          }
        })
      }, (game: GameOption) => game.name)
    }
    .width('100%')
    .height(198)
    .index(this.selectedIndex())
    .autoPlay(false)
    .indicator(true)
    .loop(false)
    .displayCount(1)
    .itemSpace(0)
    .margin({ bottom: 12 })
    .onChange((index: number) => {
      if (index >= 0 && index < GAME_OPTIONS.length) {
        this.onSelectedChange(GAME_OPTIONS[index].id);
      }
    })
  }
}

// -------- 最新对局卡片 --------
@Component
struct LatestPanel {
  @Prop latestGameName: string = '';
  @Prop latestScore: number = 0;

  build() {
    Row() {
      Column() {
        Text('最新对局')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(THEME_TEXT_PRIMARY)
        if (this.latestGameName.length > 0) {
          Text(this.latestGameName)
            .fontSize(13)
            .fontColor(THEME_TEXT_SECOND)
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.latestScore.toString())
        .fontSize(60)
        .fontWeight(FontWeight.Bold)
        .fontColor(THEME_ACCENT)
        .lineHeight(66)
    }
    .width('100%')
    .height(88)
    .padding({ left: 18, right: 18 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(THEME_CARD)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }
}

// -------- 排行榜 --------
@Component
struct ScoreBoard {
  @Prop selectedGame: GameType = GameType.SNAKE;
  @Prop scores: ScoreRecord[] = [];

  private filteredScores(): ScoreRecord[] {
    const gameName = gameNameFromType(this.selectedGame);
    const list: ScoreRecord[] = [];
    for (let i = 0; i < this.scores.length; i++) {
      if (this.scores[i].game === gameName) list.push(this.scores[i]);
    }
    list.sort((left: ScoreRecord, right: ScoreRecord) => {
      if (right.score !== left.score) return right.score - left.score;
      return right.timestamp - left.timestamp;
    });
    if (list.length > 10) return list.slice(0, 10);
    return list;
  }

  build() {
    Column() {
      Row() {
        Text('排行榜 · ' + gameLabelFromName(gameNameFromType(this.selectedGame)))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(THEME_TEXT_PRIMARY)
          .layoutWeight(1)

        Text(this.filteredScores().length.toString() + ' 条')
          .fontSize(12)
          .fontColor(THEME_TEXT_SECOND)
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (this.filteredScores().length === 0) {
        Column() {
          Text('暂无成绩')
            .fontSize(14)
            .fontColor(THEME_TEXT_SECOND)
            .height(60)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.filteredScores(), (item: ScoreRecord, index: number) => {
          Row() {
            Text((index + 1).toString())
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(index < 3 ? THEME_ACCENT : THEME_BLUE)
              .width(28)
            Text(item.score.toString())
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')
              .layoutWeight(1)
            Text(formatTime(item.timestamp))
              .fontSize(12)
              .fontColor(THEME_TEXT_SECOND)
          }
          .height(40)
          .width('100%')
          .padding({ left: 4, right: 4 })
          .borderWidth({ bottom: 1 })
          .borderColor('#E5E7EB')
        }, (item: ScoreRecord) => item.id.toString())
      }
    }
    .padding(16)
    .width('100%')
    .backgroundColor(THEME_CARD)
    .borderRadius(12)
  }
}

// -------- 选择游戏页整体 --------
@Component
export struct SelectGamePage {
  @Prop connected: boolean = false;
  @Prop selectedGame: GameType = GameType.SNAKE;
  @Prop scores: ScoreRecord[] = [];
  @Prop unlockedIds: number[] = [];
  @Prop latestGameName: string = '';
  @Prop latestScore: number = 0;
  onBack: () => void = () => {};
  onGameSelected: (game: GameType) => void = () => {};

  build() {
    Column() {
      PageShell({
        title: '选择游戏',
        connected: this.connected,
        onBack: () => this.onBack()
      })

      GameSwipingSelector({
        selectedGame: this.selectedGame,
        unlockedIds: this.unlockedIds,
        onSelectedChange: (g: GameType) => this.onGameSelected(g)
      })

      LatestPanel({
        latestGameName: this.latestGameName,
        latestScore: this.latestScore
      })

      Scroll() {
        Column() {
          ScoreBoard({
            selectedGame: this.selectedGame,
            scores: this.scores
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
