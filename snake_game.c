#include "game_port.h"

#include <stdbool.h>
#include <string.h>

#define SNAKE_MAX_LEN            (GAME_BOARD_SIZE * GAME_BOARD_SIZE)
#define SNAKE_SCORE_PER_FOOD     10

typedef enum {
    SNAKE_DIR_UP = 0,
    SNAKE_DIR_RIGHT,
    SNAKE_DIR_DOWN,
    SNAKE_DIR_LEFT
} snake_dir_t;

static game_point_t g_snake[SNAKE_MAX_LEN];
static uint8_t g_snake_len;
static game_point_t g_food;
static snake_dir_t g_dir;
static snake_dir_t g_pending_dir;
static uint16_t g_score;

static bool snake_point_equal(game_point_t left, game_point_t right)
{
    return (left.x == right.x) && (left.y == right.y);
}

static bool snake_contains(game_point_t point, uint8_t length)
{
    uint8_t index;

    for (index = 0; index < length; index++) {
        if (snake_point_equal(g_snake[index], point)) {
            return true;
        }
    }
    return false;
}

static bool snake_reverse(snake_dir_t next, snake_dir_t current)
{
    return ((next == SNAKE_DIR_UP && current == SNAKE_DIR_DOWN) ||
        (next == SNAKE_DIR_DOWN && current == SNAKE_DIR_UP) ||
        (next == SNAKE_DIR_LEFT && current == SNAKE_DIR_RIGHT) ||
        (next == SNAKE_DIR_RIGHT && current == SNAKE_DIR_LEFT));
}

static void snake_place_food(void)
{
    uint8_t try_index;
    game_point_t point;

    for (try_index = 0; try_index < SNAKE_MAX_LEN; try_index++) {
        point.x = (uint8_t)(game_rand() % GAME_BOARD_SIZE);
        point.y = (uint8_t)(game_rand() % GAME_BOARD_SIZE);
        if (!snake_contains(point, g_snake_len)) {
            g_food = point;
            return;
        }
    }
}

static void snake_init(uint16_t score)
{
    (void)memset(g_snake, 0, sizeof(g_snake));
    g_snake_len = 3;
    g_snake[0].x = 4;
    g_snake[0].y = 4;
    g_snake[1].x = 3;
    g_snake[1].y = 4;
    g_snake[2].x = 2;
    g_snake[2].y = 4;
    g_dir = SNAKE_DIR_RIGHT;
    g_pending_dir = SNAKE_DIR_RIGHT;
    g_score = score;
    snake_place_food();
}

static void snake_handle_key(game_key_t key)
{
    snake_dir_t dir = g_pending_dir;

    switch (key) {
        case GAME_KEY_UP:
            dir = SNAKE_DIR_UP;
            break;
        case GAME_KEY_DOWN:
            dir = SNAKE_DIR_DOWN;
            break;
        case GAME_KEY_LEFT:
            dir = SNAKE_DIR_LEFT;
            break;
        case GAME_KEY_RIGHT:
            dir = SNAKE_DIR_RIGHT;
            break;
        default:
            return;
    }

    if (!snake_reverse(dir, g_dir)) {
        g_pending_dir = dir;
        game_wake_controller(GAME_EVENT_KEY);
    }
}

static bool snake_step(void)
{
    game_point_t next = g_snake[0];
    bool grow;
    uint8_t check_len;
    uint8_t move_index;

    if (!snake_reverse(g_pending_dir, g_dir)) {
        g_dir = g_pending_dir;
    }

    switch (g_dir) {
        case SNAKE_DIR_UP:
            if (next.y == 0U) {
                return false;
            }
            next.y--;
            break;
        case SNAKE_DIR_DOWN:
            if (next.y >= (GAME_BOARD_SIZE - 1U)) {
                return false;
            }
            next.y++;
            break;
        case SNAKE_DIR_LEFT:
            if (next.x == 0U) {
                return false;
            }
            next.x--;
            break;
        case SNAKE_DIR_RIGHT:
        default:
            if (next.x >= (GAME_BOARD_SIZE - 1U)) {
                return false;
            }
            next.x++;
            break;
    }

    grow = snake_point_equal(next, g_food);
    check_len = grow ? g_snake_len : (uint8_t)(g_snake_len - 1U);
    if (snake_contains(next, check_len)) {
        return false;
    }

    if (grow && (g_snake_len < SNAKE_MAX_LEN)) {
        g_snake_len++;
    }

    for (move_index = (uint8_t)(g_snake_len - 1U); move_index > 0U; move_index--) {
        g_snake[move_index] = g_snake[move_index - 1U];
    }
    g_snake[0] = next;

    if (grow) {
        g_score = (uint16_t)(g_score + SNAKE_SCORE_PER_FOOD);
        game_buzzer_beep(60);
        if (g_snake_len >= SNAKE_MAX_LEN) {
            return false;
        }
        snake_place_food();
    }
    return true;
}

static void snake_render(uint8_t frame[GAME_FRAME_BYTES])
{
    uint8_t index;

    (void)memset(frame, 0, GAME_FRAME_BYTES);
    frame[g_food.y] |= (uint8_t)(1U << g_food.x);
    for (index = 0; index < g_snake_len; index++) {
        frame[g_snake[index].y] |= (uint8_t)(1U << g_snake[index].x);
    }
}

static uint16_t snake_score(void)
{
    return g_score;
}

static void snake_revive(void)
{
    snake_init(g_score);
}

const game_driver_t g_snake_driver = {
    .id = GAME_ID_SNAKE,
    .name = "snake",
    .tick_ms = 450,
    .init = snake_init,
    .handle_key = snake_handle_key,
    .step = snake_step,
    .render = snake_render,
    .score = snake_score,
    .revive = snake_revive
};
