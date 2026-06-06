#include "game_common.h"
#include "game_mqtt.h"
#include "game_port.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "ohos_run.h"

#define GAME_TASK_STACK_SIZE       0x2000
#define DISPLAY_TASK_STACK_SIZE    0x1000
#define KEY_TASK_STACK_SIZE        0x1000
#define GAME_TASK_PRIO             (osPriority_t)(17)

#define KEY_READ_PERIOD_MS         30
#define KEY_DEBOUNCE_MS            120
#define MENU_SCORE_MARK            0
#define GAME_WAIT_REVIVE_MS        9000

extern void game_display_task(void *argument);

static const uint8_t g_menu_icons[GAME_ID_COUNT][GAME_FRAME_BYTES] = {
    {
        0x00, 0x1E, 0x02, 0x1A, 0x12, 0x72, 0x40, 0x7C
    },
    {
        0x00, 0x66, 0x66, 0x18, 0x18, 0x3C, 0x30, 0x30
    },
    {
        0x00, 0x18, 0x18, 0x1C, 0x78, 0x1E, 0x12, 0x63
    },
    {
        0x18, 0x3C, 0x5A, 0x18, 0x3C, 0x24, 0x42, 0x00
    }
};

static volatile game_key_t g_last_key = GAME_KEY_NONE;
static volatile bool g_key_pending;
static volatile uint32_t g_seed_counter;

static void show_game_over_frame(void)
{
    static const uint8_t frame[GAME_FRAME_BYTES] = {
        0xFF, 0x81, 0x99, 0xA5, 0xA5, 0x99, 0x81, 0xFF
    };

    game_display_set_frame(frame);
}

static void show_menu(game_id_t selected)
{
    game_display_set_frame(g_menu_icons[selected]);
    game_display_show_score((uint16_t)(selected + 1U));
}

static void render_driver(const game_driver_t *driver)
{
    uint8_t frame[GAME_FRAME_BYTES];

    driver->render(frame);
    game_display_set_frame(frame);
    game_display_show_score(driver->score());
}

static osThreadId_t create_thread(const char *name, osThreadFunc_t func, uint32_t stack_size)
{
    osThreadAttr_t attr = {0};
    osThreadId_t thread_id;

    attr.name = name;
    attr.stack_size = stack_size;
    attr.priority = GAME_TASK_PRIO;
    thread_id = osThreadNew(func, NULL, &attr);
    if (thread_id == NULL) {
        printf("create %s failed\r\n", name);
    }
    return thread_id;
}

static game_key_t take_key(void)
{
    game_key_t key = GAME_KEY_NONE;

    if (g_key_pending) {
        key = g_last_key;
        g_key_pending = false;
    }
    return key;
}

static void game_key_task(void *argument)
{
    game_key_t key;
    game_key_t last_key = GAME_KEY_NONE;

    (void)argument;
    printf("AD key: SW1=FUNC, SW2=RIGHT, SW3=UP, SW4=LEFT, SW5=DOWN\r\n");
    printf("wire: S -> GPIO34(ADC1_CH6), V -> 3.3V, G -> GND\r\n");
    while (1) {
        key = game_key_read();
        g_seed_counter++;
        if ((key != GAME_KEY_NONE) && (key != last_key)) {
            printf("key: %s\r\n", game_key_name(key));
            g_last_key = key;
            g_key_pending = true;
            game_wake_controller(GAME_EVENT_KEY);
            game_delay_ms(KEY_DEBOUNCE_MS);
        }
        last_key = key;
        game_delay_ms(KEY_READ_PERIOD_MS);
    }
}

static game_id_t menu_loop(void)
{
    game_id_t selected = GAME_ID_SNAKE;
    game_key_t key;
    uint32_t events;

    show_menu(selected);
    while (1) {
        events = osThreadFlagsWait(GAME_EVENT_KEY, osFlagsWaitAny, game_ms_to_ticks(300));
        if ((events & osFlagsError) != 0U) {
            continue;
        }
        key = take_key();
        if (key == GAME_KEY_FUNC) {
            return selected;
        }
        if (key == GAME_KEY_RIGHT) {
            selected = (game_id_t)((selected + 1U) % GAME_ID_COUNT);
            show_menu(selected);
        } else if (key == GAME_KEY_LEFT) {
            selected = (selected == 0U) ? (GAME_ID_COUNT - 1U) : (game_id_t)(selected - 1U);
            show_menu(selected);
        }
    }
}

static bool wait_for_revive_or_restart(game_id_t game_id, uint16_t score)
{
    uint32_t wait_ms = 0;
    game_key_t key;

    game_mqtt_publish_game_over(game_id, score);
    show_game_over_frame();
    game_display_show_score(score);

    while (wait_ms < GAME_WAIT_REVIVE_MS) {
        if (game_mqtt_take_revive(game_id)) {
            return true;
        }
        (void)osThreadFlagsWait(GAME_EVENT_MASK, osFlagsWaitAny, game_ms_to_ticks(200));
        key = take_key();
        if (key == GAME_KEY_FUNC) {
            return false;
        }
        wait_ms += 200U;
    }
    return false;
}

static void run_selected_game(game_id_t game_id)
{
    const game_driver_t *driver = game_get_driver(game_id);
    bool alive = true;
    uint32_t events;
    game_key_t key;

    printf("start game: %s\r\n", driver->name);
    game_seed(g_seed_counter);
    driver->init(0);
    game_buzzer_double(60);
    render_driver(driver);

    while (1) {
        events = osThreadFlagsWait(GAME_EVENT_MASK, osFlagsWaitAny,
            game_ms_to_ticks(driver->tick_ms));
        if ((events & osFlagsError) != 0U) {
            events = 0U;
        }

        key = take_key();
        if (key != GAME_KEY_NONE) {
            if (key == GAME_KEY_FUNC && driver->id == GAME_ID_SNAKE) {
                game_buzzer_beep(35);
            } else {
                driver->handle_key(key);
            }
        }

        alive = driver->step();
        render_driver(driver);
        if (!alive) {
            uint16_t score = driver->score();
            printf("game over: %s score=%u\r\n", driver->name, (unsigned int)score);
            game_buzzer_double(180);
            if (wait_for_revive_or_restart(game_id, score)) {
                printf("revive: %s score=%u\r\n", driver->name, (unsigned int)score);
                driver->revive();
                game_buzzer_double(60);
                render_driver(driver);
                continue;
            }
            return;
        }
    }
}

static void game_controller_task(void *argument)
{
    game_id_t selected;

    (void)argument;
    game_set_controller_thread(osThreadGetId());
    game_hw_init();
    game_mqtt_start();
    printf("ESP32 pixel game console ready\r\n");

    while (1) {
        selected = menu_loop();
        run_selected_game(selected);
    }
}

static void game_entry(void)
{
    (void)create_thread("GameDisplay", game_display_task, DISPLAY_TASK_STACK_SIZE);
    (void)create_thread("GameKeys", game_key_task, KEY_TASK_STACK_SIZE);
    (void)create_thread("GameCtrl", game_controller_task, GAME_TASK_STACK_SIZE);
}

OHOS_APP_RUN(game_entry);
