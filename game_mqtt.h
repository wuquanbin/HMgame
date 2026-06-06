#ifndef GAME_MQTT_H
#define GAME_MQTT_H

#include <stdbool.h>
#include <stdint.h>

#include "game_port.h"

void game_mqtt_start(void);
void game_mqtt_publish_game_over(game_id_t game_id, uint16_t score);
bool game_mqtt_take_revive(game_id_t game_id);

#endif
