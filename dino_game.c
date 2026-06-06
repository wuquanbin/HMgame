#include "game_port.h"

#include <stdbool.h>
#include <string.h>

#define DINO_X                  1
#define DINO_GROUND_Y           6
#define DINO_SCORE_STEP         2
#define DINO_JUMP_FRAMES        5

static uint8_t g_obstacles[GAME_BOARD_SIZE];
static uint8_t g_jump_timer;
static uint8_t g_spawn_timer;
static uint16_t g_score;
static bool g_force_jump;

static uint8_t dino_y(void)
{
    if (g_jump_timer == 0U) {
        return DINO_GROUND_Y;
    }
    if (g_jump_timer >= 3U) {
        return 3U;
    }
    return 4U;
}

static void dino_spawn_obstacle(void)
{
    if ((game_rand() & 0x03U) != 0U) {
        g_obstacles[GAME_BOARD_SIZE - 1U] = (uint8_t)(1U << DINO_GROUND_Y);
    } else {
        g_obstacles[GAME_BOARD_SIZE - 1U] =
            (uint8_t)((1U << DINO_GROUND_Y) | (1U << (DINO_GROUND_Y - 1U)));
    }
    g_spawn_timer = (uint8_t)(2U + (game_rand() % 3U));
}

static void dino_init(uint16_t score)
{
    (void)memset(g_obstacles, 0, sizeof(g_obstacles));
    g_jump_timer = 0;
    g_spawn_timer = 2;
    g_score = score;
    g_force_jump = false;
}

static void dino_handle_key(game_key_t key)
{
    if ((key == GAME_KEY_UP) || (key == GAME_KEY_FUNC)) {
        g_force_jump = true;
        game_wake_controller(GAME_EVENT_KEY);
    }
}

static bool dino_step(void)
{
    uint8_t x;
    uint8_t py;

    if (g_force_jump && (g_jump_timer == 0U)) {
        g_jump_timer = DINO_JUMP_FRAMES;
    }
    g_force_jump = false;

    if (g_jump_timer > 0U) {
        g_jump_timer--;
    }

    for (x = 0; x < GAME_BOARD_SIZE - 1U; x++) {
        g_obstacles[x] = g_obstacles[x + 1U];
    }
    g_obstacles[GAME_BOARD_SIZE - 1U] = 0;

    if (g_spawn_timer > 0U) {
        g_spawn_timer--;
    }
    if (g_spawn_timer == 0U) {
        dino_spawn_obstacle();
    }

    py = dino_y();
    if ((g_obstacles[DINO_X] & (uint8_t)(1U << py)) != 0U) {
        return false;
    }

    g_score = (uint16_t)(g_score + DINO_SCORE_STEP);
    return true;
}

static void dino_render(uint8_t frame[GAME_FRAME_BYTES])
{
    uint8_t x;

    (void)memset(frame, 0, GAME_FRAME_BYTES);
    frame[7] = 0xFFU;
    for (x = 0; x < GAME_BOARD_SIZE; x++) {
        frame[x] = 0;
    }
    frame[7] = 0xFFU;
    for (x = 0; x < GAME_BOARD_SIZE; x++) {
        uint8_t bits = g_obstacles[x];
        uint8_t y;
        for (y = 0; y < GAME_BOARD_SIZE; y++) {
            if ((bits & (uint8_t)(1U << y)) != 0U) {
                frame[y] |= (uint8_t)(1U << x);
            }
        }
    }
    frame[dino_y()] |= (uint8_t)(1U << DINO_X);
    frame[(uint8_t)(dino_y() + 1U)] |= (uint8_t)(1U << DINO_X);
}

static uint16_t dino_score(void)
{
    return g_score;
}

static void dino_revive(void)
{
    (void)memset(g_obstacles, 0, sizeof(g_obstacles));
    g_jump_timer = DINO_JUMP_FRAMES;
    g_spawn_timer = 3;
}

const game_driver_t g_dino_driver = {
    .id = GAME_ID_DINO,
    .name = "dino",
    .tick_ms = 300,
    .init = dino_init,
    .handle_key = dino_handle_key,
    .step = dino_step,
    .render = dino_render,
    .score = dino_score,
    .revive = dino_revive
};
