// ============================================================
// Index — 应用入口
//   职责：
//   1. 页面路由（HomeMenu / SelectGamePage / AchievementPage / MatrixPage）
//   2. 全局状态管理（@State：选中游戏、分数、MQTT 状态等）
//   3. MQTT 连接与消息处理
//   4. 本地数据库读写
//   UI 组件全部拆分到 components/ 目录
// ============================================================

import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import {
  GameExitEvent,
  GameOverEvent,
  GameType,
  ScoreRecord,
  newlyUnlockedAchievementIds,
  gameLabelFromName,
  parseGameExitEvent,
  parseGameOverEvent
} from '../common/GameDataModel';
import { MqttClient } from '../common/MqttClient';
import { AdReviveDialog } from '../components/AdReviveDialog';
import {
  MenuPage,
  MQTT_HOST,
  MQTT_PORT,
  MQTT_USERNAME,
  MQTT_PASSWORD,
  MQTT_EVENT_TOPIC,
  MATRIX_SIZE,
  MATRIX_PATTERNS,
  MatrixPattern
} from '../common/AppConstants';
import { HomeMenu } from '../components/HomeMenu';
import { SelectGamePage } from '../components/SelectGamePage';
import { AchievementPage } from '../components/AchievementPage';
import { MatrixPage } from '../components/MatrixPage';

@Entry
@Component
struct Index {
  // ---------- 游戏状态 ----------
  @State selectedGame: GameType = GameType.SNAKE;
  @State scores: ScoreRecord[] = [];
  @State unlockedIds: number[] = [];

  // ---------- 最新对局 ----------
  @State latestGameName: string = '贪吃蛇';
  @State latestGameKey: string = 'snake';
  @State latestScore: number = 0;
  @State latestMessage: string = '';

  // ---------- 复活弹窗 ----------
  @State showReviveDialog: boolean = false;

  // ---------- 路由 ----------
  @State currentPage: MenuPage = MenuPage.HOME;

  // ---------- MQTT ----------
  @State connected: boolean = false;
  @State statusText: string = '未连接';

  // ---------- 矩阵灯 ----------
  @State matrixRows: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  @State matrixPatternName: string = '手动画板';
  @State matrixMessage: string = '点击点阵格子控制 ESP32 8x8 矩阵灯';

  private mqtt: MqttClient | null = null;
  private database: DatabaseHelper | null = null;

  // ======================================================
  // 生命周期
  // ======================================================
  aboutToAppear(): void {
    try {
      const context = this.getSafeContext();
      if (context !== null) {
        this.database = new DatabaseHelper(context);
        this.database.init()
          .then(async () => {
            await this.loadLocalData();
          })
          .catch((error: Error) => {
            this.statusText = '本地数据初始化失败';
            console.error('Database init failed: ' + JSON.stringify(error));
          });
      }
    } catch (error) {
      console.error('Index aboutToAppear failed: ' + JSON.stringify(error));
    }
    this.connectMqtt();
  }

  private getSafeContext(): common.Context | null {
    try {
      const ctx = getContext(this) as common.Context;
      if (ctx !== null && ctx !== undefined) {
        return ctx;
      }
    } catch (error) {
      console.error('getSafeContext failed: ' + JSON.stringify(error));
    }
    return null;
  }

  aboutToDisappear(): void {
    if (this.mqtt !== null) {
      this.mqtt.disconnect();
      this.mqtt = null;
    }
  }

  // ======================================================
  // 路由
  // ======================================================
  private navigateTo(page: MenuPage): void {
    this.currentPage = page;
  }

  private goHome(): void {
    this.currentPage = MenuPage.HOME;
  }

  // ======================================================
  // MQTT
  // ======================================================
  private connectMqtt(): void {
    if (this.mqtt !== null) {
      this.mqtt.disconnect();
      this.mqtt = null;
    }
    this.statusText = '正在连接 MQTT';
    this.connected = false;
    const client = new MqttClient({
      host: MQTT_HOST,
      port: MQTT_PORT,
      clientId: 'harmony_wuquanbin_' + Date.now().toString(),
      username: MQTT_USERNAME,
      password: MQTT_PASSWORD,
      subscribeTopic: MQTT_EVENT_TOPIC,
      keepAlive: 60
    });
    client.onMessage((_topic: string, payload: string) => {
      this.handleMqttPayload(_topic, payload);
    });
    client.onStatus((message: string) => {
      this.statusText = message;
    });
    this.mqtt = client;
    client.connect()
      .then(() => {
        this.connected = true;
        this.statusText = '已订阅 ' + MQTT_EVENT_TOPIC;
      })
      .catch((error: Error) => {
        this.connected = false;
        this.statusText = 'MQTT connect failed: ' + this.errorToText(error);
        console.error('MQTT connect failed: ' + JSON.stringify(error));
      });
  }

