#pragma once

// ── Pin assignments ───────────────────────────────────────────────
#define PIN_BUTTON      2   // INT0 — wake-from-sleep interrupt
#define PIN_RELAY       7   // Relay IN — HIGH = energised (open)
#define PIN_STATUS_LED  13  // Built-in LED for state feedback

// ── BlueSMiRF v2 UART ────────────────────────────────────────────
#define BT_BAUD         115200
#define BT_RX_PIN       10  // SoftwareSerial RX (connect to BT TX)
#define BT_TX_PIN       11  // SoftwareSerial TX (connect to BT RX)

// ── BLE service / characteristic UUIDs ──────────────────────────
// Must match the iOS/Watch app exactly.
#define UUID_SERVICE    "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
#define UUID_CHALLENGE  "A1B2C3D4-E5F6-7890-ABCD-EF1234567891"
#define UUID_RESPONSE   "A1B2C3D4-E5F6-7890-ABCD-EF1234567892"
#define UUID_STATUS     "A1B2C3D4-E5F6-7890-ABCD-EF1234567893"

// ── Timing (ms) ──────────────────────────────────────────────────
#define SCAN_TIMEOUT_MS         15000   // Give up scanning after 15 s
#define CONNECT_TIMEOUT_MS       5000   // Give up connecting after 5 s
#define AUTH_TIMEOUT_MS          5000   // Give up waiting for HMAC after 5 s
#define UNLOCK_AUTO_CLOSE_MS   300000   // Auto-relock after 5 min

// ── RSSI proximity threshold ─────────────────────────────────────
// -70 dBm ≈ 5 m  (standard proximity)
// -50 dBm ≈ 0.3 m (NFC-style Watch tap)
#define RSSI_THRESHOLD          -70

// ── HMAC key (32 bytes, loaded from EEPROM at boot) ──────────────
// Write the key using system/Provisioning/Provisioning.ino before
// flashing this sketch. EEPROM address 0–31 holds the 32-byte secret.
#define HMAC_KEY_LEN      32
#define HMAC_KEY_EEPROM   0     // EEPROM start address

// g_hmac_key is populated in setup() via eeprom_read_block().
// Declared extern here; defined in PasskeyLock.ino.
extern uint8_t g_hmac_key[HMAC_KEY_LEN];
#define HMAC_KEY     g_hmac_key
