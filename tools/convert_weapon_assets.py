import bpy
import sys
from mathutils import Vector, Matrix
from pathlib import Path

def parse_args():
    if "--" not in sys.argv:
        raise RuntimeError("Expected input, output, and target length after --")
    args = sys.argv[sys.argv.index("--") + 1:]
    if len(args) != 3:
        raise RuntimeError("Usage: convert_weapon_assets.py INPUT OUTPUT TARGET_LENGTH")
    return Path(args[0]), Path(args[1]), float(args[2])

def import_source(source: Path):
    suffix = source.suffix.lower()
    if suffix == ".blend":
        # Blender opened this file before running the script.
        return
    if suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(source), use_custom_normals=True)
        return
    raise RuntimeError("Unsupported weapon source: " + suffix)

def normalize_and_export(output: Path, target_length: float):
    relevant = [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "ARMATURE"}]
    meshes = [obj for obj in relevant if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh objects found in imported weapon source")

    corners = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    minimum = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    maximum = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    center = (minimum + maximum) * 0.5
    longest = max((maximum - minimum).x, (maximum - minimum).y, (maximum - minimum).z)
    if longest <= 0.0001:
        raise RuntimeError("Weapon mesh has invalid dimensions")
    factor = target_length / longest

    scale_matrix = Matrix.Scale(factor, 4)
    offset = Matrix.Translation(-center)
    for obj in relevant:
        world = obj.matrix_world.copy()
        obj.matrix_world = scale_matrix @ offset @ world

    bpy.ops.object.select_all(action="DESELECT")
    for obj in relevant:
        obj.select_set(True)
    if relevant:
        bpy.context.view_layer.objects.active = relevant[0]

    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    if not output.exists() or output.stat().st_size < 10000:
        raise RuntimeError("GLB export is missing or unexpectedly small")

def main():
    source, output, target_length = parse_args()
    import_source(source)
    normalize_and_export(output, target_length)
    print("IRON VEIL: exported", output, "at target length", target_length)

if __name__ == "__main__":
    main()
