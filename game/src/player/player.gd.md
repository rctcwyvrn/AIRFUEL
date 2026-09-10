# player.gd

## Function

The player body's identity and orchestration (roadmap Steps 1+2 plus
server-authoritative netplay, DESIGN.md §20.2 N1+N2): state, net roles,
the `_simulate()` tick, client prediction, respawn, and the HUD-facing
surface. Also the body of the offline practice bot (`bot_controlled`,
Appendix A's practice opponent — see `src/bot/`).

**Split 2026-09-10 (Lily's call)**: the mechanics live in sibling
static-helper classes over this body — the `PlayerState` pattern, ALL
state stays HERE so the codec and prediction are untouched:

- `player_movement.gd` (`PlayerMovement`) — §4/§5 movement, dashes,
  wallrun, assists.
- `player_combat.gd` (`PlayerCombat`) — §7/§8 arms, rail, sword,
  loadout + viewmodel visuals.
- `player_recorder.gd` (`PlayerRecorder`) — TAS tapes.
- `player_state.gd` (`PlayerState`) — state/cmd codec (pre-existing).
- `player_fx.gd` (`PlayerFx`) — one-shot cosmetics (pre-existing).

(Aim crush was cut 2026-09-09, Appendix A — charging never degrades a
PLAYER's turn rate; the practice bot self-imposes a tracking handicap in
its controller, not here.)

## Interface

- `class_name AirfuelPlayer extends CharacterBody3D`; the scene root of
  `player.tscn`, always in group `"player"`.
- Exports: `config: MovementConfig`, `combat: CombatConfig` (both required,
  never null at runtime), `mouse_sensitivity: float`, and two puppet-input
  flags (both mean: no camera claim, no mouse, no Input reads; a controller
  node with `process_physics_priority < 0` writes the `cmd_*` fields):
  - `ghost_controlled: bool` — TAS ghost: translucent orange body,
    excluded from HUD adoption and from rail/sword damage, collision
    layer 0 / mask world-only.
  - `bot_controlled: bool` — the practice opponent (Appendix A, spawned
    by `PracticeSpawner` with a `BotController` child): a full combat
    participant — normal player collision, damageable, scanned by the
    HUD as an enemy — rendered like a net puppet (body + shoulder
    `PuppetArm` blocks with the real-arm charge glow, per-loadout tint
    applied on `set_loadout` post-ready).
- **`role: NetRole`** — set by `Net` on the instance *before* `add_child`
  (`_ready` branches on it; the scene default `LOCAL` keeps offline
  untouched). Semantics:
  - `LOCAL` — authoritative + local human input: offline solo, the LAN
    host's own body, TAS ghosts (via `ghost_controlled`), practice bots.
  - `DRIVEN` — authoritative + net cmds: a remote client's body on the
    server. `MatchHost` writes its cmds (`PlayerState.apply_cmd`) before
    the tick; rendered like a puppet on a LAN host's screen.
  - `PREDICTED` — the client's own body: simulates immediately from local
    input, ships cmds to the server, reconciles against snapshots.
  - `REPLICA` — render-only puppet of another player on a client: physics
    processing disabled in `_ready`, fed by render-state rows, position
    eased in `_process`. Never simulated here.
- **Command layer**: all gameplay input flows through per-tick `cmd_move/
  cmd_down_dash/cmd_jump/cmd_dash/cmd_fire_l/cmd_fire_r/cmd_swap/
  cmd_respawn`, filled by `_gather_input` from the Input singleton for
  humans, or by a controller for ghosts/bots. New input reads in physics
  code MUST go through cmds, never Input directly. With `Net.autoduel` a
  PREDICTED body runs `_autoduel_cmds()` from `_gather_input`:
  cheat-aims at the opponent's REPLICA, strafes flipping every 96 ticks,
  fires the left rail on a 300-tick cadence phase-offset by 150 for the
  higher peer id — the §20.2 N2 rewind A/B instrument.
- **Cmd encoding**: `PlayerState.encode_cmd(p)`/`PlayerState.apply_cmd`
  pack/unpack the `CMD_SIZE = 8` array `[tick, move.x, move.y, down_dash,
  flags, yaw, pitch, seen_server_tick]`; flags bit order
  jump|dash|fireL|fireR|swap|respawn — identical to the TAS tape's
  bitmask. View angles ride with cmds (client-authoritative) and are
  deliberately **not** part of captured state.
- **`seen_server_tick: int`** — the newest server tick this client has
  rendered: set from snapshots on a PREDICTED body, echoed in cmd slot
  [7], written onto the DRIVEN body by `apply_cmd`. The rewind target for
  this player's shots (§20.2 N2). `0` = never seen / no rewind.
- **Net API** (called by `Net` / `MatchHost`):
  - `on_server_snapshot(ack_tick, state)` — queues a server snapshot
    (PREDICTED only); applied at the next tick's start.
  - `render_state() -> PackedFloat32Array` — the 13-float render row
    `[pos*3, vel*3, yaw, pitch, progL, progR, loadout, hp, sword_active]`.
    The peer id deliberately travels OUTSIDE the array, as a real int:
    float32's 24-bit mantissa silently corrupts 10-digit ENet peer ids
    (shipped once as "replicas never moved").
  - `apply_replica(r)` — applies a render row to a REPLICA (position
    target, velocity, look, arm progress, hp, loadout retint of the
    puppet arms, `sword_active` for `PlayerTrails`' blue lunge ribbon).
  - `capture_state()` / `restore_state(s)` — delegate to `PlayerState`
    (fixed 42-slot codec, see `player_state.gd.md`).
  - `apply_damage(amount, from_id) -> bool` — authoritative damage;
    returns whether the hit killed. Only LOCAL/DRIVEN bodies on the
    simulating process ever run it. With a match host it notifies
    `Net.match_host.on_damage` (which respawns the victim on a kill);
    **offline** (practice duels) it instead emits `damaged`/`died`
    directly and `PracticeSpawner` handles the respawn.
  - `on_net_damage(attacker_id, hp_left)` — client-side arrival of an
    authoritative damage event: syncs hp, emits the HUD signals.
  - `sim_active() -> bool` — false only for REPLICA.
- Signals: `shot_fired(side, result)` ("L"/"R" × "miss"/"body"/"head"/
  "kill" — HUD hitmarkers; emitted directly only offline, in netplay by
  Net from authoritative events), `damaged(amount, from_id)` / `died`
  (HUD flash/arc/death flash; offline emitted by `apply_damage`),
  `respawned` (ghost restart + practice-round sync).
- **Loadouts (8.3)**: Tab (`swap_loadout` → `cmd_swap`, handled in
  `PlayerCombat.handle_arms`) cycles `LOADOUTS` (rail+rail → rail+sword →
  sword+sword); `set_loadout(index)` resets both arms, pending shots,
  sword state, then `PlayerCombat.apply_loadout_visuals`. `arm_types`
  holds "rail"/"sword" per side; `loadout_name()` feeds the HUD. Weapon
  color/glow constants (`RAIL_VM_COLOR`, `SWORD_VM_COLOR`,
  `SWORD_FLARE_COLOR`, `VM_EMISSION_WARM`, `VM_COOLDOWN_COLOR`) live
  here as the shared palette.
- HUD-facing reads: `fuel`, `ramp_grace_timer`, `config`, `combat`,
  `horizontal_speed()`, `state_name()`, `move_locked`, `hp`,
  `arm_progress_left/right()` (rail charge, or sword cooldown-readiness),
  **`display_arm_progress(index)`** (role-aware — REPLICA from
  snapshot-fed `_net_prog`, simulated bodies from real arm state; the
  HUD's enemy-charge-warning source), `arm_types`, `loadout_name()`,
  `run_time`, `run_finished`, `countdown`, `recording`.
- Helper-facing state (public by necessity — the helpers are the only
  intended writers): `pending_arms`, `shot_gap_timer`, `sword_cd`,
  `sword_active`, `sword_side`, `tape_lines`, `rail_vm_mesh`/
  `sword_vm_mesh`, all movement/timer fields, and `_spend(amount)` (the
  all-or-nothing fuel spend).
- Expected children: `Head` (pitch) → `Head/Camera3D` (roll + FOV feel);
  `ArmLeft`/`ArmRight` (`RailArm`); `Head/Camera3D/ViewmodelL/R`;
  `PuppetArmL/R` and `BodyMesh`/`Head/HeadMesh` (puppet visuals). Yaw
  goes on the body itself.
- Consumes input actions: `move_forward/back/left/right`, `down_dash`
  (Q), `jump`, `dash` (Shift), `fire_left`/`fire_right`, `swap_loadout`
  (Tab), `record` (F5, dev-only), `respawn` (T, solo), `ui_cancel`.
- `MoveState { GROUNDED, AIRBORNE, WALLRUN }` in `state`.

## Implementation

**Per-role tick flow (`_physics_process`)**:

- PREDICTED: `_maybe_reconcile()` → `_gather_input()` → `net_tick += 1` →
  encode + store + `Net.send_cmd` → `_simulate(delta)` → capture into
  `_state_history` → camera feel + `PlayerCombat.update_viewmodels`.
  Reconciliation runs at tick *start*, inside the physics frame, so a
  replay's `move_and_slide` uses the physics delta.
- LOCAL: `_gather_input()` → `_simulate()` → camera feel, viewmodels,
  `PlayerRecorder.record_tick`.
- DRIVEN: `_simulate()` only — `MatchHost` already wrote this tick's cmds.
- REPLICA: `_physics_process` disabled; only `_process` runs (position
  lerp, shoulder charge glow from `_net_prog`).

**`_simulate(delta)` — the re-runnable tick**: countdown freeze → run
clock → timer decays → sword tick + `PlayerCombat.sword_hit_check` →
jump buffer → `move_locked` recompute + `PlayerCombat.handle_arms` →
per-state move (`PlayerMovement.ground_move`/`air_move`/`wallrun_move`)
→ `PlayerMovement.handle_dashes` → terminal-velocity/charge clamps →
`move_and_slide()` → `PlayerMovement.apply_glide` →
`PlayerMovement.update_state` → respawn check (manual `cmd_respawn` only
offline; `kill_y` always) → **arms stepped last** (`arm_*.step(delta)` —
a charge completing this tick fires next tick). Everything a tick's
outcome depends on lives inside `_simulate` (and in `capture_state()`);
everything visual-only stays outside so prediction can re-run the tick.

**Charge freeze (§7.2)**: `move_locked` derives from arm `is_locking()`
each tick; while locked, wish is zeroed, dashes are gated (in the
helpers), and total speed clamps to `combat.charge_speed_cap`. Aim stays
free while charging (aim crush cut).

**Prediction machinery (PREDICTED)**: `_cmd_history`/`_state_history`
back reconciliation. `on_server_snapshot` only queues; `_maybe_reconcile`
applies: prune ≤ ack, `PlayerState.agree` short-circuit, else save live
yaw/pitch, set `replaying`, `restore_state`, replay cmds ack+1..net_tick
through `apply_cmd` + `_simulate`, clear `replaying`, restore the live
look — a snapshot must never yank the camera. The `replaying` flag makes
the combat helpers skip one-shot effects (see player_combat.gd.md).

**_ready role branches**: ghost (translucent orange, collision
layer 0/mask world-only), bot (puppet visuals, normal combat), REPLICA
(physics off, puppet visuals), DRIVEN (headless-ish puppet), else
LOCAL/PREDICTED claim the camera explicitly (auto-current fails when a
remote puppet's camera entered the viewport first — shipped once as
"joiner stuck staring at a grey wall"). Viewmodel materials are
**duplicated per body** here: scene sub_resources are shared across all
instances, and with two simulating bodies (practice duels, TAS ghost)
every `update_viewmodels` writer otherwise bleeds its charge glow /
lunge flare / tint onto every other body's viewmodels (shipped as
cross-glowing weapons). Puppet-arm materials get the same duplication in
the puppet branches.

**Graybox visuals**: beams/canisters live in `PlayerFx`; viewmodel
glow/pose in `PlayerCombat.update_viewmodels`. In `_process`, DRIVEN
(LAN host screen), `bot_controlled`, and REPLICA bodies drive the
shoulder-block glow — from real arm progress (DRIVEN/bot) and
`_net_prog` (REPLICA) — the §8.1 "loud charge" tell, visually. Keep this
synced: an invisible enemy charge would gut the dodge duel.

**Trails** (`PlayerTrails` child, created in `_ready`, all bodies):
orange flight line + blue lunge ribbon; `_respawn` calls
`_trails.clear()` so the line never connects across a teleport.

**TAS recording**: see `player_recorder.gd.md`. F5 toggles offline only;
`_respawn` restarts a live tape (`PlayerRecorder.restart_tape`); the
ghost body sets `collision_layer = 0`, `collision_mask = 1` so replays
can't touch players (nondeterministic desync).

**Reset countdown** (`reset_countdown`): every `_respawn` freezes the
body while `countdown` runs; run clock, tape, and ghost playback all
gate on it. `_respawn` zeroes EVERY transient (timers, sword state,
pending arms, arm resets) — recordings replay from spawn, so spawn state
must be bit-identical between a run and its ghost. `finish_run()`
(FinishZone) freezes the clock and auto-saves an active recording.

## Assertions

- `fuel` stays in `[0, config.fuel_max]`; all spends go through `_spend`,
  which is all-or-nothing (never partial-drains below the cost).
- Dismount is the only in-play fuel refill (§5.1 — do not add refills on
  kill, death, or pickup). Movement invariants: `player_movement.gd.md`;
  combat invariants: `player_combat.gd.md`.
- The speed ceiling is **soft**: above `terminal_velocity` speed decays
  at `overspeed_decay` instead of hard-clamping — only the sword lunge
  legitimately enters that regime. `velocity.y >= -terminal_fall_speed`
  stays hard every tick, as does the charge cap while `move_locked`.
- `move_locked` must derive only from arm `is_locking()` — freeze from
  first trigger press to last pending shot, never during COOLDOWN.
- No gameplay literals: any new tunable must be a `MovementConfig`/
  `CombatConfig` field. (Known exceptions to fix if touched: camera-feel
  lerp rates and FOV factor, the replica position-lerp rate, the
  autoduel cadence literals `300`/`150`/`96`, viewmodel glow
  multipliers, and the structural constants listed in
  player_movement.gd.md.)
- **Peer ids never enter float arrays**: `render_state` is 13 floats
  with the id traveling beside it as a real int.
- **View angles never enter state**: yaw/pitch are client-authoritative,
  travel with cmds, and reconciliation restores the live look after a
  replay.
- **Replays never re-do damage or effects**: every one-shot side effect
  sits behind the `replaying` guard (enforced in the combat helpers);
  only gameplay math and state-machine advancement run in a replayed
  tick.
- **REPLICA never simulates**; **only authoritative roles apply damage**
  (LOCAL/DRIVEN on the simulating process — offline player-vs-player
  damage rides the LOCAL branch only).
- `bot_controlled` bodies are real combatants: normal player collision,
  damageable — only `ghost_controlled` gets the combat/collision
  exclusions. Neither flag may ever read Input.
- Everything `_simulate`'s outcome depends on must be inside `_simulate`
  and captured by `PlayerState` — a new sim field missing from the codec
  is a silent desync bug.
- The cmd flags bit order stays identical across `PlayerState` and the
  TAS tape line.
- Arms advance only via `step()` at the end of `_simulate` — never
  self-processing — so a completed charge fires next tick.
- **The helper split is state-free**: `PlayerMovement`/`PlayerCombat`/
  `PlayerRecorder` hold no state and type their param
  `CharacterBody3D`, never `AirfuelPlayer` (class-resolution cycle).
  Moving state into a helper breaks the `PlayerState` codec.
