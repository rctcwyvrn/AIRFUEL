# network.gd

## Function

Autoload `Net` — prototype LAN multiplayer (a Step 4 precursor; DESIGN.md
§20.2's real architecture is server-authoritative with rewind, this is NOT
that). Listen-server over ENet, client-authoritative movement: correct at
~1 ms LAN trust, throwaway-by-design beyond the peer/spawn plumbing.

## Interface

- Autoload singleton `Net` (registered in project.godot).
- Public API (used by the main menu): `host()` and `join(ip)` — both load
  the arena first, then bring up the peer. CLI equivalents (after `--`):
  `--server` / `--client <ip>` still work for headless testing. No args and
  no menu action → `active` stays false; offline solo untouched.
- Read by `player.gd`: `Net.active` (gates all its rpc sends).
- `players: Dictionary` (peer id → node) is the roster; nodes are named
  `str(peer_id)` and get `set_multiplayer_authority(id)` **before** add.

## Implementation

Server-driven roster: on `peer_connected`, the server sends the new peer
each existing id, broadcasts the new id to everyone, and spawns locally —
every peer runs the same `_spawn_player` so state stays deterministic
(each spawn prints id/position/authority/camera — keep these, they were
what caught the client-camera bug).
`_load_arena` switches from the menu to the corridor, awaits the swap,
then `free()`s the corridor's offline `Player` and every `"target"`-group
dummy (LAN is PvP-only; dummies are solo practice). Peer creation happens only
AFTER the arena is current, so no spawn rpc can land in the menu scene. Spawn
transforms (`_spawn_transform_for_index`): spawn-order index alternates
ends (even → −z facing +z, odd → +z facing −z) with +8 m lateral spread
per pair, so 1v1 is always opposite ends and 3+ players don't stack. The
index is `players.size()` at spawn time — identical on all peers because
the server-driven roster delivers spawns in the same order everywhere. Client quits on `server_disconnected`.

`kill_scored` (any_peer rpc) is the round-reset channel: the victim's
authority targets the killer's peer, which resets its own authority player.

## Assertions

- Authority is set before `add_child`, on every peer identically — late
  authority flips would let two peers simulate one body.
- Offline (`active == false`) must remain a zero-cost no-op path.
- The transform passed pre-add IS the spawn (player `_ready` captures it
  as `spawn_transform` for kill-resets) — never move a player post-add
  expecting spawn_transform to follow.
