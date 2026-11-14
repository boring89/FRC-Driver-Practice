"""Turns an Onshape robot export into the game-ready robot asset.

  blender -b -P scripts/build_robot.py -- <export.glb> <data/robots/NAME.json> <output dir>

Writes <output dir>/robot.glb in the robot frame (x forward, y left, z up,
origin on the floor under the frame centre) with one mesh per moving link:
"chassis", "steer_N" with child "wheel_N" for each swerve module (posed
straight ahead, origin at the wheel centre), and the links named in the
config. Writes <output dir>/model.json with what the CAD says about module
positions, wheel size, overall bounds and a convex hull of the superstructure.
"""

import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cadlib import linear, part_name, principled, world_corners

HULL_POINTS = 48

source, config_path, out_dir = sys.argv[sys.argv.index("--") + 1:]
config = json.loads(Path(config_path).read_text())
cad = config["cad"]
out_dir = Path(out_dir)
out_dir.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
scene = bpy.context.scene
root = next(o for o in scene.objects if o.parent is None)


def axis(text):
    vector = Vector([float(text[1] == name) for name in "xyz"])
    return -vector if text[0] == "-" else vector


# The export keeps the CAD frame (z up) but glTF readers take y as up, so the
# import arrives rolled over. Undo that, then turn CAD axes into robot axes.
forward = axis(cad["forward"])
left = axis(cad["left"])
cad_to_robot = Matrix((forward, left, forward.cross(left))).to_4x4()
root.matrix_world = cad_to_robot @ Matrix.Rotation(-math.pi / 2.0, 4, "X") @ root.matrix_world
bpy.context.view_layer.update()


def ancestry(obj):
    names = []
    while obj is not None:
        names.append(part_name(obj))
        obj = obj.parent
    return names


def mesh_points(obj):
    points = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
    obj.data.vertices.foreach_get("co", points)
    matrix = np.array(obj.matrix_world)
    return points.reshape(-1, 3) @ matrix[:3, :3].T + matrix[:3, 3]


meshes = [o for o in scene.objects if o.type == "MESH"]
print(f"imported {len(meshes)} parts, {sum(len(o.data.polygons) for o in meshes)} triangles")

# --- Sort parts into links; drop fasteners and other tiny parts. ---
module_cfg = cad["module"]
drop_patterns = [re.compile(pattern) for pattern in cad["drop"]]
positions = [Vector(p) for p in config["swerve"]["module_positions_m"]]
module_parts = defaultdict(list)
links = defaultdict(list)
doomed = []
for obj in meshes:
    name = part_name(obj)
    corners = np.array(world_corners(obj))
    size = np.linalg.norm(corners.max(axis=0) - corners.min(axis=0))
    if size < cad["min_part_size_m"] or any(pattern.search(name) for pattern in drop_patterns):
        doomed.append(obj)
        continue
    names = ancestry(obj)
    if any(module_cfg["match"] in label for label in names):
        centre = Vector(corners.mean(axis=0)).to_2d()
        index = min(range(len(positions)), key=lambda i: (positions[i] - centre).length)
        if any(pattern in name for pattern in module_cfg["wheel"]):
            links[f"wheel_{index}"].append(obj)
            if module_cfg["tread"] in name:
                module_parts[index].append(obj)
            continue
        if any(pattern in name for pattern in module_cfg["steer"]):
            links[f"steer_{index}"].append(obj)
            continue
    link = next((rule["name"] for rule in cad["links"] if any(rule["match"] in label for label in names)),
                "chassis")
    links[link].append(obj)
bpy.data.batch_remove(doomed)
kept = [o for members in links.values() for o in members]
print(f"kept {len(kept)} parts, {sum(len(o.data.polygons) for o in kept)} triangles")

# --- Where each wheel sits and which way the CAD left it pointing. ---
modules = {}
for index, treads in module_parts.items():
    points = np.concatenate([mesh_points(o) for o in treads])
    centre = 0.5 * (points.max(axis=0) + points.min(axis=0))
    # A wheel is thinnest along its axle.
    _, vectors = np.linalg.eigh(np.cov((points - centre).T))
    axle = vectors[:, 0]
    heading = math.atan2(-axle[0], axle[1])
    radius = 0.5 * (points[:, 2].max() - points[:, 2].min())
    modules[index] = {"centre": centre, "heading": heading, "radius": radius}

# --- Simplify each unique mesh once: weld, then decimate to a size-based budget. ---
budgets = {}
for obj in kept:
    corners = np.array(world_corners(obj))
    size = np.linalg.norm(corners.max(axis=0) - corners.min(axis=0))
    budget = max(100.0, cad["triangles_per_m2"] * size * size)
    budgets[obj.data] = max(budgets.get(obj.data, 0.0), budget)

