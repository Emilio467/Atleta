// M5StickC Plus2: sensores reais, sessão, estimativas identificadas e MQTT/MySQL.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <M5Unified.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <Update.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <BLESecurity.h>
#include <esp_timer.h>
#include <esp_ota_ops.h>
#include <mbedtls/md.h>
#include <mbedtls/sha256.h>
#include <mbedtls/gcm.h>
#include <mbedtls/platform_util.h>
#include <atomic>
#include "activity.h"

namespace {
constexpr char VERSION[] = "2.2.5";
constexpr uint32_t IMU_MS = 20, TELEMETRY_MS = 1000, BLUETOOTH_SUMMARY_MS = 2000;
constexpr size_t MAX_CONFIG = 2048, MAX_PAYLOAD = 2048;
constexpr char BLE_SERVICE[] = "747e1000-7e91-4e27-a560-697562673001";
constexpr char BLE_SUMMARY[] = "747e1001-7e91-4e27-a560-697562673001";
constexpr char BLE_SESSION[] = "747e1002-7e91-4e27-a560-697562673001";
constexpr char BLE_CONTROL[] = "747e1003-7e91-4e27-a560-697562673001";
constexpr char BLE_WIFI_CONTROL[] = "747e1004-7e91-4e27-a560-697562673001";
constexpr char BLE_WIFI_STATUS[] = "747e1005-7e91-4e27-a560-697562673001";
constexpr char BLE_PREFERENCE[] = "ble-enabled";
Preferences prefs;
String ssid, wifiPassword, host, user, mqttPassword, deviceId, topic, serialLine;
uint16_t mqttPort = 1883;
float weightKg = 0, stepLengthM = 0, activityMet = 0;
uint32_t athleteId = 0;
char bootId[17], sessionId[32];
uint32_t sequence = 0, sessionNumber = 0, lastImu = 0, lastGoodImu = 0, lastTelemetry = 0, lastDisplay = 0;
uint32_t lastBluetoothSummary = 0;
uint64_t activeMs = 0, lastTick = 0;
bool running = true, discardLine = false, imuHealthy = false;
float ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0;
int batteryMv = 0, batteryPercent = -1, page = 0;
StepCounter steps;
bool imuTrace = false;
bool imuTraceMqtt = false;
uint32_t traceStarted = 0, traceSamples = 0, traceDropped = 0;
// Dá tempo de retirar o USB, colocar no pulso e concluir os testes por Wi-Fi.
constexpr uint32_t MAX_TRACE_MS = 600000;
struct TraceSample {
  uint32_t ms, cadence, pending, count;
  float accel[3], gyro[3], filtered;
  uint8_t event, active;
};
TraceSample traceBatch[5];
size_t traceBatchSize = 0;
struct Message { char payload[MAX_PAYLOAD]; };
QueueHandle_t outgoing = nullptr;
std::atomic<bool> mqttOnline{false};
std::atomic<int> mqttError{-1};
std::atomic<int> wifiReason{0};
std::atomic<uint32_t> sentCount{0};
BLEServer* bleServer = nullptr;
BLECharacteristic* bleCharacteristic = nullptr;
BLECharacteristic* bleSession = nullptr;
struct WatchCommand { uint8_t action; uint32_t token, link; };
QueueHandle_t watchCommands = nullptr;
uint32_t watchToken = 0;
bool watchFinished = false;
bool bleEnabled = false, bleInitialized = false;
std::atomic<bool> bleConnected{false}, bleRestart{false};
std::atomic<int> bleDisconnectReason{-1};
constexpr int OTA_PAGE = 3;
constexpr int BLUETOOTH_WIFI_PAGE = 4;
constexpr char WIFI_SETUP_DOMAIN[] = "ATLETA-WIFI/1";
constexpr size_t WIFI_SETUP_LIMIT = 768;
constexpr uint32_t WIFI_SETUP_WINDOW_MS = 180000;
enum class WifiSetup : uint8_t { CLOSED, READY, TESTING, SAVED, AUTH_ERROR, INVALID, NETWORK_ERROR, STORAGE_ERROR, BUSY };
struct WifiFrame { uint32_t link; uint8_t size; uint8_t bytes[20]; };
struct WifiTrial { char name[33], password[65]; };
struct WifiScan { char ssid[33]; };
BLECharacteristic* bleWifiStatus = nullptr;
QueueHandle_t wifiFrames = nullptr, wifiTrials = nullptr, wifiResults = nullptr, wifiScans = nullptr;
std::atomic<uint32_t> bleLink{0}, wifiIpEvents{0};
std::atomic<bool> wifiFrameOverflow{false};
bool wifiSetupOpen = false, wifiSetupTemporaryBle = false;
WifiSetup wifiSetupStatus = WifiSetup::CLOSED;
uint32_t wifiSetupOpenedAt = 0, wifiRebootAt = 0, wifiFrameLink = 0;
uint8_t wifiChallenge[16]{};
char wifiSetupCode[17]{};
uint8_t wifiFrameData[WIFI_SETUP_LIMIT]{};
size_t wifiFrameLength = 0;
bool wifiFrameStarted = false;
String pendingWifiConfig;
constexpr uint32_t OTA_WINDOW_MS = 5UL * 60 * 1000;
constexpr uint32_t OTA_CLIENT_TIMEOUT_MS = 8000;
constexpr uint16_t OTA_PORT = 3232;
constexpr char OTA_DISCOVERY[] = "ATLETA-OTA-DISCOVERY/1";
constexpr char OTA_UPLOAD[] = "ATLETA-OTA/1";
WiFiUDP otaDiscovery;
WiFiServer otaServer(OTA_PORT);
WiFiClient otaClient;
String otaKey;
char otaNonce[33]{};
char otaHeader[196]{}, otaExpectedHash[65]{};
mbedtls_sha256_context otaHash;
size_t otaHeaderSize = 0, otaRemaining = 0, otaTotal = 0;
uint32_t otaOpenedAt = 0, otaClientActivity = 0;
bool otaOpen = false, otaReceiving = false;
const char* otaMessage = "Segure B para liberar.";

bool hasOpenAppWorkout() {
  return watchToken != 0 && !watchFinished;
}

void closeOta(const char* message) {
  if (otaReceiving) {
    Update.abort();
    mbedtls_sha256_free(&otaHash);
    otaReceiving = false;
  }
  otaClient.stop();
  if (otaOpen) {
    otaDiscovery.stop();
    otaServer.end();
    otaOpen = false;
    Serial.println("OTA_CLOSED");
  }
  otaMessage = message;
}

bool validOtaKey(const String& key) {
  if (key.length() != 64) return false;
  for (char c : key) {
    if (!(c >= 'a' && c <= 'f') && !(c >= '0' && c <= '9')) return false;
  }
  return true;
}

void loadOtaKey() {
  if (!prefs.begin("atleta-lab", true)) return;
  otaKey = prefs.getString("ota-key", "");
  prefs.end();
  if (!validOtaKey(otaKey)) otaKey = "";
}

void pairOta(const String& key) {
  if (!validOtaKey(key) || !prefs.begin("atleta-lab", false)) {
    Serial.println("OTA_PAIR_ERROR");
    return;
  }
  bool stored = prefs.putString("ota-key", key) == key.length();
  prefs.end();
  if (stored) {
    closeOta("Vinculado. Segure B.");
    otaKey = key;
  }
  Serial.println(stored ? "OTA_PAIR_OK" : "OTA_PAIR_ERROR");
}

void otaHex(const unsigned char* bytes, size_t count, char* output) {
  constexpr char digits[] = "0123456789abcdef";
  for (size_t i = 0; i < count; ++i) {
    output[2 * i] = digits[bytes[i] >> 4];
    output[2 * i + 1] = digits[bytes[i] & 15];
  }
  output[2 * count] = '\0';
}

bool otaSignature(const char* text, char* result) {
  unsigned char digest[32];
  const auto* sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (mbedtls_md_hmac(sha256,
                       reinterpret_cast<const unsigned char*>(otaKey.c_str()), otaKey.length(),
                       reinterpret_cast<const unsigned char*>(text), strlen(text), digest) != 0) {
    return false;
  }
  otaHex(digest, sizeof(digest), result);
  return true;
}

bool otaMatches(const char* a, const char* b) {
  if (strlen(a) != 64 || strlen(b) != 64) return false;
  unsigned difference = 0;
  for (size_t i = 0; i < 64; ++i) difference |= static_cast<unsigned>(a[i] ^ b[i]);
  return difference == 0;
}

void openOta() {
  if (wifiSetupOpen || !pendingWifiConfig.isEmpty() || wifiRebootAt) {
    otaMessage = "Termine a configuracao do Wi-Fi.";
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    otaMessage = "Conecte o Wi-Fi primeiro.";
    return;
  }
  if (hasOpenAppWorkout()) {
    otaMessage = "Finalize o treino no app.";
    return;
  }
  if (otaKey.isEmpty()) {
    otaMessage = "Vincule por USB no painel.";
    return;
  }
  const auto* nextPartition = esp_ota_get_next_update_partition(nullptr);
  if (!nextPartition || nextPartition == esp_ota_get_running_partition()) {
    otaMessage = "Instale o firmware por USB.";
    return;
  }

  if (!otaDiscovery.begin(OTA_PORT)) {
    otaMessage = "Falha ao liberar OTA.";
    return;
  }
  otaServer.begin();
  unsigned char nonce[16];
  esp_fill_random(nonce, sizeof(nonce));
  otaHex(nonce, sizeof(nonce), otaNonce);
  otaOpen = true;
  otaOpenedAt = millis();
  Serial.println("OTA_READY");
}

void announceOta() {
  auto packet = otaDiscovery.parsePacket();
  if (!packet) return;
  char query[sizeof(OTA_DISCOVERY)]{};
  if (packet != sizeof(OTA_DISCOVERY) - 1 ||
      otaDiscovery.read(query, packet) != packet || strcmp(query, OTA_DISCOVERY) != 0) {
    otaDiscovery.flush();
    return;
  }
  char reply[96], mac[65];
  snprintf(reply, sizeof(reply), "%s %s %s", OTA_DISCOVERY, otaNonce, VERSION);
  if (otaSignature(reply, mac) && otaDiscovery.beginPacket(otaDiscovery.remoteIP(), otaDiscovery.remotePort())) {
    otaDiscovery.printf("%s %s", reply, mac);
    otaDiscovery.endPacket();
  }
}

bool beginOtaImage() {
  // The MAC binds the image size and digest to this maintenance window.
  char protocol[16], nonce[33], length[11], digest[65], signature[65], payload[130], mac[65];
  int consumed = 0;
  if (sscanf(otaHeader, "%15s %32s %10[0-9] %64s %64s%n", protocol, nonce, length, digest,
             signature, &consumed) != 5 || consumed != otaHeaderSize ||
      strcmp(protocol, OTA_UPLOAD) != 0 || strcmp(nonce, otaNonce) != 0 || strlen(digest) != 64) {
    return false;
  }
  snprintf(payload, sizeof(payload), "%s %s %s %s", OTA_UPLOAD, nonce, length, digest);
  const auto* partition = esp_ota_get_next_update_partition(nullptr);
  unsigned long size = strtoul(length, nullptr, 10);
  if (!otaSignature(payload, mac) || !otaMatches(mac, signature) ||
      !partition || size == 0 || size > partition->size || !Update.begin(size, U_FLASH)) {
    return false;
  }
  memcpy(otaExpectedHash, digest, sizeof(otaExpectedHash));
  mbedtls_sha256_init(&otaHash);
  if (mbedtls_sha256_starts_ret(&otaHash, 0) != 0) {
    mbedtls_sha256_free(&otaHash);
    Update.abort();
    return false;
  }
  otaRemaining = otaTotal = size;
  otaReceiving = true;
  otaClient.print("READY\n");
  Serial.println("OTA_START");
  return true;
}

void receiveOtaImage() {
  static uint8_t chunk[2048];
  size_t readable = min(otaRemaining, sizeof(chunk));
  int received = otaClient.read(chunk, min(readable, static_cast<size_t>(otaClient.available())));
  if (received <= 0) return;
  if (Update.write(chunk, received) != static_cast<size_t>(received) ||
      mbedtls_sha256_update_ret(&otaHash, chunk, received) != 0) {
    otaClient.print("ERR\n");
    closeOta("Falha na gravacao.");
    return;
  }
  otaRemaining -= received;
  if (otaRemaining) return;

  unsigned char digest[32];
  char hex[65];
  bool valid = mbedtls_sha256_finish_ret(&otaHash, digest) == 0;
  if (valid) otaHex(digest, sizeof(digest), hex);
  if (!valid || !otaMatches(hex, otaExpectedHash) || !Update.end()) {
    otaClient.print("ERR\n");
    closeOta("Imagem recusada. Segure B.");
    return;
  }
  otaClient.print("OK\n");
  otaClient.stop();
  Serial.println("OTA_OK reboot");
  delay(200);
  ESP.restart();
}

void handleOta(uint32_t now) {
  if (!otaOpen) return;
  if (WiFi.status() != WL_CONNECTED || hasOpenAppWorkout() ||
      (!otaReceiving && now - otaOpenedAt >= OTA_WINDOW_MS)) {
    closeOta("OTA encerrado. Segure B.");
    return;
  }
  if (!otaReceiving) announceOta();
  if (!otaClient) {
    if (otaReceiving) {
      closeOta("Envio interrompido.");
      return;
    }
    otaClient = otaServer.available();
    otaHeaderSize = 0;
    otaClientActivity = now;
  }
  if (!otaClient) return;
  if (now - otaClientActivity >= OTA_CLIENT_TIMEOUT_MS) {
    if (otaReceiving) closeOta("Envio interrompido.");
    else otaClient.stop();
    return;
  }
  if (!otaClient.available()) return;
  otaClientActivity = now;
  if (otaReceiving) {
    receiveOtaImage();
    return;
  }
  while (otaClient.available() && otaHeaderSize + 1 < sizeof(otaHeader)) {
    char byte = static_cast<char>(otaClient.read());
    if (byte == '\n') {
      otaHeader[otaHeaderSize] = '\0';
      if (!beginOtaImage()) {
        otaClient.print("ERR\n");
        otaClient.stop();
      }
      return;
    }
    otaHeader[otaHeaderSize++] = byte;
  }
  if (otaHeaderSize + 1 == sizeof(otaHeader)) otaClient.stop();
}

void emitJson(const char* prefix, const JsonDocument& doc) {
  String line;
  serializeJson(doc, line);
  Serial.printf("%s%s\n", prefix, line.c_str());
}

bool validId(const String& id) {
  if (id.isEmpty() || id.length() > 48) return false;
  for (char c : id) if (!isalnum(static_cast<unsigned char>(c)) && c != '-' && c != '_') return false;
  return true;
}

String storedConfig() {
  prefs.begin("atleta-lab", true);
  String saved = prefs.getString("config", "{}");
  prefs.end();
  return saved;
}

bool storeConfig(const String& json) {
  if (!prefs.begin("atleta-lab", false)) return false;
  const bool stored = prefs.putString("config", json) != 0;
  prefs.end();
  return stored;
}

void loadConfig() {
  JsonDocument doc;
  if (deserializeJson(doc, storedConfig())) return;
  ssid = doc["wifi_ssid"] | "";
  wifiPassword = doc["wifi_password"] | "";
  host = doc["mqtt_host"] | "";
  mqttPort = doc["mqtt_port"] | 1883;
  deviceId = doc["device_id"] | "m5-atleta-01";
  user = doc["mqtt_username"] | "m5-atleta-01";
  mqttPassword = doc["mqtt_password"] | "";
  weightKg = doc["weight_kg"] | 0.0f;
  stepLengthM = doc["step_length_m"] | 0.0f;
  activityMet = doc["activity_met"] | 0.0f;
  athleteId = doc["athlete_id"] | 0u;
  topic = "atletas/" + deviceId + "/telemetria";
}

void acceptConfig(const String& json) {
  if (hasOpenAppWorkout() || otaOpen || wifiSetupOpen || wifiRebootAt) {
    Serial.println("CONFIG_ERROR busy");
    return;
  }
  JsonDocument doc;
  if (deserializeJson(doc, json)) { Serial.println("CONFIG_ERROR json"); return; }
  for (const char* key : {"wifi_ssid", "wifi_password", "mqtt_host", "device_id", "mqtt_username", "mqtt_password"}) {
    if (!doc[key].is<const char*>()) { Serial.println("CONFIG_ERROR fields"); return; }
  }
  String newHost = doc["mqtt_host"].as<String>();
  String newId = doc["device_id"].as<String>();
  int port = doc["mqtt_port"] | 0;
  if (!validId(newId) || newId != doc["mqtt_username"].as<String>() || newHost.isEmpty() ||
      newHost == "localhost" || newHost == "127.0.0.1" || newHost == "0.0.0.0" ||
      newHost.indexOf('/') >= 0 || newHost.indexOf(' ') >= 0 ||
      port < 1 || port > 65535 || doc["wifi_ssid"].as<String>().isEmpty() ||
      doc["wifi_ssid"].as<String>().length() > 32 || doc["wifi_password"].as<String>().length() > 64 ||
      doc["mqtt_password"].as<String>().isEmpty()) {
    Serial.println("CONFIG_ERROR values"); return;
  }
  for (const char* key : {"weight_kg", "step_length_m", "activity_met", "athlete_id"}) {
    if (doc[key].isNull()) continue;
    float value = doc[key].as<float>();
    float lower = String(key) == "weight_kg" ? 10 : String(key) == "step_length_m" ? 0.1f : 1;
    float upper = String(key) == "weight_kg" ? 400 : String(key) == "step_length_m" ? 2.5f : String(key) == "activity_met" ? 25 : 2147483647.0f;
    if (!doc[key].is<float>() || !isfinite(value) || value < lower || value > upper ||
        (String(key) == "athlete_id" && !doc[key].is<uint32_t>())) {
      Serial.println("CONFIG_ERROR profile"); return;
    }
  }
  if (!storeConfig(json)) { Serial.println("CONFIG_ERROR storage"); return; }
  Serial.println("CONFIG_OK");
  Serial.flush(); delay(300); ESP.restart();
}

bool tryWifi(const WifiTrial& trial) {
  WiFi.setAutoReconnect(false);
  WiFi.disconnect(false, false);
  vTaskDelay(pdMS_TO_TICKS(300));
  const uint32_t ipEvents = wifiIpEvents.load();
  WiFi.begin(trial.name, trial.password);
  const uint32_t started = millis();
  while (millis() - started < 18000) {
    if (wifiIpEvents.load() != ipEvents && WiFi.status() == WL_CONNECTED && WiFi.SSID() == trial.name) {
      return true;
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
  return false;
}

void networkTask(void*) {
  WiFiClient transport;
  PubSubClient mqtt(transport);
  mqtt.setBufferSize(MAX_PAYLOAD + 256);
  mqtt.setSocketTimeout(2);
  mqtt.setKeepAlive(20);
  WiFi.mode(WIFI_STA);
  WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info) {
    if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
      wifiReason = info.wifi_sta_disconnected.reason;
      Serial.printf("WIFI_DISCONNECTED reason=%d\n", wifiReason.load());
    }
    if (event == ARDUINO_EVENT_WIFI_STA_GOT_IP) {
      ++wifiIpEvents;
      wifiReason = 0;
      Serial.println("WIFI_CONNECTED");
    }
  });
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);
  const bool wifiConfigured = !ssid.isEmpty();
  const bool mqttConfigured = wifiConfigured && !host.isEmpty() && !mqttPassword.isEmpty();
  if (wifiConfigured) WiFi.begin(ssid.c_str(), wifiPassword.c_str());
  uint32_t wifiRetry = millis(), mqttRetry = 0;
  Message message;
  while (true) {
    uint32_t now = millis();
    WifiTrial trial{};
    if (wifiTrials && xQueueReceive(wifiTrials, &trial, 0) == pdTRUE) {
      mqtt.disconnect();
      mqttOnline = false;
      const bool connected = tryWifi(trial);
      mbedtls_platform_zeroize(&trial, sizeof(trial));
      WiFi.disconnect(false, false);
      WiFi.setAutoReconnect(true);
      if (wifiConfigured) WiFi.begin(ssid.c_str(), wifiPassword.c_str());
      wifiRetry = mqttRetry = millis();
      xQueueOverwrite(wifiResults, &connected);
      continue;
    }
    WifiScan scanRequest{};
    if (wifiScans && xQueueReceive(wifiScans, &scanRequest, 0) == pdTRUE) {
      // A busca falha se a tentativa automática de associação estiver em andamento.
      if (mqttOnline.exchange(false)) transport.stop();
      mqttError = -1;
      WiFi.setAutoReconnect(false);
      WiFi.disconnect(false, false);
      vTaskDelay(pdMS_TO_TICKS(300));
      int count = WiFi.scanNetworks(false, false, false, 300);
      JsonDocument scan;
      scan["scan_success"] = count >= 0;
      scan["networks_seen"] = count >= 0 ? count : 0;
      scan["configured_ssid_seen"] = false;
      scan["target_ssid"] = scanRequest.ssid;
      scan["target_ssid_seen"] = false;
      auto matches = scan["matching_networks"].to<JsonArray>();
      for (int index = 0; index < count; ++index) {
        const String foundSsid = WiFi.SSID(index);
        if (foundSsid == ssid) scan["configured_ssid_seen"] = true;
        if (foundSsid.equalsIgnoreCase(scanRequest.ssid)) {
          const bool exact = foundSsid == scanRequest.ssid;
          auto found = matches.add<JsonObject>();
          found["exact_name"] = exact;
          found["ssid"] = foundSsid;
          found["channel"] = WiFi.channel(index);
          found["rssi_dbm"] = WiFi.RSSI(index);
          found["auth_mode"] = int(WiFi.encryptionType(index));
          if (exact) scan["target_ssid_seen"] = true;
        }
      }
      WiFi.scanDelete();
      emitJson("WIFI_SCAN ", scan);
      WiFi.setAutoReconnect(true);
      if (wifiConfigured) WiFi.begin(ssid.c_str(), wifiPassword.c_str());
      wifiRetry = millis();
    }
    const bool wifiOnline = WiFi.status() == WL_CONNECTED;
    if (!wifiOnline && mqttOnline.exchange(false)) {
      transport.stop();
      mqttError = -1;
    }
    if (wifiConfigured && !wifiOnline && now - wifiRetry >= 15000) {
      wifiRetry = now; WiFi.reconnect();
    }
    if (mqttConfigured && wifiOnline && !mqtt.connected() && now - mqttRetry >= 5000) {
      mqttRetry = now;
      mqtt.setServer(host.c_str(), mqttPort);
      if (mqtt.connect(deviceId.c_str(), user.c_str(), mqttPassword.c_str())) Serial.println("MQTT_CONNECTED");
      else Serial.printf("MQTT_ERROR code=%d\n", mqtt.state());
      mqttError = mqtt.state();
    }
    if (mqtt.connected()) mqtt.loop();
    mqttOnline = wifiOnline && mqtt.connected();
    if (outgoing && xQueueReceive(outgoing, &message, 0) == pdTRUE && mqttOnline.load()) {
      // QoS 0, fila só da leitura mais recente; confirmação final é a consulta MySQL.
      if (mqtt.publish(topic.c_str(), message.payload, false)) ++sentCount;
      else Serial.println("MQTT_PUBLISH_FAILED");
    }
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

class BleCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { ++bleLink; bleConnected = true; }
  void onDisconnect(BLEServer*, esp_ble_gatts_cb_param_t* event) override {
    ++bleLink;
    bleConnected = false;
    bleDisconnectReason = static_cast<int>(event->disconnect.reason);
    bleRestart = true;
  }
};

