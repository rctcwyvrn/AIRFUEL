class_name ServerConfig
extends Resource

## Dedicated lobby-server tuning (prototype tier). Edit default_server.tres,
## not code. duel_win_kills is the 23 "1v1 duel win condition" answer:
## first to 5 kills.

@export var duel_win_kills := 5
@export var max_peers := 12
@export var challenge_timeout := 15.0
@export var max_name_length := 16

@export_group("Match Servers")
## First udp port handed to per-match child servers; forward/expose the whole
## range [match_port_start, match_port_start + match_port_count).
@export var match_port_start := 27600
@export var match_port_count := 20
## Child exits if two token-valid clients haven't arrived in time.
@export var match_hello_timeout := 60.0
## Child force-ends a match as a draw after this long (orphan guard).
@export var match_max_seconds := 600.0
## Lobby frees an unreported match record (and its port) after this long.
@export var match_result_timeout := 900.0
