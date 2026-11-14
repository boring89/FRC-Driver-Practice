"""Helpers shared by the Blender scripts that turn Onshape exports into game assets."""

import re

from mathutils import Vector


def part_name(obj):
    """Onshape part name of an imported object, without instance decorations."""
    name = obj.name.removeprefix("occurrence of ")
    return re.sub(r"(\.\d{3}| <\d+>)$", "", name)


def world_corners(obj):
    return [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]


def linear(srgb):
    """sRGB colour (as CAD and the configs give it) to the linear values glTF stores."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


def principled(material):
    material.use_nodes = True
    return next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
