#include <Arduino.h>
#include <esp_now.h>
#include <WiFi.h>
#include <ArduinoJson.h>

#define TINY_GSM_MODEM_SIM7000
#include <TinyGsmClient.h>
#include <PubSubClient.h>

// ── Konfigurācija ────────────────────────────────────────────────────────────
// SIM karte
const char APN[]      = "internet";   // LMT: "internet", Tele2: "internet.tele2.lv"
const char SIM_USER[] = "";
const char SIM_PASS[] = "";

// MQTT brokeris (HiveMQ free tier)
// Reģistrēties: https://console.hivemq.cloud → free cluster
const char MQTT_HOST[]  = "YOUR-CLUSTER.s2.eu.hivemq.cloud";
const char MQTT_USER[]  = "garden_gw";
const char MQTT_PASS[]  = "CHANGE_ME";
const int  MQTT_PORT    = 8883;
const char MQTT_CLIENT[] = "garden_gateway_01";

// MQTT tēmas
const char TOPIC_STATUS[]    = "garden/gateway/status";
const char TOPIC_IRRIGATE[]  = "garden/irrigation/command";
const char TOPIC_SENSORS[]   = "garden/sensors/";   // + node_id + "/state"

// T-SIM7000G sērijas un barošanas pini
constexpr int SIM_TX  = 27;
constexpr int SIM_RX  = 26;
constexpr int SIM_PWR = 4;

// GPIO
constexpr int PIN_RELAY = 12;
constexpr int PIN_LED   = 13;

// Intervāli
constexpr uint32_t HEARTBEAT_MS  = 5UL * 60 * 1000;  // 5 min
constexpr uint32_t MQTT_RETRY_MS = 30 * 1000;         // 30 s

// ── Globālie ─────────────────────────────────────────────────────────────────
HardwareSerial simSerial(1);
TinyGsm        modem(simSerial);
TinyGsmClientSecure gsmClient(modem);
PubSubClient   mqtt(gsmClient);

static uint32_t lastHeartbeat  = 0;
static uint32_t lastMqttRetry  = 0;
static uint32_t uptimeSec      = 0;
static bool     mqttConnected  = false;

struct __attribute__((packed)) SensorPayload {
    char    node[6];
    int16_t moisture_raw;
    uint8_t moisture_pct;
    uint16_t battery_mv;
    int16_t temp_c10;
    int8_t  rssi;
};

// ── SIM7000G ──────────────────────────────────────────────────────────────────
void simPowerOn() {
    pinMode(SIM_PWR, OUTPUT);
    digitalWrite(SIM_PWR, HIGH);
    delay(1000);
    digitalWrite(SIM_PWR, LOW);
    delay(2000);
}

bool modemInit() {
    simSerial.begin(9600, SERIAL_8N1, SIM_RX, SIM_TX);
    delay(3000);
    Serial.println("[GSM] Inicializē modemu...");
    if (!modem.init()) {
        Serial.println("[GSM] KĻŪDA: modem.init() neizdevās");
        return false;
    }
    Serial.printf("[GSM] Modelis: %s\n", modem.getModemInfo().c_str());
    Serial.println("[GSM] Gaida tīklu...");
    if (!modem.waitForNetwork(60000L)) {
        Serial.println("[GSM] KĻŪDA: tīkls nav pieejams");
        return false;
    }
    Serial.printf("[GSM] Operators: %s  RSSI: %d\n",
        modem.getOperator().c_str(), modem.getSignalQuality());
    if (!modem.gprsConnect(APN, SIM_USER, SIM_PASS)) {
        Serial.println("[GSM] KĻŪDA: GPRS savienojums neizdevās");
        return false;
    }
    Serial.printf("[GSM] IP: %s\n", modem.localIP().toString().c_str());
    return true;
}

