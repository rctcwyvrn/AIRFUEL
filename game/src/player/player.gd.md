# player.gd

## Function

The Steps 1+2 player plus server-authoritative netplay (DESIGN.md §20.2
stages N1+N2 — client prediction plus server-side rewind lag
compensation): kinematic movement controller (§4, §5) plus the dual railgun arm
system (§7, §8.1) — charge freeze/trajectory-lock, staggered dual-rail
firing, hitscan damage, canister ejection — and the sword (§8.2). One body
class plays four net roles (`NetRole`); the same `_simulate()` tick runs on
every simulating machine, and client prediction replays it against server
snapshots. (Aim crush was cut 2026-09-09, Appendix A — charging never
degrades turn rate.)

## Interface

- `class_name AirfuelPlayer extends CharacterBody3D`; the scene root of
  `player.tscn`, always in group `"player"`.
- Exports: `config: MovementConfig`, `combat: CombatConfig` (both required,
  never null at runtime), `mouse_sensitivity: float`, and
  `ghost_controlled: bool` — when true the body is a TAS/bot puppet: no
  camera claim, no mouse, no Input reads; a controller node writes the
  `cmd_*` fields directly (translucent orange body, excluded from HUD
  adoption and from rail/sword damage).
- **`role: NetRole`** — set by `Net` on the instance *before* `add_child`
  (`_ready` branches on it; the scene default `LOCAL` keeps offline
  untouched). Semantics:
  - `LOCAL` — authoritative + local human input: offline solo, the LAN
    host's own body, TAS ghosts (via `ghost_controlled`).
  - `DRIVEN` — authoritative + net cmds: a remote client's body on the
    server. `MatchHost` writes its cmds (`PlayerState.apply_cmd`) before the tick;
    rendered like a puppet on a LAN host's screen, headless elsewhere.
  - `PREDICTED` — the client's own body: simulates immediately from local
    input, ships cmds to the server, reconciles against snapshots.
  - `REPLICA` — render-only puppet of another player on a client: physics
    processing disabled in `_ready`, fed by render-state rows, position
    eased in `_process`. Never simulated here.
