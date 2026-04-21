#pragma once
#include <stdint.h>

// Initialise BlueSMiRF v2 via SoftwareSerial and put it in BLE central mode.
void bt_init();

// Begin scanning for a peripheral advertising UUID_SERVICE.
// Resets internal found/connected state.
void bt_scan_start();

// Returns true once a device with RSSI >= RSSI_THRESHOLD has been found.
bool bt_scan_found();

// Initiate connection to the found device. Non-blocking; poll bt_connected().
void bt_connect();

bool bt_connected();

void bt_disconnect();

// Put BlueSMiRF into low-power command mode between uses.
void bt_sleep();

// Write the 32-byte nonce to the CHALLENGE characteristic.
void bt_send_challenge(const uint8_t *nonce, uint8_t len);

// Returns true when the peripheral has written to the RESPONSE characteristic.
bool bt_response_ready();

// Copy the response bytes into buf (caller must provide 32 bytes).
void bt_read_response(uint8_t *buf, uint8_t len);

// Write a 1-byte status value to the STATUS characteristic (notify).
void bt_notify_status(uint8_t status);