class WifiControl : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic*, esp_ble_gatts_cb_param_t* param) override {
    if (!wifiFrames || param->write.is_prep || param->write.len == 0 || param->write.len > 20) return;
    WifiFrame frame{bleLink.load(), static_cast<uint8_t>(param->write.len), {}};
    memcpy(frame.bytes, param->write.value, frame.size);
    if (xQueueSend(wifiFrames, &frame, 0) != pdTRUE) wifiFrameOverflow = true;
  }
};

class WatchControl : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    auto packet = characteristic->getValue();
    if (!watchCommands || packet.size() != 5) return;
    uint8_t action = static_cast<uint8_t>(packet[0]);
    if (action < 1 || action > 4) return;
    uint32_t token = 0;
    memcpy(&token, packet.data() + 1, sizeof(token));
    if (token) {
      WatchCommand command{action, token, bleLink.load()};
      xQueueSend(watchCommands, &command, 0);
    }
  }
};

void setBluetooth(bool enabled) {
  if (enabled && !bleInitialized) {
    BLEDevice::init("Atleta-M5");
    BLEDevice::setEncryptionLevel(ESP_BLE_SEC_ENCRYPT);
    BLESecurity security;
    security.setAuthenticationMode(ESP_LE_AUTH_BOND);
    security.setCapability(ESP_IO_CAP_NONE);
    security.setKeySize(16);
    bleServer = BLEDevice::createServer();
    bleServer->setCallbacks(new BleCallbacks());
    auto service = bleServer->createService(BLEUUID(BLE_SERVICE), 21);
    bleCharacteristic = service->createCharacteristic(BLE_SUMMARY,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    bleCharacteristic->addDescriptor(new BLE2902());
    uint8_t initial[16] = {1};
    initial[10] = initial[11] = initial[12] = 255;
    bleCharacteristic->setValue(initial, sizeof(initial));
    bleSession = service->createCharacteristic(BLE_SESSION,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    bleSession->addDescriptor(new BLE2902());
    uint8_t sessionInitial[18] = {2};
    sessionInitial[10] = sessionInitial[11] = sessionInitial[12] = 255;
    bleSession->setValue(sessionInitial, sizeof(sessionInitial));
    auto control = service->createCharacteristic(BLE_CONTROL, BLECharacteristic::PROPERTY_WRITE);
    control->setAccessPermissions(ESP_GATT_PERM_WRITE_ENCRYPTED);
    watchCommands = xQueueCreate(4, sizeof(WatchCommand));
    control->setCallbacks(new WatchControl());
    auto wifiControl = service->createCharacteristic(BLE_WIFI_CONTROL, BLECharacteristic::PROPERTY_WRITE);
    wifiControl->setAccessPermissions(ESP_GATT_PERM_WRITE_ENCRYPTED);
    wifiControl->setCallbacks(new WifiControl());
    bleWifiStatus = service->createCharacteristic(BLE_WIFI_STATUS, BLECharacteristic::PROPERTY_READ);
    bleWifiStatus->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED);
    uint8_t setupClosed[17]{};
    bleWifiStatus->setValue(setupClosed, sizeof(setupClosed));
    service->start();
    BLEDevice::getAdvertising()->addServiceUUID(BLE_SERVICE);
    BLEDevice::getAdvertising()->setScanResponse(true);
    bleInitialized = true;
  }
  bleEnabled = enabled;
  if (bleInitialized) {
    if (enabled) BLEDevice::startAdvertising();
    else {
      BLEDevice::getAdvertising()->stop();
      if (bleConnected) bleServer->disconnect(bleServer->getConnId());
    }
  }
  Serial.printf("BLE_STATUS enabled=%d connected=%d\n", bleEnabled, bleConnected.load());
}

bool loadBluetoothPreference() {
  // Versões anteriores ainda não têm uma preferência salva para o Bluetooth.
  if (!prefs.begin("atleta-lab", true)) return true;
  const bool enabled = prefs.getBool(BLE_PREFERENCE, true);
  prefs.end();
  return enabled;
}

void setBluetoothPreference(bool enabled) {
  bool saved = false;
  if (prefs.begin("atleta-lab", false)) {
    saved = prefs.putBool(BLE_PREFERENCE, enabled) == 1;
    prefs.end();
  }
  if (!saved) Serial.println("BLE_PREFERENCE_ERROR");
  setBluetooth(enabled);
}

void publishWifiSetup(WifiSetup state) {
  wifiSetupStatus = state;
  if (!bleWifiStatus) return;
  uint8_t value[17] = {static_cast<uint8_t>(state)};
  if (wifiSetupOpen) memcpy(value + 1, wifiChallenge, sizeof(wifiChallenge));
  bleWifiStatus->setValue(value, sizeof(value));
}

void resetWifiFrames() {
  wifiFrameLength = 0;
  wifiFrameStarted = false;
  mbedtls_platform_zeroize(wifiFrameData, sizeof(wifiFrameData));
}

void closeWifiSetup() {
  wifiSetupOpen = false;
  mbedtls_platform_zeroize(wifiSetupCode, sizeof(wifiSetupCode));
  resetWifiFrames();
  publishWifiSetup(WifiSetup::CLOSED);
  if (wifiSetupTemporaryBle) setBluetooth(false);
  wifiSetupTemporaryBle = false;
}

void openWifiSetup() {
  if (hasOpenAppWorkout() || otaOpen || !wifiFrames || !wifiTrials || !wifiResults) {
    publishWifiSetup(WifiSetup::BUSY);
    return;
  }
  wifiSetupTemporaryBle = !bleEnabled;
  if (!bleEnabled) setBluetooth(true);
  uint8_t code[8];
  esp_fill_random(code, sizeof(code));
  otaHex(code, sizeof(code), wifiSetupCode);
  esp_fill_random(wifiChallenge, sizeof(wifiChallenge));
  resetWifiFrames();
  xQueueReset(wifiFrames);
  wifiFrameOverflow = false;
  wifiSetupOpenedAt = millis();
  wifiSetupOpen = true;
  publishWifiSetup(WifiSetup::READY);
}

bool decryptWifiSettings(const char* secret, uint8_t* plain, size_t length) {
  unsigned char key[32]{};
  const auto* sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (!sha256 || mbedtls_md_hmac(sha256, reinterpret_cast<const uint8_t*>(secret), strlen(secret),
          reinterpret_cast<const uint8_t*>(WIFI_SETUP_DOMAIN), sizeof(WIFI_SETUP_DOMAIN) - 1, key) != 0) {
    return false;
  }
  mbedtls_gcm_context context;
  mbedtls_gcm_init(&context);
  const bool ok = mbedtls_gcm_setkey(&context, MBEDTLS_CIPHER_ID_AES, key, 256) == 0 &&
      mbedtls_gcm_auth_decrypt(&context, length, wifiFrameData, 12, wifiChallenge, sizeof(wifiChallenge),
          wifiFrameData + 12 + length, 16, wifiFrameData + 12, plain) == 0;
  mbedtls_gcm_free(&context);
  mbedtls_platform_zeroize(key, sizeof(key));
  return ok;
}

bool stageWifiSettings(const JsonDocument& request) {
  JsonString network = request["ssid"].as<JsonString>();
  JsonString password = request["password"].as<JsonString>();
  if (network.isNull() || password.isNull() || network.size() == 0 || network.size() > 32 ||
      strlen(network.c_str()) != network.size() || strlen(password.c_str()) != password.size() ||
      (password.size() != 0 && password.size() < 8) || password.size() > 64) return false;
  if (password.size() == 64 && strspn(password.c_str(), "0123456789abcdefABCDEF") != 64) return false;
  JsonDocument config;
  if (deserializeJson(config, storedConfig()) || !config.is<JsonObject>()) return false;
  config["wifi_ssid"] = network;
  config["wifi_password"] = password;
  // O painel só sugere um servidor quando ele conhece o endereço na rede escolhida.
  if (const JsonObjectConst server = request["server"].as<JsonObjectConst>()) {
    const char* address = server["host"] | "";
    JsonString brokerPassword = server["password"].as<JsonString>();
    IPAddress ip;
    if (!ip.fromString(address) || !ip[0] || ip[0] == 127 || !server["port"].is<uint16_t>() ||
        !server["port"].as<uint16_t>() || brokerPassword.isNull() || brokerPassword.size() == 0 ||
        brokerPassword.size() > 128 || strlen(brokerPassword.c_str()) != brokerPassword.size()) return false;
    config["mqtt_host"] = address;
    config["mqtt_port"] = server["port"].as<uint16_t>();
    config["mqtt_password"] = brokerPassword;
    config["device_id"] = "m5-atleta-01";
    config["mqtt_username"] = "m5-atleta-01";
  }
  if (config.overflowed() || measureJson(config) >= MAX_CONFIG) return false;
  WifiTrial trial{};
  memcpy(trial.name, network.c_str(), network.size());
  memcpy(trial.password, password.c_str(), password.size());
  serializeJson(config, pendingWifiConfig);
  const bool queued = !pendingWifiConfig.isEmpty() && xQueueSend(wifiTrials, &trial, 0) == pdTRUE;
  mbedtls_platform_zeroize(&trial, sizeof(trial));
  if (!queued) pendingWifiConfig = "";
  return queued;
}

void completeWifiFrames() {
  const size_t overhead = 12 + 16;
  if (!wifiFrameStarted || wifiFrameLength <= overhead) {
    publishWifiSetup(WifiSetup::INVALID);
    return;
  }
  if (hasOpenAppWorkout()) {
    publishWifiSetup(WifiSetup::BUSY);
    return;
  }
  uint8_t plain[WIFI_SETUP_LIMIT - overhead]{};
  const size_t length = wifiFrameLength - overhead;
  const bool authorized = (!otaKey.isEmpty() && decryptWifiSettings(otaKey.c_str(), plain, length)) ||
      decryptWifiSettings(wifiSetupCode, plain, length);
  if (authorized) esp_fill_random(wifiChallenge, sizeof(wifiChallenge));
  JsonDocument request;
  const bool valid = authorized && !deserializeJson(request, plain, length) && stageWifiSettings(request);
  mbedtls_platform_zeroize(plain, sizeof(plain));
  publishWifiSetup(!authorized ? WifiSetup::AUTH_ERROR : valid ? WifiSetup::TESTING : WifiSetup::INVALID);
}

void handleWifiSetup(uint32_t now) {
  if (wifiRebootAt && static_cast<int32_t>(now - wifiRebootAt) >= 0) ESP.restart();
  if (!wifiSetupOpen) return;
  if (!pendingWifiConfig.isEmpty()) {
    bool connected;
    if (xQueueReceive(wifiResults, &connected, 0) != pdTRUE) return;
    if (!connected) {
      publishWifiSetup(WifiSetup::NETWORK_ERROR);
    } else if (!storeConfig(pendingWifiConfig)) {
      publishWifiSetup(WifiSetup::STORAGE_ERROR);
    } else {
      wifiSetupOpen = false;
      wifiRebootAt = now + 3500;
      publishWifiSetup(WifiSetup::SAVED);
    }
    pendingWifiConfig = "";
    return;
  }
  if (now - wifiSetupOpenedAt >= WIFI_SETUP_WINDOW_MS) {
    closeWifiSetup();
    return;
  }
  if (wifiFrameOverflow.exchange(false)) {
    resetWifiFrames();
    xQueueReset(wifiFrames);
    publishWifiSetup(WifiSetup::INVALID);
  }
  WifiFrame frame;
  while (xQueueReceive(wifiFrames, &frame, 0) == pdTRUE) {
    if (frame.link != bleLink.load()) continue;
    if (frame.bytes[0] == 1 && frame.size == 1) {
      resetWifiFrames();
      wifiFrameStarted = true;
      wifiFrameLink = frame.link;
      publishWifiSetup(WifiSetup::READY);
    } else if (!wifiFrameStarted || frame.link != wifiFrameLink) {
      continue;
    } else if (frame.bytes[0] == 2 && frame.size > 1 && wifiFrameLength + frame.size - 1 <= sizeof(wifiFrameData)) {
      memcpy(wifiFrameData + wifiFrameLength, frame.bytes + 1, frame.size - 1);
      wifiFrameLength += frame.size - 1;
    } else if (frame.bytes[0] == 3 && frame.size == 1) {
      completeWifiFrames();
      resetWifiFrames();
      return;
    } else {
      resetWifiFrames();
      publishWifiSetup(WifiSetup::INVALID);
    }
  }
}

const char* bluetoothState() {
  return !bleEnabled ? "desligado" : bleConnected ? "conectado" : "anunciando";
}

void inventory(bool scanExternal) {
  JsonDocument doc;
  doc["firmware"] = VERSION;
  doc["board"] = "M5StickCPlus2";
  doc["chip"] = ESP.getChipModel();
  doc["flash_bytes"] = ESP.getFlashChipSize();
  doc["psram_bytes"] = ESP.getPsramSize();
  doc["imu_enabled"] = M5.Imu.isEnabled();
  doc["imu_type"] = static_cast<int>(M5.Imu.getType());
  doc["imu_who_am_i"] = M5.In_I2C.readRegister8(0x68, 0x75, 100000);
  doc["rtc_0x51_responds"] = M5.In_I2C.scanID(uint8_t(0x51));
  doc["external_scan_performed"] = scanExternal;
  auto addresses = doc["external_i2c_addresses"].to<JsonArray>();
  if (scanExternal) {
    // Apenas o barramento Grove documentado: SDA32/SCL33. Nenhum GPIO aleatório.
    doc["external_sda"] = M5.Ex_I2C.getSDA();
    doc["external_scl"] = M5.Ex_I2C.getSCL();
    bool scanned = M5.Ex_I2C.getSDA() == 32 && M5.Ex_I2C.getSCL() == 33 && M5.Ex_I2C.begin();
    doc["external_scan_ok"] = scanned;
    if (scanned) for (uint8_t address = 8; address < 120; ++address) {
      if (M5.Ex_I2C.scanID(address, 100000)) addresses.add(address);
    }
  }
  doc["analog_sensor_identification"] = "requires_model_and_wiring";
  doc["ble_state"] = bluetoothState();
  doc["wifi_ssid"] = ssid;
  doc["wifi_status_code"] = int(WiFi.status());
  doc["wifi_disconnect_reason"] = wifiReason.load();
  doc["wifi_ip"] = WiFi.localIP().toString();
  doc["mqtt_host"] = host;
  doc["mqtt_port"] = mqttPort;
  emitJson("INVENTORY ", doc);
}

void startSession() {
  watchToken = 0; watchFinished = false;
  ++sessionNumber; activeMs = 0; steps.reset(); running = true;
  snprintf(sessionId, sizeof(sessionId), "%s-%lu", bootId, static_cast<unsigned long>(sessionNumber));
  Serial.println("SESSION_STARTED");
}

void handleWatchCommands() {
  if (!watchCommands) return;
  WatchCommand command{};
  while (xQueueReceive(watchCommands, &command, 0) == pdTRUE) {
    if (!bleEnabled || !bleConnected || command.link != bleLink.load() || wifiSetupOpen || wifiRebootAt) continue;
    if (command.action == 1) {
      // The same start can be retried without resetting the step counter.
      if (command.token == watchToken || (watchToken && !watchFinished)) continue;
      startSession();
      watchToken = command.token;
      continue;
    }
    if (command.token != watchToken || watchFinished) continue;
    running = command.action == 3;
    watchFinished = command.action == 4;
    steps.breakSequence();
  }
}

void selfTest() {
  StepCounter stationary, rotating, walking, invalid, interrupted, tooFast, irregular, changing;
  constexpr uint32_t irregularPeaks[] = {500, 1000, 2600, 3100, 4700,
                                          5200, 6800, 7300, 8900, 9400};
  constexpr uint32_t changingPeaks[] = {500, 1000, 1500, 2220, 2720, 3220, 3720, 4220};
  for (uint32_t t = 0; t < 10000; t += 20) {
    float phase = 2 * PI * 2 * t / 1000;
    stationary.add(t, 0, 0, 1);
    rotating.add(t, sinf(phase), 0, cosf(phase));
    walking.add(t, 0, 0, 1 + 0.23f * sinf(phase));
    invalid.add(t, NAN, 0, 1);
    interrupted.add(t * 100, 0, 0, 1 + 0.23f * sinf(phase));
    tooFast.add(t, 0, 0, 1 + 0.23f * sinf(phase * 2));
    float bump = 1;
    for (uint32_t peak : irregularPeaks) {
      float delta = (static_cast<float>(t) - peak) / 65;
      bump += 0.3f * expf(-delta * delta);
    }
    irregular.add(t, 0, 0, bump);
    bump = 1;
    for (uint32_t peak : changingPeaks) {
      float delta = (static_cast<float>(t) - peak) / 65;
      bump += 0.3f * expf(-delta * delta);
    }
    changing.add(t, 0, 0, bump);
  }
  JsonDocument doc;
  doc["stationary_zero"] = stationary.steps == 0;
  doc["rotation_zero"] = rotating.steps == 0;
  doc["invalid_zero"] = invalid.steps == 0;
  doc["gaps_zero"] = interrupted.steps == 0;
  doc["regular_peaks"] = walking.steps >= 18 && walking.steps <= 21;
  doc["irregular_zero"] = irregular.steps == 0;
  doc["double_peaks_limited"] = tooFast.steps <= 23;
  doc["short_walk_variable_cadence"] = changing.steps == 8;
  doc["variable_cadence_steps"] = changing.steps;
  doc["synthetic_steps"] = walking.steps;
  doc["distance_formula"] = fabsf(estimatedDistanceKm(1000, 0.7f) - 0.7f) < 0.0001f;
  doc["calories_formula"] = fabsf(estimatedCalories(3600000, 70, 3.8f) - 266) < 0.001f;
  doc["missing_profile_null"] = isnan(estimatedDistanceKm(100, 0)) && isnan(estimatedCalories(1000, 0, 0));
  emitJson("SELFTEST ", doc);
}

void stopImuTrace() {
  if (!imuTrace) return;
  imuTrace = false;
  Serial.printf("IMU_TRACE_DONE samples=%lu dropped=%lu\n",
      static_cast<unsigned long>(traceSamples), static_cast<unsigned long>(traceDropped));
}

void traceImuSample(uint32_t now) {
  if (!imuTrace) return;
  if (imuTraceMqtt) {
    if (traceBatchSize == 5) { ++traceDropped; return; }
    traceBatch[traceBatchSize++] = {now, steps.cadenceInterval(), steps.pendingPeaks(), steps.steps,
        {ax, ay, az}, {gx, gy, gz}, steps.filteredAcceleration(),
        static_cast<uint8_t>(steps.lastEvent()), static_cast<uint8_t>(running ? 1 : 0)};
    ++traceSamples; return;
  }
  char line[224];
  int length = snprintf(line, sizeof(line),
      "IMU_SAMPLE %lu,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.4f,%lu,%lu,%u,%lu,%u\n",
      static_cast<unsigned long>(now), ax, ay, az, gx, gy, gz,
      steps.filteredAcceleration(), static_cast<unsigned long>(steps.cadenceInterval()),
      static_cast<unsigned long>(steps.pendingPeaks()), static_cast<unsigned>(steps.lastEvent()),
      static_cast<unsigned long>(steps.steps), running ? 1 : 0);
  // Não bloquear a amostragem se o computador parar de ler a USB.
  if (length <= 0 || length >= static_cast<int>(sizeof(line)) || Serial.availableForWrite() < length) {
    ++traceDropped; return;
  }
  Serial.write(reinterpret_cast<const uint8_t*>(line), length);
  ++traceSamples;
}

void readSerial() {
  while (Serial.available()) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r') continue;
    if (c != '\n') {
      if (!discardLine) {
        if (serialLine.length() >= MAX_CONFIG) { serialLine = ""; discardLine = true; Serial.println("CONFIG_ERROR too_long"); }
        else serialLine += c;
      }
      continue;
    }
    if (!discardLine) {
      if (serialLine.startsWith("CONFIG ")) acceptConfig(serialLine.substring(7));
      else if (serialLine.startsWith("OTA_PAIR ")) pairOta(serialLine.substring(9));
      else if (serialLine == "INVENTORY") inventory(false);
      else if (serialLine == "SCAN_I2C") inventory(true);
      else if (serialLine == "SELFTEST") selfTest();
      else if (serialLine == "TRACE_IMU ON") {
        imuTrace = true; imuTraceMqtt = false; traceBatchSize = 0;
        traceStarted = millis(); traceSamples = 0; traceDropped = 0;
        Serial.printf("IMU_TRACE_BEGIN schema=1 rate_hz=50 timeout_s=%lu start_ms=%lu\n",
            static_cast<unsigned long>(MAX_TRACE_MS / 1000), static_cast<unsigned long>(traceStarted));
      }
      else if (serialLine == "TRACE_MQTT ON") {
        if (WiFi.status() != WL_CONNECTED || !mqttOnline.load()) {
          Serial.println("IMU_TRACE_ERROR wifi_mqtt_offline");
        } else {
          imuTrace = true; imuTraceMqtt = true; traceBatchSize = 0;
          traceStarted = millis(); traceSamples = 0; traceDropped = 0;
          Serial.printf("IMU_TRACE_BEGIN schema=2 transport=mqtt rate_hz=50 timeout_s=%lu start_ms=%lu\n",
              static_cast<unsigned long>(MAX_TRACE_MS / 1000), static_cast<unsigned long>(traceStarted));
        }
      }
      else if (serialLine == "TRACE_IMU OFF") stopImuTrace();
      else if (serialLine == "SCAN_WIFI" || serialLine.startsWith("SCAN_WIFI ")) {
        const String target = serialLine == "SCAN_WIFI" ? ssid : serialLine.substring(10);
        WifiScan request{};
        if (!wifiScans || otaOpen || wifiSetupOpen || wifiRebootAt || target.length() >= sizeof(request.ssid)) {
          Serial.println("WIFI_SCAN_ERROR");
        } else {
          target.toCharArray(request.ssid, sizeof(request.ssid));
          xQueueOverwrite(wifiScans, &request);
        }
      }
      else if (serialLine == "BLE ON") setBluetooth(true);
      else if (serialLine == "BLE OFF") setBluetooth(false);
      else if (serialLine == "SESSION START") startSession();
      else if (serialLine == "SESSION PAUSE") { running = false; steps.breakSequence(); Serial.println("SESSION_PAUSED"); }
      else if (serialLine == "SESSION RESUME") {
        if (watchFinished) Serial.println("SESSION_FINISHED");
        else { running = true; steps.breakSequence(); Serial.println("SESSION_RESUMED"); }
      }
      else if (serialLine == "STATUS") Serial.printf("STATUS firmware=%s configured=%d wifi=%d mqtt=%d imu=%d sent=%lu steps=%lu ble=%s\n",
          VERSION, !host.isEmpty() && !ssid.isEmpty(), WiFi.status() == WL_CONNECTED, mqttOnline.load(), imuHealthy,
          static_cast<unsigned long>(sentCount.load()), static_cast<unsigned long>(steps.steps), bluetoothState());
    }
    serialLine = ""; discardLine = false;
  }
}

