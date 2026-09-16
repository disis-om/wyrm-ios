#ifndef NTL_NET_H
#define NTL_NET_H

#include <thermite.h>

/**
 * The NTL network — where everybody else's tags come from.
 *
 * A second websocket, alongside the arena's own, to `ws.ntl-slither.com`. It is
 * not part of slither and the arena knows nothing about it: it is how every
 * player running the mod tells every other what they are wearing.
 *
 * Documented in ntl-tags.md. Two directions, and they are not symmetrical:
 * outbound is JSON, inbound is a flat table of four-byte records.
 */

/** Opens, announces and keeps the connection fed. Safe to call every frame. */
void ntl_net_tick(tenv* env);

/** Drops the connection and forgets what everyone was wearing. */
void ntl_net_close(tenv* env);

#endif
