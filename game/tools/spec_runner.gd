extends Node

## Headless runner for the .tr-style definition specs (Trellis-style pilot):
## parses every ```test block in game/src/player/movement/*.gd.md, builds
## MoveSim / MovementConfig / fake-probe fixtures from the `with` lines,
## calls the paired definition, and compares outcomes (float compares are
## approx — expected values in the specs are decimal literals).
## Run: godot4 --headless --path game res://tools/spec_runner.tscn
## Exit 0 = all green; 1 = failures (each printed with expected vs got).
##
## Conventions understood (spec side, see CLAUDE.md):
##   with sim = {field: value, ...}      unlisted fields keep MoveSim defaults
##   with cfg = {field: value, ...}      overrides on MovementConfig.new()
##                                       (SCHEMA defaults, not default_tuning)
##   with probe = fake_probe {...}       every call returns this hit; {} = miss
##   (args) => {changed sim fields}      or  => value  or  => value, {fields}
##   identifiers: sim, cfg, probe, BASIS_IDENTITY, MoveState names, xfail

const SPEC_DIR := "res://src/player/movement/"

const DEFS := {
	"air_accelerate": preload("res://src/player/movement/air_accelerate.gd"),
	"air_move": preload("res://src/player/movement/air_move.gd"),
	"apply_glide": preload("res://src/player/movement/apply_glide.gd"),
	"coyote_walljump": preload("res://src/player/movement/coyote_walljump.gd"),
	"decay_excess_speed": preload("res://src/player/movement/decay_excess_speed.gd"),
	"dismount": preload("res://src/player/movement/dismount.gd"),
	"ground_move": preload("res://src/player/movement/ground_move.gd"),
	"handle_dashes": preload("res://src/player/movement/handle_dashes.gd"),
	"speed_limits": preload("res://src/player/movement/speed_limits.gd"),
	"spend_fuel": preload("res://src/player/movement/spend_fuel.gd"),
	"try_attach_wall": preload("res://src/player/movement/try_attach_wall.gd"),
	"update_state": preload("res://src/player/movement/update_state.gd"),
	"wallrun_move": preload("res://src/player/movement/wallrun_move.gd"),
	"wish_dir": preload("res://src/player/movement/wish_dir.gd"),
}

var total := 0
var failed := 0
var xfail := 0


func _ready() -> void:
	var files := Array(DirAccess.get_files_at(SPEC_DIR))
	files.sort()
	for f: String in files:
		if f.ends_with(".gd.md") and DEFS.has(f.trim_suffix(".gd.md")):
			_run_spec(f.trim_suffix(".gd.md"))
	print("spec-runner: %d cases, %d failed, %d xfail" % [total, failed, xfail])
	get_tree().quit(1 if failed > 0 else 0)


func _run_spec(def_name: String) -> void:
	var text := FileAccess.get_file_as_string(SPEC_DIR + def_name + ".gd.md")
	var sig := _parse_sig(text)
	if sig.is_empty():
		_fail(def_name, "-", "no gd-sig block found")
		return
	for block: Dictionary in _parse_test_blocks(text):
		var k := 0
		for case_line: String in block.cases:
			k += 1
			var label: String = "%s %s#%d" % [def_name, block.name, k]
			var ok: bool = _run_case(def_name, sig, block, case_line, label)
			total += 1
			if ok and block.is_xfail:
				_fail(label, "-", "XPASS: xfail block passed")
			elif not ok and block.is_xfail:
				xfail += 1
				print("xfail %s" % label)
			elif not ok:
				failed += 1


## Parses the first ```gd-sig fence: {func_name, param_types: Array[String]}.
func _parse_sig(text: String) -> Dictionary:
	var line := _fence_body(text, "```gd-sig")
	if line == "" or ":" not in line:
		return {}
	var func_name := line.get_slice(":", 0).strip_edges()
	var params := line.substr(line.find("(") + 1, line.rfind(")") - line.find("(") - 1)
	var types: Array[String] = []
	for p: String in _split_top(params, ","):
		types.append(p.get_slice(":", 1).strip_edges())
	return {func_name = func_name, param_types = types}