void telemetry() {
  if (!imuHealthy) { Serial.println("SENSOR_ERROR imu_no_valid_sample"); return; }
  JsonDocument doc;
  doc["schema_version"] = 1; doc["firmware_version"] = VERSION;
  doc["source"] = "device"; doc["device_id"] = deviceId;
  doc["boot_id"] = bootId; doc["sample_seq"] = sequence++;
  doc["uptime_ms"] = uint64_t(esp_timer_get_time() / 1000);
  doc["accel_x_g"] = ax; doc["accel_y_g"] = ay; doc["accel_z_g"] = az;
  auto accel = doc["accel_g"].to<JsonArray>(); accel.add(ax); accel.add(ay); accel.add(az);
  auto gyro = doc["gyro_dps"].to<JsonArray>(); gyro.add(gx); gyro.add(gy); gyro.add(gz);
  if (athleteId) doc["athlete_id"] = athleteId; else doc["athlete_id"] = nullptr;
  doc["sessao"] = sessionId; doc["sessao_ativa"] = running;
  doc["duracao_s"] = activeMs / 1000; doc["passos"] = steps.steps;
  float distance = estimatedDistanceKm(steps.steps, stepLengthM);
  float calories = estimatedCalories(activeMs, weightKg, activityMet);
  if (isfinite(distance)) doc["distancia_km"] = distance; else doc["distancia_km"] = nullptr;
  if (isfinite(calories)) doc["calorias_kcal"] = calories; else doc["calorias_kcal"] = nullptr;
  if (isfinite(distance) && distance > 0) doc["ritmo_min_km"] = activeMs / 60000.0f / distance;
  else doc["ritmo_min_km"] = nullptr;
  doc["bpm"] = nullptr; doc["temperatura_pele_c"] = nullptr;
  doc["latitude"] = nullptr; doc["longitude"] = nullptr; doc["gps"] = "sem_modulo_configurado";
  doc["wifi"] = WiFi.status() == WL_CONNECTED ? "conectado" : "desconectado";
  doc["bluetooth"] = bluetoothState();
  if (batteryMv > 0) doc["battery_mv"] = batteryMv; else doc["battery_mv"] = nullptr;
  if (batteryPercent >= 0) doc["battery_percent_estimate"] = batteryPercent;
  else doc["battery_percent_estimate"] = nullptr;
  if (WiFi.status() == WL_CONNECTED) doc["wifi_rssi_dbm"] = WiFi.RSSI(); else doc["wifi_rssi_dbm"] = nullptr;
  doc["mqtt_connected"] = mqttOnline.load();
  auto quality = doc["measurement_status"].to<JsonObject>();
  quality["passos"] = "estimativa_mpu6886";
  quality["distancia"] = stepLengthM > 0 ? "estimativa_por_passos" : "sem_comprimento_passo";
  quality["calorias"] = weightKg > 0 && activityMet > 0 ? "estimativa_bruta_met_informado" : "sem_peso_ou_met";
  quality["bpm"] = "sensor_nao_configurado";
  quality["temperatura_pele"] = "sensor_nao_configurado";
  quality["gps"] = "sensor_nao_configurado";
  quality["bateria"] = "percentual_estimado_por_tensao";
  if (traceBatchSize) {
    doc["imu_trace_schema"] = 2;
    doc["imu_trace_dropped"] = traceDropped;
    auto batch = doc["imu_trace"].to<JsonArray>();
    for (size_t i = 0; i < traceBatchSize; ++i) {
      const auto& sample = traceBatch[i];
      auto row = batch.add<JsonArray>();
      row.add(sample.ms);
      // Inteiros compactos: aceleração/filtro em 0,0001 g, gyro em 0,01 °/s.
      for (float value : sample.accel) row.add(static_cast<int32_t>(lroundf(value * 10000)));
      for (float value : sample.gyro) row.add(static_cast<int32_t>(lroundf(value * 100)));
      row.add(static_cast<int32_t>(lroundf(sample.filtered * 10000)));
      row.add(sample.cadence); row.add(sample.pending); row.add(sample.event);
      row.add(sample.count); row.add(sample.active);
    }
    while (measureJson(doc) >= MAX_PAYLOAD && batch.size()) {
      batch.remove(batch.size() - 1); ++traceDropped;
    }
    doc["imu_trace_dropped"] = traceDropped;
    traceBatchSize = 0;
  }
  if (measureJson(doc) >= MAX_PAYLOAD) { Serial.println("TELEMETRY_ERROR payload_too_large"); return; }
  Message message{};
  serializeJson(doc, message.payload, sizeof(message.payload));
  // No modo MQTT, a transmissão USB de 10 payloads/s excederia 115200 baud
  // e atrasaria o IMU. O resumo USB normal volta ao encerrar o diagnóstico.
  if (!imuTrace || !imuTraceMqtt) Serial.printf("TELEMETRY %s\n", message.payload);
  if (outgoing) xQueueOverwrite(outgoing, &message);
}

