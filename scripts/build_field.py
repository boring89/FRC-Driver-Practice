"""Turns an Onshape field export into the game-ready field asset.

  blender -b -P scripts/build_field.py -- <export.glb> <data/fields/YEAR.json> <output dir>

Writes <output dir>/field.glb, laid out in the FRC field frame (origin at the
blue right-hand corner, x toward red, z up), containing:
  - one merged visual mesh per major field element, fasteners dropped
  - "field-colonly": a welded, decimated triangle mesh that Godot imports as a
    static collider
and <output dir>/game_pieces.json with where the CAD stages each game piece.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cadlib import linear, part_name, principled, world_corners

source, config_path, out_dir = sys.argv[sys.argv.index("--") + 1:]
config = json.loads(Path(config_path).read_text())
out_dir = Path(out_dir)
out_dir.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
scene = bpy.context.scene
root = next(o for o in scene.objects if o.parent is None)

# The export keeps the CAD frame (field centre at the origin, z up) but glTF
# readers take y as up, so the import arrives rolled over. Undo that and move
# the origin to the corner.
root.matrix_world = (
    Matrix.Translation((config["half_length_m"], config["half_width_m"], 0.0))
    @ Matrix.Rotation(-np.pi / 2.0, 4, "X")
    @ root.matrix_world
)
bpy.context.view_layer.update()


def local_dimensions(obj):
    corners = np.array(obj.bound_box)
    return np.sort(corners.max(axis=0) - corners.min(axis=0))


def base_color(obj):
    slots = obj.material_slots
    if not slots or slots[0].material is None:
        return None
    return tuple(slots[0].material.diffuse_color[:3])


def close(color, rgb, tolerance=0.01):
    return color is not None and all(abs(a - b) < tolerance for a, b in zip(color, rgb))


def make_material(name, color, metallic, roughness, alpha=1.0):
    material = bpy.data.materials.new(name)
    shader = principled(material)
    shader.inputs["Base Color"].default_value = (*linear(color), 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Alpha"].default_value = alpha
    material.diffuse_color = (*linear(color), alpha)
    material.use_backface_culling = alpha == 1.0
    return material


meshes = [o for o in scene.objects if o.type == "MESH"]
print(f"imported {len(meshes)} parts, {sum(len(o.data.polygons) for o in meshes)} triangles")

# --- Game pieces: record where the CAD stages them, then take them out. ---
pieces = []
doomed = []
for obj in meshes:
    kind = config["game_pieces"].get(part_name(obj))
    if kind is None:
        continue
    corners = world_corners(obj)
    centre = sum(corners, Vector()) / 8.0
    # Direction of the part's longest side, e.g. the axis of a coral pipe.
    local = np.array(obj.bound_box)
    longest = int(np.argmax(local.max(axis=0) - local.min(axis=0)))
    axis = (obj.matrix_world.to_3x3() @ Vector([float(i == longest) for i in range(3)])).normalized()
    pieces.append({
        "type": kind,
        "position": [round(v, 4) for v in centre],
        "axis": [round(v, 4) for v in axis],
    })
    doomed.append(obj)

# --- Fasteners and other tiny parts are invisible at field scale. ---
for obj in meshes:
    if obj in doomed:
        continue
    corners = np.array(world_corners(obj))
    if np.linalg.norm(corners.max(axis=0) - corners.min(axis=0)) < config["min_part_size_m"]:
        doomed.append(obj)
doomed_set = set(doomed)
meshes = [o for o in meshes if o not in doomed_set]
bpy.data.batch_remove(doomed)
print(f"kept {len(meshes)} parts, {sum(len(o.data.polygons) for o in meshes)} triangles; "
      f"recorded {len(pieces)} game pieces")

# --- Collision mesh, built before materials and joins change anything. ---
collision_cfg = config["collision"]
vertex_blocks = []
triangle_blocks = []
offset = 0
for obj in meshes:
    ancestry = [part_name(obj)]
    parent = obj.parent
    while parent is not None:
        ancestry.append(part_name(parent))
        parent = parent.parent
    if any(pattern in label for pattern in collision_cfg["exclude"] for label in ancestry):
        continue
    corners = np.array(world_corners(obj))
    if corners[:, 2].max() < 0.02:
        continue
    if np.linalg.norm(corners.max(axis=0) - corners.min(axis=0)) < collision_cfg["min_part_size_m"]:
        continue
    mesh = obj.data
    mesh.calc_loop_triangles()
    vertices = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", vertices)
    triangles = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int32)
    mesh.loop_triangles.foreach_get("vertices", triangles)
    matrix = np.array(obj.matrix_world)
    vertices = vertices.reshape(-1, 3) @ matrix[:3, :3].T + matrix[:3, 3]
    triangles = triangles.reshape(-1, 3)
    if np.linalg.det(matrix[:3, :3]) < 0.0:
        # Mirrored instance: restore outward-facing winding.
        triangles = triangles[:, ::-1]
    vertex_blocks.append(vertices)
    triangle_blocks.append(triangles + offset)
    offset += len(vertices)

vertices = np.concatenate(vertex_blocks)
triangles = np.concatenate(triangle_blocks)
# Weld to 0.1 mm so the decimator sees connected surfaces rather than loose faces.
_, first, inverse = np.unique(np.round(vertices * 1e4).astype(np.int64), axis=0,
                              return_index=True, return_inverse=True)
vertices = vertices[first]
triangles = inverse.reshape(-1)[triangles]
degenerate = (triangles[:, 0] == triangles[:, 1]) | (triangles[:, 1] == triangles[:, 2]) \
    | (triangles[:, 0] == triangles[:, 2])
triangles = triangles[~degenerate]

collision_mesh = bpy.data.meshes.new("field_collision")
collision_mesh.vertices.add(len(vertices))
collision_mesh.vertices.foreach_set("co", vertices.astype(np.float32).reshape(-1))
collision_mesh.loops.add(len(triangles) * 3)
collision_mesh.loops.foreach_set("vertex_index", triangles.astype(np.int32).reshape(-1))
collision_mesh.polygons.add(len(triangles))
collision_mesh.polygons.foreach_set("loop_start", np.arange(0, len(triangles) * 3, 3, dtype=np.int32))
collision_mesh.polygons.foreach_set("loop_total", np.full(len(triangles), 3, dtype=np.int32))
collision_mesh.update(calc_edges=True)
collision_mesh.validate()
collision = bpy.data.objects.new("field-colonly", collision_mesh)
scene.collection.objects.link(collision)
modifier = collision.modifiers.new("decimate", "DECIMATE")
modifier.ratio = collision_cfg["decimate_ratio"]
decimated = bpy.data.meshes.new_from_object(collision.evaluated_get(bpy.context.evaluated_depsgraph_get()))
decimated.validate()
collision.modifiers.clear()
collision.data = decimated
print(f"collision: {len(triangles)} triangles welded, {len(decimated.polygons)} after decimation")

# --- Materials. ---
for material in list(bpy.data.materials):
    color = tuple(material.diffuse_color[:3])
    shader = principled(material)
    # Onshape writes its sRGB appearance colours straight into the linear
    # glTF field, which washes everything out; convert them properly.
    shader.inputs["Base Color"].default_value = (*linear(color), 1.0)
    shader.inputs["Roughness"].default_value = 0.6
    material.use_backface_culling = True
    for rule in config["materials"]:
        if close(color, rule["rgb"]):
            shader.inputs["Base Color"].default_value = (*linear(rule["color"]), 1.0)
            shader.inputs["Metallic"].default_value = rule["metallic"]
            shader.inputs["Roughness"].default_value = rule["roughness"]

clear_cfg = config["clear_panels"]
clear = make_material("polycarbonate", (0.85, 0.92, 1.0), 0.0, 0.1, clear_cfg["alpha"])
part_materials = [
    (rule["match"], make_material(rule["match"], rule["color"], rule["metallic"], rule["roughness"]))
    for rule in config["parts"]
]
clear_count = 0
for obj in meshes:
    name = part_name(obj)
    override = next((material for match, material in part_materials if match in name), None)
    if override is None and close(base_color(obj), clear_cfg["rgb"]):
        thin, wide, _ = local_dimensions(obj)
        if thin <= clear_cfg["max_thickness_m"] and wide >= clear_cfg["min_width_m"]:
            override = clear
            clear_count += 1
    if override is not None:
        # Slot on the object so other instances of the same mesh keep their own look.
        for slot in obj.material_slots:
            slot.link = "OBJECT"
            slot.material = override
print(f"{clear_count} clear panels")

# --- Merge each major element into one mesh. ---
groups = defaultdict(list)
for obj in meshes:
    top = obj
    while top.parent is not root and top.parent is not None:
        top = top.parent
    # Small top-level items (tape, carpet, posts) share one mesh.
    label = part_name(top) if len(top.children_recursive) > 100 else "misc"
    groups[(label, top.name if label != "misc" else "")].append(obj)

merged = []
for index, ((label, _), members) in enumerate(sorted(groups.items())):
    name = f"field_{index:02d}_{label}"
    target = bpy.data.objects.new(name, bpy.data.meshes.new(name))
    scene.collection.objects.link(target)
    with bpy.context.temp_override(
            active_object=target, selected_objects=members + [target],
            selected_editable_objects=members + [target]):
        bpy.ops.object.join()
    for layer in list(target.data.uv_layers):
        target.data.uv_layers.remove(layer)
    merged.append(target)
    print(f"  {target.name}: {len(members)} parts, {len(target.data.polygons)} triangles")

keep = set(merged) | {collision}
bpy.data.batch_remove([o for o in scene.objects if o not in keep])

bpy.ops.export_scene.gltf(
    filepath=str(out_dir / "field.glb"), export_format="GLB", export_yup=True,
    export_apply=False, export_texcoords=False, export_normals=True, export_materials="EXPORT")
(out_dir / "game_pieces.json").write_text(json.dumps(pieces, indent=1) + "\n")
size = (out_dir / "field.glb").stat().st_size / 1e6
print(f"wrote {out_dir / 'field.glb'} ({size:.1f} MB), "
      f"{sum(len(o.data.polygons) for o in merged)} visual triangles")