  private async handleMqttPayload(_topic: string, payload: string): Promise<void> {
    // 处理退出事件（不弹窗，只更新状态）
    const exitEvent: GameExitEvent | null = parseGameExitEvent(payload);
    if (exitEvent !== null) {
      this.latestGameKey = exitEvent.game;
      this.latestGameName = gameLabelFromName(exitEvent.game);
      this.latestScore = exitEvent.score;
      this.selectedGame = exitEvent.gameType;
      this.showReviveDialog = false;
      this.latestMessage = this.latestGameName + ' 已退出菜单，得分 ' + exitEvent.score.toString();
      return;
    }

    // 处理游戏结束事件（保存成绩 + 解锁成就 + 弹复活）
    const event: GameOverEvent | null = parseGameOverEvent(payload);
    if (event === null) return;

    this.latestGameKey = event.game;
    this.latestGameName = gameLabelFromName(event.game);
    this.latestScore = event.score;
    this.latestMessage = this.latestGameName + ' 游戏结束，得分 ' + event.score.toString();
    this.selectedGame = event.gameType;

    if (this.database !== null) {
      this.scores = await this.database.addScore(event.game, event.score);
      const newIds = newlyUnlockedAchievementIds(event.gameType, event.score, this.unlockedIds);
      if (newIds.length > 0) {
        this.unlockedIds = await this.database.unlockAchievements(newIds);
        this.latestMessage = this.latestMessage + '，解锁 ' + newIds.length.toString() + ' 个成就';
      }
    }
    this.showReviveDialog = true;
  }

  private async sendReviveCommand(): Promise<void> {
    const payload = '{"type":"revive","game":"' + this.latestGameKey + '"}';
    if (this.mqtt !== null && this.mqtt.isConnected()) {
      try {
        console.info('Game command publish revive: ' + payload);
        await this.mqtt.publish('wuquanbin/game/cmd', payload);
        this.showReviveDialog = false;
        this.latestMessage = '已发送复活指令：' + this.latestGameName;
      } catch (error) {
        this.latestMessage = '复活指令发送失败：' + this.errorToText(error);
        console.error('Game command revive failed: ' + this.errorToText(error));
      }
    } else {
      this.latestMessage = 'MQTT 未连接，复活指令未发送';
    }
  }

  private async sendExitCommand(): Promise<void> {
    const payload = '{"type":"exit","game":"' + this.latestGameKey + '"}';
    if (this.mqtt !== null && this.mqtt.isConnected()) {
      try {
        console.info('Game command publish exit: ' + payload);
        await this.mqtt.publish('wuquanbin/game/cmd', payload);
        this.showReviveDialog = false;
        this.latestMessage = '已发送退出指令：' + this.latestGameName;
      } catch (error) {
        this.latestMessage = '退出指令发送失败：' + this.errorToText(error);
        console.error('Game command exit failed: ' + this.errorToText(error));
      }
    } else {
      this.latestMessage = 'MQTT 未连接，退出指令未发送';
    }
  }

  private async loadLocalData(): Promise<void> {
    if (this.database === null) return;
    this.scores = await this.database.getScores();
    this.unlockedIds = await this.database.getUnlockedAchievementIds();
  }

  private errorToText(error: Object): string {
    try {
      return JSON.stringify(error);
    } catch (jsonError) {
      return String(error);
    }
  }

  // ======================================================
  // 矩阵灯操作
  // ======================================================
  private toggleMatrixCell(cellIndex: number): void {
    const row = Math.floor(cellIndex / MATRIX_SIZE);
    const col = cellIndex % MATRIX_SIZE;
    if (row < 0 || row >= MATRIX_SIZE) return;
    const mask = 1 << col;
    const nextRows = this.copyRows(this.matrixRows);
    if ((nextRows[row] & mask) !== 0) {
      nextRows[row] = nextRows[row] & (~mask);
    } else {
      nextRows[row] = nextRows[row] | mask;
    }
    this.matrixRows = nextRows;
    this.matrixPatternName = '手动画板';
    this.publishMatrixFrame('pixel', col, row, (nextRows[row] & mask) !== 0, 'manual');
  }

  private applyMatrixPattern(pattern: MatrixPattern): void {
    this.matrixRows = this.copyRows(pattern.rows);
    this.matrixPatternName = pattern.name;
    this.publishMatrixFrame('pattern', -1, -1, false, pattern.code);
  }