void publishBluetoothSummary() {
  if (bleEnabled && bleCharacteristic) {
    uint8_t data[16] = {1, uint8_t((running ? 1 : 0) | (imuHealthy ? 2 : 0) |
                                (WiFi.status() == WL_CONNECTED ? 4 : 0) | (mqttOnline ? 8 : 0))};
    uint32_t count = steps.steps, seconds = activeMs / 1000;
    uint16_t mv = batteryMv > 0 ? batteryMv : 0xffff;
    memcpy(data + 2, &count, 4); memcpy(data + 6, &seconds, 4); memcpy(data + 10, &mv, 2);
    data[12] = batteryPercent >= 0 ? batteryPercent : 255;
    bleCharacteristic->setValue(data, sizeof(data));
    if (bleConnected) bleCharacteristic->notify();
    if (bleSession) {
      uint8_t session[18]{};
      memcpy(session, data, 13);
      session[0] = 2;
      if (watchFinished) session[1] |= 16;
      memcpy(session + 13, &watchToken, sizeof(watchToken));
      bleSession->setValue(session, sizeof(session));
      if (bleConnected) bleSession->notify();
    }
  }
}

void drawStatus() {
  auto& screen = M5.Display;
  screen.fillScreen(TFT_BLACK); screen.setTextColor(TFT_WHITE); screen.setTextSize(1);
  screen.setCursor(4, 3); screen.printf("ATLETA  %s       %s", VERSION, running ? "ATIVO" : "PAUSA");
  screen.drawFastHLine(4, 16, 232, TFT_DARKGREY);
  if (page == OTA_PAGE) {
    screen.setCursor(4, 24);
    screen.setTextColor(TFT_CYAN);
    screen.println("ATUALIZACAO WI-FI (OTA)\n");
    screen.setTextColor(TFT_WHITE);
    if (otaReceiving) {
      screen.printf("Recebendo: %u%%\n", static_cast<unsigned>((otaTotal - otaRemaining) * 100 / otaTotal));
      screen.println("Mantenha o relogio ligado.");
    } else if (otaOpen) {
      screen.println("Pronto para receber.");
      screen.println("Clique em Atualizar M5");
      screen.println("no painel do computador.");
      screen.println("Segure B para cancelar.");
    } else {
      screen.println(otaMessage);
    }
    screen.setCursor(4, 116);
    screen.println("Toque B para voltar.");
    return;
  }
  if (page == BLUETOOTH_WIFI_PAGE) {
    screen.setCursor(4, 24);
    screen.setTextColor(TFT_CYAN);
    screen.println("WI-FI POR BLUETOOTH\n");
    screen.setTextColor(TFT_WHITE);
    if (wifiSetupStatus == WifiSetup::TESTING) {
      screen.println("Testando a nova rede...");
    } else if (wifiSetupStatus == WifiSetup::SAVED) {
      screen.println("Rede confirmada. Reiniciando.");
    } else if (wifiSetupOpen) {
      if (wifiSetupStatus == WifiSetup::NETWORK_ERROR) screen.println("Rede falhou. Confira a senha.");
      else if (wifiSetupStatus == WifiSetup::STORAGE_ERROR) screen.println("Falha ao salvar. Tente de novo.");
      else screen.println("No painel: Configurar Wi-Fi");
      screen.printf("Codigo opcional: %s\n", wifiSetupCode);
      screen.println("Segure B para cancelar.");
    } else if (wifiSetupStatus == WifiSetup::BUSY) {
      screen.println("Finalize o treino e tente de novo.");
    } else {
      screen.println("Segure B para liberar no painel.");
    }
    screen.setCursor(4, 116);
    screen.println("Toque B para voltar.");
    return;
  }
  if (page == 0) {
    screen.setCursor(4, 24); screen.setTextSize(2); screen.printf("Passos: %lu", static_cast<unsigned long>(steps.steps));
    screen.setTextSize(1); screen.setCursor(4, 49);
    screen.printf("Tempo ativo: %lu s  Bateria: %d%%\n", static_cast<unsigned long>(activeMs / 1000), batteryPercent);
    if (stepLengthM > 0) screen.printf("Distancia est.: %.3f km\n", estimatedDistanceKm(steps.steps, stepLengthM));
    else screen.println("Distancia: informe comprimento do passo");
    if (weightKg > 0 && activityMet > 0) screen.printf("Calorias est.: %.2f kcal\n", estimatedCalories(activeMs, weightKg, activityMet));
    else screen.println("Calorias: informe peso e MET");
    screen.printf("Wi-Fi: %s  MQTT: %s\n", WiFi.status() == WL_CONNECTED ? "OK" : "off", mqttOnline ? "OK" : "off");
    screen.printf("BLE: %s", bluetoothState());
  } else if (page == 1) {
    screen.setCursor(4, 25);
    screen.printf("MPU6886: %s\n\n", imuHealthy ? "respondendo" : "sem leitura");
    screen.printf("A: %+.3f %+.3f %+.3f g\n", ax, ay, az);
    screen.printf("G: %+.1f %+.1f %+.1f dps\n", gx, gy, gz);
    screen.printf("Bateria: %d mV (%% estimado)\n", batteryMv);
    screen.printf("MQTT envios: %lu | erro: %d\n", static_cast<unsigned long>(sentCount.load()), mqttError.load());
    screen.println("Passos: estimativa experimental");
  } else {
    screen.setCursor(4, 25); screen.setTextColor(TFT_YELLOW);
    screen.println("SENSORES EXTERNOS\n"); screen.setTextColor(TFT_WHITE);
    screen.println("BPM: sensor nao configurado");
    screen.println("Pele: sensor nao configurado");
    screen.println("GPS: modulo nao configurado\n");
    screen.println("Inspecao de conexoes por USB.");
  }
  screen.setTextColor(TFT_CYAN); screen.setCursor(4, 116);
  screen.println("A pausa | B tela | segure B: Bluetooth");
  screen.println("Segure A: nova sessao");
}
}

