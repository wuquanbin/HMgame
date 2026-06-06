#include "game_port.h"

extern const game_driver_t g_snake_driver;
extern const game_driver_t g_tetris_driver;
extern const game_driver_t g_dino_driver;
extern const game_driver_t g_plane_driver;

static const game_driver_t *const g_drivers[GAME_ID_COUNT] = {
    &g_snake_driver,
    &g_tetris_driver,
    &g_dino_driver,
    &g_plane_driver
};

const game_driver_t *game_get_driver(game_id_t id)
{
    if (id >= GAME_ID_COUNT) {
        return g_drivers[GAME_ID_SNAKE];
    }
    return g_drivers[id];
}