  private applyRandomMatrixPattern(): void {
    if (MATRIX_PATTERNS.length === 0) return;
    const index = Math.floor(Math.random() * MATRIX_PATTERNS.length);
    this.applyMatrixPattern(MATRIX_PATTERNS[index]);
  }

  private clearMatrix(): void {
    this.matrixRows = [0, 0, 0, 0, 0, 0, 0, 0];
    this.matrixPatternName = '清空';
    this.publishMatrixFrame('clear', -1, -1, false, 'clear');
  }

  private fillMatrix(): void {
    this.matrixRows = [255, 255, 255, 255, 255, 255, 255, 255];
    this.matrixPatternName = '全部点亮';
    this.publishMatrixFrame('fill', -1, -1, true, 'fill');
  }

  private async publishMatrixFrame(action: string, x: number = -1, y: number = -1, on: boolean = false, name: string = ''): Promise<void> {
    const payload = this.buildMatrixPayload(action, x, y, on, name);
    console.info('Matrix command publish: ' + payload);

    if (this.mqtt !== null && this.mqtt.isConnected()) {
      try {
        await this.mqtt.publish('wuquanbin/game/cmd', payload);
        this.matrixMessage = '已发送 ' + this.matrixActionText(action, x, y, on);
      } catch (error) {
        this.matrixMessage = '矩阵灯指令发送失败：' + this.errorToText(error);
      }
    } else {
      this.matrixMessage = 'MQTT 未连接，矩阵灯指令未发送';
    }
  }

  private buildMatrixPayload(action: string, x: number, y: number, on: boolean, name: string): string {
    return '{"type":"matrix","action":"' + action + '","name":"' + name + '","x":' + x.toString() +
      ',"y":' + y.toString() + ',"on":' + (on ? '1' : '0') + ',"rows":' + this.matrixRowsToJson() + '}';
  }

  private matrixRowsToJson(): string {
    let text = '[';
    for (let index = 0; index < MATRIX_SIZE; index++) {
      if (index > 0) text += ',';
      text += this.matrixRows[index].toString();
    }
    return text + ']';
  }

  private matrixActionText(action: string, x: number, y: number, on: boolean): string {
    if (action === 'pixel') return '点阵(' + x.toString() + ',' + y.toString() + ') ' + (on ? '点亮' : '熄灭');
    if (action === 'pattern') return '图案：' + this.matrixPatternName;
    if (action === 'clear') return '清空矩阵灯';
    if (action === 'fill') return '全部点亮';
    return '当前矩阵画面';
  }

  private copyRows(rows: number[]): number[] {
    const list: number[] = [];
    for (let index = 0; index < MATRIX_SIZE; index++) list.push(rows[index]);
    return list;
  }

  // ======================================================
  // 主渲染
  // ======================================================
  build() {
    Stack() {
      if (this.currentPage === MenuPage.HOME) {
        HomeMenu({
          onNavigate: (page: MenuPage) => this.navigateTo(page)
        })
      } else if (this.currentPage === MenuPage.SELECT_GAME) {
        SelectGamePage({
          connected: this.connected,
          selectedGame: this.selectedGame,
          scores: this.scores,
          unlockedIds: this.unlockedIds,
          latestGameName: this.latestGameName,
          latestScore: this.latestScore,
          onBack: () => this.goHome(),
          onGameSelected: (g: GameType) => { this.selectedGame = g; }
        })
      } else if (this.currentPage === MenuPage.ACHIEVEMENTS) {
        AchievementPage({
          connected: this.connected,
          selectedGame: this.selectedGame,
          unlockedIds: this.unlockedIds,
          onBack: () => this.goHome(),
          onGameSelected: (g: GameType) => { this.selectedGame = g; }
        })
      } else {
        MatrixPage({
          connected: this.connected,
          statusText: this.statusText,
          matrixPatternName: this.matrixPatternName,
          matrixMessage: this.matrixMessage,
          matrixRows: this.matrixRows,
          onBack: () => this.goHome(),
          onCellTap: (idx: number) => this.toggleMatrixCell(idx),
          onApplyPattern: (p: MatrixPattern) => this.applyMatrixPattern(p),
          onRandomPattern: () => this.applyRandomMatrixPattern(),
          onClear: () => this.clearMatrix(),
          onFill: () => this.fillMatrix(),
          onConnect: () => this.connectMqtt(),
          onSendFrame: () => this.publishMatrixFrame('frame')
        })
      }

      if (this.showReviveDialog) {
        AdReviveDialog({
          gameName: this.latestGameName,
          score: this.latestScore,
          visible: this.showReviveDialog,
          onRevive: () => { this.sendReviveCommand(); },
          onCancel: () => { this.sendExitCommand(); }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
