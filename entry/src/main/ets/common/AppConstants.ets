// ============================================================
// AppConstants — 全局常量、枚举、主题色、菜单配置
// ============================================================

// ---------- 主题色 ----------
export const THEME_BLUE = '#4775C8';           // 主色（深蓝）：主按钮、标题
export const THEME_BLUE_DARK = '#3A63A8';      // 主色按压态
export const THEME_BLUE_LIGHT = '#DCE6F7';     // 辅助浅蓝：次级按钮边框、淡底纹
export const THEME_BLUE_BG = '#F0F5FF';        // 顶部通栏浅蓝底
export const THEME_BG = '#F7F9FF';             // 页面背景
export const THEME_CARD = '#FFFFFF';           // 卡片底色
export const THEME_GREY_BG = '#F1F3F7';        // 底部辅助栏浅灰
export const THEME_TEXT_PRIMARY = '#173C82';   // 主文字
export const THEME_TEXT_SECOND = '#64748B';    // 说明小字
export const THEME_TEXT_MUTED = '#9CA3AF';     // 更次级说明
export const THEME_SUCCESS = '#15803D';
export const THEME_DANGER = '#DC2626';
export const THEME_ACCENT = '#EA580C';         // 分数等橙色强调

// ---------- MQTT 配置 ----------
export const MQTT_HOST = 'broker.emqx.io';
export const MQTT_PORT = 1883;
export const MQTT_USERNAME = 'wqb';
export const MQTT_PASSWORD = '123';
export const MQTT_EVENT_TOPIC = 'wuquanbin/game/event';
export const MQTT_CMD_TOPIC = 'wuquanbin/game/cmd';

// ---------- 页面分区 ----------
export enum MenuPage {
  HOME = 0,
  SELECT_GAME = 1,
  ACHIEVEMENTS = 2,
  OTHER_PLAY = 3
}

// ---------- 主菜单配置 ----------
export class MainMenuOption {
  page: MenuPage = MenuPage.SELECT_GAME;
  title: string = '';
  subtitle: string = '';      // 辅助说明小字
  isPrimary: boolean = false; // 是否为主按钮

  constructor(page: MenuPage, title: string, subtitle: string = '', isPrimary: boolean = false) {
    this.page = page;
    this.title = title;
    this.subtitle = subtitle;
    this.isPrimary = isPrimary;
  }
}

export const MAIN_MENU_OPTIONS: MainMenuOption[] = [
  new MainMenuOption(MenuPage.SELECT_GAME, '选择游戏', '挑选关卡、模式，开始游玩', true),
  new MainMenuOption(MenuPage.ACHIEVEMENTS, '游戏成就', '查看通关徽章、历史得分记录'),
  new MainMenuOption(MenuPage.OTHER_PLAY, '其他玩法', '休闲小游戏、矩阵灯控制')
];

// ---------- 矩阵灯常量 ----------
export const MATRIX_SIZE = 8;
export const MATRIX_GRID_TEMPLATE = '1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr';
export const MATRIX_INDEXES: number[] = [
  0, 1, 2, 3, 4, 5, 6, 7,
  8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23,
  24, 25, 26, 27, 28, 29, 30, 31,
  32, 33, 34, 35, 36, 37, 38, 39,
  40, 41, 42, 43, 44, 45, 46, 47,
  48, 49, 50, 51, 52, 53, 54, 55,
  56, 57, 58, 59, 60, 61, 62, 63
];

// ---------- 矩阵灯预设图案 ----------
export class MatrixPattern {
  name: string = '';
  code: string = '';
  rows: number[] = [];

  constructor(name: string, code: string, rows: number[]) {
    this.name = name;
    this.code = code;
    this.rows = rows;
  }
}

export const MATRIX_PATTERNS: MatrixPattern[] = [
  new MatrixPattern('爱心', 'heart', [0x00, 0x66, 0xFF, 0xFF, 0x7E, 0x3C, 0x18, 0x00]),
  new MatrixPattern('笑脸', 'smile', [0x00, 0x66, 0x66, 0x00, 0x81, 0x42, 0x3C, 0x00]),
  new MatrixPattern('云朵', 'cloud', [0x00, 0x18, 0x3C, 0x7E, 0xFF, 0xFE, 0x7C, 0x00]),
  new MatrixPattern('哭脸', 'cry', [0x00, 0x66, 0x66, 0x24, 0x00, 0x3C, 0x42, 0x81]),
  new MatrixPattern('星星', 'star', [0x18, 0x3C, 0x7E, 0xDB, 0x3C, 0x66, 0xC3, 0x00]),
  new MatrixPattern('箭头', 'arrow', [0x08, 0x0C, 0xFE, 0xFF, 0xFE, 0x0C, 0x08, 0x00])
];

// ---------- 版本信息 ----------
export const APP_VERSION = 'v1.0.0';
