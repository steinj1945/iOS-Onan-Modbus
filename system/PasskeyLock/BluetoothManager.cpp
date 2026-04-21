#include "BluetoothManager.h"
#include "Config.h"
#include <Arduino.h>
#include <SoftwareSerial.h>
#include <string.h>

// BlueSMiRF v2 uses the BC127 module.
// Communication: AT commands over UART.
// BLE central role: SCAN → CONNECT → GATT read/write.

static SoftwareSerial btSerial(BT_RX_PIN, BT_TX_PIN);

static bool s_found     = false;
static bool s_connected = false;
static bool s_response_ready = false;
static char s_peer_addr[18];       // "AA:BB:CC:DD:EE:FF\0"
static uint8_t s_response_buf[32];

// ── Helpers ───────────────────────────────────────────────────────

static void bt_cmd(const char *cmd) {
    btSerial.println(cmd);
}

// Read a line from BT serial into buf (up to max-1 chars). Returns false on timeout.
static bool bt_readline(char *buf, uint8_t max, uint32_t timeout_ms = 2000) {
    uint32_t t = millis();
    uint8_t i = 0;
    while (millis() - t < timeout_ms) {
        if (btSerial.available()) {
            char c = btSerial.read();
            if (c == '\n') { buf[i] = '\0'; return true; }
            if (c != '\r' && i < max - 1) buf[i++] = c;
        }
    }
    buf[i] = '\0';
    return false;
}

static void bt_flush() {
    while (btSerial.available()) btSerial.read();
}

// ── Public API ────────────────────────────────────────────────────

void bt_init() {
    btSerial.begin(BT_BAUD);
    delay(500);
    bt_flush();

    // Reset to known state
    bt_cmd("AT+RESET");
    delay(1000);
    bt_flush();

    // Set BLE central role (BC127 command)
    bt_cmd("AT+BTMODE 4");   // 4 = BLE Central
    delay(200);
    bt_flush();

    // Set device name
    bt_cmd("AT+NAME OnanLock");
    delay(200);
    bt_flush();

    bt_cmd("AT+SAVE");
    delay(200);
}

void bt_scan_start() {
    s_found     = false;
    s_connected = false;
    s_response_ready = false;
    bt_flush();
    // Scan for 10 seconds, report all found devices
    bt_cmd("AT+SCAN 10");
}

bool bt_scan_found() {
    // Parse scan result lines: "SCAN <addr> <rssi> <name>"
    char line[80];
    while (btSerial.available()) {
        if (bt_readline(line, sizeof(line), 50)) {
            if (strncmp(line, "SCAN ", 5) == 0) {
                // Extract RSSI (field 3)
                char *tok = strtok(line + 5, " ");  // addr
                if (!tok) continue;
                strncpy(s_peer_addr, tok, sizeof(s_peer_addr) - 1);
                tok = strtok(NULL, " ");  // rssi
                if (!tok) continue;
                int rssi = atoi(tok);
                tok = strtok(NULL, " ");  // service UUID or name — filter by UUID
                if (tok && strstr(tok, "A1B2C3D4") != NULL && rssi >= RSSI_THRESHOLD) {
                    s_found = true;
                    return true;
                }
            }
        }
    }
    return false;
}

void bt_connect() {
    char cmd[40];
    snprintf(cmd, sizeof(cmd), "AT+CONNECT %s", s_peer_addr);
    bt_cmd(cmd);
}

bool bt_connected() {
    char line[40];
    while (btSerial.available()) {
        if (bt_readline(line, sizeof(line), 50)) {
            if (strstr(line, "CONNECTED") != NULL) {
                s_connected = true;
                return true;
            }
        }
    }
    return s_connected;
}

void bt_disconnect() {
    if (s_connected) {
        bt_cmd("AT+DISCONNECT");
        delay(200);
        s_connected = false;
    }
}

void bt_sleep() {
    bt_cmd("AT+SLEEP");
}

void bt_send_challenge(const uint8_t *nonce, uint8_t len) {
    // Write nonce as hex string to CHALLENGE characteristic
    // BC127 GATT write: AT+GATTWRITE <handle> <hex>
    // Handle 0x0010 = CHALLENGE char (set during provisioning)
    char cmd[100] = "AT+GATTWRITE 0x0010 ";
    uint8_t pos = strlen(cmd);
    for (uint8_t i = 0; i < len && pos < sizeof(cmd) - 3; i++) {
        snprintf(cmd + pos, 3, "%02X", nonce[i]);
        pos += 2;
    }
    bt_cmd(cmd);
}

bool bt_response_ready() {
    // BC127 notifies: "GATT_VAL 0x0011 <hex>" when peripheral writes RESPONSE char
    char line[100];
    while (btSerial.available()) {
        if (bt_readline(line, sizeof(line), 50)) {
            if (strncmp(line, "GATT_VAL 0x0011 ", 16) == 0) {
                // Decode hex response into s_response_buf
                const char *hex = line + 16;
                for (uint8_t i = 0; i < 32 && hex[i*2] && hex[i*2+1]; i++) {
                    char byte_str[3] = { hex[i*2], hex[i*2+1], '\0' };
                    s_response_buf[i] = (uint8_t)strtol(byte_str, NULL, 16);
                }
                s_response_ready = true;
                return true;
            }
        }
    }
    return false;
}

void bt_read_response(uint8_t *buf, uint8_t len) {
    memcpy(buf, s_response_buf, len < 32 ? len : 32);
    s_response_ready = false;
}

void bt_notify_status(uint8_t status) {
    char cmd[30];
    snprintf(cmd, sizeof(cmd), "AT+GATTWRITE 0x0012 %02X", status);
    bt_cmd(cmd);
}
