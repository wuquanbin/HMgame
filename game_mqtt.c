#include "game_mqtt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cmsis_os2.h"
#include "lwip/inet.h"
#include "MQTTClient.h"
#include "wifi_device.h"
#include "wifi_error_code.h"

#define WIFI_SSID                 "MIFI_1E85"
#define WIFI_TIMEOUT_SECONDS      15
#define ONE_SECOND_MS             1000

#define MQTT_BROKER_HOST          "broker.emqx.io"
#define MQTT_BROKER_PORT          1883
#define MQTT_CLIENT_ID            "esp32_wuquanbin_gamebox"
#define MQTT_USERNAME             "wqb"
#define MQTT_PASSWORD             "123"
#define MQTT_TOPIC_EVENT          "wuquanbin/game/event"
#define MQTT_TOPIC_CMD            "wuquanbin/game/cmd"
#define MQTT_TOPIC_LEGACY         "wuquanbin"

#define MQTT_BUF_SIZE             2048
#define MQTT_CMD_TIMEOUT_MS       3000
#define MQTT_TASK_STACK_SIZE      0x1800
#define MQTT_TASK_PRIO            (osPriority_t)(13)

static MQTTClient g_mqtt_client;
static Network g_network;
static unsigned char *g_send_buf;
static unsigned char *g_read_buf;
static volatile bool g_mqtt_ready;
static volatile uint8_t g_revive_mask;
static osMutexId_t g_mqtt_mutex;

static int g_scan_done;
static int g_connect_done;
static int g_wifi_event_registered;
static WifiEvent g_wifi_event_handler = {0};

static void mqtt_lock(void)
{
    if (g_mqtt_mutex != NULL) {
        (void)osMutexAcquire(g_mqtt_mutex, osWaitForever);
    }
}

static void mqtt_unlock(void)
{
    if (g_mqtt_mutex != NULL) {
        (void)osMutexRelease(g_mqtt_mutex);
    }
}

static const char *game_mqtt_name(game_id_t game_id)
{
    const game_driver_t *driver = game_get_driver(game_id);

    return driver->name;
}

static game_id_t game_mqtt_parse_game(const char *payload)
{
    if (strstr(payload, "\"snake\"") != NULL) {
        return GAME_ID_SNAKE;
    }
    if (strstr(payload, "\"tetris\"") != NULL) {
        return GAME_ID_TETRIS;
    }
    if (strstr(payload, "\"dino\"") != NULL) {
        return GAME_ID_DINO;
    }
    if (strstr(payload, "\"plane\"") != NULL) {
        return GAME_ID_PLANE;
    }
    return GAME_ID_COUNT;
}

static void mqtt_callback(MessageData *msg_data)
{
    char payload[160];
    int copy_len;
    game_id_t game_id;

    copy_len = msg_data->message->payloadlen;
    if (copy_len >= (int)sizeof(payload)) {
        copy_len = (int)sizeof(payload) - 1;
    }
    (void)memcpy(payload, msg_data->message->payload, (size_t)copy_len);
    payload[copy_len] = '\0';

    printf("MQTT cmd: %s\r\n", payload);
    if (strstr(payload, "\"revive\"") == NULL) {
        return;
    }

    game_id = game_mqtt_parse_game(payload);
    if (game_id < GAME_ID_COUNT) {
        g_revive_mask |= (uint8_t)(1U << game_id);
        game_wake_controller(GAME_EVENT_REVIVE);
    }
}

bool game_mqtt_take_revive(game_id_t game_id)
{
    uint8_t bit;

    if (game_id >= GAME_ID_COUNT) {
        return false;
    }
    bit = (uint8_t)(1U << game_id);
    if ((g_revive_mask & bit) == 0U) {
        return false;
    }
    g_revive_mask &= (uint8_t)(~bit);
    return true;
}

static void on_wifi_scan_changed(int state, int size)
{
    (void)state;
    if (size > 0) {
        g_scan_done = 1;
        printf("WiFi scan done, ap count=%d\r\n", size);
    }
}

static void on_wifi_connection_changed(int state, WifiLinkedInfo *info)
{
    (void)info;
    if (state > 0) {
        g_connect_done = 1;
        printf("WiFi connected callback\r\n");
    } else {
        g_connect_done = 0;
        printf("WiFi disconnected, state=%d\r\n", state);
    }
}