void setup() {
  pinMode(4, OUTPUT); digitalWrite(4, HIGH);
  Serial.setTxBufferSize(3072);
  auto cfg = M5.config();
  cfg.fallback_board = m5::board_t::board_M5StickCPlus2;
  cfg.serial_baudrate = 115200; cfg.internal_imu = true;
  cfg.internal_mic = false; cfg.internal_spk = false;
  cfg.external_imu = false; cfg.external_rtc = false;
  M5.begin(cfg);
  M5.Display.setRotation(1); M5.Display.setBrightness(65);
  M5.BtnA.setHoldThresh(1200); M5.BtnB.setHoldThresh(1200);
  loadConfig();
  loadOtaKey();
  snprintf(bootId, sizeof(bootId), "%08lx%08lx", static_cast<unsigned long>(esp_random()), static_cast<unsigned long>(esp_random()));
  startSession();
  lastTick = esp_timer_get_time() / 1000;
  outgoing = xQueueCreate(1, sizeof(Message));
  wifiFrames = xQueueCreate(12, sizeof(WifiFrame));
  wifiTrials = xQueueCreate(1, sizeof(WifiTrial));
  wifiResults = xQueueCreate(1, sizeof(bool));
  wifiScans = xQueueCreate(1, sizeof(WifiScan));
  if (loadBluetoothPreference()) setBluetooth(true);
  if (xTaskCreatePinnedToCore(networkTask, "atleta-network", 8192, nullptr, 1, nullptr, 0) != pdPASS)
    Serial.println("NETWORK_ERROR task_memory");
  Serial.printf("ATLETA_LAB_READY firmware=%s board=M5StickCPlus2\n", VERSION);
  inventory(false); drawStatus();
}

