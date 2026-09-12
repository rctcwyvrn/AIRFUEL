# CLAUDE.md — Airfuel

Airfuel is a solo-dev 6v6 movement shooter prototype in Godot 4.7 (GDScript).
The toolchain is pinned: `shell.nix` (godot 4.7.2-stable),
`docker/Dockerfile` (`GODOT_VERSION=4.7.2`), and
`.github/workflows/release.yml` (`GODOT_VERSION`) must name the same
version. Read this first, then the sidecar doc of any file you touch.

## Where things are

- `design/DESIGN.md` — **the design authority.** 26 sections. Consult it before
  any gameplay decision. Appendix A lists cut ideas *with reasons* — never
  re-propose them. Appendix B lists every tuning variable.
- `game/` — the Godot project. Implements **prototype roadmap Steps 1–3**
  (movement, railgun combat, duel feedback HUD, DESIGN.md §24) plus
  prototype-tier LAN multiplayer, the sword, and a Dockerized lobby server
  (`docker/`, first-to-5 1v1s). Step 3's answer comes from LAN 1v1
  playtesting (the bot was cut — Appendix A). Everything else waits —
  do not build ahead of the roadmap.
- `game/README.md` — how to run, controls, what Steps 1–3 are trying to answer.
- `shell.nix` — dev environment. All Godot work goes through it.

## Build / run / verify

```sh
nix-shell                                        # from repo root; binary is godot4
godot4 --path game --editor                      # open editor
godot4 --path game                               # play
godot4 --headless --path game --import           # verify: scan + register classes
godot4 --headless --path game --quit-after 300   # verify: 5s smoke run, must be silent
```

Run both verify commands after any change to `game/`. Script errors print to
stderr; a clean run prints only the engine banner. Then run the
**`sidecar-check` skill** (`/sidecar-check`) to confirm the sidecar docs still
match the code — a PostToolUse hook in `.claude/settings.json` will also remind
you whenever a Godot file changes.

## Conventions

### Sidecar docs (required)

**Every Godot file is paired with a markdown doc named `<filename>.md` beside
it** (`player.gd` → `player.gd.md`, `hud.tscn` → `hud.tscn.md`). This covers
`.gd`, `.tscn`, `.tres`, and `project.godot`.

The default sidecar has four sections:

- **Function** — what the file is for, in terms of the design doc.
- **Interface** — what the rest of the project may rely on: exports, public
  fields/methods, node paths, groups, consumed input actions, signals.
- **Implementation** — how it works; the non-obvious decisions and their why.
- **Assertions** — invariants that must survive any edit. Treat these as a
  checklist before and after changing the paired file.

**Definition files use a `.tr`-style spec instead** (the Trellis-style
pilot — currently `game/src/player/movement/`, one public static function
or data type per file, pure over plain data): YAML frontmatter (`name:`),
prose spec, a ` ```gd-sig` (or ` ```gd-type`) block, labelled
` ```requires`/` ```ensures` clauses, named ` ```test` blocks
(`(args) => outcome`, `with` fixture lines — aspirational until a runner
exists, but kept exact), and an `## Implementation` section. The format
follows `~/code/trellis` `docs/tr-grammar.md` §3 where GDScript allows.
Node-facing shells, facades, scenes, and tools keep the four-section
format. Movement changes must keep the TAS trajectory fingerprint
bit-identical: run `godot4 --headless --path game
res://tools/fingerprint.tscn` and compare against
`game/tas/parkour.fingerprint` (re-baseline only on a deliberate behavior
change, same machine only).

**When you change a Godot file, update its sidecar in the same change.** When
you create a Godot file, create its sidecar. A stale sidecar is a bug.

Verification is automated: the **`sidecar-check` skill**
(`.claude/skills/sidecar-check/`) compares every sidecar against its Godot file
claim-by-claim and fixes drift. Run it after any `game/` change, before ending
a turn that touched Godot files, or standalone as `/sidecar-check` for a full
audit. Its `check_pairs.sh` gives a fast structural pass (missing/stale/orphan
pairs).

### Code

- GDScript, tabs, typed (`:=`, typed params/returns), snake_case files.
- **No gameplay literals in scripts.** Every tunable number lives in
  `game/src/player/default_tuning.tres` (schema:
  `game/src/player/movement_config.gd`, mirroring DESIGN.md Appendix B). If you
  need a new number, add a config field + tres value, don't inline it.
- Scenes are hand-written `.tscn` — keep them minimal and diffable. Omit `uid`
  attributes; the editor adds them.
- **tscn `Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)` basis is ROW-major** —
  emitting axis vectors (columns) transposes the rotation. Symmetric for
  yaw-only boxes, silently wrong for compound rotations (this shipped once
  as "giant holes in the parkour track").
- **Formatting/lint are enforced**: after editing any `.gd` file, run
  `gdformat <files>` and `gdlint game/src` (both in the devshell; config in
  `gdlintrc` at the repo root) — gdlint must exit clean.

### Releases

- CI (`.github/workflows/release.yml`): a push to `main` whose commit
  subject starts with `vX.Y.Z` exports the "Windows Desktop" + "Linux"
  presets, tags the commit, creates a GitHub release with both zips, and
  butler-pushes to itch.io (`rctcwyvrn/airfuel`, channels
  `windows`/`linux`, `--userversion X.Y.Z`). Ordinary subjects build
  nothing. `.gitmessage` (wired via local `git config commit.template`)
  documents the convention.
- `game/project.godot` keeps `config/version="dev"` in-repo; CI seds in
  the release number, and the main menu shows it (`VersionLabel`). Don't
  commit a real number there.

### Process

- The developer (Lily) collaborates through questions — when a design point is
  ambiguous, ask rather than assume; DESIGN.md §23 tracks open questions.
- Don't commit unless asked.
