#!/usr/bin/env python3
"""Generate Quest-friendly, rounded PBR GLB visuals for IRON VEIL."""
from pathlib import Path
import numpy as np
import trimesh
from trimesh.visual.material import PBRMaterial
from trimesh.visual.texture import TextureVisuals

def mat(name, rgb, metallic=0.0, roughness=0.7):
    return PBRMaterial(name=name, baseColorFactor=[*rgb, 255],
                       metallicFactor=metallic, roughnessFactor=roughness)

polymer = mat("Matte black polymer", (30, 34, 31), 0.02, 0.86)
steel = mat("Dark anodized metal", (72, 78, 75), 0.68, 0.42)
rubber = mat("Textured rubber", (17, 20, 18), 0.0, 0.96)
glass = mat("Optic coated glass", (26, 91, 84), 0.55, 0.2)
brass = mat("Muted hardware", (126, 105, 65), 0.62, 0.45)
fabric = mat("Olive tactical fabric", (53, 62, 46), 0.0, 0.94)
armor = mat("Glove reinforcement", (78, 82, 64), 0.02, 0.88)

def put(scene, mesh, name, material):
    mesh.visual = TextureVisuals(material=material)
    scene.add_geometry(mesh, geom_name=name, node_name=name)

def rounded_box(scene, name, size, pos, material, soften=2):
    mesh = trimesh.creation.box(extents=size)
    for _ in range(soften):
        vertices, faces = trimesh.remesh.subdivide(mesh.vertices, mesh.faces)
        mesh = trimesh.Trimesh(vertices=vertices, faces=faces, process=False)
    trimesh.smoothing.filter_taubin(mesh, lamb=0.42, nu=-0.45, iterations=3)
    mesh.apply_translation(pos)
    put(scene, mesh, name, material)

def cylinder(scene, name, radius, length, pos, axis, material, sections=32):
    mesh = trimesh.creation.cylinder(radius=radius, height=length, sections=sections)
    mesh.apply_transform(trimesh.geometry.align_vectors([0, 0, 1], np.asarray(axis, dtype=float)))
    mesh.apply_translation(pos)
    put(scene, mesh, name, material)

def capsule(scene, name, radius, height, pos, material, scale=(1,1,1)):
    mesh = trimesh.creation.capsule(height=height, radius=radius, count=[20, 12])
    mesh.apply_scale(scale)
    mesh.apply_translation(pos)
    put(scene, mesh, name, material)

# Rifle is aligned with the original hand pose: muzzle points down local -Z.
def build_rifle():
    scene = trimesh.Scene()
    rounded_box(scene, "Adjustable stock", (.13,.16,.27), (0,-.005,.31), polymer)
    rounded_box(scene, "Soft butt pad", (.135,.165,.035), (0,-.005,.455), rubber)
    cylinder(scene, "Buffer tube", .029,.24,(0,0,.18),(0,0,1),steel)
    rounded_box(scene, "Lower receiver", (.112,.145,.245),(0,-.075,-.13),steel)
    rounded_box(scene, "Upper receiver", (.112,.105,.35),(0,.012,-.205),polymer)
    rounded_box(scene, "Ejection port recess", (.012,.052,.12),(.058,-.002,-.19),rubber,1)
    rounded_box(scene, "Ejection port cover", (.012,.038,.105),(.066,.004,-.19),steel,1)
    capsule(scene, "Forward assist", .018,.042,(.064,.035,-.31),steel,(1,1,.7))
    # Rounded free-float handguard replaces the old rectangular fore-end.
    capsule(scene, "Rounded handguard", .061,.43,(0,.012,-.535),polymer,(1,1,1))
    cylinder(scene, "Barrel", .018,.66,(0,.012,-.99),(0,0,1),steel)
    cylinder(scene, "Gas block", .027,.075,(0,.012,-.79),(0,0,1),steel)
    cylinder(scene, "Flash hider", .027,.085,(0,.012,-1.36),(0,0,1),steel)
    rounded_box(scene, "Top rail spine", (.055,.025,.72),(0,.078,-.50),steel,1)
    for i in range(15):
        rounded_box(scene, f"Top rail tooth {i}",(.061,.014,.022),(0,.096,-.16-i*.048),polymer,1)
    for side in (-1,1):
        rounded_box(scene, f"Side rail {side}",(.018,.045,.32),(side*.061,.012,-.54),steel,1)
        for j in range(6):
            rounded_box(scene,f"Side rail lug {side}-{j}",(.012,.014,.027),(side*.073,.012,-.41-j*.05),polymer,1)
    # Optic housing is a rounded tube with glass front/rear apertures.
    rounded_box(scene,"Optic mount",(.09,.05,.13),(0,.135,-.29),steel,1)
    capsule(scene,"Red dot optic housing",.045,.15,(0,.205,-.29),polymer,(1,1,1))
    cylinder(scene,"Optic front lens",.037,.008,(0,.205,-.37),(0,0,1),glass)
    cylinder(scene,"Optic rear lens",.037,.008,(0,.205,-.21),(0,0,1),glass)
    capsule(scene,"Pistol grip",.043,.20,(0,-.19,-.09),rubber,(.9,1,.9))
    rounded_box(scene,"Magazine well",(.095,.07,.12),(0,-.155,-.19),polymer,1)
    capsule(scene,"Curved polymer magazine",.039,.27,(0,-.315,-.20),polymer,(1,1,1))
    rounded_box(scene,"Magazine floor plate",(.086,.027,.11),(0,-.46,-.20),steel,1)
    # Rounded trigger guard and curved trigger.
    capsule(scene,"Trigger guard",.012,.12,(0,-.17,-.115),steel,(2.8,1,.65))
    capsule(scene,"Trigger",.008,.065,(0,-.15,-.13),brass,(.8,1,.8))
    rounded_box(scene,"Front sight base",(.065,.06,.045),(0,.105,-.72),steel,1)
    rounded_box(scene,"Front sight ears",(.11,.02,.03),(0,.145,-.72),steel,1)
    rounded_box(scene,"Front sight post",(.012,.07,.014),(0,.18,-.72),steel,1)
    out=Path("assets/models/weapons/m4_carbine.glb")
    out.parent.mkdir(parents=True,exist_ok=True)
    scene.export(out)
    print(f"Created rounded rifle {out} ({out.stat().st_size} bytes)")

