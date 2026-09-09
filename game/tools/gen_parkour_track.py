#!/usr/bin/env python3
"""Generates game/maps/parkour_track.tscn (hallway + obstacles + arrows +
ghost waypoints). Run from repo root: python3 game/tools/gen_parkour_track.py
Track edits happen HERE, then regenerate — never hand-edit the tscn."""
import math

def mat_mul(A, B):
    return [[sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def basis_str(M):
    # tscn Transform3D takes the basis ROW-major — emitting columns transposes
    # the rotation (this bug shipped: pitched halls tilted sideways = holes)
    return ", ".join("%.5f, %.5f, %.5f" % tuple(M[i]) for i in range(3))
def ry(t):
    c, s = math.cos(t), math.sin(t); return [[c,0,s],[0,1,0],[-s,0,c]]
def rx(t):
    c, s = math.cos(t), math.sin(t); return [[1,0,0],[0,c,-s],[0,s,c]]
def rz(t):
    c, s = math.cos(t), math.sin(t); return [[c,-s,0],[s,c,0],[0,0,1]]
def col(M, j):
    return (M[0][j], M[1][j], M[2][j])
def box(name, M, pos, size, mat, extra=""):
    pos = tuple(pos)
    return (f'\n[node name="{name}" type="CSGBox3D" parent="."]\n'
            f"transform = Transform3D({basis_str(M)}, %.3f, %.3f, %.3f)\n" % pos +
            f"use_collision = true\nsize = Vector3({size[0]}, {size[1]}, {size[2]})\n"
            + extra + f'material = SubResource("{mat}")\n')
def cylnode(name, pos, r, h, mat):
    pos = tuple(pos)
    return (f'\n[node name="{name}" type="CSGCylinder3D" parent="."]\n'
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.3f, %.3f, %.3f)\n" % pos +
            f"use_collision = true\nradius = {r}\nheight = {h}\n"
            f'material = SubResource("{mat}")\n')

HEADER = '''[gd_scene load_steps=16 format=3]

[ext_resource type="PackedScene" path="res://src/player/player.tscn" id="1_player"]
[ext_resource type="PackedScene" path="res://src/hud/hud.tscn" id="2_hud"]
[ext_resource type="Script" path="res://src/ghost/ghost.gd" id="3_ghost"]
[ext_resource type="Script" path="res://src/race/finish_zone.gd" id="4_finish"]

[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]
sky_top_color = Color(0.25, 0.32, 0.45, 1)
sky_horizon_color = Color(0.55, 0.58, 0.62, 1)
ground_bottom_color = Color(0.12, 0.12, 0.14, 1)
ground_horizon_color = Color(0.55, 0.58, 0.62, 1)

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_mat")

[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
glow_enabled = true
glow_intensity = 0.6
glow_bloom = 0.1

[sub_resource type="StandardMaterial3D" id="mat_floor"]
albedo_color = Color(0.42, 0.44, 0.47, 1)

[sub_resource type="StandardMaterial3D" id="mat_wall"]
albedo_color = Color(0.55, 0.62, 0.72, 1)

[sub_resource type="StandardMaterial3D" id="mat_panel"]
albedo_color = Color(0.3, 0.72, 0.65, 1)

[sub_resource type="StandardMaterial3D" id="mat_obstacle"]
albedo_color = Color(0.95, 0.08, 0.08, 1)
emission_enabled = true
emission = Color(1, 0.1, 0.1, 1)
emission_energy_multiplier = 0.8

[sub_resource type="StandardMaterial3D" id="mat_arrow"]
albedo_color = Color(1, 0.55, 0.1, 1)
emission_enabled = true
emission = Color(1, 0.55, 0.1, 1)
emission_energy_multiplier = 2.0

[sub_resource type="StandardMaterial3D" id="mat_light"]
albedo_color = Color(1, 1, 0.95, 1)
emission_enabled = true
emission = Color(1, 0.98, 0.9, 1)
emission_energy_multiplier = 2.5

[sub_resource type="StandardMaterial3D" id="mat_finish"]
albedo_color = Color(0.1, 0.85, 0.25, 1)
emission_enabled = true
emission = Color(0.15, 1, 0.3, 1)
emission_energy_multiplier = 1.2

[sub_resource type="BoxShape3D" id="finish_shape"]
size = Vector3(24, 30, 3)

[sub_resource type="StandardMaterial3D" id="mat_cyl"]
albedo_color = Color(0.85, 0.5, 0.2, 1)

[node name="ParkourTrack" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866025, 0, -0.5, -0.353553, 0.707107, -0.612372, 0.353553, 0.707107, 0.612372, 0, 120, 0)
shadow_enabled = true
directional_shadow_max_distance = 600.0
'''

W, WH, BASE_Y = 24.0, 30.0, 40.0
body = HEADER
pos = [0.0, BASE_Y, 0.0]
heading = 0.0
wps = [(0.0, BASE_Y + 3.0, -14.0)]
min_y = BASE_Y
obst_n = 0
PATTERNS = ["blockL", "pillar", "blockR", "bar"]

def hall_part(tag, start, hdg, pitch, L, with_obstacle):
    global obst_n
    a = math.radians(pitch)
    M = mat_mul(ry(hdg), rx(-a))
    side, lup, fwd3 = col(M, 0), col(M, 1), col(M, 2)
    mid = tuple(start[k] + fwd3[k] * L / 2 for k in range(3))
    fl = tuple(mid[k] - lup[k] * 1.0 for k in range(3))
    out = box(f"{tag}Floor", M, fl, (W, 2, L + 5), "mat_floor")
    for sn, ss in (("L", 1.0), ("R", -1.0)):
        wc = tuple(mid[k] + side[k] * ss * (W/2 + 0.5) + lup[k] * (WH/2 - 1) for k in range(3))
        out += box(f"{tag}Wall{sn}", M, wc, (1, WH + 2, L + 8), "mat_wall")
    rc = tuple(mid[k] + lup[k] * WH for k in range(3))
    out += box(f"{tag}Roof", M, rc, (W + 2, 2, L + 5), "mat_floor", "cast_shadow = 0\n")
    if with_obstacle and L >= 20 and pitch == 0:
        pat = PATTERNS[obst_n % len(PATTERNS)]
        obst_n += 1
        if pat == "blockL":
            oc = [mid[k] + side[k] * (W/2 - 6.5) + lup[k] * 14 for k in range(3)]
            out += box(f"Obst{obst_n}", M, oc, (13, 29, 1.5), "mat_obstacle")
        elif pat == "blockR":
            oc = [mid[k] - side[k] * (W/2 - 6.5) + lup[k] * 14 for k in range(3)]
            out += box(f"Obst{obst_n}", M, oc, (13, 29, 1.5), "mat_obstacle")
        elif pat == "pillar":
            oc = [mid[k] + lup[k] * 14 for k in range(3)]
            out += box(f"Obst{obst_n}", M, oc, (5, 29, 1.5), "mat_obstacle")
        else:
            oc = [mid[k] + lup[k] * 10 for k in range(3)]
            out += box(f"Obst{obst_n}", M, oc, (W, 8, 1.5), "mat_obstacle")
    end = tuple(start[k] + fwd3[k] * L for k in range(3))
    return out, end

body += box("StartPad", ry(0), (0, BASE_Y - 0.5, -12), (W, 1, 26), "mat_floor")
body += box("StartWallL", ry(0), (W/2 + 0.5, BASE_Y + 14, -12), (1, WH, 26), "mat_wall")
body += box("StartWallR", ry(0), (-W/2 - 0.5, BASE_Y + 14, -12), (1, WH, 26), "mat_wall")
body += box("StartCap", ry(0), (0, BASE_Y + 14, -25.5), (W + 2, WH, 1), "mat_wall")
body += box("StartRoof", ry(0), (0, BASE_Y + WH - 0.5, -12), (W + 2, 1, 26), "mat_floor", "cast_shadow = 0\n")

SEGS = [
    (120, 0, -1), (140, 10, 1), (100, 0, 1), (150, -10, -1),
    (130, 12, -1), (140, 0, 1), (120, -12, 1), (150, 10, -1),
    (130, 0, 1), (120, -8, -1), (150, 8, 0),
]
for i, (L, pitch, turn) in enumerate(SEGS):
    # half-angle blend wedges at each pitch change: joints bend 6 deg max,
    # and the thick slabs swallow those wedges entirely (no sky slivers)
    parts = ([(0.20, 0.0), (0.08, pitch / 2), (0.44, pitch), (0.08, pitch / 2), (0.20, 0.0)]
             if pitch != 0 else [(1.0, 0.0)])
    for j, (frac, p) in enumerate(parts):
        nodes, pos_end = hall_part(f"H{i+1}p{j+1}", pos, heading, p, L * frac, i > 0)
        body += nodes
        wps.append(tuple(pos[k] + (pos_end[k] - pos[k]) * 0.5 + (3.2 if k == 1 else 0.0)
                         for k in range(3)))
        pos = list(pos_end)
    min_y = min(min_y, pos[1])
    d = (math.sin(heading), 0.0, math.cos(heading))
    if turn == 0:
        body += box("EndCapFloor", ry(heading), (pos[0] + d[0]*12, pos[1] - 0.5, pos[2] + d[2]*12), (W, 1, 26), "mat_floor")
        body += box("EndCapWall", ry(heading), (pos[0] + d[0]*24.5, pos[1] + 14, pos[2] + d[2]*24.5), (W + 2, WH, 1), "mat_finish")
        fz = (pos[0] + d[0]*22.5, pos[1] + 14, pos[2] + d[2]*22.5)
        body += (f'\n[node name="FinishZone" type="Area3D" parent="." groups=["finish"]]\n'
                 f"transform = Transform3D({basis_str(ry(heading))}, %.3f, %.3f, %.3f)\n" % fz +
                 f'script = ExtResource("4_finish")\n'
                 f"collision_mask = 4\n")
        body += ('\n[node name="FinishShape" type="CollisionShape3D" parent="FinishZone"]\n'
                 'shape = SubResource("finish_shape")\n')
        body += box("EndCapRoof", ry(heading), (pos[0] + d[0]*12, pos[1] + WH - 0.5, pos[2] + d[2]*12), (W + 2, 1, 26), "mat_floor", "cast_shadow = 0\n")
        for sn, sv in (("L", 1.0), ("R", -1.0)):
            sf = (math.cos(heading)*sv, 0.0, -math.sin(heading)*sv)
            body += box(f"EndCapWall{sn}", ry(heading), (pos[0] + d[0]*12 + sf[0]*(W/2+0.5), pos[1] + 14, pos[2] + d[2]*12 + sf[2]*(W/2+0.5)), (1, WH, 26), "mat_wall")
        wps.append((pos[0] + d[0]*8, pos[1] + 3.2, pos[2] + d[2]*8))
        break
    pc = tuple(pos[k] + d[k] * W / 2 for k in range(3))
    RY = ry(heading)
    sflat = (math.cos(heading), 0.0, -math.sin(heading))
    body += box(f"C{i+1}Pad", RY, (pc[0], pc[1] - 1.0, pc[2]), (W + 6, 2, W + 6), "mat_floor")
    body += box(f"C{i+1}Roof", RY, (pc[0], pc[1] + WH, pc[2]), (W + 6, 2, W + 6), "mat_floor", "cast_shadow = 0\n")
    body += box(f"C{i+1}Far", RY, [pc[0] + d[0]*(W/2 + 0.5), pc[1] + 14, pc[2] + d[2]*(W/2 + 0.5)], (W + 6, WH + 2, 1), "mat_wall")
    body += box(f"C{i+1}Side", RY, [pc[0] - sflat[0]*turn*(W/2 + 0.5), pc[1] + 14, pc[2] - sflat[2]*turn*(W/2 + 0.5)], (1, WH + 2, W + 6), "mat_wall")
    for px, pz in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        pcorner = [pc[0] + sflat[0]*px*(W/2 + 0.5) + d[0]*pz*(W/2 + 0.5),
                   pc[1] + 14,
                   pc[2] + sflat[2]*px*(W/2 + 0.5) + d[2]*pz*(W/2 + 0.5)]
        # bright red: these interrupt a wallrun line, so they must read as
        # obstacles from far away, not blend into the wall
        body += box(f"C{i+1}Post{('P' if px > 0 else 'N')}{('P' if pz > 0 else 'N')}",
                    RY, pcorner, (3, WH + 2, 3), "mat_obstacle")
    body += box(f"C{i+1}Light", RY, [pc[0], pc[1] + WH - 1.2, pc[2]], (6, 0.3, 6), "mat_light", "cast_shadow = 0\n")
    body += (f'\n[node name="C{i+1}Omni" type="OmniLight3D" parent="."]\n'
             f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.2f, %.2f, %.2f)\n" % (pc[0], pc[1] + WH - 4, pc[2]) +
             "light_energy = 0.8\nomni_range = 45.0\n")
    body += cylnode(f"C{i+1}Cyl", [pc[0] - sflat[0]*turn*(W/4), pc[1] - 1.0, pc[2] - sflat[2]*turn*(W/4)], 2.5, 26.0, "mat_cyl")
    ainner = tuple(pc[k] + d[k]*(W/2 - 0.4) for k in range(3))
    for bi, (yoff, ang) in enumerate([(2.0, -math.pi/4), (-2.0, math.pi/4)]):
        Mbar = mat_mul(RY, rz(ang * turn))
        bc = (ainner[0], ainner[1] + 12.0 + yoff, ainner[2])
        body += box(f"C{i+1}Arrow{bi+1}", Mbar, bc, (6, 1.4, 0.6), "mat_arrow", "cast_shadow = 0\n")
    wps.append((pc[0], pc[1] + 3.2, pc[2]))
    heading += turn * math.pi / 2
    nd = (math.sin(heading), 0.0, math.cos(heading))
    pos = [pc[k] + nd[k] * W / 2 for k in range(3)]

flat = ", ".join("%.2f, %.2f, %.2f" % w for w in wps)
body += f'''
[node name="Player" parent="." instance=ExtResource("1_player")]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, {BASE_Y + 2.6}, -18)

[node name="HUD" parent="." instance=ExtResource("2_hud")]

[node name="GhostRunner" parent="." instance=ExtResource("1_player")]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, {BASE_Y + 2.6}, -18)
ghost_controlled = true

[node name="TasController" type="Node" parent="GhostRunner"]
script = ExtResource("3_ghost")
tape_path = "res://tas/parkour.tas"
waypoints = PackedVector3Array({flat})
'''
open("game/maps/parkour_track.tscn", "w").write(body)
print("hallway v3: %d obstacles, arrows at %d corners, %d waypoints, min y %.0f"
      % (obst_n, sum(1 for s in SEGS if s[2] != 0), len(wps), min_y))
