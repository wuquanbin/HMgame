#include "game_common.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "driver/adc.h"
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_err.h"

#define GAME_I2C_SPEED                  100000
#define GAME_I2C_TIMEOUT_MS             100

#define GAME_ADKEY_SAMPLE_COUNT         8
#define GAME_ADKEY_NO_KEY_MAX           100
#define GAME_ADKEY_SW5_MAX              300
#define GAME_ADKEY_SW4_MAX              500
#define GAME_ADKEY_SW3_MAX              700
#define GAME_ADKEY_SW2_MAX              900

#define HT16K33_CMD_SYSTEM_SETUP        0x21
#define HT16K33_CMD_DISPLAY_ON          0x81
#define HT16K33_CMD_BRIGHTNESS          0xE8

#define TM1650_CMD_I2C_ADDR             0x24
#define TM1650_DISPLAY_ON_BRIGHTNESS    0x09
#define TM1650_DIGIT_COUNT              4

#define GAME_BEEP_GAP_MS                35

static const uint8_t g_tm1650_digits[10] = {
    0x3F, 0x06, 0x5B, 0x4F, 0x66,
    0x6D, 0x7D, 0x07, 0x7F, 0x6F
};

static const uint8_t g_tm1650_digit_addr[TM1650_DIGIT_COUNT] = {
    0x34, 0x35, 0x36, 0x37
};

static volatile uint8_t g_frame[GAME_FRAME_BYTES];
static volatile uint16_t g_score;
static uint32_t g_rng = 0x4f1bbc11U;
static osThreadId_t g_controller_thread_id;

uint32_t game_ms_to_ticks(uint32_t ms)
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

void game_delay_ms(uint32_t ms)
{
    osDelay(game_ms_to_ticks(ms));
}

void game_set_controller_thread(osThreadId_t thread_id)
{
    g_controller_thread_id = thread_id;
}

void game_wake_controller(uint32_t flags)
{
    osThreadId_t thread_id = g_controller_thread_id;

    if (thread_id != NULL) {
        (void)osThreadFlagsSet(thread_id, flags);
    }
}

static void game_gpio_write(uint8_t pin, bool high)
{
    (void)gpio_set_level((gpio_num_t)pin, high ? 1 : 0);
}

static void game_gpio_output(uint8_t pin, bool high)
{
    gpio_config_t gpio_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = 1ULL << pin,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .pull_up_en = GPIO_PULLUP_DISABLE
    };

    (void)gpio_config(&gpio_conf);
    game_gpio_write(pin, high);
}

static esp_err_t game_i2c_write_to_addr(uint8_t i2c_addr, const uint8_t *buffer, size_t length)
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
    ret = i2c_master_cmd_begin((i2c_port_t)CONFIG_GAME_I2C_BUS_ID, cmd,
        game_ms_to_ticks(GAME_I2C_TIMEOUT_MS));
    i2c_cmd_link_delete(cmd);
    return ret;
}

static esp_err_t game_i2c_write_matrix(const uint8_t *buffer, size_t length)
{
    return game_i2c_write_to_addr((uint8_t)CONFIG_GAME_MATRIX_I2C_ADDR, buffer, length);
}

static void game_matrix_write_cmd(uint8_t cmd)
{
    (void)game_i2c_write_matrix(&cmd, 1U);
}

static void game_tm1650_write(uint8_t i2c_addr, uint8_t value)
{
    (void)game_i2c_write_to_addr(i2c_addr, &value, 1U);
}

static void game_tm1650_clear(void)
{
    uint8_t digit_index;

    for (digit_index = 0; digit_index < TM1650_DIGIT_COUNT; digit_index++) {
        game_tm1650_write(g_tm1650_digit_addr[digit_index], 0x00);
    }
}

static void game_tm1650_init(void)
{
    game_tm1650_write(TM1650_CMD_I2C_ADDR, TM1650_DISPLAY_ON_BRIGHTNESS);
    game_tm1650_clear();
}

void game_display_show_score(uint16_t score)
{
    g_score = score;
}

static void game_tm1650_show_score(uint16_t score)
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
        game_tm1650_write(g_tm1650_digit_addr[digit_index], display_data[digit_index]);
    }
}

void game_display_set_frame(const uint8_t frame[GAME_FRAME_BYTES])
{
    uint8_t row_index;

    for (row_index = 0; row_index < GAME_FRAME_BYTES; row_index++) {
        g_frame[row_index] = frame[row_index];
    }
}

void game_display_clear(void)
{
    uint8_t frame[GAME_FRAME_BYTES] = {0};

    game_display_set_frame(frame);
}

static void game_matrix_show_frame(void)
{
    uint8_t matrix_data[17] = {0};
    uint8_t row_index;

    matrix_data[0] = 0x00;
    for (row_index = 0; row_index < GAME_FRAME_BYTES; row_index++) {
        matrix_data[(row_index * 2U) + 1U] = g_frame[row_index];
        matrix_data[(row_index * 2U) + 2U] = 0x00;
    }
    (void)game_i2c_write_matrix(matrix_data, sizeof(matrix_data));
}

