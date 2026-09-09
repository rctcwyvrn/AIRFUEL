# player.gd

## Function

The Steps 1+2 player (plus prototype LAN netplay): kinematic movement
controller (DESIGN.md §4, §5) plus the dual railgun arm system (§7, §8.1) —
charge freeze/trajectory-lock, staggered dual-rail firing, hitscan damage,
canister ejection. (Aim crush was cut 2026-09-09, Appendix A — charging
never degrades turn rate.)

## Interface

- `class_name AirfuelPlayer extends CharacterBody3D`; the scene root of
  `player.tscn`, always in group `"player"`.
- Exports: `config: MovementConfig`, `combat: CombatConfig` (both required,
  never null at runtime), `mouse_sensitivity: float`, and
  `ghost_controlled: bool` — when true the body is a TAS/bot puppet: no
  camera claim, no mouse, no Input reads; a controller node writes the
  `cmd_*` fields directly (translucent orange body, excluded from HUD
  adoption and from rail/sword damage).
- **Command layer**: all gameplay input flows through per-tick `cmd_move/
  cmd_vert/cmd_jump/cmd_dash/cmd_fire_l/cmd_fire_r/cmd_swap/cmd_respawn`,
  filled by `_gather_input` from the Input singleton for humans, or by a
  controller (with `process_physics_priority < 0`) for ghosts/bots. New
  input reads in physics code MUST go through cmds, never Input directly.
- Signals: `shot_fired(side, result)` (side "L"/"R", result "miss"/"body"/
  "head"/"kill" — HUD hitmarkers), `damaged(amount, from_id)` (emitted on the
  victim's authority — HUD hit flash + directional damage arc), `died` (HUD
  death flash), `respawned` (ghost restart sync).
- **Loadouts (8.3)**: Tab (`swap_loadout`) cycles rail+rail → rail+sword →
  sword+sword; `arm_types` holds "rail"/"sword" per side, `loadout_name()`
  feeds the HUD. Swapping resets both rail arms, pending shots, and sword
  cooldowns; `_apply_loadout_visuals` swaps viewmodel mesh + stance (rail:
  level block; sword: long blade, rolled inward/tilted up — pose stored as
  `pose_rot` meta so recovery lerps return to stance, not zero). Lunges
  play a stab (position + rotation kick, blade emission flare while live).
- **Remote weapon telegraph**: `_send_state` also carries both arms'
  progress + `loadout_index`; puppets tint their shoulder `PuppetArm`
  blocks per loadout and glow rail arms with charge — the §8.1 "loud
  charge" tell, visually. Keep this synced: an invisible charge on the
  enemy would gut the dodge duel.
- **Sword (8.2)**: `_trigger_arm` on a sword side lunges toward the camera —
  a full-commit redirect to `sword_lunge_speed` (120, deliberately **above**
  terminal velocity; the soft ceiling bleeds it back to 80), arming ramp
  grace so the post-burst speed persists. Fueled, per-arm cooldown, blocked
  while charge-locked or wallrunning. For `sword_active_time` after, `_sword_hit_check`
  kills the first player/dummy within `sword_hit_range` (99 dmg, one hit
  per lunge). No freeze, no ranged component, ever.
- Read by the HUD (polled): `fuel`, `ramp_grace_timer`, `config`,
  `horizontal_speed() -> float`, `state_name() -> String`; event-driven via
  the `shot_fired`/`damaged`/`died` signals.
- Expected children: `Head` (Node3D, pitch) → `Head/Camera3D` (roll + FOV
  feel); `ArmLeft`/`ArmRight` (`RailArm` nodes). Yaw goes on the body itself.
