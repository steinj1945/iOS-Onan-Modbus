#include "BluetoothManager.h"
#include "Config.h"
#include "CryptoAuth.h"     // random_nonce()
#include "SessionCrypto.h"  // session_encrypt()
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Arduino.h>
#include <string.h>

// ── Shared state (written from BLE task, read from main loop) ─────
static volatile bool s_connected        = false;
static volatile bool s_subscribed       = false;
static volatile bool s_response_ready   = false;

static BLEServer*         s_server        = nullptr;
static BLECharacteristic* s_challengeChar = nullptr;
static BLECharacteristic* s_responseChar  = nullptr;

// Plaintext nonce generated on subscribe; retrieved by StateMachine for HMAC verify.
static uint8_t  s_nonce[32];
static uint8_t  s_response_buf[SESSION_PACKET_LEN];
static uint16_t s_response_received = 0;

// ── Helpers ───────────────────────────────────────────────────────

static void send_challenge_chunks() {
    uint8_t enc[SESSION_PACKET_LEN];
    random_nonce(s_nonce, sizeof(s_nonce));
    if (!session_encrypt(s_nonce, enc)) {
        Serial.println("[BLE] session_encrypt failed — challenge not sent");
        return;
    }
    // Send in 20-byte chunks; iOS accumulates until it has 60 bytes.
    const int CHUNK = 20;
    for (int off = 0; off < SESSION_PACKET_LEN; ) {
        int len = min(CHUNK, SESSION_PACKET_LEN - off);
        s_challengeChar->setValue(enc + off, len);
        s_challengeChar->notify();
        off += len;
        if (off < SESSION_PACKET_LEN) vTaskDelay(pdMS_TO_TICKS(50));
    }
    s_subscribed = true;
    Serial.println("[BLE] challenge notified (3 × 20 bytes)");
}

// ── CCCD callback — fires when iOS writes the subscription descriptor ─
class ChallengeCCCDCallback : public BLEDescriptorCallbacks {
    void onWrite(BLEDescriptor* desc) override {
        // BLE2902 updates its internal flag before calling onWrite.
        bool notifications = ((BLE2902*)desc)->getNotifications();
        Serial.printf("[BLE] CCCD write: notifications=%s\n", notifications ? "ON" : "OFF");
        if (notifications) {
            send_challenge_chunks();
        } else {
            s_subscribed = false;
        }
    }
};

// ── Response characteristic write callback ────────────────────────
class ResponseCallback : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* chr) override {
        uint8_t* data = chr->getData();
        size_t   len  = chr->getLength();

        Serial.printf("[BLE] response chunk: %u bytes (have %u/%d)\n",
                      (unsigned)len, s_response_received + (unsigned)len, SESSION_PACKET_LEN);

        if (s_response_received + len > SESSION_PACKET_LEN) {
            Serial.println("[BLE] response overflow — discarding");
            s_response_received = 0;
            return;
        }
        memcpy(s_response_buf + s_response_received, data, len);
        s_response_received += (uint16_t)len;

        if (s_response_received >= SESSION_PACKET_LEN) {
            Serial.println("[BLE] response complete (60 bytes)");
            s_response_ready    = true;
            s_response_received = 0;
        }
    }
};

// ── Server connection callbacks ───────────────────────────────────
class ServerCallback : public BLEServerCallbacks {
    void onConnect(BLEServer*) override {
        s_connected = true;
        Serial.println("[BLE] central connected");
    }
    void onDisconnect(BLEServer*) override {
        s_connected         = false;
        s_subscribed        = false;
        s_response_ready    = false;
        s_response_received = 0;
        Serial.println("[BLE] central disconnected");
    }
};

// ── Public API ────────────────────────────────────────────────────

void bt_init() {
    BLEDevice::init("CopCarPasskey");
    // Request a large MTU so iOS can send the full 60-byte response in one write.
    BLEDevice::setMTU(185);

    s_server = BLEDevice::createServer();
    s_server->setCallbacks(new ServerCallback());

    BLEService* svc = s_server->createService(BLEUUID(UUID_SERVICE));

    // challengeUUID: NOTIFY — ESP32 sends encrypted nonce; iOS reads it.
    s_challengeChar = svc->createCharacteristic(
        BLEUUID(UUID_CHALLENGE),
        BLECharacteristic::PROPERTY_NOTIFY
    );
    BLE2902* cccd = new BLE2902();
    cccd->setCallbacks(new ChallengeCCCDCallback());
    s_challengeChar->addDescriptor(cccd);

    // responseUUID: WRITE_NO_RSP — iOS sends encrypted HMAC; ESP32 receives it.
    s_responseChar = svc->createCharacteristic(
        BLEUUID(UUID_RESPONSE),
        BLECharacteristic::PROPERTY_WRITE_NR
    );
    s_responseChar->setCallbacks(new ResponseCallback());

    svc->start();
    Serial.println("[BLE] GATT service registered");
}

void bt_advertise_start() {
    s_connected         = false;
    s_subscribed        = false;
    s_response_ready    = false;
    s_response_received = 0;

    BLEAdvertising* adv = BLEDevice::getAdvertising();
    adv->addServiceUUID(BLEUUID(UUID_SERVICE));
    adv->setScanResponse(true);
    adv->setMinPreferred(0x06);  // helps iPhone connection establishment
    adv->setMaxPreferred(0x12);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] advertising started");
}

bool bt_connected() {
    return s_connected;
}

bool bt_central_subscribed() {
    return s_subscribed;
}

void bt_get_nonce(uint8_t* buf, uint8_t len) {
    uint8_t copy = (len < (uint8_t)sizeof(s_nonce)) ? len : (uint8_t)sizeof(s_nonce);
    memcpy(buf, s_nonce, copy);
}

bool bt_response_ready() {
    return s_response_ready;
}

void bt_read_response(uint8_t* buf, uint8_t len) {
    uint8_t copy = (len < SESSION_PACKET_LEN) ? len : SESSION_PACKET_LEN;
    memcpy(buf, s_response_buf, copy);
    s_response_ready = false;
}

void bt_disconnect() {
    BLEDevice::stopAdvertising();
    // Deep sleep follows every call to bt_disconnect(); the radio going off
    // closes the BLE connection — no explicit ATT disconnect needed.
    s_connected         = false;
    s_subscribed        = false;
    s_response_ready    = false;
    s_response_received = 0;
    Serial.println("[BLE] advertising stopped");
}