static int wifi_init_once(void)
{
    WifiErrorCode ret;

    if (g_wifi_event_registered != 0) {
        return 0;
    }

    g_wifi_event_handler.OnWifiScanStateChanged = on_wifi_scan_changed;
    g_wifi_event_handler.OnWifiConnectionChanged = on_wifi_connection_changed;
    ret = RegisterWifiEvent(&g_wifi_event_handler);
    if (ret != WIFI_SUCCESS) {
        printf("RegisterWifiEvent failed, ret=%d\r\n", ret);
        return ret;
    }
    g_wifi_event_registered = 1;
    printf("RegisterWifiEvent success\r\n");
    return 0;
}

static int wait_scan_result(void)
{
    int timeout = WIFI_TIMEOUT_SECONDS;

    while (timeout-- > 0) {
        if (g_scan_done != 0) {
            return 0;
        }
        osDelay(ONE_SECOND_MS);
    }
    printf("WiFi scan timeout\r\n");
    return -1;
}

static int wait_connect_result(void)
{
    int timeout = WIFI_TIMEOUT_SECONDS;

    while (timeout-- > 0) {
        if (g_connect_done != 0) {
            return 0;
        }
        osDelay(ONE_SECOND_MS);
    }
    printf("WiFi connect timeout\r\n");
    return -1;
}

static void print_ip_info(unsigned int ip_address)
{
    struct in_addr addr;

    addr.s_addr = ip_address;
    printf("WiFi IP: %s\r\n", inet_ntoa(addr));
}

static int wait_ip_ready(void)
{
    int timeout = WIFI_TIMEOUT_SECONDS;
    WifiLinkedInfo linked_info = {0};

    while (timeout-- > 0) {
        if ((GetLinkedInfo(&linked_info) == WIFI_SUCCESS) &&
            (linked_info.connState == WIFI_CONNECTED) &&
            (linked_info.ipAddress != 0U)) {
            print_ip_info(linked_info.ipAddress);
            return 0;
        }
        osDelay(ONE_SECOND_MS);
    }
    printf("WiFi DHCP/IP timeout\r\n");
    return -1;
}

static int wifi_connect(void)
{
    WifiErrorCode ret;
    WifiDeviceConfig config = {0};
    int network_id = -1;

    if (wifi_init_once() != 0) {
        return -1;
    }

    ret = EnableWifi();
    if (ret != WIFI_SUCCESS) {
        printf("EnableWifi failed, ret=%d\r\n", ret);
        return ret;
    }
    if (IsWifiActive() == WIFI_STA_NOT_ACTIVE) {
        printf("WiFi station is not active\r\n");
        return -1;
    }

    g_scan_done = 0;
    (void)Scan();
    (void)wait_scan_result();

    (void)strncpy(config.ssid, WIFI_SSID, sizeof(config.ssid) - 1U);
    config.securityType = WIFI_SEC_TYPE_OPEN;
    config.ipType = DHCP;

    ret = AddDeviceConfig(&config, &network_id);
    if (ret != WIFI_SUCCESS) {
        printf("AddDeviceConfig failed, ret=%d\r\n", ret);
        return ret;
    }

    g_connect_done = 0;
    printf("Connecting WiFi SSID: %s\r\n", config.ssid);
    ret = ConnectTo(network_id);
    if (ret != WIFI_SUCCESS) {
        printf("ConnectTo failed, ret=%d\r\n", ret);
        return ret;
    }
    if (wait_connect_result() != 0) {
        return -1;
    }
    return wait_ip_ready();
}

static int mqtt_alloc_buffer(void)
{
    g_send_buf = (unsigned char *)malloc(MQTT_BUF_SIZE);
    g_read_buf = (unsigned char *)malloc(MQTT_BUF_SIZE);
    if ((g_send_buf == NULL) || (g_read_buf == NULL)) {
        printf("MQTT malloc buffer failed\r\n");
        free(g_send_buf);
        free(g_read_buf);
        g_send_buf = NULL;
        g_read_buf = NULL;
        return -1;
    }
    return 0;
}

static void mqtt_close(void)
{
    mqtt_lock();
    g_mqtt_ready = false;
    if (MQTTIsConnected(&g_mqtt_client)) {
        (void)MQTTDisconnect(&g_mqtt_client);
    }
    NetworkDisconnect(&g_network);
    free(g_send_buf);
    free(g_read_buf);
    g_send_buf = NULL;
    g_read_buf = NULL;
    mqtt_unlock();
}

