#include "game_port.h"

#include <stdbool.h>
#include <string.h>

#define TETRIS_SCORE_PER_ROW      100
#define TETRIS_SOFT_DROP_SCORE    1

typedef struct {
    int8_t x;
    int8_t y;
} tetris_cell_t;

typedef struct {
    const tetris_cell_t cells[4][4];
    uint8_t rotations;
} tetris_piece_t;

static const tetris_piece_t g_pieces[] = {
    {{{{0, 1}, {1, 1}, {2, 1}, {3, 1}},
      {{2, 0}, {2, 1}, {2, 2}, {2, 3}},
      {{0, 2}, {1, 2}, {2, 2}, {3, 2}},
      {{1, 0}, {1, 1}, {1, 2}, {1, 3}}}, 4},
    {{{{0, 0}, {1, 0}, {0, 1}, {1, 1}},
      {{0, 0}, {1, 0}, {0, 1}, {1, 1}},
      {{0, 0}, {1, 0}, {0, 1}, {1, 1}},
      {{0, 0}, {1, 0}, {0, 1}, {1, 1}}}, 1},
    {{{{1, 0}, {0, 1}, {1, 1}, {2, 1}},
      {{1, 0}, {1, 1}, {2, 1}, {1, 2}},
      {{0, 1}, {1, 1}, {2, 1}, {1, 2}},
      {{1, 0}, {0, 1}, {1, 1}, {1, 2}}}, 4},
    {{{{0, 0}, {1, 0}, {1, 1}, {2, 1}},
      {{2, 0}, {1, 1}, {2, 1}, {1, 2}},
      {{0, 1}, {1, 1}, {1, 2}, {2, 2}},
      {{1, 0}, {0, 1}, {1, 1}, {0, 2}}}, 4}
};

static uint8_t g_board[GAME_BOARD_SIZE];
static uint8_t g_piece_index;
static uint8_t g_rotation;
static int8_t g_piece_x;
static int8_t g_piece_y;
static uint16_t g_score;
static bool g_force_drop;

static bool tetris_cell_blocked(int8_t x, int8_t y)
{
    if ((x < 0) || (x >= (int8_t)GAME_BOARD_SIZE) || (y >= (int8_t)GAME_BOARD_SIZE)) {
        return true;
    }
    if (y < 0) {
        return false;
    }
    return (g_board[y] & (uint8_t)(1U << (uint8_t)x)) != 0U;
}

static bool tetris_fits(int8_t x, int8_t y, uint8_t rotation)
{
    const tetris_piece_t *piece = &g_pieces[g_piece_index];
    uint8_t index;

    rotation %= piece->rotations;
    for (index = 0; index < 4U; index++) {
        int8_t px = (int8_t)(x + piece->cells[rotation][index].x);
        int8_t py = (int8_t)(y + piece->cells[rotation][index].y);
        if (tetris_cell_blocked(px, py)) {
            return false;
        }
    }
    return true;
}

static bool tetris_spawn_piece(void)
{
    g_piece_index = (uint8_t)(game_rand() % (sizeof(g_pieces) / sizeof(g_pieces[0])));
    g_rotation = 0;
    g_piece_x = 2;
    g_piece_y = -1;
    g_force_drop = false;
    return tetris_fits(g_piece_x, g_piece_y, g_rotation);
}

static void tetris_merge_piece(void)
{
    const tetris_piece_t *piece = &g_pieces[g_piece_index];
    uint8_t index;

    for (index = 0; index < 4U; index++) {
        int8_t px = (int8_t)(g_piece_x + piece->cells[g_rotation][index].x);
        int8_t py = (int8_t)(g_piece_y + piece->cells[g_rotation][index].y);
        if ((py >= 0) && (py < (int8_t)GAME_BOARD_SIZE) &&
            (px >= 0) && (px < (int8_t)GAME_BOARD_SIZE)) {
            g_board[py] |= (uint8_t)(1U << (uint8_t)px);
        }
    }
}

static void tetris_clear_rows(void)
{
    int8_t y;
    uint8_t write_y = GAME_BOARD_SIZE - 1U;
    uint8_t new_board[GAME_BOARD_SIZE] = {0};

    for (y = (int8_t)GAME_BOARD_SIZE - 1; y >= 0; y--) {
        if (g_board[y] == 0xFFU) {
            g_score = (uint16_t)(g_score + TETRIS_SCORE_PER_ROW);
            continue;
        }
        new_board[write_y] = g_board[y];
        if (write_y > 0U) {
            write_y--;
        }
    }
    (void)memcpy(g_board, new_board, sizeof(g_board));
}

static void tetris_init(uint16_t score)
{
    (void)memset(g_board, 0, sizeof(g_board));
    g_score = score;
    (void)tetris_spawn_piece();
}

static void tetris_handle_key(game_key_t key)
{
    uint8_t next_rotation;

    switch (key) {
        case GAME_KEY_LEFT:
            if (tetris_fits((int8_t)(g_piece_x - 1), g_piece_y, g_rotation)) {
                g_piece_x--;
            }
            break;
        case GAME_KEY_RIGHT:
            if (tetris_fits((int8_t)(g_piece_x + 1), g_piece_y, g_rotation)) {
                g_piece_x++;
            }
            break;
        case GAME_KEY_UP:
        case GAME_KEY_FUNC:
            next_rotation = (uint8_t)((g_rotation + 1U) % g_pieces[g_piece_index].rotations);
            if (tetris_fits(g_piece_x, g_piece_y, next_rotation)) {
                g_rotation = next_rotation;
            }
            break;
        case GAME_KEY_DOWN:
            g_force_drop = true;
            break;
        default:
            return;
    }
    game_wake_controller(GAME_EVENT_KEY);
}

static bool tetris_step(void)
{
    uint8_t drops = g_force_drop ? 2U : 1U;
    uint8_t index;

    g_force_drop = false;
    for (index = 0; index < drops; index++) {
        if (tetris_fits(g_piece_x, (int8_t)(g_piece_y + 1), g_rotation)) {
            g_piece_y++;
            if (drops > 1U) {
                g_score = (uint16_t)(g_score + TETRIS_SOFT_DROP_SCORE);
            }
        } else {
            tetris_merge_piece();
            tetris_clear_rows();
            return tetris_spawn_piece();
        }
    }
    return true;
}

static void tetris_render(uint8_t frame[GAME_FRAME_BYTES])
{
    const tetris_piece_t *piece = &g_pieces[g_piece_index];
    uint8_t index;

    (void)memcpy(frame, g_board, GAME_FRAME_BYTES);
    for (index = 0; index < 4U; index++) {
        int8_t px = (int8_t)(g_piece_x + piece->cells[g_rotation][index].x);
        int8_t py = (int8_t)(g_piece_y + piece->cells[g_rotation][index].y);
        if ((py >= 0) && (py < (int8_t)GAME_BOARD_SIZE) &&
            (px >= 0) && (px < (int8_t)GAME_BOARD_SIZE)) {
            frame[py] |= (uint8_t)(1U << (uint8_t)px);
        }
    }
}

static uint16_t tetris_score(void)
{
    return g_score;
}

static void tetris_revive(void)
{
    uint8_t y;

    for (y = 0; y < 2U; y++) {
        g_board[y] = 0;
    }
    (void)tetris_spawn_piece();
}

const game_driver_t g_tetris_driver = {
    .id = GAME_ID_TETRIS,
    .name = "tetris",
    .tick_ms = 650,
    .init = tetris_init,
    .handle_key = tetris_handle_key,
    .step = tetris_step,
    .render = tetris_render,
    .score = tetris_score,
    .revive = tetris_revive
};
