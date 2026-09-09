class_name ServerConfig
extends Resource

## Dedicated lobby-server tuning (prototype tier). Edit default_server.tres,
## not code. duel_win_kills is the 23 "1v1 duel win condition" answer:
## first to 5 kills.

@export var duel_win_kills := 5
@export var max_peers := 12
@export var challenge_timeout := 15.0
@export var max_name_length := 16