- **Command layer**: all gameplay input flows through per-tick `cmd_move/
  cmd_vert/cmd_jump/cmd_dash/cmd_fire_l/cmd_fire_r/cmd_swap/cmd_respawn`,
  filled by `_gather_input` from the Input singleton for humans, or by a
  controller (with `process_physics_priority < 0`) for ghosts/bots. New
  input reads in physics code MUST go through cmds, never Input directly.
  With `Net.autoduel` a PREDICTED body runs `_autoduel_cmds()` from
  `_gather_input`: cheat-aims at the opponent's REPLICA (i.e. where it
  renders on *this* screen — exactly what rewind compensates for),
  strafes side to side flipping every 96 ticks, and fires the left rail
  on a 300-tick cadence phase-offset by 150 for the higher peer id so
  the duelists alternate (one strafes while the other's shot lands) —
  the §20.2 N2 rewind A/B instrument. Headless smoke duels run a
  first-to-N match to completion without a human.
- **Cmd encoding**: `PlayerState.encode_cmd(p)`/`PlayerState.apply_cmd(p, c)`
  pack/unpack a `PlayerState.CMD_SIZE = 8` PackedFloat32Array (the codec
  lives in player_state.gd alongside the state codec):
  `[tick, move.x, move.y, vert, flags,
  yaw, pitch, seen_server_tick]`. The flags bit order is
  jump|dash|fireL|fireR|swap|respawn — identical to the TAS tape's button
  bitmask. View angles ride with cmds (they are client-authoritative) and
  `PlayerState.apply_cmd` writes them directly; they are deliberately
  **not** part of captured state.
- **`seen_server_tick: int`** — the newest server tick this client has
  rendered: set from arriving snapshots on a PREDICTED body, echoed to the
  server in cmd slot [7], and written onto the DRIVEN body by
  `PlayerState.apply_cmd`. It is the rewind target for this player's shots
  (§20.2 N2 — `MatchHost` rewinds victims to where this shooter's screen
  had them). `0` = never seen a snapshot / no rewind.
- **Net API** (called by `Net` / `MatchHost`):
  - `on_server_snapshot(ack_tick, state)` — queues a server snapshot
    (PREDICTED only); applied at the next tick's start.
  - `PlayerState.apply_cmd(self/body, c)` — writes a net cmd onto a body (DRIVEN on the
    server, or a history entry during reconciliation replay).
  - `render_state() -> PackedFloat32Array` — the 12-float render row the
    server sends about this body for other clients' replicas:
    `[pos*3, vel*3, yaw, pitch, progL, progR, loadout, hp]`. The peer id
    deliberately travels OUTSIDE the array, as a real int: float32's
    24-bit mantissa silently corrupts 10-digit ENet peer ids (shipped
    once as "replicas never moved").
  - `apply_replica(r)` — applies a render row to a REPLICA (position target,
    velocity, look, arm progress, hp, loadout retint of the puppet arms);
    indexed for the 12-float id-less row above.
  - `capture_state()` / `restore_state(s)` — delegate to `PlayerState`
    (fixed 42-slot codec, see `player_state.gd.md`).
  - `apply_damage(amount, from_id) -> bool` — server-side authoritative
    damage; returns whether the hit killed (attackers turn it into
    "kill" vs "body"). Only LOCAL/DRIVEN bodies on the simulating
    process ever run it; notifies `Net.match_host.on_damage` (which
    respawns the victim on a kill). Replaces the old LAN-trust
    `take_damage` rpc.
  - `sim_active() -> bool` — false only for REPLICA. KillZones etc. act on
    simulating bodies and must ignore render-only replicas.
  - Beam/canister cosmetics live in the static `PlayerFx` class
    (`player_fx.gd`): the player calls `PlayerFx.spawn_beam` /
    `PlayerFx.spawn_canister` from `_fire_rail`, and `Net` calls
    `PlayerFx.spawn_beam` directly to mirror an opponent's shot fx on
    clients. `_spawn_beam`/`_spawn_canister` no longer exist on the
    player.
- **The old rpcs are gone**: `take_damage`, `_send_state`,
  `_remote_shot_fx`, and `round_reset` no longer exist. Damage is applied
  server-side via `apply_damage`; state flows through `MatchHost` snapshots
  and render rows; shot/damage feedback returns as Net events (`_ev_shot`/
  `_ev_damage` → the victim's `on_net_damage`, which syncs hp and emits the
  signals in-class).
- Signals: `shot_fired(side, result)` (side "L"/"R", result "miss"/"body"/
  "head"/"kill" — HUD hitmarkers; emitted directly only offline, in netplay
  `Net` emits it on the local body from the authoritative ev_shot),
  `damaged(amount, from_id)` / `died` (in netplay emitted by
  `on_net_damage` when Net's ev_damage lands; HUD hit flash, damage arc,
  death flash), `respawned` (ghost restart sync).
- **Loadouts (8.3)**: Tab (`swap_loadout`) cycles rail+rail → rail+sword →
  sword+sword; `arm_types` holds "rail"/"sword" per side, `loadout_name()`
  feeds the HUD. Swapping resets both rail arms, pending shots, and sword
  cooldowns; `_apply_loadout_visuals` swaps viewmodel mesh + stance (rail:
  level block; sword: long blade, rolled inward/tilted up — pose stored as
  `pose_rot` meta so recovery lerps return to stance, not zero). Lunges
  play a stab (position + rotation kick, blade emission flare while live).
- **Remote weapon telegraph**: `render_state` carries both arms' progress +
  `loadout_index`; REPLICA bodies tint their shoulder `PuppetArm` blocks
  per loadout and glow rail arms with charge (from the snapshot-fed
  `_net_prog`), DRIVEN bodies on a LAN host's screen glow from real arm
  state — the §8.1 "loud charge" tell, visually. Keep this synced: an
  invisible charge on the enemy would gut the dodge duel.
- **Sword (8.2)**: `_trigger_arm` on a sword side lunges toward the camera —
  a full-commit redirect to `sword_lunge_speed` (120, deliberately **above**
  terminal velocity; the soft ceiling bleeds it back to 80), arming ramp
  grace so the post-burst speed persists. Fueled, per-arm cooldown, blocked
  while charge-locked or wallrunning. For `sword_active_time` after,
  `_sword_hit_check` kills the first player/dummy within `sword_hit_range`
  (99 dmg, one hit per lunge). Kills only where the sim is authoritative:
  a PREDICTED lunge is pure movement (`_sword_hit_check` returns early);
  the server's copy of the lunge lands the kill via `apply_damage` +
  `match_host.on_shot`. In netplay, reach against players is measured to
  `Net.match_host.rewound_position(victim, self)` — where the victim was
  on the lunger's screen, the same §20.2 N2 lag compensation as rail
  hits. No freeze, no ranged component, ever.
- Read by the HUD (polled): `fuel`, `ramp_grace_timer`, `config`,
  `horizontal_speed() -> float`, `state_name() -> String`; event-driven via
  the `shot_fired`/`damaged`/`died` signals.
- HUD-facing reads: `move_locked`, `arm_progress_left/right()`, `hp`,
  `combat`, `arm_types`; **`display_arm_progress(index)`** answers
  regardless of role — REPLICA from the snapshot-fed `_net_prog`, simulated
  bodies (incl. DRIVEN on a LAN host's screen) from real arm state — and is
  the HUD's enemy-charge-warning source; `arm_types`/position feed the
  sword proximity warning.
- Expected children: `Head` (Node3D, pitch) → `Head/Camera3D` (roll + FOV
  feel); `ArmLeft`/`ArmRight` (`RailArm` nodes);
  `Head/Camera3D/ViewmodelL`/`ViewmodelR` (first-person arm blocks);
  `PuppetArmL`/`PuppetArmR` and `BodyMesh` (puppet visuals). Yaw goes
  on the body itself.
- Consumes input actions: `move_forward/back/left/right`, `strafe_down`
  (Q — up was removed; double jump covers it), `jump`, `dash` (Shift),
  `fire_left` (LMB), `fire_right` (RMB), `swap_loadout` (Tab), `record`
  (F5), `respawn`, `ui_cancel`.
- `MoveState { GROUNDED, AIRBORNE, WALLRUN }` in `state`.

## Implementation

**Per-role tick flow (`_physics_process`)**:

- PREDICTED: `_maybe_reconcile()` → `_gather_input()` → `net_tick += 1` →
  `PlayerState.encode_cmd(self)` stored in `_cmd_history[net_tick]` and shipped via
  `Net.send_cmd` → `_simulate(delta)` → `_state_history[net_tick] =
  capture_state()` → camera feel + viewmodels. Reconciliation runs at tick
  *start*, inside the physics frame, so a replay's `move_and_slide` uses
  the physics delta.
- LOCAL: `_gather_input()` → `_simulate()` → camera feel, viewmodels, TAS
  recording.
- DRIVEN: `_simulate()` only — `MatchHost` already wrote this tick's cmds
  via `PlayerState.apply_cmd`; no camera/viewmodel/recording work.
- REPLICA: `_physics_process` is disabled in `_ready`; only `_process`
  runs (position lerp toward `_net_target_pos`, shoulder charge glow).

**`_simulate(delta)` — the re-runnable tick**: countdown freeze → run
clock → timer decays (incl. `shot_gap_timer`) → sword tick + hit check →
jump buffer → `move_locked` recompute + `_handle_arms` (charge starts,
pending fires) → per-state move (`_ground_move` / `_air_move` /
`_wallrun_move`) → `_handle_dashes` → terminal-velocity/charge clamps →
`move_and_slide()` → `_apply_glide` → `_update_state` (floor check, wall
attach) → respawn check (manual `cmd_respawn` only offline — a free escape
would break duels; `kill_y` always) → **arms stepped last**
(`arm_left/right.step(delta)`). Everything a tick's outcome depends on
lives inside `_simulate` (and therefore in `capture_state()`); everything
visual-only (camera feel, viewmodels, recording, net sends) stays outside
so prediction can re-run the tick. The arms were self-processing child
nodes (which ran *after* the parent); explicit `step()` at tick end
preserves that ordering — a charge completing this tick fires next tick.

**Prediction machinery (PREDICTED)**: `_cmd_history` / `_state_history`
(tick → cmd / captured state) back reconciliation. `on_server_snapshot`
only queues `[ack_tick, state]`; `_maybe_reconcile` applies it: prune
history ≤ ack, then `PlayerState.agree(predicted@ack, server)` — on
agreement nothing else happens. On misprediction: save live yaw/pitch, set
`replaying = true`, `restore_state(server)`, replay `_cmd_history` for
ticks ack+1..net_tick through `PlayerState.apply_cmd` + `_simulate` (re-capturing
`_state_history`), clear `replaying`, restore the live yaw/pitch — the
mouse may have moved since those cmds were recorded, and a replay must
never yank the camera.

**`replaying` suppression**: replayed ticks keep gameplay math and the arm
state machines honest but skip one-shot effects — `_fire_rail` returns
right after `on_fired()` (no hit test, no damage, no beam/canister/kick,
no match-host report), and `_trigger_arm`'s sword stab kick is skipped.
Damage and effects happened when the tick first ran (or on the server);
replays never re-do them.

**Firing (§7.1, §8.1)**: `_handle_arms` starts charges on trigger press;
completed charges queue in `pending_arms` (FIFO = press order) and fire no
closer than `min_shot_gap` apart, sequenced by **`shot_gap_timer`** — a
tick timer decayed in `_simulate` and captured in state, replacing the old
wall-clock `last_shot_time`, because prediction replays re-run this code.
`_fire_rail` is role-dependent: `arm.on_fired()` always advances the state
machine; `replaying` short-circuits everything else; then the hit test
splits into two branches. **Authoritative netplay** (`Net.match_host !=
null and role != PREDICTED`): `Net.match_host.eval_rail_hit(self, from,
dir, range_max)` — the lag-compensated (§20.2 N2) hit test, which checks
victims at their *rewound* positions (where this shooter's client had
rendered them, keyed by the shooter's `seen_server_tick`) and returns
`{end, victim}`; a non-null victim takes `apply_damage(damage_body, ...)`,
whose bool return picks the "kill" vs "body" result. **Offline /
PREDICTED**: a local raycast from the camera center (`range_max`, mask =
player mask OR layer 2 so it hits movement-transparent targets), reading
`hit_zone` meta for body/head damage against `TargetDummy`; against
players a PREDICTED shot is muzzle-flash only ("body" visual result — the
server's copy of the same shot decides the hit and ev_shot brings the
result back). Local fx (viewmodel kick, `PlayerFx.spawn_beam` from the
arm's muzzle `vm.global_transform * (0,0,-0.35)`,
`PlayerFx.spawn_canister` ejection) are gated on `not Net.headless`;
`Net.match_host.on_shot(...)` reports the shot on the simulating process;
`shot_fired` emits directly only offline (`not Net.active`).

**Graybox visuals**: the beam and canister one-shots moved to the static
`PlayerFx` class (see `player_fx.gd.md`) — the player only decides *when*
to call them. `_update_viewmodels` (every rendered tick) sets each viewmodel
material's `emission_energy_multiplier` from charge progress (or the
sword's lunge flare) and lerps the viewmodel back to its `rest_pos`/
`pose_rot` metas after the fire kick. In `_process`, DRIVEN (LAN host
screen) and REPLICA bodies drive the shoulder-block glow instead — from
real arm progress and `_net_prog` respectively.

- **Charge freeze (§7.2)**: `move_locked` is true while either arm
  `is_locking()`. Grounded → horizontal velocity zeroed (rooted). Airborne →
  ballistic: gravity/ramp decay continue, all steering (wish, Q, double jump,
  dashes) gated off. Wallrunning → the run *continues* (Lily's call: the wall
  is your trajectory) but the dismount jump is ignored; running off the wall
  end drops into the airborne lock. While locked, total speed is clamped to
  `combat.charge_speed_cap` (charging at high speed instantly bleeds you to
  40 — the freeze makes you slower and more readable, not just steerless).
  Aim stays free while charging (aim crush cut 2026-09-09, Appendix A).
- **Wall detection is ray-based, not collision-based**, so curved surfaces
  (cylinders) work. Attach: 12 radial horizontal rays from body center
  (`_try_attach_wall`), best = nearest hit with a wall-ish normal. Maintain:
  re-probe toward `-wall_normal` each tick at 1.6× distance, falling back to
  ±0.6 rad rotations so the normal tracks curvature (`_wallrun_move`).
- **Dismount** (`_dismount`): fuel grant scales with along-wall speed *above*
  `min_wallrun_speed` (slow wall-hugging ≈ nothing). Jump dismounts also get
  the speed boost + push-off + up-velocity; falling off / timing out grants
  fuel only. This is an interpretation of §4.2 — deliberate chaining pays.
- **Ramp persistence**: `_dismount` arms `ramp_grace_timer`; while it runs,
  airborne excess speed doesn't decay. After it expires, `_decay_excess_speed`
  pulls horizontal speed toward `base_run_speed`. Ground contact bleeds excess
  via `_ground_move` instead.
- **Re-attach guard**: for `wall_rearm_time` after dismount, walls whose normal
  is within 25° of `last_wall_normal` are ignored — blocks same-wall re-grab
  without slowing transfer to the *next* wall.
- **Air control**: projection-capped acceleration (`_air_accelerate` adds speed
  only up to a cap along the wish direction). Free control caps at
  `base_run_speed`; the fueled strafe tier caps at `air_strafe_speed_cap` and
  drains `air_strafe_cost_per_sec` only when it can actually add speed.
  Vertical strafe (inline in `_air_move`) is Q-down only, fueled, capped at
  `air_strafe_vertical_cap`, airborne only; upward mobility is the double
  jump.
- **Wallrun exits**: jump and dash leave the wall; Shift+Q does NOT — on a
  wall it's a stick-and-slide (down-dash velocity while staying attached).
  A dash off the wall is a full jump-grade dismount (fuel + speed boost)
  with the dash impulse stacked on top — dashing must never leave you
  stuck — but it arms the longer `dash_wall_rearm_time` so you can't
  pogo the same wall. **Dismount/coyote boosts are capped at
  `terminal_velocity`**: uncapped, the dash-off→re-attach loop compounded
  to hundreds of m/s (shipped once). The sword lunge stays the only thing
  allowed past terminal.
- **Dash is Shift + held direction, camera-aimed** (Lily's scheme, revised
  2026-09-08 from yaw-plane to full camera): WASD components follow the
  camera basis including pitch — W+Shift goes wherever you look; Q adds
  world-down. Bare Shift is inert. Shift+Q with no WASD held fires the §4.4
  down dash instead, with its own `down_dash_*` tuning and no cooldown (fuel
  is its limiter); every other direction uses
  `air_dash_impulse`/`air_dash_cost`/`air_dash_cooldown`.
  Double jump is fuel-gated plus a short cooldown (interpretation of §4.5:
  fuel is the constraint, cooldown just prevents hover-spam).
- **Feel assists (Celeste-inspired, all in the Assists config group)**:
  `_apply_glide` runs after `move_and_slide` (except during wallrun) — on a
  glancing hit against a wall-ish surface it restores horizontal speed
  (`glide_speed_retention`, default 90%) along the slide direction, so
  obstacles deflect instead of stopping; impacts steeper than
  `glide_max_impact_angle_deg` from the surface still stop you. **Wall
  coyote**: falling off a wall arms `wall_coyote_timer` — jump within it
  and `_coyote_walljump` applies the full dismount boost (fuel was already
  granted at falloff, so no double-grant). **Ground coyote**: walking off
  an edge (not jumping — gated on `velocity.y <= 1`) leaves the free jump
  available briefly. **Jump buffer**: any jump press is buffered
  `jump_buffer_time`; landing consumes it. Air jump priority: wall coyote →
  ground coyote → fueled double jump.
- **Flight trail** (`_update_trail_line`, `_process`, all bodies): one
  long thin orange world-space line — 2 m position samples, 150-point /
  4 s rolling window, alpha ramp to the tail, rebuilt into an
  ImmediateMesh LINE_STRIP each frame; cleared on respawn.
- **TAS recording (F5, `record` action)**: offline only — the toggle is
  gated on `not Net.active` (tapes are a solo instrument) and the per-tick
  log line only runs on the LOCAL path of `_physics_process`. Toggling on
  respawns you (clean tape from spawn state) and logs one line per physics
  tick — absolute yaw/pitch + cmd fields + button bitmask (same bit order
  as `PlayerState.encode_cmd`) — with a header naming the map and tick rate; toggling
  off writes `user://tas/run_<datetime>.tas` and prints the real
  filesystem path. F5 is a dev-only tool for authoring the repo ghost; T
  is the player-facing run reset. Any respawn mid-recording restarts the
  tape, so a saved tape is always one clean spawn-to-finish attempt (a
  teleport mid-tape would desync replay). Feed a tape to the parkour ghost
  via `TasController.tape_path`. Tapes assume the tuning they were
  recorded under — retune movement, re-record the tape.
- The ghost body sets `collision_layer = 0` AND `collision_mask = 1`
  (world only): nothing collides into it, and it cannot bump players —
  a replay that can touch a nearby player desyncs nondeterministically.
- `_respawn` zeroes EVERY transient (cooldowns, coyote/buffer/rearm/grace
  timers, sword state, pending arms) — recordings replay from spawn, so
  spawn state must be bit-identical between a run and its ghost (leftover
  ramp-grace at record start shipped once as ghost desync). Tape headers
  carry `loadout=` (recorded via `set_loadout`; Tab cycles through it).
- **Reset countdown** (`reset_countdown`, default 3 s): every `_respawn`
  freezes the body in place (look is free) while `countdown` runs; the run
  clock, tape recording, AND ghost playback all gate on it, so a run and
  its replay stay tick-aligned from GO. Applies in net round-resets too.
- **Run timer**: `run_time` accumulates per tick until `run_finished`;
  every `_respawn` zeroes and restarts it. `finish_run()` (called by a
  `FinishZone`) freezes the clock and auto-saves an active TAS recording —
  a finished run yields its own tape.
- Respawn on `respawn` action (solo only — disabled when `Net.active`, a
  free escape would break duels) or falling below `config.kill_y`.
- `hp` initialized from `combat.hp_max` (2; rail body dmg 1 = 2 shots).
- LOCAL/PREDICTED bodies must claim `camera.current = true` explicitly in
  `_ready` — Godot's auto-current fails when a remote puppet's camera
  entered the viewport first (client-side join order; this shipped once as
  "joiner stuck staring at a grey wall").

## Assertions

- `fuel` stays in `[0, config.fuel_max]`; all spends go through `_spend`,
  which is all-or-nothing (never partial-drains below the cost).
- Wallrunning itself never costs fuel; **dismount is the only in-play refill**
  (DESIGN.md §5.1 — do not add refills on kill, death, or pickup).
- `wall_normal` is always near-horizontal: probes reject `|normal.y| > 0.4`.
- `state == WALLRUN` implies not on floor; `_wallrun_move` bails to
  `_dismount(false)` on floor contact, lost wall, timeout, or speed below
  `min_wallrun_speed`.
- The speed ceiling is **soft**: above `terminal_velocity`, speed decays at
  `overspeed_decay` (fast) instead of hard-clamping — only the sword lunge
  legitimately enters that regime. `velocity.y >= -terminal_fall_speed`
  stays hard every tick, as does the charge cap.
- No gameplay literals: any new tunable must be a `MovementConfig` field.
  (Current known exceptions to fix if touched: the vertical-settle rate `20.0`
  in `_wallrun_move`, camera-feel lerp rates and FOV factor, the 12-ray count,
  probe rotation `0.6`, the 25° rearm cone, the replica position-lerp rate,
  and the autoduel cadence literals `300`/`150`/`96`.)
- `_update_state` never overrides WALLRUN — only wallrun code exits wallrun.
- No charge cancel exists anywhere; a charge always ends in a shot. Dual
  shots are never closer than `combat.min_shot_gap`, sequenced FIFO through
  `pending_arms` + `shot_gap_timer` — a simulated tick timer captured in
  state, never wall clock (replays re-run this code).
- `move_locked` must derive only from arm `is_locking()` — freeze from first
  trigger press to last pending shot, never during COOLDOWN.
- **Peer ids must never be packed into float arrays**: `render_state` is
  12 floats with the id traveling beside it as a real int — float32's
  24-bit mantissa silently corrupts 10-digit ENet peer ids (this shipped
  as a real replication bug: replicas never moved).
- **Netplay hit tests go through rewind**: in authoritative netplay
  `_fire_rail` resolves victims via `Net.match_host.eval_rail_hit` and
  `_sword_hit_check` measures reach against `rewound_position` — never
  against victims' live server positions (§20.2 N2).
- Coyote walljump must never grant fuel (falloff already did); jumping
  dismounts must clear `wall_coyote_timer` so boosts can't stack.
- Glide only redirects horizontal speed — it must never add speed
  (`target` is capped by pre-impact speed × retention).
- **View angles never enter state**: yaw/pitch are client-authoritative and
  travel with cmds; `capture_state`/`restore_state` (PlayerState) must not
  touch them, and reconciliation must restore the live look angles after a
  replay — a snapshot must never yank the camera.
- **Replays never re-do damage or effects**: every one-shot side effect
  (raycast damage, beams, canisters, viewmodel kicks, match-host reports,
  hitmarker signals) must be behind the `replaying` guard; only gameplay
  math and state-machine advancement run in a replayed tick.
- **REPLICA never simulates**: physics processing off from `_ready`,
  `sim_active()` false — everything it shows comes from render rows.
- **Only authoritative roles apply damage**: `apply_damage` runs solely on
  LOCAL/DRIVEN bodies of the simulating process; `_fire_rail` and
  `_sword_hit_check` must keep their PREDICTED guards (a predicted shot or
  lunge is visuals/movement only — the server decides hits).
- Everything `_simulate`'s outcome depends on must be inside `_simulate`
  and captured by `PlayerState` — a new sim field missing from the codec
  is a silent desync bug.
- The cmd flags bit order (jump|dash|fireL|fireR|swap|respawn) must stay
  identical across `PlayerState.encode_cmd`/`apply_cmd` and the TAS tape line.
- Arms advance only via `step()` at the end of `_simulate` — never
  self-processing — so a completed charge fires next tick, matching the
  old child-node processing order.