void loop() {
  M5.update();
  uint32_t now = millis();
  uint64_t tick = esp_timer_get_time() / 1000;
  if (running) activeMs += tick - lastTick;
  lastTick = tick;
  if (pendingWifiConfig.isEmpty() && !wifiRebootAt) {
    if (M5.BtnA.wasHold()) startSession();
    else if (M5.BtnA.wasClicked() && !watchFinished) { running = !running; steps.breakSequence(); }
    if (M5.BtnB.wasHold()) {
      if (page == BLUETOOTH_WIFI_PAGE) {
        if (wifiSetupOpen) closeWifiSetup();
        else openWifiSetup();
      } else if (page == OTA_PAGE) {
        if (otaOpen) closeOta("OTA cancelado. Segure B.");
        else openOta();
      } else {
        setBluetoothPreference(!bleEnabled);
      }
    } else if (M5.BtnB.wasClicked()) {
      if (otaOpen) closeOta("OTA cancelado. Segure B.");
      if (wifiSetupOpen) closeWifiSetup();
      page = (page + 1) % (BLUETOOTH_WIFI_PAGE + 1);
    }
  }
  if (bleRestart.exchange(false)) {
    Serial.printf("BLE_DISCONNECTED reason=%d\n", bleDisconnectReason.load());
    if (bleEnabled && !bleConnected) BLEDevice::startAdvertising();
  }
  readSerial();
  handleWatchCommands();
  handleOta(millis());
  handleWifiSetup(millis());
  now = millis();
  if (imuTrace && millis() - traceStarted >= MAX_TRACE_MS) stopImuTrace();
  if (now - lastImu >= IMU_MS) {
    lastImu = now;
    auto updated = M5.Imu.update();
    if (updated & m5::IMU_Class::sensor_mask_accel) {
      auto data = M5.Imu.getImuData();
      ax = data.accel.x; ay = data.accel.y; az = data.accel.z;
      gx = data.gyro.x; gy = data.gyro.y; gz = data.gyro.z;
      imuHealthy = isfinite(ax) && isfinite(ay) && isfinite(az) && isfinite(gx) && isfinite(gy) && isfinite(gz);
      if (imuHealthy) {
        lastGoodImu = now;
        if (running) steps.add(now, ax, ay, az, gx, gy, gz);
        traceImuSample(now);
      } else {
        steps.breakSequence();
      }
    } else if (imuHealthy && now - lastGoodImu > 200) {
      imuHealthy = false;
      steps.breakSequence();
    }
  }
  if (now - lastBluetoothSummary >= BLUETOOTH_SUMMARY_MS) {
    lastBluetoothSummary = now;
    batteryMv = M5.Power.getBatteryVoltage();
    batteryPercent = batteryMv > 0 ? M5.Power.getBatteryLevel() : -1;
    publishBluetoothSummary();
  }
  const uint32_t telemetryInterval = imuTrace && imuTraceMqtt ? 100 : TELEMETRY_MS;
  if (now - lastTelemetry >= telemetryInterval) {
    lastTelemetry = now;
    telemetry();
  }
  if (now - lastDisplay >= 500) { lastDisplay = now; drawStatus(); }
  delay(2);
}
