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

// ── Kalibrācijas mode ─────────────────────────────────────────────────────────
// Aktivizējas ja 2 sekunžu laikā pēc boot tiek saņemts seriālais signāls.
// calibrate.py savienojas ar šo protokolu.

void saveCalib(uint16_t dry, uint16_t wet) {
    EEPROM.begin(16);
    uint32_t magic = MAGIC;
    EEPROM.put(EE_MAGIC, magic);
    EEPROM.put(EE_DRY,   dry);
    EEPROM.put(EE_WET,   wet);
    EEPROM.commit();
}

void runCalibrationMode() {
    Serial.println("\n[CALIB] Kalibrācijas mode aktīvs. Gaida komandas...");
    Serial.println("[CALIB] Komandas: CALIB_READ | CALIB_SAVE:dry:wet | CALIB_STATUS | CALIB_EXIT");

    pinMode(PIN_SENSOR_PWR, OUTPUT);
    analogSetAttenuation(ADC_11db);
    analogSetWidth(12);

    String buf;
    buf.reserve(32);

    while (true) {
        while (Serial.available()) {
            char c = Serial.read();
            if (c == '\n' || c == '\r') {
                buf.trim();
                if (buf.length() == 0) { buf = ""; continue; }

                if (buf == "CALIB_READ") {
                    // Ieslēdz sensoru, streamo 20 ADC vērtības
                    digitalWrite(PIN_SENSOR_PWR, HIGH);
                    delay(SENSOR_WARMUP_MS);
                    for (int i = 0; i < 20; i++) {
                        uint16_t adc = analogRead(PIN_MOISTURE);
                        Serial.printf("ADC:%d\n", adc);
                        delay(80);
                    }
                    digitalWrite(PIN_SENSOR_PWR, LOW);

                } else if (buf.startsWith("CALIB_SAVE:")) {
                    // Formāts: CALIB_SAVE:3200:1200
                    int colon1 = buf.indexOf(':', 11);
                    if (colon1 < 0) { Serial.println("ERR:bad format"); buf = ""; continue; }
                    uint16_t dry = (uint16_t)buf.substring(11, colon1).toInt();
                    uint16_t wet = (uint16_t)buf.substring(colon1 + 1).toInt();
                    if (dry <= wet) { Serial.println("ERR:dry must be > wet"); buf = ""; continue; }
                    saveCalib(dry, wet);
                    Serial.printf("CALIB_OK dry=%d wet=%d\n", dry, wet);

                } else if (buf == "CALIB_STATUS") {
                    Calib cal = loadCalib();
                    if (cal.valid) {
                        Serial.printf("CALIB_STATUS:dry=%d,wet=%d,valid=1\n", cal.dry, cal.wet);
                    } else {
                        Serial.println("CALIB_STATUS:valid=0,defaults=3200:1200");
                    }
                    // Arī nolasa pašreizējo ADC
                    digitalWrite(PIN_SENSOR_PWR, HIGH);
                    delay(SENSOR_WARMUP_MS);
                    uint16_t raw = readADCmedian(PIN_MOISTURE);
                    uint8_t  pct = rawToPercent(raw, cal);
                    uint16_t batt = readBattMv();
                    digitalWrite(PIN_SENSOR_PWR, LOW);
                    Serial.printf("CALIB_STATUS:current_adc=%d,pct=%d,batt_mv=%d\n", raw, pct, batt);

                } else if (buf == "CALIB_EXIT") {
                    Serial.println("[CALIB] Iziet uz normālo mode. Restartē...");
                    Serial.flush();
                    delay(200);
                    ESP.restart();

                } else {
                    Serial.printf("ERR:unknown command '%s'\n", buf.c_str());
                }
                buf = "";
            } else {
                buf += c;
            }
        }
        delay(10);
    }
}

// ── Normālais mērīšanas cikls ─────────────────────────────────────────────────
void runNormalMode() {
    Serial.printf("\n[%s] Wake — ", NODE_ID);

    pinMode(PIN_SENSOR_PWR, OUTPUT);
    digitalWrite(PIN_SENSOR_PWR, HIGH);
    delay(SENSOR_WARMUP_MS);

    analogSetAttenuation(ADC_11db);
    analogSetWidth(12);

    Calib cal = loadCalib();
    if (!cal.valid) Serial.print("(nav kalibrācijas) ");

    uint16_t raw     = readADCmedian(PIN_MOISTURE);
    uint8_t  pct     = rawToPercent(raw, cal);
    uint16_t batt_mv = readBattMv();
    Serial.printf("raw=%d pct=%d%% batt=%dmV", raw, pct, batt_mv);

    ds18b20.begin();
    ds18b20.requestTemperatures();
    float   temp   = ds18b20.getTempCByIndex(0);
    int16_t temp10 = (temp > -100.0f) ? (int16_t)(temp * 10) : INT16_MIN;
    Serial.printf(" temp=%.1f°C", temp);

    digitalWrite(PIN_SENSOR_PWR, LOW);

    SensorPayload pld{};
    strncpy(pld.node, NODE_ID, sizeof(pld.node) - 1);
    pld.moisture_raw = (int16_t)raw;
    pld.moisture_pct = pct;
    pld.battery_mv   = batt_mv;
    pld.temp_c10     = temp10;
    pld.rssi         = (int8_t)WiFi.RSSI();

    bool ok = espNowSend(pld);
    Serial.printf(" → ESP-NOW %s\n", ok ? "OK" : "FAIL");

    WiFi.mode(WIFI_OFF);
    Serial.printf("Deep sleep %d min...\n", SLEEP_MIN);
    Serial.flush();

    esp_sleep_enable_timer_wakeup((uint64_t)SLEEP_MIN * 60 * 1000000ULL);
    esp_deep_sleep_start();
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    delay(100);

    // Kalibrācijas mode detektors: ja 2s laikā USB sūta datus → calib mode
    bool calibMode = false;
    uint32_t t0 = millis();
    while (millis() - t0 < 2000) {
        if (Serial.available()) { calibMode = true; break; }
    }

    if (calibMode) runCalibrationMode();
    else           runNormalMode();
}

void loop() {}
