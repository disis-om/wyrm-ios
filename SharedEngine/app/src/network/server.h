#ifndef SERVER_H
#define SERVER_H

#include <thermite.h>
#include <stdbool.h>
#include <stddef.h>

struct mg_connection;

void server_init(tenv* env);
/**
 * Opens the arena socket, or says it could not.
 *
 * Returns false only while a previous socket is still finishing — the caller
 * must keep the join pending and ask again rather than treat that as a dial.
 */
bool server_connect(tenv* env);
void server_poll(tenv* env);
void server_destroy(tenv* env);
bool server_address_is_valid(const char* address);

/**
 * The one way anything reaches the arena.
 *
 * Every gameplay packet and every handshake byte goes through here so that the
 * trace is a complete record rather than a sample — a send that bypasses this
 * is a send that will be missing from the line that explains a drop. It also
 * puts the null-connection check in one place instead of at seven call sites.
 */
void arena_send(struct mg_connection* c, const void* data, size_t len);

#endif
