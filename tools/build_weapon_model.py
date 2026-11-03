#!/usr/bin/env python3
"""Build the bundled, detailed M4-style training prop as a Godot-importable GLB."""
from pathlib import Path
import trimesh
from trimesh.visual.material import PBRMaterial
from trimesh.visual.texture import TextureVisuals

out = Path("assets/models/weapons/m4_carbine.glb")
out.parent.mkdir(parents=True, exist_ok=True)
scene = trimesh.Scene()

def material(name, rgb, metallic=0.0, roughness=0.7):
    return PBRMaterial(name=name, baseColorFactor=[*rgb, 255],
                       metallicFactor=metallic, roughnessFactor=roughness)

polymer = material("Black polymer", (27, 31, 28), 0.03, 0.84)
steel = material("Anodized steel", (67, 72, 68), 0.72, 0.38)
rubber = material("Rubber", (12, 14, 13), 0.0, 0.96)
glass = material("Optic glass", (24, 83, 78), 0.5, 0.18)
brass = material("Hardware", (116, 95, 58), 0.7, 0.4)

def add(mesh, name, mat):
    mesh.visual = TextureVisuals(material=mat)
    scene.add_geometry(mesh, geom_name=name, node_name=name)

def box(name, size, pos, mat):
    # Beveled convex hulls remove the sharp, toy-like cube silhouette from
    # receivers, stock, optic housing, magazine, and accessory housings.
    size = __import__("numpy").array(size, dtype=float)
    radius = max(0.0015, float(size.min()) * 0.16)
    core = __import__("numpy").maximum(size - radius * 2.0, radius * 0.35)
    corner_clouds = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                sphere = trimesh.creation.icosphere(subdivisions=2, radius=radius)
                sphere.apply_translation((sx * core[0] * 0.5, sy * core[1] * 0.5, sz * core[2] * 0.5))
                corner_clouds.append(sphere)
    mesh = trimesh.util.concatenate(corner_clouds).convex_hull
    mesh.apply_translation(pos)
    add(mesh, name, mat)

def cylinder(name, radius, length, pos, axis, mat, sections=32):
    mesh = trimesh.creation.cylinder(radius=radius, height=length, sections=sections)
    direction = trimesh.unitize(axis)
    mesh.apply_transform(trimesh.geometry.align_vectors([0, 0, 1], direction))
    mesh.apply_translation(pos)
    add(mesh, name, mat)

# Coordinates match the existing weapon grip and muzzle placement in main.gd.
box("Adjustable stock", (.12,.15,.27), (0,-.005,.31), polymer)
box("Rubber butt pad", (.125,.16,.028), (0,-.005,.455), rubber)
cylinder("Buffer tube", .028,.24,(0,0,.18),(0,0,1),steel)
box("Lower receiver", (.108,.135,.24),(0,-.075,-.13),steel)
box("Upper receiver", (.108,.095,.34),(0,.015,-.20),polymer)
box("Ejection port", (.009,.045,.11),(.057,-.005,-.19),rubber)
box("Dust cover", (.01,.035,.095),(.063,-.005,-.19),steel)
cylinder("Forward assist",.018,.025,(.06,.035,-.31),(1,0,0),steel,20)
box("Free float handguard",(.13,.13,.38),(0,.01,-.53),polymer)
cylinder("Barrel",.018,.63,(0,.01,-.99),(0,0,1),steel)
cylinder("Gas block",.026,.07,(0,.01,-.78),(0,0,1),steel)
cylinder("Flash hider",.027,.075,(0,.01,-1.33),(0,0,1),steel)
box("Picatinny top rail",(.05,.025,.78),(0,.085,-.50),steel)
for i in range(14):
    box(f"Rail tooth {i}",(.052,.012,.018),(0,.103,-.15-i*.052),polymer)
box("Optic mount",(.09,.055,.13),(0,.14,-.29),steel)
box("Red dot optic",(.095,.10,.14),(0,.21,-.29),polymer)
cylinder("Front optic lens",.039,.006,(0,.21,-.365),(0,0,1),glass)
cylinder("Rear optic lens",.039,.006,(0,.21,-.215),(0,0,1),glass)
box("Pistol grip",(.075,.19,.10),(0,-.19,-.09),rubber)
box("Magazine upper",(.078,.14,.11),(0,-.25,-.20),steel)
box("Magazine upper",(.078,.11,.11),(0,-.255,-.20),steel)
box("Magazine body upper",(.074,.12,.098),(0,-.355,-.195),polymer)
box("Magazine body mid",(.071,.12,.094),(0,-.455,-.18),polymer)
box("Magazine body lower",(.068,.09,.09),(0,-.55,-.16),polymer)
box("Magazine floor plate",(.085,.025,.115),(0,-.605,-.16),steel)
box("Trigger guard",(.075,.018,.095),(0,-.155,-.11),steel)
box("Trigger",(.012,.045,.018),(0,-.15,-.12),brass)
box("Front sight post",(.018,.085,.025),(0,.14,-.70),steel)
box("Front sight ears",(.11,.02,.03),(0,.13,-.70),steel)
for side in (-1,1):
    box(f"Side rail {side}",(.018,.05,.30),(side*.073,.01,-.53),steel)
    for j in range(5):
        box(f"Side rail lug {side}-{j}",(.012,.012,.025),(side*.084,.01,-.40-j*.055),polymer)