static int mqtt_connect(void)
{
    int rc;
    MQTTPacket_connectData data = MQTTPacket_connectData_initializer;

    NetworkInit(&g_network);
    printf("MQTT connecting TCP %s:%d ...\r\n", MQTT_BROKER_HOST, MQTT_BROKER_PORT);
    rc = NetworkConnect(&g_network, MQTT_BROKER_HOST, MQTT_BROKER_PORT);
    if (rc != 0) {
        printf("MQTT TCP connect failed, rc=%d\r\n", rc);
        return rc;
    }
    if (mqtt_alloc_buffer() != 0) {
        NetworkDisconnect(&g_network);
        return -1;
    }

    MQTTClientInit(&g_mqtt_client, &g_network, MQTT_CMD_TIMEOUT_MS,
        g_send_buf, MQTT_BUF_SIZE, g_read_buf, MQTT_BUF_SIZE);

    data.keepAliveInterval = 60;
    data.cleansession = 1;
    data.clientID.cstring = MQTT_CLIENT_ID;
    data.username.cstring = MQTT_USERNAME;
    data.password.cstring = MQTT_PASSWORD;

    rc = MQTTConnect(&g_mqtt_client, &data);
    if (rc != 0) {
        printf("MQTT CONNECT failed, rc=%d\r\n", rc);
        mqtt_close();
        return rc;
    }

    rc = MQTTSubscribe(&g_mqtt_client, MQTT_TOPIC_CMD, QOS0, mqtt_callback);
    if (rc != 0) {
        printf("MQTT subscribe failed, rc=%d\r\n", rc);
        mqtt_close();
        return rc;
    }

    g_mqtt_ready = true;
    printf("MQTT ready, cmd=%s, event=%s\r\n", MQTT_TOPIC_CMD, MQTT_TOPIC_EVENT);
    return 0;
}

void game_mqtt_publish_game_over(game_id_t game_id, uint16_t score)
{
    char payload[160];
    MQTTMessage message;

    mqtt_lock();
    if (!g_mqtt_ready || !MQTTIsConnected(&g_mqtt_client)) {
        printf("MQTT offline, skip score upload: %s %u\r\n",
            game_mqtt_name(game_id), (unsigned int)score);
        mqtt_unlock();
        return;
    }

    (void)snprintf(payload, sizeof(payload),
        "{\"type\":\"game_over\",\"game\":\"%s\",\"score\":%u}",
        game_mqtt_name(game_id), (unsigned int)score);

    (void)memset(&message, 0, sizeof(message));
    message.qos = QOS0;
    message.retained = 0;
    message.payload = payload;
    message.payloadlen = strlen(payload);

    if (MQTTPublish(&g_mqtt_client, MQTT_TOPIC_EVENT, &message) == 0) {
        printf("MQTT publish %s: %s\r\n", MQTT_TOPIC_EVENT, payload);
    } else {
        printf("MQTT publish failed: %s\r\n", payload);
    }
    if (MQTTPublish(&g_mqtt_client, MQTT_TOPIC_LEGACY, &message) == 0) {
        printf("MQTT publish %s: %s\r\n", MQTT_TOPIC_LEGACY, payload);
    } else {
        printf("MQTT publish legacy failed: %s\r\n", payload);
    }
    mqtt_unlock();
}

static void game_mqtt_task(void *argument)
{
    (void)argument;
    game_delay_ms(1200);

    while (1) {
        if (!g_mqtt_ready) {
            if ((wifi_connect() == 0) && (mqtt_connect() == 0)) {
                printf("Game MQTT connected\r\n");
            } else {
                printf("Game MQTT connect retry later\r\n");
                game_delay_ms(5000);
                continue;
            }
        }

        mqtt_lock();
        int yield_rc = MQTTYield(&g_mqtt_client, 1000);
        mqtt_unlock();
        if (yield_rc != 0) {
            printf("MQTT yield failed, reconnect\r\n");
            mqtt_close();
            game_delay_ms(3000);
        }
        game_delay_ms(50);
    }
}

void game_mqtt_start(void)
{
    osThreadAttr_t attr = {0};

    if (g_mqtt_mutex == NULL) {
        g_mqtt_mutex = osMutexNew(NULL);
    }
    attr.name = "GameMqtt";
    attr.stack_size = MQTT_TASK_STACK_SIZE;
    attr.priority = MQTT_TASK_PRIO;
    if (osThreadNew(game_mqtt_task, NULL, &attr) == NULL) {
        printf("create GameMqtt failed\r\n");
    }
}
