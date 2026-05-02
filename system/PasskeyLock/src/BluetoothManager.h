#pragma once
#include <stdint.h>

// Initialise the ESP32 BLE stack as a GATT server (peripheral).
// Creates the service and characteristics; does NOT start advertising.
void bt_init();

// Begin advertising UUID_SERVICE so the iOS central can discover and connect.
void bt_advertise_start();

// Returns true once a central is connected.
bool bt_connected();

// Returns true once the iOS central has subscribed to challengeUUID AND the
// encrypted challenge nonce has been notified successfully.
bool bt_central_subscribed();

// Copy the 32-byte plaintext nonce that was used for the challenge into buf.
// Only valid after bt_central_subscribed() returns true.
void bt_get_nonce(uint8_t *buf, uint8_t len);

// Returns true when the full SESSION_PACKET_LEN-byte encrypted response has
// been received via writes on responseUUID.
bool bt_response_ready();

// Copy the received encrypted response packet into buf.
void bt_read_response(uint8_t *buf, uint8_t len);

// Stop advertising and drop the active connection (if any).
// Deep sleep follows immediately after in every call path, so a graceful ATT
// disconnect is skipped — the radio going off is sufficient.
void bt_disconnect();