holder = bpy.data.objects.new("decimate_holder", None)
replacements = {}
for mesh, budget in budgets.items():
    work = bmesh.new()
    work.from_mesh(mesh)
    bmesh.ops.remove_doubles(work, verts=work.verts, dist=1e-4)
    work.to_mesh(mesh)
    work.free()
    if len(mesh.polygons) <= budget:
        continue
    temp = bpy.data.objects.new("decimate", mesh)
    scene.collection.objects.link(temp)
    modifier = temp.modifiers.new("decimate", "DECIMATE")
    modifier.ratio = budget / len(mesh.polygons)
    replacements[mesh] = bpy.data.meshes.new_from_object(
        temp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(temp)
for obj in kept:
    if obj.data in replacements:
        obj.data = replacements[obj.data]
print(f"simplified to {sum(len(o.data.polygons) for o in kept)} triangles "
      f"({len(replacements)} of {len(budgets)} unique meshes decimated)")

# --- Materials: Onshape writes sRGB colours into glTF's linear field. ---
for material in bpy.data.materials:
    shader = principled(material)
    shader.inputs["Base Color"].default_value = (*linear(material.diffuse_color[:3]), 1.0)
    shader.inputs["Roughness"].default_value = 0.55
    material.use_backface_culling = True

# --- One mesh per link. ---
merged = {}
for name, members in sorted(links.items()):
    target = bpy.data.objects.new(name, bpy.data.meshes.new(name))
    scene.collection.objects.link(target)
    with bpy.context.temp_override(
            active_object=target, selected_objects=members + [target],
            selected_editable_objects=members + [target]):
        bpy.ops.object.join()
    mesh = target.data
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.set_sharp_from_angle(angle=math.radians(35.0))
    merged[name] = target
    print(f"  {name}: {len(members)} parts, {len(mesh.polygons)} triangles")
bpy.data.batch_remove([o for o in scene.objects if o not in set(merged.values())])

# --- Pose each module straight ahead, with its origin at the wheel centre. ---
for index, module in modules.items():
    centre = Vector(module["centre"])
    straighten = Matrix.Rotation(-module["heading"], 4, "Z") @ Matrix.Translation(-centre)
    steer = merged.get(f"steer_{index}")
    wheel = merged[f"wheel_{index}"]
    if steer is None:
        steer = bpy.data.objects.new(f"steer_{index}", bpy.data.meshes.new(f"steer_{index}"))
        scene.collection.objects.link(steer)
        merged[steer.name] = steer
    for obj in (steer, wheel):
        obj.data.transform(straighten)
    steer.location = centre
    wheel.parent = steer

# --- Convex hull of everything above the drivebase, for collision. ---
superstructure = [merged[rule["name"]] for rule in cad["links"] if rule["name"] in merged]
hull_points = []
if superstructure:
    points = np.concatenate([mesh_points(o) for o in superstructure])
    work = bmesh.new()
    for point in points[:: max(1, len(points) // 20000)]:
        work.verts.new(point)
    result = bmesh.ops.convex_hull(work, input=work.verts)
    inside = {v for v in result["geom_interior"] + result["geom_unused"] if isinstance(v, bmesh.types.BMVert)}
    bmesh.ops.delete(work, geom=list(inside), context="VERTS")
    hull_mesh = bpy.data.meshes.new("hull")
    work.to_mesh(hull_mesh)
    work.free()
    hull = bpy.data.objects.new("hull", hull_mesh)
    scene.collection.objects.link(hull)
    if len(hull_mesh.vertices) > HULL_POINTS:
        modifier = hull.modifiers.new("decimate", "DECIMATE")
        modifier.ratio = HULL_POINTS / len(hull_mesh.vertices)
        hull_mesh = bpy.data.meshes.new_from_object(hull.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    hull_points = [[round(c, 4) for c in v.co] for v in hull_mesh.vertices]
    bpy.data.objects.remove(hull)

all_points = np.concatenate([mesh_points(o) for o in merged.values() if not o.name.startswith(("steer", "wheel"))])
meta = {
    "modules": [
        {"position": [round(float(v), 4) for v in modules[i]["centre"][:2]],
         "cad_heading_deg": round(math.degrees(modules[i]["heading"]), 1)}
        for i in sorted(modules)
    ],
    "wheel_radius_m": round(float(np.mean([m["radius"] for m in modules.values()])), 4),
    "bounds_min_m": [round(float(v), 4) for v in all_points.min(axis=0)],
    "bounds_max_m": [round(float(v), 4) for v in all_points.max(axis=0)],
    "hull": hull_points,
}
(out_dir / "model.json").write_text(json.dumps(meta, indent=1) + "\n")

bpy.ops.export_scene.gltf(
    filepath=str(out_dir / "robot.glb"), export_format="GLB", export_yup=True,
    export_apply=False, export_texcoords=False, export_normals=True, export_materials="EXPORT")
size = (out_dir / "robot.glb").stat().st_size / 1e6
print(f"wrote {out_dir / 'robot.glb'} ({size:.1f} MB), "
      f"{sum(len(o.data.polygons) for o in merged.values())} triangles")
print(json.dumps({k: v for k, v in meta.items() if k != "hull"}))