func _fence_body(text: String, opener: String) -> String:
	var at := text.find(opener)
	if at == -1:
		return ""
	var start := text.find("\n", at) + 1
	return text.substr(start, text.find("```", start) - start).strip_edges()


## Every ```test block: {name, is_xfail, withs: Dictionary, cases: Array}.
func _parse_test_blocks(text: String) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var line := lines[i].strip_edges()
		if not line.begins_with("```test"):
			i += 1
			continue
		var words := line.trim_prefix("```test").strip_edges().split(" ")
		var block := {name = words[0], is_xfail = "xfail" in words, withs = {}, cases = []}
		i += 1
		while i < lines.size() and not lines[i].strip_edges().begins_with("```"):
			var body := lines[i].strip_edges()
			if body.begins_with("with "):
				var eq := body.find("=")
				block.withs[body.substr(5, eq - 5).strip_edges()] = (
					body.substr(eq + 1).strip_edges()
				)
			elif body.begins_with("("):
				block.cases.append(body)
			i += 1
		blocks.append(block)
	return blocks


func _run_case(
	def_name: String, sig: Dictionary, block: Dictionary, case_line: String, label: String
) -> bool:
	# Fresh fixtures per case: cases in one block are independent.
	var cfg := MovementConfig.new()
	if block.withs.has("cfg"):
		var overrides: Dictionary = _parse_value(block.withs.cfg)
		for key: String in overrides:
			cfg.set(key, _to_float(overrides[key]))
	var sim := MoveSim.new()
	if block.withs.has("sim"):
		var fields: Dictionary = _parse_value(block.withs.sim)
		for key: String in fields:
			sim.set(key, _resolve_by_sample(fields[key], sim.get(key)))
	var probe := _make_probe(block.withs.get("probe", "fake_probe {}"))

	var arrow := case_line.rfind("=>")
	var arg_text := case_line.substr(0, arrow).strip_edges()
	var args := _build_args(
		_split_top(arg_text.substr(1, arg_text.rfind(")") - 1), ","),
		sig.param_types,
		{sim = sim, cfg = cfg, probe = probe}
	)
	var ret: Variant = Callable(DEFS[def_name], sig.func_name).callv(args)
	return _check_outcome(case_line.substr(arrow + 2).strip_edges(), ret, sim, label)


func _build_args(tokens: Array, types: Array[String], bindings: Dictionary) -> Array:
	var args := []
	for j in tokens.size():
		var tok: String = tokens[j].strip_edges()
		if bindings.has(tok):
			args.append(bindings[tok])
		elif tok == "BASIS_IDENTITY":
			args.append(Basis.IDENTITY)
		else:
			args.append(_resolve_by_type(_parse_value(tok), types[j]))
	return args


func _check_outcome(outcome: String, ret: Variant, sim: MoveSim, label: String) -> bool:
	var parts := _split_top(outcome, ",") if not outcome.begins_with("{") else [outcome]
	var ok := true
	for part: String in parts:
		part = part.strip_edges()
		if part.begins_with("{"):
			var expected: Dictionary = _parse_value(part)
			for key: String in expected:
				var want: Variant = _resolve_by_sample(expected[key], sim.get(key))
				if not _approx_eq(sim.get(key), want):
					_fail(label, key, "expected %s, got %s" % [want, sim.get(key)])
					ok = false
		else:
			var want_ret: Variant = _resolve_by_sample(_parse_value(part), ret)
			if not _approx_eq(ret, want_ret):
				_fail(label, "return", "expected %s, got %s" % [want_ret, ret])
				ok = false
	return ok


func _make_probe(spec: String) -> Callable:
	var hit_spec: Dictionary = _parse_value(spec.trim_prefix("fake_probe").strip_edges())
	if hit_spec.is_empty():
		return func(_dir: Vector3, _scale: float) -> Dictionary: return {}
	var hit := {
		normal = _resolve_by_type(hit_spec.normal, "Vector3"),
		position = _resolve_by_type(hit_spec.position, "Vector3"),
	}
	return func(_dir: Vector3, _scale: float) -> Dictionary: return hit.duplicate()


