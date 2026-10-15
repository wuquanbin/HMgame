export enum GameType {
  SNAKE = 0,
  TETRIS = 1,
  DINO = 2,
  PLANE = 3
}

export class GameOption {
  id: GameType = GameType.SNAKE;
  name: string = '';
  label: string = '';

  constructor(id: GameType, name: string, label: string) {
    this.id = id;
    this.name = name;
    this.label = label;
  }
}

export class ScoreRecord {
  id: number = 0;
  game: string = '';
  score: number = 0;
  timestamp: number = 0;

  constructor(id: number, game: string, score: number, timestamp: number) {
    this.id = id;
    this.game = game;
    this.score = score;
    this.timestamp = timestamp;
  }
}

export class Achievement {
  id: number = 0;
  gameType: GameType = GameType.SNAKE;
  name: string = '';
  description: string = '';
  threshold: number = 0;

  constructor(id: number, gameType: GameType, name: string, description: string, threshold: number) {
    this.id = id;
    this.gameType = gameType;
    this.name = name;
    this.description = description;
    this.threshold = threshold;
  }
}

export class GameOverEvent {
  game: string = '';
  gameType: GameType = GameType.SNAKE;
  score: number = 0;

  constructor(game: string, gameType: GameType, score: number) {
    this.game = game;
    this.gameType = gameType;
    this.score = score;
  }
}

export class GameExitEvent {
  game: string = '';
  gameType: GameType = GameType.SNAKE;
  score: number = 0;

  constructor(game: string, gameType: GameType, score: number) {
    this.game = game;
    this.gameType = gameType;
    this.score = score;
  }
}

interface RawGameEvent {
  type?: string;
  game?: string;
  score?: number;
}

export const GAME_OPTIONS: GameOption[] = [
  new GameOption(GameType.SNAKE, 'snake', '贪吃蛇'),
  new GameOption(GameType.TETRIS, 'tetris', '俄罗斯方块'),
  new GameOption(GameType.DINO, 'dino', '小恐龙 Dino'),
  new GameOption(GameType.PLANE, 'plane', '飞机大战')
];

export function getGameBgImageForType(gameId: GameType): string {
  switch (gameId) {
    case GameType.SNAKE:
      return 'snake';
    case GameType.TETRIS:
      return 'tetris';
    case GameType.DINO:
      return 'dino';
    case GameType.PLANE:
      return 'plane';
    default:
      return 'snake';
  }
}

export const ACHIEVEMENTS: Achievement[] = [
  new Achievement(1, GameType.SNAKE, '第一颗果实', '贪吃蛇达到 50 分', 50),
  new Achievement(2, GameType.SNAKE, '灵活转向', '贪吃蛇达到 100 分', 100),
  new Achievement(3, GameType.SNAKE, '蛇王挑战', '贪吃蛇达到 120 分', 120),
  new Achievement(4, GameType.TETRIS, '落块入门', '俄罗斯方块达到 100 分', 100),
  new Achievement(5, GameType.TETRIS, '消行节奏', '俄罗斯方块达到 300 分', 300),
  new Achievement(6, GameType.TETRIS, '八格大师', '俄罗斯方块达到 600 分', 600),
  new Achievement(7, GameType.DINO, '起跳成功', '小恐龙达到 40 分', 40),
  new Achievement(8, GameType.DINO, '荒野长跑', '小恐龙达到 100 分', 100),
  new Achievement(9, GameType.DINO, '极限反应', '小恐龙达到 180 分', 180),
  new Achievement(10, GameType.PLANE, '命中目标', '飞机大战达到 60 分', 60),
  new Achievement(11, GameType.PLANE, '王牌飞行', '飞机大战达到 160 分', 160),
  new Achievement(12, GameType.PLANE, '空域守护者', '飞机大战达到 300 分', 300)
];

export function gameTypeFromName(name: string): GameType {
  for (let index = 0; index < GAME_OPTIONS.length; index++) {
    if (GAME_OPTIONS[index].name === name) {
      return GAME_OPTIONS[index].id;
    }
  }
  return GameType.SNAKE;
}

export function gameNameFromType(type: GameType): string {
  for (let index = 0; index < GAME_OPTIONS.length; index++) {
    if (GAME_OPTIONS[index].id === type) {
      return GAME_OPTIONS[index].name;
    }
  }
  return 'snake';
}

export function gameLabelFromName(name: string): string {
  const type = gameTypeFromName(name);
  for (let index = 0; index < GAME_OPTIONS.length; index++) {
    if (GAME_OPTIONS[index].id === type) {
      return GAME_OPTIONS[index].label;
    }
  }
  return '贪吃蛇';
}

export function achievementsForGame(type: GameType): Achievement[] {
  const list: Achievement[] = [];
  for (let index = 0; index < ACHIEVEMENTS.length; index++) {
    if (ACHIEVEMENTS[index].gameType === type) {
      list.push(ACHIEVEMENTS[index]);
    }
  }
  return list;
}

export function achievementUnlocked(unlockedIds: number[], id: number): boolean {
  for (let index = 0; index < unlockedIds.length; index++) {
    if (unlockedIds[index] === id) {
      return true;
    }
  }
  return false;
}

export function newlyUnlockedAchievementIds(gameType: GameType, score: number, unlockedIds: number[]): number[] {
  const list: number[] = [];
  for (let index = 0; index < ACHIEVEMENTS.length; index++) {
    const achievement = ACHIEVEMENTS[index];
    if (achievement.gameType === gameType &&
      score >= achievement.threshold &&
      !achievementUnlocked(unlockedIds, achievement.id)) {
      list.push(achievement.id);
    }
  }
  return list;
}

export function parseGameOverEvent(payload: string): GameOverEvent | null {
  try {
    const data = JSON.parse(payload) as RawGameEvent;
    if (data.type !== 'game_over') {
      return null;
    }
    if (typeof data.game !== 'string' || typeof data.score !== 'number') {
      return null;
    }
    return new GameOverEvent(data.game, gameTypeFromName(data.game), data.score);
  } catch (error) {
    console.error('GameDataModel parse failed: ' + JSON.stringify(error));
  }
  return null;
}

export function parseGameExitEvent(payload: string): GameExitEvent | null {
  try {
    const data = JSON.parse(payload) as RawGameEvent;
    if (data.type !== 'game_exit') {
      return null;
    }
    if (typeof data.game !== 'string' || typeof data.score !== 'number') {
      return null;
    }
    return new GameExitEvent(data.game, gameTypeFromName(data.game), data.score);
  } catch (error) {
    console.error('GameDataModel parse exit failed: ' + JSON.stringify(error));
  }
  return null;
}

export function formatTime(timestamp: number): string {
  const date = new Date(timestamp);
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  const hour = date.getHours().toString().padStart(2, '0');
  const minute = date.getMinutes().toString().padStart(2, '0');
  return month + '-' + day + ' ' + hour + ':' + minute;
}
