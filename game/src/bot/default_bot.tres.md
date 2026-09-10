# default_bot.tres

## Function

The practice bot's single tuning set (no difficulty knob — Lily's call).
Schema and per-field meaning: `bot_config.gd`.

## Interface

- `Resource` with `script_class="BotConfig"`; preloaded by
  `PracticeSpawner` (`BOT_CONFIG`) and assigned to the spawned
  `BotController.bot`.

## Implementation

Currently overrides nothing — the shipped values ARE the `bot_config.gd`
schema defaults. Add `field = value` lines here (or live-edit in the
inspector) to retune; the schema defaults should keep mirroring the
intended ship values.

## Assertions

- Keeps `script = ExtResource` pointing at `bot_config.gd`; practice mode
  breaks silently (null config) without it.
