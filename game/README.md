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

## Multiplayer (server-authoritative — §20.2 stage N1)

All netplay runs one netcode: an authoritative process simulates every
player from per-tick input commands; your own client *predicts* its body
locally and reconciles against server snapshots, opponents render as
snapshot-fed puppets. Damage and kills only ever happen on the server,
with **server-side rewind**: rail and sword hits are evaluated against
where the victim was on the shooter's screen (capped by
`ServerConfig.rewind_max_ms`, default 250 ms) — aim at what you see.

**LAN listen server** — menu: **HOST LAN GAME** / **JOIN** (blank =
127.0.0.1 for two instances locally). The host simulates everyone and plays
as a zero-latency local body. CLI equivalents:

```sh
godot4 --path game -- --server
godot4 --path game -- --client <ip>
```

Host spawns at the −z end, joiners at +z. 2 HP, every rail hit = 1 damage
(two shots to kill), a kill resets both duelists with full fuel.
No args = offline solo, unchanged (offline never touches the netcode).
WSL2 note: for a real two-machine LAN test, run the Windows build or
forward udp/27555 out of WSL.

Dev/test flags (either mode): `--fake-lag <ms>` adds artificial round-trip
latency on a client (prediction stress-test); `--autoduel` makes lobby
clients challenge/accept automatically, then cheat-aim at the opponent and
strafe while firing (headless soak tests — at high fake-lag this only
lands hits if rewind works); `--spawn-gap <m>` spawns duelists close
together with line of sight so autoduels actually connect;
`--rewind-ms <ms>` overrides the rewind window (0 disables — the lag-comp
A/B lever). Server-side flags forward from the lobby to its match servers.

## Hosted lobby server (Docker)

A dedicated **matchmaker**: it never simulates a game itself. When a
challenge is accepted it spawns a private per-match **child server process**
on a port from the range udp/27600–27619 (config: `ServerConfig`) and both
duelists hop to it; the child runs the authoritative first-to-5 duel, then
the players rejoin the lobby, report the result, and the name-keyed W–L
records update. Concurrent 1v1s are isolated by construction — separate
processes. Forward/publish the whole port range along with 27555.

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
the proxy can't carry UDP. The lobby lists everyone with W–L (kept by
username for as long as the server runs); click **CHALLENGE** on an idle
player, they accept, and you're both dropped onto a private per-match
server for a first-to-5-kills corridor duel (DESIGN.md §12.2), then
returned to the lobby. Disconnecting mid-match forfeits. Tuning (win
kills, peer cap, challenge timeout, match-server port range/timeouts):
`src/net/default_server.tres` (schema `src/net/server_config.gd`).

CLI equivalents:

```sh
godot4 --headless --path game -- --dedicated          # serve (no Docker)
godot4 --path game -- --lobby <ip> --name <username>  # join a server
# dev flags: --autoduel (auto challenge/accept/fire, loops matches),
#            --fake-lag <ms>, --spawn-gap <m>  — see the LAN section
```

## What to test (Step 1–3 questions from the design doc)

- Does chained-short-runs feel emerge from the dismount reward?
- Is curved-surface wallrun viable (orange slots' rounded caps)?
- How far apart can platforms be before flow breaks (the parkour track's gaps)?
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