for x in (-.058,.058):
    for z in (-.29,-.08):
        cylinder("Receiver pin",.008,.006,(x,-.075,z),(1,0,0),brass,16)

scene.export(out)
print(f"Created {out} ({out.stat().st_size} bytes)")

# Generate matching, smooth tactical-glove hand models for both controllers.
def ellipsoid(mesh_name, center, scale, mat, hand_scene):
    mesh = trimesh.creation.icosphere(subdivisions=2, radius=1.0)
    mesh.apply_scale(scale)
    mesh.apply_translation(center)
    mesh.visual = TextureVisuals(material=mat)
    hand_scene.add_geometry(mesh, geom_name=mesh_name, node_name=mesh_name)

def link(mesh_name, start, end, radius, mat, hand_scene):
    start, end = __import__("numpy").array(start, dtype=float), __import__("numpy").array(end, dtype=float)
    delta = end - start
    mesh = trimesh.creation.cylinder(radius=radius, height=float(__import__("numpy").linalg.norm(delta)), sections=16)
    mesh.apply_transform(trimesh.geometry.align_vectors([0,0,1], delta))
    mesh.apply_translation((start + end) * 0.5)
    mesh.visual = TextureVisuals(material=mat)
    hand_scene.add_geometry(mesh, geom_name=mesh_name, node_name=mesh_name)

def build_hand(side, filename):
    from pathlib import Path
    Path(filename).parent.mkdir(parents=True, exist_ok=True)
    hand_scene = trimesh.Scene()
    glove = material("Dark olive tactical glove", (48, 55, 43), 0.0, 0.92)
    armor = material("Reinforced knuckle fabric", (72, 76, 60), 0.02, 0.88)
    rubber = material("Grip rubber", (25, 29, 25), 0.0, 0.98)
    mirror = float(side)
    ellipsoid("Glove palm", (0,0,0), (.083,.105,.037), glove, hand_scene)
    ellipsoid("Padded palm heel", (0,.075,.005), (.068,.060,.041), rubber, hand_scene)
    # Four fingers: articulated segments and raised knuckle pads.
    finger_x = [-.052,-.018,.018,.052]
    finger_len = [.105,.125,.118,.095]
    for i, x in enumerate(finger_x):
        x *= mirror
        top = -.07
        middle = top - finger_len[i]*.48
        tip = top - finger_len[i]
        link(f"Finger {i} proximal", (x,top,0), (x, middle, -.006), .014, glove, hand_scene)
        link(f"Finger {i} distal", (x,middle,-.006), (x,tip,-.014), .0115, glove, hand_scene)
        ellipsoid(f"Finger {i} knuckle", (x,top,.024), (.018,.021,.012), armor, hand_scene)
        ellipsoid(f"Finger {i} joint", (x,middle,-.006), (.012,.014,.012), armor, hand_scene)
        ellipsoid(f"Finger {i} fingertip", (x,tip,-.014), (.012,.018,.012), glove, hand_scene)
    # Opposing thumb sweeps outward and down toward a natural grip pose.
    t0=(mirror*.066,-.025,0); t1=(mirror*.112,-.078,-.006); t2=(mirror*.13,-.13,-.015)
    link("Thumb base",t0,t1,.019,glove,hand_scene)
    link("Thumb tip",t1,t2,.014,glove,hand_scene)
    ellipsoid("Thumb knuckle",t1,(.021,.022,.016),armor,hand_scene)
    ellipsoid("Thumb tip pad",t2,(.016,.021,.014),glove,hand_scene)
    # Wrist cuff and stitched reinforcement panels.
    link("Wrist cuff",(0,.07,0),(0,.19,0),.047,rubber,hand_scene)
    ellipsoid("Cuff rim",(0,.17,0),(.052,.025,.052),armor,hand_scene)
    hand_scene.export(filename)

build_hand(-1, "assets/models/hands/left_hand.glb")
build_hand(1, "assets/models/hands/right_hand.glb")
