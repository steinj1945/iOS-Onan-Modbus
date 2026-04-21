#include "StateMachine.h"
#include "BluetoothManager.h"
#include "RelayController.h"
#include "CryptoAuth.h"
#include "Config.h"
#include <Arduino.h>
#include <avr/sleep.h>
#include <avr/power.h>

volatile bool g_button_pressed = false;

static State       s_state       = State::SLEEP;
static uint32_t    s_state_enter = 0;
static uint8_t     s_nonce[32];

static void enter(State next) {
    s_state       = next;
    s_state_enter = millis();
}

static bool timed_out(uint32_t limit_ms) {
    return (millis() - s_state_enter) >= limit_ms;
}

static void go_sleep() {
    relay_off();
    bt_disconnect();
    bt_sleep();
    g_button_pressed = false;

    // Visual indicator: LED off
    digitalWrite(PIN_STATUS_LED, LOW);

    // AVR power-down sleep — woken by INT0 (button)
    set_sleep_mode(SLEEP_MODE_PWR_DOWN);
    sleep_enable();
    sleep_cpu();          // ← execution halts here until interrupt
    sleep_disable();

    enter(State::SCANNING);
}

void sm_init() {
    pinMode(PIN_BUTTON, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(PIN_BUTTON), []() {
        g_button_pressed = true;
    }, FALLING);

    relay_init();
    bt_init();
    enter(State::SLEEP);
}

void sm_update() {
    switch (s_state) {

    case State::SLEEP:
        go_sleep();
        // Returns here after button wakes MCU
        break;

    case State::SCANNING:
        digitalWrite(PIN_STATUS_LED, (millis() / 300) % 2);  // fast blink
        if (g_button_pressed) { g_button_pressed = false; enter(State::SLEEP); break; }
        if (timed_out(SCAN_TIMEOUT_MS)) { enter(State::SLEEP); break; }
        if (bt_scan_found()) enter(State::CONNECTING);
        break;

    case State::CONNECTING:
        digitalWrite(PIN_STATUS_LED, (millis() / 100) % 2);  // very fast blink
        if (timed_out(CONNECT_TIMEOUT_MS)) { enter(State::SCANNING); break; }
        if (!bt_connected()) break;
        // Connected — generate nonce and send challenge
        random_nonce(s_nonce, sizeof(s_nonce));
        bt_send_challenge(s_nonce, sizeof(s_nonce));
        enter(State::AUTHENTICATING);
        break;

    case State::AUTHENTICATING:
        if (timed_out(AUTH_TIMEOUT_MS)) { enter(State::SLEEP); break; }
        if (!bt_response_ready()) break;
        {
            uint8_t response[32];
            bt_read_response(response, sizeof(response));
            if (hmac_verify(s_nonce, sizeof(s_nonce),
                            response, sizeof(response),
                            HMAC_KEY, HMAC_KEY_LEN)) {
                relay_on();
                bt_notify_status(0x01);
                digitalWrite(PIN_STATUS_LED, HIGH);
                enter(State::UNLOCKED);
            } else {
                bt_notify_status(0x00);
                enter(State::SLEEP);
            }
        }
        break;

    case State::UNLOCKED:
        if (g_button_pressed || timed_out(UNLOCK_AUTO_CLOSE_MS)) {
            g_button_pressed = false;
            enter(State::SLEEP);
        }
        break;
    }
}