def ellipsoid(scene, name, center, scale, material):
    mesh=trimesh.creation.icosphere(subdivisions=3,radius=1.0)
    mesh.apply_scale(scale); mesh.apply_translation(center)
    put(scene,mesh,name,material)

def link(scene, name, start, end, radius, material):
    start,end=np.asarray(start,dtype=float),np.asarray(end,dtype=float)
    delta=end-start
    mesh=trimesh.creation.cylinder(radius=radius,height=float(np.linalg.norm(delta)),sections=20)
    mesh.apply_transform(trimesh.geometry.align_vectors([0,0,1],delta))
    mesh.apply_translation((start+end)*.5)
    put(scene,mesh,name,material)

def build_hand(side, filename):
    Path(filename).parent.mkdir(parents=True,exist_ok=True)
    scene=trimesh.Scene()
    mirror=float(side)
    ellipsoid(scene,"Glove palm",(0,0,0),(.083,.105,.037),fabric)
    ellipsoid(scene,"Padded palm heel",(0,.075,.005),(.068,.060,.041),rubber)
    finger_x=[-.052,-.018,.018,.052]
    finger_len=[.105,.125,.118,.095]
    for i,x in enumerate(finger_x):
        x*=mirror; top=-.07; middle=top-finger_len[i]*.48; tip=top-finger_len[i]
        link(scene,f"Finger {i} proximal",(x,top,0),(x,middle,-.006),.014,fabric)
        link(scene,f"Finger {i} distal",(x,middle,-.006),(x,tip,-.014),.0115,fabric)
        ellipsoid(scene,f"Finger {i} knuckle",(x,top,.024),(.018,.021,.012),armor)
        ellipsoid(scene,f"Finger {i} joint",(x,middle,-.006),(.012,.014,.012),armor)
        ellipsoid(scene,f"Finger {i} fingertip",(x,tip,-.014),(.012,.018,.012),fabric)
    t0=(mirror*.066,-.025,0); t1=(mirror*.112,-.078,-.006); t2=(mirror*.13,-.13,-.015)
    link(scene,"Thumb base",t0,t1,.019,fabric)
    link(scene,"Thumb tip",t1,t2,.014,fabric)
    ellipsoid(scene,"Thumb knuckle",t1,(.021,.022,.016),armor)
    ellipsoid(scene,"Thumb tip pad",t2,(.016,.021,.014),fabric)
    link(scene,"Wrist cuff",(0,.07,0),(0,.19,0),.047,rubber)
    ellipsoid(scene,"Cuff rim",(0,.17,0),(.052,.025,.052),armor)
    scene.export(filename)
    print(f"Created glove {filename} ({Path(filename).stat().st_size} bytes)")

build_rifle()
build_hand(-1,"assets/models/hands/left_hand.glb")
build_hand(1,"assets/models/hands/right_hand.glb")

def build_house_cqb():
    # The downloaded house is a full exterior asset. Bake a second CQB version
    # by removing the street-facing wall faces and roof faces, so its actual
    # rooms, stairs and authored interior remain visible and enterable.
    source=Path("assets/models/environment/suburban_house.glb")
    if not source.exists():
        print("No source house found; skipping cutaway build")
        return
    source_scene=trimesh.load(source,force="scene")
    bounds=source_scene.bounds
    front_z=float(bounds[0,2])
    roof_y=float(bounds[1,1])
    floor_y=float(bounds[0,1])
    cutaway=trimesh.Scene()
    removed_faces=0
    for index, original in enumerate(source_scene.dump(concatenate=False)):
        if not isinstance(original,trimesh.Trimesh):
            continue
        mesh=original.copy()
        centers=mesh.triangles_center
        normals=mesh.face_normals
        front_wall=(centers[:,2] < front_z+0.14) & (centers[:,1] > floor_y+0.22) & (centers[:,1] < roof_y-0.42)
        roof_faces=(centers[:,1] > roof_y-0.16) & (normals[:,1] > 0.35)
        keep=~(front_wall | roof_faces)
        removed_faces += int((~keep).sum())
        if keep.any():
            mesh.update_faces(keep)
            mesh.remove_unreferenced_vertices()
            if len(mesh.faces)>0:
                cutaway.add_geometry(mesh,geom_name=f"CQB_House_{index}",node_name=f"CQB_House_{index}")
    if len(cutaway.geometry)==0:
        raise RuntimeError("House cutaway generation removed all geometry")
    out=Path("assets/models/environment/suburban_house_cqb.glb")
    cutaway.export(out)
    print(f"Created CQB cutaway {out} ({out.stat().st_size} bytes; removed {removed_faces} facade/roof faces)")

build_house_cqb()