// ── MQTT ──────────────────────────────────────────────────────────────────────
void onMqttMessage(char* topic, byte* payload, unsigned int len) {
    String t(topic);
    String msg((char*)payload, len);

    if (t == TOPIC_IRRIGATE) {
        // Payload: {"action":"on","duration_sec":120}
        JsonDocument doc;
        if (deserializeJson(doc, msg) == DeserializationError::Ok) {
            const char* action = doc["action"] | "off";
            uint32_t dur = doc["duration_sec"] | 0;
            if (strcmp(action, "on") == 0 && dur > 0) {
                Serial.printf("[IRRIGATE] Ieslēdz %lus\n", (unsigned long)dur);
                digitalWrite(PIN_RELAY, HIGH);
                digitalWrite(PIN_LED, HIGH);
                delay(dur * 1000UL);
                digitalWrite(PIN_RELAY, LOW);
                digitalWrite(PIN_LED, LOW);
                // Apstiprinājums atpakaļ
                mqtt.publish("garden/irrigation/status", "{\"status\":\"done\"}");
            } else {
                digitalWrite(PIN_RELAY, LOW);
                digitalWrite(PIN_LED, LOW);
                mqtt.publish("garden/irrigation/status", "{\"status\":\"off\"}");
            }
        }
    }
}

bool mqttConnect() {
    if (!modem.isGprsConnected()) {
        Serial.println("[MQTT] GPRS nav savienots, restartē...");
        modem.gprsConnect(APN, SIM_USER, SIM_PASS);
        delay(3000);
    }
    Serial.printf("[MQTT] Savienojas ar %s...\n", MQTT_HOST);
    mqtt.setServer(MQTT_HOST, MQTT_PORT);
    mqtt.setCallback(onMqttMessage);
    mqtt.setKeepAlive(60);
    mqtt.setSocketTimeout(10);

    if (!mqtt.connect(MQTT_CLIENT, MQTT_USER, MQTT_PASS)) {
        Serial.printf("[MQTT] KĻŪDA: kods %d\n", mqtt.state());
        return false;
    }
    mqtt.subscribe(TOPIC_IRRIGATE);
    Serial.println("[MQTT] Savienots");
    return true;
}

void publishHeartbeat() {
    JsonDocument doc;
    doc["gw"]      = "garden_01";
    doc["uptime"]  = uptimeSec;
    doc["rssi"]    = modem.getSignalQuality();
    doc["ip"]      = modem.localIP().toString();
    doc["relay"]   = digitalRead(PIN_RELAY);

    char buf[200];
    serializeJson(doc, buf);
    mqtt.publish(TOPIC_STATUS, buf, true);
}

// ── ESP-NOW uztvērējs ─────────────────────────────────────────────────────────
void onReceive(const uint8_t* mac, const uint8_t* data, int len) {
    if (len != sizeof(SensorPayload)) return;
    SensorPayload pld;
    memcpy(&pld, data, sizeof(pld));
    pld.node[5] = '\0';

    Serial.printf("[ESP-NOW] %s: moisture=%d%% raw=%d batt=%dmV temp=%.1f°C\n",
        pld.node, pld.moisture_pct, pld.moisture_raw,
        pld.battery_mv, pld.temp_c10 / 10.0f);

    if (!mqttConnected) return;

    // Tēma: garden/sensors/g01/state
    char topic[50];
    snprintf(topic, sizeof(topic), "%s%s/state", TOPIC_SENSORS, pld.node);

    JsonDocument doc;
    doc["node"]         = pld.node;
    doc["moisture_raw"] = pld.moisture_raw;
    doc["moisture_pct"] = pld.moisture_pct;
    doc["battery_mv"]   = pld.battery_mv;
    doc["temp_c"]       = pld.temp_c10 / 10.0f;
    doc["rssi_node"]    = pld.rssi;

    char buf[256];
    serializeJson(doc, buf);
    mqtt.publish(topic, buf, false);

    // HA MQTT auto-discovery (publicē tikai pirmo reizi)
    publishHADiscovery(pld.node);
}

