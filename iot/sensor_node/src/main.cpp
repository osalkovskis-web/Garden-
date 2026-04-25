#include <Arduino.h>
#include <esp_now.h>
#include <WiFi.h>
#include <esp_sleep.h>
#include <EEPROM.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <ArduinoJson.h>

// ── Konfigurācija ────────────────────────────────────────────────────────────
// Nodot kompilatoram: -DNODE_ID='"g01"' vai mainīt šeit
#ifndef NODE_ID
#define NODE_ID "g01"
#endif

// Vārtejas MAC adrese — jānolasa no T-SIM7000G seriālā monitora ar AT+CGSN
// vai WiFi.macAddress(). Aizpildīt pirms uzliešanas!
static uint8_t GATEWAY_MAC[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

// GPIO
constexpr int PIN_SENSOR_PWR  = 32; // MOSFET gate — ieslēdz sensoru
constexpr int PIN_MOISTURE    = 34; // ADC (tikai input, nav pull-up!)
constexpr int PIN_BATT        = 35; // ADC voltage divider 100k/100k
constexpr int PIN_TEMP        = 25; // DS18B20 data

// Mērīšanas parametri
constexpr int   ADC_SAMPLES      = 16;   // vidējā no N mērījumiem
constexpr int   SENSOR_WARMUP_MS = 200;  // ms pēc barošanas ieslēgšanas
constexpr int   SLEEP_MIN        = 15;   // deep sleep garums minūtēs
constexpr float BATT_DIVIDER     = 2.0f; // voltage divider koeficients (100k/100k)
constexpr float ADC_REF          = 3.3f;
constexpr int   ADC_MAX          = 4095;

// EEPROM adreses kalibrācijai
constexpr int EE_MAGIC    = 0;   // 4 baiti — 0xCAFEBABE ja kalibrēts
constexpr int EE_DRY      = 4;   // 2 baiti uint16 — sauss ADC
constexpr int EE_WET      = 6;   // 2 baiti uint16 — mitrs ADC
constexpr uint32_t MAGIC  = 0xCAFEBABE;

// ── Struktūras ────────────────────────────────────────────────────────────────
struct __attribute__((packed)) SensorPayload {
    char    node[6];
    int16_t moisture_raw;
    uint8_t moisture_pct;
    uint16_t battery_mv;
    int16_t temp_c10;     // grādi × 10, lai ietaupītu vietu (18.5° → 185)
    int8_t  rssi;
};

// ── Globālie ─────────────────────────────────────────────────────────────────
static volatile bool ack_received = false;
OneWire oneWire(PIN_TEMP);
DallasTemperature ds18b20(&oneWire);

// ── Kalibrācija ───────────────────────────────────────────────────────────────
struct Calib { uint16_t dry; uint16_t wet; bool valid; };

Calib loadCalib() {
    EEPROM.begin(16);
    uint32_t magic;
    EEPROM.get(EE_MAGIC, magic);
    if (magic != MAGIC) return {3200, 1200, false};
    uint16_t dry, wet;
    EEPROM.get(EE_DRY, dry);
    EEPROM.get(EE_WET, wet);
    return {dry, wet, true};
}

// ── ADC mērīšana ─────────────────────────────────────────────────────────────
uint16_t readADCmedian(int pin) {
    uint16_t buf[ADC_SAMPLES];
    for (int i = 0; i < ADC_SAMPLES; i++) {
        buf[i] = analogRead(pin);
        delay(2);
    }
    // insertion sort + vidējais bez galējiem 4
    for (int i = 1; i < ADC_SAMPLES; i++) {
        uint16_t key = buf[i];
        int j = i - 1;
        while (j >= 0 && buf[j] > key) { buf[j+1] = buf[j]; j--; }
        buf[j+1] = key;
    }
    uint32_t sum = 0;
    for (int i = 2; i < ADC_SAMPLES - 2; i++) sum += buf[i];
    return sum / (ADC_SAMPLES - 4);
}

uint8_t rawToPercent(uint16_t raw, const Calib& c) {
    if (raw >= c.dry) return 0;
    if (raw <= c.wet) return 100;
    return (uint8_t)(100UL * (c.dry - raw) / (c.dry - c.wet));
}

uint16_t readBattMv() {
    uint16_t raw = readADCmedian(PIN_BATT);
    return (uint16_t)((float)raw / ADC_MAX * ADC_REF * BATT_DIVIDER * 1000.0f);
}

// ── ESP-NOW ───────────────────────────────────────────────────────────────────
void onSent(const uint8_t* mac, esp_now_send_status_t status) {
    ack_received = (status == ESP_NOW_SEND_SUCCESS);
}

bool espNowSend(const SensorPayload& pld) {
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    if (esp_now_init() != ESP_OK) return false;

    esp_now_register_send_cb(onSent);

    esp_now_peer_info_t peer{};
    memcpy(peer.peer_addr, GATEWAY_MAC, 6);
    peer.channel = 0;
    peer.encrypt = false;
    if (esp_now_add_peer(&peer) != ESP_OK) {
        esp_now_deinit();
        return false;
    }

    ack_received = false;
    esp_now_send(GATEWAY_MAC, (uint8_t*)&pld, sizeof(pld));

    // Gaida ACK max 300ms
    uint32_t t = millis();
    while (!ack_received && millis() - t < 300) delay(5);

    esp_now_deinit();
    return ack_received;
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    delay(100);

    Serial.printf("\n[%s] Wake — ", NODE_ID);

    // Ieslēdz sensoru caur MOSFET
    pinMode(PIN_SENSOR_PWR, OUTPUT);
    digitalWrite(PIN_SENSOR_PWR, HIGH);
    delay(SENSOR_WARMUP_MS);

    // ADC konfigurācija
    analogSetAttenuation(ADC_11db);
    analogSetWidth(12);

    // Kalibrācija
    Calib cal = loadCalib();
    if (!cal.valid) Serial.print("(nav kalibrācijas, default vērtības) ");

    // Mitrums
    uint16_t raw = readADCmedian(PIN_MOISTURE);
    uint8_t  pct = rawToPercent(raw, cal);
    Serial.printf("raw=%d pct=%d%%", raw, pct);

    // Baterija
    uint16_t batt_mv = readBattMv();
    Serial.printf(" batt=%dmV", batt_mv);

    // Temperatūra
    ds18b20.begin();
    ds18b20.requestTemperatures();
    float temp = ds18b20.getTempCByIndex(0);
    int16_t temp10 = (temp > -100.0f) ? (int16_t)(temp * 10) : INT16_MIN;
    Serial.printf(" temp=%.1f°C", temp);

    // Izslēdz sensoru (taupa bateriju)
    digitalWrite(PIN_SENSOR_PWR, LOW);

    // Sagatavo payload
    SensorPayload pld{};
    strncpy(pld.node, NODE_ID, sizeof(pld.node) - 1);
    pld.moisture_raw = (int16_t)raw;
    pld.moisture_pct = pct;
    pld.battery_mv   = batt_mv;
    pld.temp_c10     = temp10;
    pld.rssi         = (int8_t)WiFi.RSSI();

    // Sūta
    bool ok = espNowSend(pld);
    Serial.printf(" → ESP-NOW %s\n", ok ? "OK" : "FAIL");

    WiFi.mode(WIFI_OFF);

    Serial.printf("Deep sleep %d min...\n", SLEEP_MIN);
    Serial.flush();

    esp_sleep_enable_timer_wakeup((uint64_t)SLEEP_MIN * 60 * 1000000ULL);
    esp_deep_sleep_start();
}

void loop() {}