- HUD-facing reads: `move_locked`, `arm_progress_left/right()`, `hp`,
  `combat`, `arm_types`; on puppets `remote_arm_progress(index)` (the synced
  `_send_state` progress — the HUD's enemy-charge-warning source) and
  `arm_types`/position for the sword proximity warning.
- Consumes input actions: `move_forward/back/left/right`, `strafe_down`
  (Q — up was removed; double jump covers it), `jump`, `dash` (Shift),
  `fire_left` (LMB), `fire_right` (RMB), `respawn`, `ui_cancel`.
- `MoveState { GROUNDED, AIRBORNE, WALLRUN }` in `state`.

## Implementation

Per-physics-tick order in `_physics_process` (order is load-bearing):
timers → `move_locked` recompute + `_handle_arms` (charge starts, pending
fires) → per-state move (`_ground_move` / `_air_move` / `_wallrun_move`) →
`_handle_dashes` → terminal-velocity clamps → `move_and_slide()` →
`_update_state` (floor check, wall attach) → `_camera_feel` (speed FOV;
wallrun banks the camera `wallrun_camera_roll_deg` at
`wallrun_camera_roll_speed` and adds `wallrun_fov_bonus`) → respawn check.

**Charge freeze (§7.2)**: `move_locked` is true while either arm
`is_locking()`. Grounded → horizontal velocity zeroed (rooted). Airborne →
ballistic: gravity/ramp decay continue, all steering (wish, Q/E, double jump,
dashes) gated off. Wallrunning → the run *continues* (Lily's call: the wall
is your trajectory) but the dismount jump is ignored; running off the wall
end drops into the airborne lock. While locked, total speed is clamped to `combat.charge_speed_cap`
(charging at high speed instantly bleeds you to 40 — the freeze makes you
slower and more readable, not just steerless). Aim stays free while charging
(aim crush cut 2026-09-09, Appendix A).

**Firing (§7.1, §8.1)**: `_handle_arms` starts charges on trigger press;
completed charges queue in `pending_arms` (FIFO = press order) and fire no
closer than `min_shot_gap` apart. `_fire_rail` raycasts from the camera
center (`range_max`, mask = player mask OR layer 2 so it hits
movement-transparent targets), reads `hit_zone` meta off the collider for body/head
damage against `TargetDummy`, then spawns the beam from the firing arm's
viewmodel muzzle (`vm.global_transform * (0,0,-0.35)`), kicks that viewmodel
back, spawns a `canister.tscn` rigid body with inherited velocity +
randomized tumble, and emits `shot_fired`.

**Graybox visuals**: `_spawn_beam` builds a thin emissive BoxMesh
(0.05×0.05×length) at the midpoint, oriented with `look_at` (up-vector
fallback for near-vertical shots), alpha+emission tweened to 0 over 0.2s
then freed. `_update_viewmodels` (every tick, after `_camera_feel`) sets
each viewmodel material's `emission_energy_multiplier` to
`arm.progress() * 3.0` — the arm block glows as its charge builds — and
lerps the viewmodel back to its `rest_pos` meta after the fire kick.

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
  Vertical strafe (`_vertical_input`) is Q-down only, fueled, capped at
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
  world-down. Bare Shift is inert. Shift+Q with no WASD held fires the §4.4 down dash instead, with its
  own `down_dash_*` tuning and no cooldown (fuel is its limiter); every other
  direction uses `air_dash_impulse`/`air_dash_cost`/`air_dash_cooldown`.
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
- **TAS recording (F5, `record` action)**: toggling on respawns you (clean
  tape from spawn state) and logs one line per physics tick — absolute
  yaw/pitch + cmd fields + button bitmask — with a header naming the map
  and tick rate; toggling off writes `user://tas/run_<datetime>.tas` and
  prints the real filesystem path. F5 is a dev-only tool for authoring the
  repo ghost; T is the player-facing run reset. Any respawn mid-recording
  restarts the tape, so a saved tape is always one clean spawn-to-finish
  attempt (a teleport mid-tape would desync replay). Feed a tape to the parkour ghost via
  `TasController.tape_path`. Tapes assume the tuning they were recorded
  under — retune movement, re-record the tape.
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
  its replay stay tick-aligned from GO. Applies in LAN round-resets too.
- **Run timer**: `run_time` accumulates per tick until `run_finished`;
  every `_respawn` zeroes and restarts it. `finish_run()` (called by a
  `FinishZone`) freezes the clock and auto-saves an active TAS recording —
  a finished run yields its own tape.
- Respawn on `respawn` action (solo only — disabled when `Net.active`, a
  free escape would break duels) or falling below `config.kill_y`.
- **Networking (LAN-trust, gated on `Net.active`)**: the authority peer
  simulates everything above and broadcasts `_send_state` (pos/vel/yaw/
  pitch, unreliable_ordered) each tick; non-authority instances disable
  physics + input + camera + viewmodels, show the red dummy-sized
  `BodyMesh`, and lerp toward the last state in `_process`. Hits on remote players rpc
  `take_damage` to the victim's authority (shooter-decided, LAN-trust);
  the victim emits `damaged(amount, from_id)` on every hit, and at 0 hp
  emits `died`, broadcasts `Net.report_kill(killer, victim)` (all
  peers tally the scoreboard and re-emit `Net.kill_reported` for the HUD
  feed/banner; the killer's peer `round_reset(true)`s its
  own player) and `_respawn`s — **a kill resets both duelists** to their
  spawns with full hp/fuel. Kill rpcs must route through `Net` (same node
  path on every peer); an rpc on the victim's own node lands on the
  victim's *puppet* at the killer's end — that bug shipped once. `_remote_shot_fx` mirrors beams.
  `hp` initialized from `combat.hp_max` (2; rail body dmg 1 = 2 shots).
- The authority player must claim `camera.current = true` explicitly in
  `_ready` — Godot's auto-current fails on clients because the host puppet's
  camera enters the viewport first and is then disabled, leaving no current
  camera (this shipped once as "joiner stuck staring at a grey wall").

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
  probe rotation `0.6`, and the 25° rearm cone.)
- `_update_state` never overrides WALLRUN — only wallrun code exits wallrun.
- No charge cancel exists anywhere; a charge always ends in a shot. Dual
  shots are never closer than `combat.min_shot_gap` (verified: same-tick
  charges fire 0.352s apart with the default 0.35 gap).
- `move_locked` must derive only from arm `is_locking()` — freeze from first
  trigger press to last pending shot, never during COOLDOWN.
- Beam meshes always free themselves (tween callback) — a leaked beam per
  shot would accumulate fast.
- Coyote walljump must never grant fuel (falloff already did); jumping
  dismounts must clear `wall_coyote_timer` so boosts can't stack.
- Glide only redirects horizontal speed — it must never add speed
  (`target` is capped by pre-impact speed × retention).
