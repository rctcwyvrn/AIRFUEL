# Airfuel — Godot prototype

**Roadmap Steps 1 + 2** (see `../design/DESIGN.md` §24). Gray box corridor,
one player, three stationary targets. Wallrun economy, dismount grants, ramp
persistence, dashes, terminal velocity, Airfuel meter — plus dual railgun
arms: 1s auto-firing charge, movement freeze / trajectory lock,
staggered dual-rail gap, hitscan (2 body / 1 head), canister ejection.

## Run

```sh
nix-shell                      # from the repo root
godot4 --path game --editor    # open in editor
godot4 --path game             # just play
```

## Controls

| Input | Action |
|---|---|
| WASD + mouse | Strafe / look |
| Q | Strafe down in the air (fuel) |
| Space | Jump / double jump (fuel) / wallrun dismount |
| Shift + WASD/Q | Dash in that direction (fuel); Shift+Q alone = down dash |
| LMB / RMB | Fire left / right arm — rail: 1s charge, auto-fire, locks movement; sword: fueled lunge-kill |
| Tab | Cycle loadout: rail+rail / rail+sword / sword+sword |
| T | Reset the run (solo only; 3-2-1 countdown, then timer/ghost/recording go) |
| F5 | Dev: record a TAS ghost tape (toggle; finish line auto-saves) |
| Esc | Release mouse |

Bare Shift does nothing — a dash always needs a held direction. Dashing
while wallrunning dismounts with the full jump boost + dash impulse
(the wall you left locks out briefly); Shift+Q on the wall slides you
down it without detaching. WASD dashes
follow the camera (W+Shift = wherever you're looking, pitch included);
Q dashes straight down. Up is the double jump's job.

## LAN multiplayer (prototype tier)

Use the main menu: **HOST LAN GAME** on one machine, **JOIN** with the
host's IP on the other (blank = 127.0.0.1 for two instances locally).
CLI equivalents for scripted/headless runs:

```sh
godot4 --path game -- --server
godot4 --path game -- --client <ip>
```

Client-authoritative movement (LAN-trust — not the shipping §20.2 netcode).
Host spawns at the −z end, joiners at +z. 2 HP, every rail hit = 1 damage
(two shots to kill), death resets you to your spawn with full fuel.
No args = offline solo, unchanged. WSL2 note: for a real two-machine LAN
test, run the Windows build or forward udp/27555 out of WSL.

## Hosted lobby server (Docker)

A dedicated server that is a **matchmaker + relay only** — it never loads
the arena; each matched pair runs its own local arena and exchanges
targeted state, so concurrent 1v1s never see each other.

```sh
docker build -f docker/Dockerfile -t airfuel-server .   # from repo root
docker run --rm -p 27555:27555/udp airfuel-server
# or: docker compose -f docker/compose.yaml up -d --build
```

In-game: enter a username + the server address in the menu's **JOIN
SERVER** row (blank = the official server, `play.airfuel-game.com`).

DNS layout (Cloudflare): `airfuel-game.com` + `www` are **Proxied** dummy
records whose only job is an edge Redirect Rule →
<https://rctcwyvrn.itch.io/airfuel>; `play.airfuel-game.com` is a
**DNS-only** A record straight to the game host — it must stay grey-cloud,
the proxy can't carry UDP. The lobby lists everyone with session W–L; click **CHALLENGE** on an
idle player, they accept, and you're both dropped into a private
first-to-5-kills corridor duel (DESIGN.md §12.2), then returned to the
lobby. Disconnecting mid-match forfeits. Tuning (win kills, peer cap,
challenge timeout): `src/net/default_server.tres`.

CLI equivalents:

```sh
godot4 --headless --path game -- --dedicated          # serve (no Docker)
godot4 --path game -- --lobby <ip> --name <username>  # join a server
# --autoduel: dev flag — auto-challenge/accept (headless smoke tests)
```

## What to test (Step 1–3 questions from the design doc)

- Does chained-short-runs feel emerge from the dismount reward?
- Is curved-surface wallrun viable (orange cylinders)?
- How far apart can platforms be before flow breaks (floor gaps, teal panels)?
- How long should the corridor actually be?
- Does the rail charge feel good to commit to? (freeze + no cancel)
- Is the dual-rail stagger a usable rhythm instrument?
- **In LAN 1v1s: is charge-freeze-dodge a fun conversation or a coinflip?**
  Charge → tell → dodge in both directions; do the HUD warnings (enemy
  charge, sword proximity, damage direction) carry the information game?

## Tuning

Movement numbers: `src/player/default_tuning.tres` (schema
`movement_config.gd`). Combat numbers: `src/weapons/default_combat.tres`
(schema `combat_config.gd`). Both mirror DESIGN.md Appendix B; edit in the
inspector while the game runs for live tuning.

## Layout

- `src/player/` — kinematic controller (`CharacterBody3D` base, radial ray
  probes for flat + curved walls), movement tuning resource
- `src/weapons/` — rail arm state machine, combat tuning, canister prop
- `src/targets/` — self-respawning 2 HP practice dummy (orange head = lethal)
- `src/hud/` — fuel bar, speed/state readout, charge bars, hitmarkers
- `maps/graybox_corridor.tscn` — the test corridor (solo range + LAN arena)
- `maps/parkour_track.tscn` — snaking high-speed parkour time trial (solo;
  timer stops at the green wall, F5 tapes auto-save there)
