"""Prints a summary of a glTF/GLB export: size, hierarchy, triangle budget.

  blender -b -P scripts/inspect_glb.py -- <file.glb>
"""

import sys
from collections import Counter

import bpy
from mathutils import Vector

path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
empties = [o for o in bpy.context.scene.objects if o.type == "EMPTY"]
total = sum(len(o.data.loop_triangles) or len(o.data.polygons) for o in meshes)
print(f"objects: {len(meshes)} meshes, {len(empties)} empties, {len(bpy.data.meshes)} unique meshes")
print(f"polygons: {sum(len(o.data.polygons) for o in meshes)}")

low = Vector((1e9, 1e9, 1e9))
high = Vector((-1e9, -1e9, -1e9))
sizes = []
for o in meshes:
    corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
    for c in corners:
        low = Vector(map(min, low, c))
        high = Vector(map(max, high, c))
    diagonal = (Vector(map(max, *corners)) - Vector(map(min, *corners))).length
    sizes.append((diagonal, len(o.data.polygons), o.name))
print(f"bounds (Blender, z up): min {tuple(round(v, 3) for v in low)} max {tuple(round(v, 3) for v in high)}")
print(f"size: {tuple(round(v, 3) for v in high - low)}")

for limit in (0.02, 0.05, 0.1, 0.3, 1.0):
    small = [s for s in sizes if s[0] < limit]
    print(f"parts under {limit} m: {len(small)} objects, {sum(s[1] for s in small)} polygons")

print("heaviest parts:")
for diagonal, polygons, name in sorted(sizes, key=lambda s: -s[1])[:15]:
    print(f"  {polygons:>8} polys  {diagonal:6.2f} m  {name}")

print("top-level nodes:")
for o in bpy.context.scene.objects:
    if o.parent is None:
        print(f"  {o.type:<6} {o.name}  children={len(o.children)}")
        for child in list(o.children)[:40]:
            print(f"    {child.type:<6} {child.name}  children={len(child.children_recursive)}")

materials = Counter()
for o in meshes:
    for slot in o.material_slots:
        if slot.material:
            materials[slot.material.name] += len(o.data.polygons)
print(f"materials: {len(bpy.data.materials)}")
for name, polygons in materials.most_common(15):
    material = bpy.data.materials[name]
    color = tuple(round(c, 2) for c in material.diffuse_color)
    print(f"  {polygons:>8} polys  {name}  {color}")
