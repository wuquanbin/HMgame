/**
 * Description: Snake game for ESP32 Plus modules:
 *              I2C 8x8 dot matrix, TM1650 4-digit tube, active buzzer.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "cmsis_os2.h"
#include "driver/adc.h"
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_err.h"
#include "ohos_run.h"

#ifndef CONFIG_SNAKE_ADKEY_ADC_CHANNEL
#define CONFIG_SNAKE_ADKEY_ADC_CHANNEL   ADC1_CHANNEL_6
#endif
#ifndef CONFIG_SNAKE_I2C_BUS_ID
#define CONFIG_SNAKE_I2C_BUS_ID          1
#endif
#ifndef CONFIG_SNAKE_I2C_SCL_PIN
#define CONFIG_SNAKE_I2C_SCL_PIN         22
#endif
#ifndef CONFIG_SNAKE_I2C_SDA_PIN
#define CONFIG_SNAKE_I2C_SDA_PIN         21
#endif
#ifndef CONFIG_SNAKE_MATRIX_I2C_ADDR
#define CONFIG_SNAKE_MATRIX_I2C_ADDR     112
#endif
#ifndef CONFIG_SNAKE_BUZZER_PIN
#define CONFIG_SNAKE_BUZZER_PIN          5
#endif
#ifndef CONFIG_SNAKE_BUZZER_ACTIVE_LEVEL
#define CONFIG_SNAKE_BUZZER_ACTIVE_LEVEL 1
#endif
#ifndef CONFIG_SNAKE_TICK_MS
#define CONFIG_SNAKE_TICK_MS             5000
#endif

#define SNAKE_BOARD_SIZE                 8
#define SNAKE_MAX_LEN                    (SNAKE_BOARD_SIZE * SNAKE_BOARD_SIZE)
#define SNAKE_SCORE_PER_FOOD             10

#define SNAKE_DISPLAY_STACK_SIZE         0x1000
#define SNAKE_GAME_STACK_SIZE            0x1000
#define SNAKE_ADKEY_STACK_SIZE           0x1000
#define SNAKE_TASK_PRIO                  (osPriority_t)(17)

#define SNAKE_ADKEY_SAMPLE_COUNT         8
#define SNAKE_ADKEY_READ_PERIOD_MS       30
#define SNAKE_ADKEY_DEBOUNCE_MS          90
#define SNAKE_ADKEY_NO_KEY_MAX           100
#define SNAKE_ADKEY_SW5_MAX              300
#define SNAKE_ADKEY_SW4_MAX              500
#define SNAKE_ADKEY_SW3_MAX              700
#define SNAKE_ADKEY_SW2_MAX              900

#define SNAKE_I2C_SPEED                  100000
#define SNAKE_I2C_TIMEOUT_MS             100
#define SNAKE_DISPLAY_REFRESH_MS         40

#define SNAKE_EVENT_DIRECTION            0x00000001U
#define SNAKE_EVENT_PAUSE                0x00000002U
#define SNAKE_EVENT_RESTART              0x00000004U
#define SNAKE_EVENT_MASK                 (SNAKE_EVENT_DIRECTION | SNAKE_EVENT_PAUSE | SNAKE_EVENT_RESTART)

#define HT16K33_CMD_SYSTEM_SETUP         0x21
#define HT16K33_CMD_DISPLAY_ON           0x81
#define HT16K33_CMD_BRIGHTNESS           0xE8

#define TM1650_CMD_I2C_ADDR              0x24
#define TM1650_DISPLAY_ON_BRIGHTNESS     0x09
#define TM1650_DIGIT_COUNT               4

#define SNAKE_BEEP_SHORT_MS              80
#define SNAKE_BEEP_LONG_MS               180
#define SNAKE_BEEP_GAP_MS                40

typedef struct {
    uint8_t x;
    uint8_t y;
} snake_point_t;

typedef enum {
    SNAKE_DIR_UP = 0,
    SNAKE_DIR_RIGHT,
    SNAKE_DIR_DOWN,
    SNAKE_DIR_LEFT
} snake_dir_t;

typedef enum {
    SNAKE_ADKEY_NONE = 0,
    SNAKE_ADKEY_SW1,
    SNAKE_ADKEY_SW2,
    SNAKE_ADKEY_SW3,
    SNAKE_ADKEY_SW4,
    SNAKE_ADKEY_SW5
} snake_adkey_t;

static const uint8_t g_tm1650_digits[10] = {
    0x3F, 0x06, 0x5B, 0x4F, 0x66,
    0x6D, 0x7D, 0x07, 0x7F, 0x6F
};

static const uint8_t g_tm1650_digit_i2c_addr[TM1650_DIGIT_COUNT] = {
    0x34, 0x35, 0x36, 0x37
};

static snake_point_t g_snake[SNAKE_MAX_LEN];
static uint8_t g_snake_len;
static snake_point_t g_food;
static volatile snake_dir_t g_dir;
static volatile snake_dir_t g_pending_dir;
static volatile bool g_game_over;
static volatile bool g_paused;
static volatile bool g_restart_request;
static volatile uint16_t g_score;
static volatile uint8_t g_led_frame[SNAKE_BOARD_SIZE];
static uint32_t g_rng = 0x12345678;
static osThreadId_t g_game_thread_id;

static uint32_t snake_ms_to_ticks(uint32_t ms)
{
    uint32_t tick_freq = osKernelGetTickFreq();
    uint64_t ticks;

    if (tick_freq == 0U) {
        return (ms == 0U) ? 1U : ms;
    }

    ticks = (((uint64_t)ms * tick_freq) + 999U) / 1000U;
    if (ticks == 0U) {
        ticks = 1U;
    }
    if (ticks > UINT32_MAX) {
        ticks = UINT32_MAX;
    }
    return (uint32_t)ticks;
}

static void snake_delay_ms(uint32_t ms)
{
    osDelay(snake_ms_to_ticks(ms));
}

static void snake_wake_game(uint32_t flags)
{
    osThreadId_t game_thread_id = g_game_thread_id;

    if (game_thread_id != NULL) {
        (void)osThreadFlagsSet(game_thread_id, flags);
    }
}

static void snake_gpio_write(uint8_t pin, bool high)
{
    (void)gpio_set_level((gpio_num_t)pin, high ? 1 : 0);
}

static void snake_gpio_output(uint8_t pin, bool high)
{
    gpio_config_t gpio_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = 1ULL << pin,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .pull_up_en = GPIO_PULLUP_DISABLE
    };

    (void)gpio_config(&gpio_conf);
    snake_gpio_write(pin, high);
}

static esp_err_t snake_i2c_write_to_addr(uint8_t i2c_addr, const uint8_t *buffer, size_t length)
{
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    esp_err_t ret;

    if (cmd == NULL) {
        return ESP_FAIL;
    }

    (void)i2c_master_start(cmd);
    (void)i2c_master_write_byte(cmd, (uint8_t)((i2c_addr << 1U) | I2C_MASTER_WRITE), true);
    if ((buffer != NULL) && (length > 0U)) {
        (void)i2c_master_write(cmd, (uint8_t *)buffer, length, true);
    }
    (void)i2c_master_stop(cmd);
    ret = i2c_master_cmd_begin((i2c_port_t)CONFIG_SNAKE_I2C_BUS_ID, cmd,
        snake_ms_to_ticks(SNAKE_I2C_TIMEOUT_MS));
    i2c_cmd_link_delete(cmd);
    return ret;
}

static esp_err_t snake_i2c_write(const uint8_t *buffer, size_t length)
{
    return snake_i2c_write_to_addr((uint8_t)CONFIG_SNAKE_MATRIX_I2C_ADDR, buffer, length);
}

static void snake_tm1650_write(uint8_t i2c_addr, uint8_t value)
{
    (void)snake_i2c_write_to_addr(i2c_addr, &value, 1U);
}

static void snake_tm1650_clear(void)
{
    uint8_t digit_index;

    for (digit_index = 0; digit_index < TM1650_DIGIT_COUNT; digit_index++) {
        snake_tm1650_write(g_tm1650_digit_i2c_addr[digit_index], 0x00);
    }
}

static void snake_tm1650_init(void)
{
    snake_tm1650_write(TM1650_CMD_I2C_ADDR, TM1650_DISPLAY_ON_BRIGHTNESS);
    snake_tm1650_clear();
}

static void snake_tm1650_show_score(uint16_t score)
{
    uint8_t display_data[TM1650_DIGIT_COUNT];
    uint8_t digit_index;

    if (score > 9999U) {
        score = 9999U;
    }

    display_data[0] = g_tm1650_digits[score / 1000U];
    display_data[1] = g_tm1650_digits[(score / 100U) % 10U];
    display_data[2] = g_tm1650_digits[(score / 10U) % 10U];
    display_data[3] = g_tm1650_digits[score % 10U];

    for (digit_index = 0; digit_index < TM1650_DIGIT_COUNT; digit_index++) {
        snake_tm1650_write(g_tm1650_digit_i2c_addr[digit_index], display_data[digit_index]);
    }
}

static void snake_matrix_write_cmd(uint8_t cmd)
{
    (void)snake_i2c_write(&cmd, 1U);
}

static void snake_matrix_init(void)
{
    i2c_config_t i2c_config = {0};
    esp_err_t ret;

    i2c_config.mode = I2C_MODE_MASTER;
    i2c_config.sda_io_num = (gpio_num_t)CONFIG_SNAKE_I2C_SDA_PIN;
    i2c_config.scl_io_num = (gpio_num_t)CONFIG_SNAKE_I2C_SCL_PIN;
    i2c_config.sda_pullup_en = GPIO_PULLUP_ENABLE;
    i2c_config.scl_pullup_en = GPIO_PULLUP_ENABLE;
    i2c_config.master.clk_speed = SNAKE_I2C_SPEED;

    ret = i2c_param_config((i2c_port_t)CONFIG_SNAKE_I2C_BUS_ID, &i2c_config);
    if (ret != ESP_OK) {
        printf("snake i2c param config failed: %d\n", ret);
        return;
    }

    ret = i2c_driver_install((i2c_port_t)CONFIG_SNAKE_I2C_BUS_ID, I2C_MODE_MASTER, 0, 0, 0);
    if ((ret != ESP_OK) && (ret != ESP_ERR_INVALID_STATE)) {
        printf("snake i2c driver install failed: %d\n", ret);
        return;
    }

    snake_matrix_write_cmd(HT16K33_CMD_SYSTEM_SETUP);
    snake_matrix_write_cmd(HT16K33_CMD_DISPLAY_ON);
    snake_matrix_write_cmd(HT16K33_CMD_BRIGHTNESS);
}

static void snake_matrix_show_frame(void)
{
    uint8_t matrix_data[17] = {0};
    uint8_t row_index;

    matrix_data[0] = 0x00;
    for (row_index = 0; row_index < SNAKE_BOARD_SIZE; row_index++) {
        matrix_data[(row_index * 2U) + 1U] = g_led_frame[row_index];
        matrix_data[(row_index * 2U) + 2U] = 0x00;
    }
    (void)snake_i2c_write(matrix_data, sizeof(matrix_data));
}

static void snake_buzzer_init(void)
{
    snake_gpio_output(CONFIG_SNAKE_BUZZER_PIN, CONFIG_SNAKE_BUZZER_ACTIVE_LEVEL == 0);
}

static void snake_buzzer_on(bool on)
{
    bool level = on ? (CONFIG_SNAKE_BUZZER_ACTIVE_LEVEL != 0) :
        (CONFIG_SNAKE_BUZZER_ACTIVE_LEVEL == 0);

    snake_gpio_write(CONFIG_SNAKE_BUZZER_PIN, level);
}

static void snake_buzzer_beep(uint16_t duration_ms)
{
    snake_buzzer_on(true);
    snake_delay_ms(duration_ms);
    snake_buzzer_on(false);
    snake_delay_ms(SNAKE_BEEP_GAP_MS);
}

static bool snake_point_equal(snake_point_t left, snake_point_t right)
{
    return (left.x == right.x) && (left.y == right.y);
}

static bool snake_contains_point(snake_point_t point, uint8_t length)
{
    uint8_t point_index;

    for (point_index = 0; point_index < length; point_index++) {
        if (snake_point_equal(g_snake[point_index], point)) {
            return true;
        }
    }
    return false;
}

static uint32_t snake_rand(void)
{
    g_rng = (g_rng * 1103515245U) + 12345U;
    return g_rng;
}

static void snake_place_food(void)
{
    uint8_t try_index;
    snake_point_t point;

    for (try_index = 0; try_index < SNAKE_MAX_LEN; try_index++) {
        point.x = (uint8_t)(snake_rand() % SNAKE_BOARD_SIZE);
        point.y = (uint8_t)(snake_rand() % SNAKE_BOARD_SIZE);
        if (!snake_contains_point(point, g_snake_len)) {
            g_food = point;
            return;
        }
    }

    for (point.y = 0; point.y < SNAKE_BOARD_SIZE; point.y++) {
        for (point.x = 0; point.x < SNAKE_BOARD_SIZE; point.x++) {
            if (!snake_contains_point(point, g_snake_len)) {
                g_food = point;
                return;
            }
        }
    }
}

static void snake_render_frame(void)
{
    uint8_t frame[SNAKE_BOARD_SIZE] = {0};
    uint8_t item_index;

    if (g_game_over) {
        for (item_index = 0; item_index < SNAKE_BOARD_SIZE; item_index++) {
            frame[item_index] = (item_index == 0U || item_index == 7U) ? 0xFF : 0x81;
        }
    } else {
        frame[g_food.y] |= (uint8_t)(1U << g_food.x);
        for (item_index = 0; item_index < g_snake_len; item_index++) {
            frame[g_snake[item_index].y] |= (uint8_t)(1U << g_snake[item_index].x);
        }
    }

    for (item_index = 0; item_index < SNAKE_BOARD_SIZE; item_index++) {
        g_led_frame[item_index] = frame[item_index];
    }
}

static void snake_reset_game(void)
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
    g_score = 0;
    g_game_over = false;
    g_paused = false;
    g_restart_request = false;
    snake_place_food();
    snake_render_frame();
}

static bool snake_is_reverse(snake_dir_t next, snake_dir_t current)
{
    return ((next == SNAKE_DIR_UP && current == SNAKE_DIR_DOWN) ||
        (next == SNAKE_DIR_DOWN && current == SNAKE_DIR_UP) ||
        (next == SNAKE_DIR_LEFT && current == SNAKE_DIR_RIGHT) ||
        (next == SNAKE_DIR_RIGHT && current == SNAKE_DIR_LEFT));
}

static void snake_step(void)
{
    snake_point_t next = g_snake[0];
    bool grow;
    uint8_t check_len;
    uint8_t move_index;

    if (!snake_is_reverse(g_pending_dir, g_dir)) {
        g_dir = g_pending_dir;
    }

    switch (g_dir) {
        case SNAKE_DIR_UP:
            if (next.y == 0U) {
                g_game_over = true;
                return;
            }
            next.y--;
            break;
        case SNAKE_DIR_DOWN:
            if (next.y >= (SNAKE_BOARD_SIZE - 1U)) {
                g_game_over = true;
                return;
            }
            next.y++;
            break;
        case SNAKE_DIR_LEFT:
            if (next.x == 0U) {
                g_game_over = true;
                return;
            }
            next.x--;
            break;
        case SNAKE_DIR_RIGHT:
        default:
            if (next.x >= (SNAKE_BOARD_SIZE - 1U)) {
                g_game_over = true;
                return;
            }
            next.x++;
            break;
    }

    grow = snake_point_equal(next, g_food);
    check_len = grow ? g_snake_len : (uint8_t)(g_snake_len - 1U);
    if (snake_contains_point(next, check_len)) {
        g_game_over = true;
        return;
    }

    if (grow && g_snake_len < SNAKE_MAX_LEN) {
        g_snake_len++;
    }

    for (move_index = (uint8_t)(g_snake_len - 1U); move_index > 0U; move_index--) {
        g_snake[move_index] = g_snake[move_index - 1U];
    }
    g_snake[0] = next;

    if (grow) {
        g_score = (uint16_t)(g_score + SNAKE_SCORE_PER_FOOD);
        snake_buzzer_beep(SNAKE_BEEP_SHORT_MS);
        if (g_snake_len >= SNAKE_MAX_LEN) {
            g_game_over = true;
            return;
        }
        snake_place_food();
    }
}

static void snake_finish_step(void)
{
    snake_render_frame();
    if (g_game_over) {
        snake_render_frame();
        snake_buzzer_beep(SNAKE_BEEP_LONG_MS);
        snake_buzzer_beep(SNAKE_BEEP_LONG_MS);
        printf("snake game over, score = %u. Press restart key.\n", (unsigned int)g_score);
    }
}

static void snake_handle_direction(snake_dir_t dir)
{
    if (g_game_over || snake_is_reverse(dir, g_dir)) {
        return;
    }

    g_pending_dir = dir;
    snake_wake_game(SNAKE_EVENT_DIRECTION);
}

static void snake_adkey_init(void)
{
    (void)adc1_config_width(ADC_WIDTH_BIT_10);
    (void)adc1_config_channel_atten(CONFIG_SNAKE_ADKEY_ADC_CHANNEL, ADC_ATTEN_DB_11);
}

static uint16_t snake_adkey_read_raw(void)
{
    uint32_t raw_total = 0;
    uint8_t sample_index;

    for (sample_index = 0; sample_index < SNAKE_ADKEY_SAMPLE_COUNT; sample_index++) {
        raw_total += (uint32_t)adc1_get_raw(CONFIG_SNAKE_ADKEY_ADC_CHANNEL);
    }
    return (uint16_t)(raw_total / SNAKE_ADKEY_SAMPLE_COUNT);
}

static snake_adkey_t snake_adkey_classify(uint16_t raw)
{
    if (raw <= SNAKE_ADKEY_NO_KEY_MAX) {
        return SNAKE_ADKEY_NONE;
    }
    if (raw <= SNAKE_ADKEY_SW5_MAX) {
        return SNAKE_ADKEY_SW5;
    }
    if (raw <= SNAKE_ADKEY_SW4_MAX) {
        return SNAKE_ADKEY_SW4;
    }
    if (raw <= SNAKE_ADKEY_SW3_MAX) {
        return SNAKE_ADKEY_SW3;
    }
    if (raw <= SNAKE_ADKEY_SW2_MAX) {
        return SNAKE_ADKEY_SW2;
    }
    return SNAKE_ADKEY_SW1;
}

static void snake_adkey_handle(snake_adkey_t key)
{
    switch (key) {
        case SNAKE_ADKEY_SW3:
            snake_handle_direction(SNAKE_DIR_UP);
            break;
        case SNAKE_ADKEY_SW5:
            snake_handle_direction(SNAKE_DIR_DOWN);
            break;
        case SNAKE_ADKEY_SW4:
            snake_handle_direction(SNAKE_DIR_LEFT);
            break;
        case SNAKE_ADKEY_SW2:
            snake_handle_direction(SNAKE_DIR_RIGHT);
            break;
        case SNAKE_ADKEY_SW1:
            g_paused = !g_paused;
            snake_wake_game(SNAKE_EVENT_PAUSE);
            printf("snake %s.\n", g_paused ? "paused" : "resumed");
            break;
        case SNAKE_ADKEY_NONE:
        default:
            break;
    }
}

static const char *snake_adkey_name(snake_adkey_t key)
{
    switch (key) {
        case SNAKE_ADKEY_SW1:
            return "SW1";
        case SNAKE_ADKEY_SW2:
            return "SW2";
        case SNAKE_ADKEY_SW3:
            return "SW3";
        case SNAKE_ADKEY_SW4:
            return "SW4";
        case SNAKE_ADKEY_SW5:
            return "SW5";
        case SNAKE_ADKEY_NONE:
        default:
            return "NONE";
    }
}

static void snake_adkey_task(void *argument)
{
    snake_adkey_t key;
    snake_adkey_t last_key = SNAKE_ADKEY_NONE;
    uint16_t raw;

    (void)argument;
    snake_adkey_init();
    printf("snake adkey ready: SW3=up, SW5=down, SW4=left, SW2=right, SW1=pause.\n");
    printf("wire: S -> GPIO34(ADC1_CH6), V -> 3.3V, G -> GND.\n");

    while (1) {
        raw = snake_adkey_read_raw();
        key = snake_adkey_classify(raw);
        if ((key != SNAKE_ADKEY_NONE) && (key != last_key)) {
            printf("snake adkey: %s raw=%u\n", snake_adkey_name(key), (unsigned int)raw);
            snake_adkey_handle(key);
            snake_delay_ms(SNAKE_ADKEY_DEBOUNCE_MS);
        }
        last_key = key;
        snake_delay_ms(SNAKE_ADKEY_READ_PERIOD_MS);
    }
}

static void snake_display_task(void *argument)
{
    (void)argument;
    snake_matrix_init();
    snake_tm1650_init();

    while (1) {
        snake_matrix_show_frame();
        snake_tm1650_show_score(g_score);
        snake_delay_ms(SNAKE_DISPLAY_REFRESH_MS);
    }
}

static void snake_game_task(void *argument)
{
    uint32_t events;

    (void)argument;
    snake_buzzer_init();
    snake_reset_game();
    snake_buzzer_beep(SNAKE_BEEP_SHORT_MS);
    snake_buzzer_beep(SNAKE_BEEP_SHORT_MS);

    while (1) {
        events = osThreadFlagsWait(SNAKE_EVENT_MASK, osFlagsWaitAny,
            snake_ms_to_ticks(CONFIG_SNAKE_TICK_MS));
        if ((events & osFlagsError) != 0U) {
            events = 0U;
        }

        if (((events & SNAKE_EVENT_RESTART) != 0U) || g_restart_request) {
            snake_reset_game();
            snake_buzzer_beep(SNAKE_BEEP_SHORT_MS);
            continue;
        }

        if (g_paused) {
            continue;
        }

        if (g_game_over) {
            continue;
        }

        snake_step();
        snake_finish_step();
    }
}

static osThreadId_t snake_create_thread(const char *name, osThreadFunc_t func, uint32_t stack_size)
{
    osThreadAttr_t attr = {0};
    osThreadId_t thread_id;

    attr.name = name;
    attr.stack_size = stack_size;
    attr.priority = SNAKE_TASK_PRIO;

    thread_id = osThreadNew(func, NULL, &attr);
    if (thread_id == NULL) {
        printf("snake create %s failed.\n", name);
    }
    return thread_id;
}

static void snake_entry(void)
{
    g_game_thread_id = snake_create_thread("SnakeGame", snake_game_task, SNAKE_GAME_STACK_SIZE);
    (void)snake_create_thread("SnakeDisplay", snake_display_task, SNAKE_DISPLAY_STACK_SIZE);
    (void)snake_create_thread("SnakeAdKey", snake_adkey_task, SNAKE_ADKEY_STACK_SIZE);
}

OHOS_APP_RUN(snake_entry);
