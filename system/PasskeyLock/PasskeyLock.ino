#include <EEPROM.h>
#include "Config.h"
#include "StateMachine.h"

uint8_t g_hmac_key[HMAC_KEY_LEN];

void setup() {
    Serial.begin(115200);
    // Load secret from EEPROM (written by Provisioning.ino)
    eeprom_read_block(g_hmac_key, (const void *)HMAC_KEY_EEPROM, HMAC_KEY_LEN);
    sm_init();
}

void loop() {
    sm_update();
}