void publishHADiscovery(const char* nodeId) {
    // Statiska atmiņa — publicē tikai vienu reizi katram mezglam
    static char published[16][6] = {};
    static int  count = 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(published[i], nodeId) == 0) return;
    }
    if (count < 16) strncpy(published[count++], nodeId, 5);

    // Mitrums
    char cfg_topic[80], payload[400];
    snprintf(cfg_topic, sizeof(cfg_topic),
        "homeassistant/sensor/%s_moisture/config", nodeId);
    snprintf(payload, sizeof(payload),
        "{\"name\":\"%s mitrums\","
        "\"state_topic\":\"garden/sensors/%s/state\","
        "\"value_template\":\"{{ value_json.moisture_pct }}\","
        "\"unit_of_measurement\":\"%%\","
        "\"device_class\":\"moisture\","
        "\"unique_id\":\"%s_moisture\","
        "\"device\":{\"identifiers\":[\"%s\"],\"name\":\"D\\u0101rza sensors %s\"}}",
        nodeId, nodeId, nodeId, nodeId, nodeId);
    mqtt.publish(cfg_topic, payload, true);

    // Baterija
    snprintf(cfg_topic, sizeof(cfg_topic),
        "homeassistant/sensor/%s_battery/config", nodeId);
    snprintf(payload, sizeof(payload),
        "{\"name\":\"%s baterija\","
        "\"state_topic\":\"garden/sensors/%s/state\","
        "\"value_template\":\"{{ (value_json.battery_mv | int / 1000) | round(2) }}\","
        "\"unit_of_measurement\":\"V\","
        "\"device_class\":\"voltage\","
        "\"unique_id\":\"%s_battery\","
        "\"device\":{\"identifiers\":[\"%s\"]}}",
        nodeId, nodeId, nodeId, nodeId);
    mqtt.publish(cfg_topic, payload, true);

    // Temperatūra
    snprintf(cfg_topic, sizeof(cfg_topic),
        "homeassistant/sensor/%s_temp/config", nodeId);
    snprintf(payload, sizeof(payload),
        "{\"name\":\"%s temperatūra\","
        "\"state_topic\":\"garden/sensors/%s/state\","
        "\"value_template\":\"{{ value_json.temp_c }}\","
        "\"unit_of_measurement\":\"°C\","
        "\"device_class\":\"temperature\","
        "\"unique_id\":\"%s_temp\","
        "\"device\":{\"identifiers\":[\"%s\"]}}",
        nodeId, nodeId, nodeId, nodeId);
    mqtt.publish(cfg_topic, payload, true);
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    Serial.println("\n[GW] Dārza vārteja sākas...");

    pinMode(PIN_RELAY, OUTPUT);
    pinMode(PIN_LED,   OUTPUT);
    digitalWrite(PIN_RELAY, LOW);
    digitalWrite(PIN_LED,   LOW);

    // ESP-NOW
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    if (esp_now_init() != ESP_OK) {
        Serial.println("[GW] ESP-NOW init KĻŪDA");
    } else {
        esp_now_register_recv_cb(onReceive);
        Serial.printf("[GW] MAC: %s\n", WiFi.macAddress().c_str());
        Serial.println("[GW] ESP-NOW gatavs");
    }

    // Modens
    simPowerOn();
    if (modemInit()) {
        mqttConnected = mqttConnect();
        if (mqttConnected) {
            publishHeartbeat();
            digitalWrite(PIN_LED, HIGH);
        }
    }

    lastHeartbeat = millis();
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
    uint32_t now = millis();
    uptimeSec = now / 1000;

    // MQTT keepalive
    if (mqttConnected) {
        if (!mqtt.loop()) {
            mqttConnected = false;
            Serial.println("[MQTT] Savienojums zaudēts");
        }
    }

    // MQTT reconnect
    if (!mqttConnected && (now - lastMqttRetry > MQTT_RETRY_MS)) {
        lastMqttRetry = now;
        mqttConnected = mqttConnect();
        if (mqttConnected) digitalWrite(PIN_LED, HIGH);
        else               digitalWrite(PIN_LED, LOW);
    }

    // Heartbeat
    if (mqttConnected && (now - lastHeartbeat > HEARTBEAT_MS)) {
        lastHeartbeat = now;
        publishHeartbeat();
    }

    delay(10);
}
