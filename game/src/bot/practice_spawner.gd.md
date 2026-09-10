# practice_spawner.gd

## Function

Offline practice-duel plumbing (DESIGN.md Appendix A: the practice bot).
A dormant node in the arena scene that spawns the AI opponent and runs
the endless round loop — but ONLY when the main menu queued a duel, so
PLAY SOLO and every netplay use of the same map are untouched.

## Interface

- `class_name PracticeSpawner extends Node`; instanced in
  `graybox_corridor.tscn` as `PracticeSpawner`.
- Exports: `bot_spawn` (world position, default `(0, 2.6, 430)` — the far
  end of the corridor, opposite the human spawn at z −430, so duels open
  across the whole arena — Lily's call), `bot_spawn_yaw_deg` (default 0 =
  facing −Z, toward the human spawn).
- Consumes `BotController.pending_loadout` (set by `main_menu.gd`,
  −1 = none) and resets it to −1 immediately — a later plain scene load
  spawns nothing.
- Preloads `player.tscn` and `default_bot.tres`.

## Implementation

`_ready` bails when `Net.active` or nothing is pending; otherwise defers
`_spawn` (the scene tree is still being built during `_ready`). Spawning
first frees every `"target"`-group dummy (`_clear_dummies` — practice is
a duel, not target practice; solo keeps them), then:
instance `player.tscn` with `bot_controlled = true` set BEFORE
`add_child` (the flag branches `_ready`), place it at `bot_spawn`, fix
its loadout for the session via `set_loadout` (after add — it touches
`@onready` arm nodes), then attach a `BotController.new()` child with the
default BotConfig.

Round loop: either body's `died` → `_reset_round` (deferred — never
teleport bodies mid-physics-tick) respawns BOTH bodies, so every round
opens from spawn state behind the standard 3-2-1 countdown, winner
included. The human's `respawned` (manual T reset, `kill_y`) resets the
bot too, keeping rounds symmetric; the `_resetting` flag stops the
resets the handlers themselves trigger from recursing. Offline `died` /
`damaged` exist because `apply_damage` emits them when
`Net.match_host == null` (see player.gd.md).

## Assertions

- Must stay inert (no spawn, no connections) when `Net.active` or
  `pending_loadout < 0` — netplay strips/spawns its own bodies and must
  never meet a practice bot.
- `pending_loadout` is consumed exactly once, before any await/defer.
- `bot_controlled` must be set before `add_child`.
- Round resets go through each body's `_respawn()` deferred — both bodies
  reset together, always into the countdown.
