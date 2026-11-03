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
    mesh = trimesh.creation.box(extents=size)
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
box("Magazine body",(.075,.20,.10),(0,-.40,-.20),polymer)
box("Magazine floor plate",(.085,.025,.115),(0,-.515,-.20),steel)
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
