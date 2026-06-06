#ifndef GAME_COMMON_H
#define GAME_COMMON_H

#include <stdbool.h>
#include <stdint.h>

#include "cmsis_os2.h"

#ifndef CONFIG_GAME_ADKEY_ADC_CHANNEL
#define CONFIG_GAME_ADKEY_ADC_CHANNEL   ADC1_CHANNEL_6
#endif
#ifndef CONFIG_GAME_I2C_BUS_ID
#define CONFIG_GAME_I2C_BUS_ID          1
#endif
#ifndef CONFIG_GAME_I2C_SCL_PIN
#define CONFIG_GAME_I2C_SCL_PIN         22
#endif
#ifndef CONFIG_GAME_I2C_SDA_PIN
#define CONFIG_GAME_I2C_SDA_PIN         21
#endif
#ifndef CONFIG_GAME_MATRIX_I2C_ADDR
#define CONFIG_GAME_MATRIX_I2C_ADDR     112
#endif
#ifndef CONFIG_GAME_BUZZER_PIN
#define CONFIG_GAME_BUZZER_PIN          5
#endif
#ifndef CONFIG_GAME_BUZZER_ACTIVE_LEVEL
#define CONFIG_GAME_BUZZER_ACTIVE_LEVEL 1
#endif

#define GAME_BOARD_SIZE                 8
#define GAME_FRAME_BYTES                GAME_BOARD_SIZE

#define GAME_EVENT_KEY                  0x00000001U
#define GAME_EVENT_TICK                 0x00000002U
#define GAME_EVENT_REVIVE               0x00000004U
#define GAME_EVENT_MASK                 (GAME_EVENT_KEY | GAME_EVENT_TICK | GAME_EVENT_REVIVE)

typedef struct {
    uint8_t x;
    uint8_t y;
} game_point_t;

typedef enum {
    GAME_KEY_NONE = 0,
    GAME_KEY_FUNC,
    GAME_KEY_RIGHT,
    GAME_KEY_UP,
    GAME_KEY_LEFT,
    GAME_KEY_DOWN
} game_key_t;

void game_hw_init(void);
void game_display_set_frame(const uint8_t frame[GAME_FRAME_BYTES]);
void game_display_clear(void);
void game_display_show_score(uint16_t score);
void game_buzzer_beep(uint16_t duration_ms);
void game_buzzer_double(uint16_t duration_ms);
void game_delay_ms(uint32_t ms);
uint32_t game_ms_to_ticks(uint32_t ms);
uint32_t game_rand(void);
void game_seed(uint32_t seed);

game_key_t game_key_read(void);
const char *game_key_name(game_key_t key);

void game_set_controller_thread(osThreadId_t thread_id);
void game_wake_controller(uint32_t flags);

#endif
