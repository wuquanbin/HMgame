#include "game_port.h"

#include <stdbool.h>
#include <string.h>

#define PLANE_PLAYER_Y             7
#define PLANE_BULLET_MAX           3
#define PLANE_ENEMY_MAX            4
#define PLANE_SCORE_PER_KILL       20

typedef struct {
    bool active;
    int8_t x;
    int8_t y;
} plane_actor_t;

static uint8_t g_player_x;
static plane_actor_t g_bullets[PLANE_BULLET_MAX];
static plane_actor_t g_enemies[PLANE_ENEMY_MAX];
static uint8_t g_spawn_timer;
static uint16_t g_score;
static bool g_fire_request;

static void plane_spawn_enemy(void)
{
    uint8_t index;

    for (index = 0; index < PLANE_ENEMY_MAX; index++) {
        if (!g_enemies[index].active) {
            g_enemies[index].active = true;
            g_enemies[index].x = (int8_t)(game_rand() % GAME_BOARD_SIZE);
            g_enemies[index].y = 0;
            g_spawn_timer = (uint8_t)(1U + (game_rand() % 3U));
            return;
        }
    }
    g_spawn_timer = 2;
}

static void plane_fire(void)
{
    uint8_t index;

    for (index = 0; index < PLANE_BULLET_MAX; index++) {
        if (!g_bullets[index].active) {
            g_bullets[index].active = true;
            g_bullets[index].x = (int8_t)g_player_x;
            g_bullets[index].y = PLANE_PLAYER_Y - 1;
            return;
        }
    }
}

static void plane_init(uint16_t score)
{
    (void)memset(g_bullets, 0, sizeof(g_bullets));
    (void)memset(g_enemies, 0, sizeof(g_enemies));
    g_player_x = 3;
    g_spawn_timer = 1;
    g_score = score;
    g_fire_request = false;
}

static void plane_handle_key(game_key_t key)
{
    switch (key) {
        case GAME_KEY_LEFT:
            if (g_player_x > 0U) {
                g_player_x--;
            }
            break;
        case GAME_KEY_RIGHT:
            if (g_player_x < (GAME_BOARD_SIZE - 1U)) {
                g_player_x++;
            }
            break;
        case GAME_KEY_FUNC:
        case GAME_KEY_UP:
            g_fire_request = true;
            break;
        default:
            return;
    }
    game_wake_controller(GAME_EVENT_KEY);
}

static bool plane_step(void)
{
    uint8_t b;
    uint8_t e;

    if (g_fire_request) {
        plane_fire();
    }
    g_fire_request = false;

    for (b = 0; b < PLANE_BULLET_MAX; b++) {
        if (g_bullets[b].active) {
            g_bullets[b].y--;
            if (g_bullets[b].y < 0) {
                g_bullets[b].active = false;
            }
        }
    }

    for (e = 0; e < PLANE_ENEMY_MAX; e++) {
        if (g_enemies[e].active) {
            g_enemies[e].y++;
            if (g_enemies[e].y >= (int8_t)GAME_BOARD_SIZE) {
                g_enemies[e].active = false;
            }
        }
    }

    if (g_spawn_timer > 0U) {
        g_spawn_timer--;
    }
    if (g_spawn_timer == 0U) {
        plane_spawn_enemy();
    }

    for (b = 0; b < PLANE_BULLET_MAX; b++) {
        if (!g_bullets[b].active) {
            continue;
        }
        for (e = 0; e < PLANE_ENEMY_MAX; e++) {
            if (g_enemies[e].active &&
                (g_bullets[b].x == g_enemies[e].x) &&
                (g_bullets[b].y == g_enemies[e].y)) {
                g_bullets[b].active = false;
                g_enemies[e].active = false;
                g_score = (uint16_t)(g_score + PLANE_SCORE_PER_KILL);
                game_buzzer_beep(55);
                break;
            }
        }
    }

    for (e = 0; e < PLANE_ENEMY_MAX; e++) {
        if (g_enemies[e].active &&
            (g_enemies[e].y >= (int8_t)(PLANE_PLAYER_Y - 1)) &&
            (g_enemies[e].x == (int8_t)g_player_x)) {
            return false;
        }
    }
    return true;
}

static void plane_render(uint8_t frame[GAME_FRAME_BYTES])
{
    uint8_t index;

    (void)memset(frame, 0, GAME_FRAME_BYTES);
    frame[PLANE_PLAYER_Y] |= (uint8_t)(1U << g_player_x);
    if (g_player_x > 0U) {
        frame[PLANE_PLAYER_Y] |= (uint8_t)(1U << (g_player_x - 1U));
    }
    if (g_player_x < (GAME_BOARD_SIZE - 1U)) {
        frame[PLANE_PLAYER_Y] |= (uint8_t)(1U << (g_player_x + 1U));
    }
    frame[PLANE_PLAYER_Y - 1U] |= (uint8_t)(1U << g_player_x);

    for (index = 0; index < PLANE_BULLET_MAX; index++) {
        if (g_bullets[index].active &&
            (g_bullets[index].y >= 0) && (g_bullets[index].y < (int8_t)GAME_BOARD_SIZE)) {
            frame[g_bullets[index].y] |= (uint8_t)(1U << (uint8_t)g_bullets[index].x);
        }
    }

    for (index = 0; index < PLANE_ENEMY_MAX; index++) {
        if (g_enemies[index].active &&
            (g_enemies[index].y >= 0) && (g_enemies[index].y < (int8_t)GAME_BOARD_SIZE)) {
            frame[g_enemies[index].y] |= (uint8_t)(1U << (uint8_t)g_enemies[index].x);
        }
    }
}

static uint16_t plane_score(void)
{
    return g_score;
}

static void plane_revive(void)
{
    (void)memset(g_bullets, 0, sizeof(g_bullets));
    (void)memset(g_enemies, 0, sizeof(g_enemies));
    g_player_x = 3;
    g_spawn_timer = 2;
}

const game_driver_t g_plane_driver = {
    .id = GAME_ID_PLANE,
    .name = "plane",
    .tick_ms = 280,
    .init = plane_init,
    .handle_key = plane_handle_key,
    .step = plane_step,
    .render = plane_render,
    .score = plane_score,
    .revive = plane_revive
};
