#include "RelayController.h"
#include "Config.h"
#include <Arduino.h>

static bool s_state = false;

void relay_init() {
    pinMode(PIN_RELAY_SET,   OUTPUT);
    pinMode(PIN_RELAY_RESET, OUTPUT);
    digitalWrite(PIN_RELAY_SET,   LOW);
    digitalWrite(PIN_RELAY_RESET, LOW);
}

void relay_on() {
    s_state = true;
    digitalWrite(PIN_RELAY_SET, HIGH);
    delay(RELAY_PULSE_MS);
    digitalWrite(PIN_RELAY_SET, LOW);
    Serial.printf("[RELAY]: ON\n");
}

void relay_off() {
    s_state = false;
    digitalWrite(PIN_RELAY_RESET, HIGH);
    delay(RELAY_PULSE_MS);
    digitalWrite(PIN_RELAY_RESET, LOW);
    Serial.printf("[RELAY]: OFF\n");
}

bool relay_state() {
    return s_state;
}
