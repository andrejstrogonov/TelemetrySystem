#include <stdint.h>

/* Rev A: extended Hamming SEC-DED, 48 data bits -> 55-bit code word. */
void ECC_Turbo_Decoder(const uint8_t *r, uint8_t *data_out,
                       uint8_t *ecc_corrected, uint8_t *ecc_uncorrectable) {
    const uint8_t parity_pos[6] = {1, 2, 4, 8, 16, 32};
    uint8_t corrected_r[55];
    uint8_t syndrome = 0;
    uint8_t overall_parity = 0;

    for (int index = 0; index < 55; ++index) {
        corrected_r[index] = r[index] & 1U;
        overall_parity ^= corrected_r[index];
    }

    for (int parity_index = 0; parity_index < 6; ++parity_index) {
        const int position = parity_pos[parity_index];
        uint8_t check = 0;
        for (int code_position = 1; code_position <= 54; ++code_position) {
            if ((code_position & position) != 0) {
                check ^= corrected_r[code_position - 1];
            }
        }
        if (check != 0) {
            syndrome = (uint8_t)(syndrome | position);
        }
    }

    *ecc_corrected = 0;
    *ecc_uncorrectable = 0;
    if (syndrome == 0 && overall_parity != 0) {
        corrected_r[54] ^= 1U;
        *ecc_corrected = 1;
    } else if (syndrome != 0 && overall_parity != 0 && syndrome <= 54) {
        corrected_r[syndrome - 1] ^= 1U;
        *ecc_corrected = 1;
    } else if (syndrome != 0 && overall_parity == 0) {
        *ecc_uncorrectable = 1;
    }

    int data_index = 0;
    for (int code_position = 1; code_position <= 54; ++code_position) {
        if (code_position != 1 && code_position != 2 && code_position != 4 &&
            code_position != 8 && code_position != 16 && code_position != 32) {
            data_out[data_index++] = corrected_r[code_position - 1];
        }
    }
}
