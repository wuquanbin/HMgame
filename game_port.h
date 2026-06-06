#ifndef GAME_PORT_H
#define GAME_PORT_H

#include <stdint.h>

#include "game_common.h"

typedef enum {
    GAME_ID_SNAKE = 0,
    GAME_ID_TETRIS,
    GAME_ID_DINO,
    GAME_ID_PLANE,
    GAME_ID_COUNT
} game_id_t;

typedef struct {
    game_id_t id;
    const char *name;
    uint16_t tick_ms;
    void (*init)(uint16_t score);
    void (*handle_key)(game_key_t key);
    bool (*step)(void);
    void (*render)(uint8_t frame[GAME_FRAME_BYTES]);
    uint16_t (*score)(void);
    void (*revive)(void);
} game_driver_t;

const game_driver_t *game_get_driver(game_id_t id);

#endif
