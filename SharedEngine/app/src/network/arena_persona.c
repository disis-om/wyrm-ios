#include "arena_persona.h"

#include <stdlib.h>

#include "../external/mongoose.h"

/*
 * The two client identities, in the order the retry path tries them.
 *
 * Web first — see the note beside the enum for why that order is the measured
 * one. The AIR fingerprint below is `Main.as:36660`, a genuinely different
 * twenty bytes from the web client's rather than a reordering of them.
 */
static const arena_persona personas[NUM_ARENA_PERSONAS] = {
    [ARENA_PERSONA_AIR] = {.name = "air",
                           .version = 294,
                           .fingerprint = {174, 130, 141, 205, 68, 146, 67,
                                           52, 249, 89, 211, 15, 66, 45, 140,
                                           145, 133, 167, 10, 202},
                           .crc32_answer = true,
                           .full_c_packet = true},
    [ARENA_PERSONA_WEB] = {.name = "web",
                           .version = 291,
                           .fingerprint = {54, 206, 204, 169, 97, 178, 74, 136,
                                           124, 117, 14, 210, 106, 236, 8, 208,
                                           136, 213, 140, 111},
                           .crc32_answer = false,
                           .full_c_packet = false},
};

const arena_persona* arena_persona_get(int index) {
  /* A persona index survives in the settings file, and a file written by a
     build that knew about more of them must not walk off the end of this. */
  if (index < 0 || index >= NUM_ARENA_PERSONAS) index = ARENA_PERSONA_AIR;
  return personas + index;
}

size_t arena_persona_crc32_answer(const uint8_t* packet, size_t packet_len,
                                  uint8_t* out) {
  /* The reference reads `param2 - 1` bytes starting at `param1[1]`, so a
     challenge that is only its command byte hashes nothing. CRC32 of an empty
     buffer is well defined and the arena will simply refuse the answer, which
     is the honest outcome for a challenge that carried none. */
  size_t body_len = packet_len ? packet_len - 1 : 0;

  /* `(byte + position * 3) % 256`, exactly as `Main.as` walks it backwards.
     Direction does not matter here; the arithmetic is per-byte. */
  uint8_t stack_buf[256];
  uint8_t* body = stack_buf;
  if (body_len > sizeof(stack_buf)) {
    body = malloc(body_len);
    if (!body) return 0;
  }
  for (size_t i = 0; i < body_len; i++)
    body[i] = (uint8_t)((packet[i + 1] + i * 3) % 256);

  uint32_t crc = mg_crc32(0, (const char*)body, body_len);
  if (body != stack_buf) free(body);

  /* `writeInt` is big-endian, and the reference indexes that ByteArray in
     order — so the most significant byte is nibbled first. */
  uint8_t be[4] = {(uint8_t)(crc >> 24), (uint8_t)(crc >> 16),
                   (uint8_t)(crc >> 8), (uint8_t)crc};

  int c = 12;
  size_t o = 0;
  for (int i = 0; i < 4; i++) {
    int high = be[i] / 16;
    int low = be[i] % 16;
    /* The case bit is random in the reference and the arena ignores it: the
       answer is read as a letter's position in the alphabet, not its case. */
    out[o++] = (uint8_t)(65 + (rand() % 2 ? 32 : 0) + (high + c) % 26);
    c += 11;
    out[o++] = (uint8_t)(65 + (rand() % 2 ? 32 : 0) + (low + c) % 26);
    c += 11;
  }
  return o;
}
