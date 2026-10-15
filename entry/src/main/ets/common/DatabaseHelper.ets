import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ScoreRecord } from './GameDataModel';

const STORE_NAME = 'Esp32GameConsoleStore';
const KEY_SCORES = 'scores';
const KEY_UNLOCKED = 'unlockedAchievements';

export class DatabaseHelper {
  private context: common.Context;
  private store: preferences.Preferences | null = null;

  constructor(context: common.Context) {
    this.context = context;
  }

  async init(): Promise<void> {
    try {
      this.store = await preferences.getPreferences(this.context, STORE_NAME);
    } catch (error) {
      this.store = null;
      console.error('DatabaseHelper init failed: ' + JSON.stringify(error));
    }
  }

  async addScore(game: string, score: number): Promise<ScoreRecord[]> {
    const rows = await this.getScores();
    rows.push(new ScoreRecord(Date.now(), game, score, Date.now()));
    await this.saveScores(rows);
    return rows;
  }

  async getScores(): Promise<ScoreRecord[]> {
    if (this.store === null) {
      return [];
    }
    try {
      const raw = await this.store.get(KEY_SCORES, '[]') as string;
      return this.parseScores(raw);
    } catch (error) {
      console.error('DatabaseHelper getScores failed: ' + JSON.stringify(error));
      return [];
    }
  }

  async saveScores(rows: ScoreRecord[]): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      await this.store.put(KEY_SCORES, JSON.stringify(rows));
      await this.store.flush();
    } catch (error) {
      console.error('DatabaseHelper saveScores failed: ' + JSON.stringify(error));
    }
  }

  async getUnlockedAchievementIds(): Promise<number[]> {
    if (this.store === null) {
      return [];
    }
    try {
      const raw = await this.store.get(KEY_UNLOCKED, '[]') as string;
      return this.parseNumberList(raw);
    } catch (error) {
      console.error('DatabaseHelper getUnlocked failed: ' + JSON.stringify(error));
      return [];
    }
  }

  async saveUnlockedAchievementIds(ids: number[]): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      await this.store.put(KEY_UNLOCKED, JSON.stringify(ids));
      await this.store.flush();
    } catch (error) {
      console.error('DatabaseHelper saveUnlocked failed: ' + JSON.stringify(error));
    }
  }

  async unlockAchievements(ids: number[]): Promise<number[]> {
    const current = await this.getUnlockedAchievementIds();
    for (let index = 0; index < ids.length; index++) {
      if (!this.containsNumber(current, ids[index])) {
        current.push(ids[index]);
      }
    }
    await this.saveUnlockedAchievementIds(current);
    return current;
  }

  private parseScores(raw: string): ScoreRecord[] {
    const rows: ScoreRecord[] = [];
    try {
      const data = JSON.parse(raw) as ScoreRecord[];
      if (!Array.isArray(data)) {
        return rows;
      }
      for (let index = 0; index < data.length; index++) {
        const item = data[index];
        if (typeof item.game === 'string' &&
          typeof item.score === 'number' &&
          typeof item.timestamp === 'number') {
          rows.push(new ScoreRecord(item.id, item.game, item.score, item.timestamp));
        }
      }
    } catch (error) {
      console.error('DatabaseHelper parseScores failed: ' + JSON.stringify(error));
    }
    return rows;
  }

  private parseNumberList(raw: string): number[] {
    const rows: number[] = [];
    try {
      const data = JSON.parse(raw) as number[];
      if (!Array.isArray(data)) {
        return rows;
      }
      for (let index = 0; index < data.length; index++) {
        if (typeof data[index] === 'number') {
          rows.push(data[index]);
        }
      }
    } catch (error) {
      console.error('DatabaseHelper parseNumberList failed: ' + JSON.stringify(error));
    }
    return rows;
  }

  private containsNumber(list: number[], value: number): boolean {
    for (let index = 0; index < list.length; index++) {
      if (list[index] === value) {
        return true;
      }
    }
    return false;
  }
}