static void game_matrix_init(void)
{
    i2c_config_t i2c_config = {0};
    esp_err_t ret;

    i2c_config.mode = I2C_MODE_MASTER;
    i2c_config.sda_io_num = (gpio_num_t)CONFIG_GAME_I2C_SDA_PIN;
    i2c_config.scl_io_num = (gpio_num_t)CONFIG_GAME_I2C_SCL_PIN;
    i2c_config.sda_pullup_en = GPIO_PULLUP_ENABLE;
    i2c_config.scl_pullup_en = GPIO_PULLUP_ENABLE;
    i2c_config.master.clk_speed = GAME_I2C_SPEED;

    ret = i2c_param_config((i2c_port_t)CONFIG_GAME_I2C_BUS_ID, &i2c_config);
    if (ret != ESP_OK) {
        printf("game i2c param config failed: %d\n", ret);
        return;
    }

    ret = i2c_driver_install((i2c_port_t)CONFIG_GAME_I2C_BUS_ID, I2C_MODE_MASTER, 0, 0, 0);
    if ((ret != ESP_OK) && (ret != ESP_ERR_INVALID_STATE)) {
        printf("game i2c driver install failed: %d\n", ret);
        return;
    }

    game_matrix_write_cmd(HT16K33_CMD_SYSTEM_SETUP);
    game_matrix_write_cmd(HT16K33_CMD_DISPLAY_ON);
    game_matrix_write_cmd(HT16K33_CMD_BRIGHTNESS);
}

static void game_buzzer_init(void)
{
    game_gpio_output(CONFIG_GAME_BUZZER_PIN, CONFIG_GAME_BUZZER_ACTIVE_LEVEL == 0);
}

static void game_buzzer_on(bool on)
{
    bool level = on ? (CONFIG_GAME_BUZZER_ACTIVE_LEVEL != 0) :
        (CONFIG_GAME_BUZZER_ACTIVE_LEVEL == 0);

    game_gpio_write(CONFIG_GAME_BUZZER_PIN, level);
}

void game_buzzer_beep(uint16_t duration_ms)
{
    game_buzzer_on(true);
    game_delay_ms(duration_ms);
    game_buzzer_on(false);
    game_delay_ms(GAME_BEEP_GAP_MS);
}

void game_buzzer_double(uint16_t duration_ms)
{
    game_buzzer_beep(duration_ms);
    game_buzzer_beep(duration_ms);
}

static void game_adkey_init(void)
{
    (void)adc1_config_width(ADC_WIDTH_BIT_10);
    (void)adc1_config_channel_atten(CONFIG_GAME_ADKEY_ADC_CHANNEL, ADC_ATTEN_DB_11);
}

static uint16_t game_adkey_read_raw(void)
{
    uint32_t raw_total = 0;
    uint8_t sample_index;

    for (sample_index = 0; sample_index < GAME_ADKEY_SAMPLE_COUNT; sample_index++) {
        raw_total += (uint32_t)adc1_get_raw(CONFIG_GAME_ADKEY_ADC_CHANNEL);
    }
    return (uint16_t)(raw_total / GAME_ADKEY_SAMPLE_COUNT);
}

game_key_t game_key_read(void)
{
    uint16_t raw = game_adkey_read_raw();

    if (raw <= GAME_ADKEY_NO_KEY_MAX) {
        return GAME_KEY_NONE;
    }
    if (raw <= GAME_ADKEY_SW5_MAX) {
        return GAME_KEY_DOWN;
    }
    if (raw <= GAME_ADKEY_SW4_MAX) {
        return GAME_KEY_LEFT;
    }
    if (raw <= GAME_ADKEY_SW3_MAX) {
        return GAME_KEY_UP;
    }
    if (raw <= GAME_ADKEY_SW2_MAX) {
        return GAME_KEY_RIGHT;
    }
    return GAME_KEY_FUNC;
}

const char *game_key_name(game_key_t key)
{
    switch (key) {
        case GAME_KEY_FUNC:
            return "SW1/FUNC";
        case GAME_KEY_RIGHT:
            return "SW2/RIGHT";
        case GAME_KEY_UP:
            return "SW3/UP";
        case GAME_KEY_LEFT:
            return "SW4/LEFT";
        case GAME_KEY_DOWN:
            return "SW5/DOWN";
        case GAME_KEY_NONE:
        default:
            return "NONE";
    }
}

uint32_t game_rand(void)
{
    g_rng = (g_rng * 1103515245U) + 12345U;
    return g_rng;
}

void game_seed(uint32_t seed)
{
    if (seed != 0U) {
        g_rng ^= seed;
    }
}

void game_hw_init(void)
{
    game_matrix_init();
    game_tm1650_init();
    game_buzzer_init();
    game_adkey_init();
    game_display_clear();
    game_display_show_score(0);
}

void game_display_task(void *argument)
{
    (void)argument;
    while (1) {
        game_matrix_show_frame();
        game_tm1650_show_score(g_score);
        game_delay_ms(40);
    }
}
