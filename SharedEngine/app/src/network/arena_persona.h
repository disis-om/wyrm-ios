#ifndef ARENA_PERSONA_H
#define ARENA_PERSONA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * Which slither client Wyrm claims to be on the wire.
 *
 * There are two originals and they are not the same client. The web client
 * (`game1107241958.js`, version 291) and the Android AIR client
 * (`wise newton/.../Main.as`, version 294) carry different fingerprints, answer
 * the arena's challenge with completely different algorithms, and send a
 * different settings packet on open.
 *
 * That distinction is the whole reason this file exists. The web client's
 * challenge packet contains the obfuscated program from which the web client
 * derives its 27-byte response. The AIR client's answer is instead a CRC32
 * compiled into a store binary.
 *
 * Neither can be proven from source alone, so Wyrm carries both and lets the
 * retry path decide — see `retry_join` in `game/loop.c`. Once one is proven on
 * device the other is a small subtraction.
 */
typedef struct arena_persona {
  /* Goes in every arena log line, so one capture names the winner. */
  const char* name;
  /* Bytes 2..3 of the join packet. */
  uint16_t version;
  /* Bytes 4..23 of the join packet. */
  uint8_t fingerprint[20];
  /* true: the 8-byte CRC32 answer below. false: `decode_secret`'s 27 bytes. */
  bool crc32_answer;
  /* true: the AIR settings block. false: the web client's bare `63 00`. */
  bool full_c_packet;
} arena_persona;

/*
 * Web first, and that order is measured rather than assumed.
 *
 * On `148.113.20.151`, the web identity answered the challenge, was admitted,
 * and played a full seventeen-second match. The AIR identity answered the same
 * challenge on the same arena and the server sent literally nothing back before
 * hanging up — one inbound packet, the challenge itself. Vlither, which does
 * work on these arenas, carries the web fingerprint and does not contain the
 * AIR one at all.
 *
 * AIR stays as a fallback because it costs nothing: the retry only alternates
 * when an identity was actually put to the test, so a refused socket never
 * spends an attempt on it.
 */
enum {
  ARENA_PERSONA_WEB = 0,
  ARENA_PERSONA_AIR = 1,
  NUM_ARENA_PERSONAS = 2
};

/** The persona at `index`, wrapped into range so a stale save cannot escape. */
const arena_persona* arena_persona_get(int index);

/**
 * The AIR client's challenge answer, transcribed from `Main.as:36536-36572`.
 *
 * Writes exactly `ARENA_CRC32_ANSWER_LEN` bytes and returns that length. The
 * command byte at `packet[0]` is skipped, as the reference skips it: only the
 * challenge body is hashed.
 */
enum { ARENA_CRC32_ANSWER_LEN = 8 };
size_t arena_persona_crc32_answer(const uint8_t* packet, size_t packet_len,
                                  uint8_t* out);

#endif