## --- value syntax: numbers, true/false, identifiers, [..] arrays, {k: v} ---
## Scalars stay raw String tokens until a type resolves them (by declared
## param type or by the sample value already sitting in the target field).


func _parse_value(text: String) -> Variant:
	return _parse_at(text, [0])


func _parse_at(s: String, pos: Array) -> Variant:
	_skip_ws(s, pos)
	var c := s[pos[0]]
	if c == "[":
		var arr := []
		pos[0] += 1
		_skip_ws(s, pos)
		while s[pos[0]] != "]":
			arr.append(_parse_at(s, pos))
			_skip_ws(s, pos)
			if s[pos[0]] == ",":
				pos[0] += 1
		pos[0] += 1
		return arr
	if c == "{":
		var dict := {}
		pos[0] += 1
		_skip_ws(s, pos)
		while s[pos[0]] != "}":
			var colon := s.find(":", pos[0])
			var key := s.substr(pos[0], colon - pos[0]).strip_edges()
			pos[0] = colon + 1
			dict[key] = _parse_at(s, pos)
			_skip_ws(s, pos)
			if s[pos[0]] == ",":
				pos[0] += 1
				_skip_ws(s, pos)
		pos[0] += 1
		return dict
	var j: int = pos[0]
	while j < s.length() and s[j] not in ",]}":
		j += 1
	var tok := s.substr(pos[0], j - pos[0]).strip_edges()
	pos[0] = j
	return tok


func _skip_ws(s: String, pos: Array) -> void:
	while pos[0] < s.length() and s[pos[0]] in " \t":
		pos[0] += 1


## Splits at top-level delimiters only (nesting via [], {}, ()).
func _split_top(s: String, delim: String) -> Array:
	var parts := []
	var depth := 0
	var start := 0
	for j in s.length():
		if s[j] in "[{(":
			depth += 1
		elif s[j] in "]})":
			depth -= 1
		elif s[j] == delim and depth == 0:
			parts.append(s.substr(start, j - start))
			start = j + 1
	if start < s.length():
		parts.append(s.substr(start))
	return parts


func _resolve_by_type(v: Variant, type_name: String) -> Variant:
	match type_name:
		"float":
			return _to_float(v)
		"bool":
			return v == "true"
		"Vector3":
			return Vector3(_to_float(v[0]), _to_float(v[1]), _to_float(v[2]))
		"Vector2":
			return Vector2(_to_float(v[0]), _to_float(v[1]))
		"Array[Dictionary]":
			var rows: Array[Dictionary] = []
			for row: Dictionary in v:
				(
					rows
					. append(
						{
							normal = _resolve_by_type(row.normal, "Vector3"),
							deflector = row.deflector == "true",
						}
					)
				)
			return rows
	return v


func _resolve_by_sample(v: Variant, sample: Variant) -> Variant:
	match typeof(sample):
		TYPE_VECTOR3:
			return _resolve_by_type(v, "Vector3")
		TYPE_VECTOR2:
			return _resolve_by_type(v, "Vector2")
		TYPE_FLOAT:
			return _to_float(v)
		TYPE_BOOL:
			return v == "true"
		TYPE_INT:  # MoveState names (or a plain int)
			var tok := str(v)
			return MoveSim.MoveState[tok] if MoveSim.MoveState.has(tok) else tok.to_int()
	return v


func _to_float(v: Variant) -> float:
	return str(v).to_float()


func _approx_eq(a: Variant, b: Variant) -> bool:
	if a is Vector3 and b is Vector3:
		return (a as Vector3).is_equal_approx(b as Vector3) or a == b
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b)) or float(a) == float(b)
	return a == b


func _fail(label: String, field: String, msg: String) -> void:
	push_error("FAIL %s [%s]: %s" % [label, field, msg])
