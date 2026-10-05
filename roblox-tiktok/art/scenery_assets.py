"""Builds the Diamond Rush scenery pack in Blender and exports it for Roblox.

Every asset is generated here (no hand-made files), so the pack can be rebuilt
or restyled. Each asset is one closed mesh, coloured with vertex colours, under
Roblox's 20,000-triangle limit, modelled at real size (1 Blender unit = 1 stud)
standing on its base at the origin.

    blender --background --python art/scenery_assets.py          (Blender 4.2+)
    python art/scenery_assets.py                                   (with `pip install bpy`)

Writes src/shared/ScenePackData.luau (the meshes as data the game builds itself),
art/DiamondRushScenery.fbx (the same pack for an optional Studio import),
art/manifest.json and preview renders in art/previews/. Pass --no-render to skip
the previews.
"""
import math
import random
import sys
from pathlib import Path

import bpy  # must come first: it makes bmesh and mathutils importable
import bmesh
from mathutils import Matrix, Vector, noise

ART = Path(__file__).resolve().parent
PREVIEWS = ART / "previews"
MAX_TRIANGLES = 20000


# Helpers ------------------------------------------------------------------------
def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def smoothstep(a, b, x):
    t = clamp((x - a) / (b - a)) if b != a else 0.0
    return t * t * (3 - 2 * t)


def mix(c1, c2, t):
    return tuple(c1[i] + (c2[i] - c1[i]) * t for i in range(3))


def scale(c, k):
    return tuple(clamp(v * k) for v in c)


def srgb(r, g, b):
    """0-255 sRGB to the linear values Blender stores."""
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b))


def fbm(p, octaves=4):
    return noise.fractal(p, 0.5, 2.0, octaves, noise_basis="PERLIN_ORIGINAL")


def material():
    mat = bpy.data.materials.get("VertexColour")
    if mat:
        return mat
    mat = bpy.data.materials.new("VertexColour")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Color"
    mat.node_tree.links.new(attribute.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.88
    return mat


def finish(name, bm, colour_of_face, smooth_of_face=lambda f: False, location=(0, 0, 0)):
    """Colours every face corner, rests the mesh on z=0 and links it to the scene."""
    bm.normal_update()
    layer = bm.loops.layers.float_color.new("Color")
    for face in bm.faces:
        colours = colour_of_face(face)
        face.smooth = smooth_of_face(face)
        for index, loop in enumerate(face.loops):
            c = colours[index] if isinstance(colours, list) else colours
            loop[layer] = (c[0], c[1], c[2], 1.0)
    low = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= low
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    triangles = len(bm.faces)
    if triangles > MAX_TRIANGLES:
        raise SystemExit(f"{name} has {triangles} triangles (Roblox allows {MAX_TRIANGLES})")
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.color_attributes.active_color = mesh.color_attributes["Color"]
    mesh.materials.append(material())
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    return obj, triangles


def add_ico(bm, centre, radius, subdivisions=2, squash=(1, 1, 1)):
    result = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    verts = result["verts"]
    for v in verts:
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2])) + Vector(centre)
    return verts


def add_tube(bm, points, radii, sides=8, cap=True):
    """A closed tube through `points` (Vectors) with a radius at each point.
    Returns the end cap faces (first, last)."""
    rings = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        axis = (b - a).normalized()
        side = axis.cross(Vector((0, 0, 1)))
        if side.length < 1e-4:
            side = axis.cross(Vector((1, 0, 0)))
        side.normalize()
        other = axis.cross(side)
        ring = []
        for k in range(sides):
            angle = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (side * math.cos(angle) + other * math.sin(angle)) * radii[i]))
        rings.append(ring)
    for r1, r2 in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((r1[k], r1[(k + 1) % sides], r2[(k + 1) % sides], r2[k]))
    if cap:
        return bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])
    return None, None


def face_centre(face):
    return face.calc_center_median()


# Mountains ------------------------------------------------------------------------
SNOW = srgb(240, 244, 250)
SNOW_SHADE = srgb(196, 212, 232)
ROCK_LIGHT = srgb(146, 134, 120)
ROCK_DARK = srgb(78, 72, 70)
ALPINE = srgb(104, 118, 66)
FOREST = srgb(34, 62, 38)


def mountain(name, seed, width, depth, peaks, grid=94):
    """A snow-capped massif: a heightfield of ridged noise shaped by peak
    envelopes, closed with skirts and a base so it is watertight."""
    bm = bmesh.new()
    cols, rows = grid, int(grid * depth / width)
    top = max(p[2] for p in peaks)
    heights = {}

    def height(x, y):
        envelope = 0.0
        for px, py, ph, pr in peaks:
            d = math.hypot(x - px, (y - py) * 1.15) / pr
            envelope = max(envelope, ph * (1 - smoothstep(0, 1, d)) ** 1.35)
        p = Vector((x / 70 + seed, y / 70 - seed, seed * 0.37))
        ridges = noise.ridged_multi_fractal(p, 1.0, 2.05, 6, 1.0, 2.1, noise_basis="PERLIN_ORIGINAL")
        detail = fbm(Vector((x / 23, y / 23, seed)), 4)
        edge = min(x + width / 2, width / 2 - x, y + depth / 2, depth / 2 - y)
        fade = smoothstep(0, 40, edge)
        z = envelope * (0.42 + 0.34 * ridges) + detail * 4 * fade
        return z * fade - 12 * (1 - fade)

    verts = []
    for j in range(rows + 1):
        row = []
        for i in range(cols + 1):
            x = -width / 2 + width * i / cols
            y = -depth / 2 + depth * j / rows
            z = height(x, y)
            heights[(i, j)] = z
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
    # Skirt and base close the surface.
    border = [verts[0][i] for i in range(cols + 1)] + [verts[j][cols] for j in range(1, rows + 1)] \
        + [verts[rows][i] for i in range(cols - 1, -1, -1)] + [verts[j][0] for j in range(rows - 1, 0, -1)]
    low = [bm.verts.new((v.co.x, v.co.y, -30)) for v in border]
    n = len(border)
    for k in range(n):
        bm.faces.new((border[(k + 1) % n], border[k], low[k], low[(k + 1) % n]))
    bm.faces.new(list(reversed(low)))  # the base faces down

    def concavity(i, j):
        if 0 < i < cols and 0 < j < rows:
            around = (heights[(i - 1, j)] + heights[(i + 1, j)] + heights[(i, j - 1)] + heights[(i, j + 1)]) / 4
            return clamp((around - heights[(i, j)]) / 6)
        return 0.0

    index = {v: (i, j) for j, row in enumerate(verts) for i, v in enumerate(row)}

    def colour_vertex(v, normal):
        x, y, z = v.co
        steep = 1 - normal.z
        n = fbm(Vector((x / 40, y / 40, seed + 3)), 3)
        snow_line = top * 0.5 + n * top * 0.12
        rock = mix(ROCK_LIGHT, ROCK_DARK, clamp(0.45 + fbm(Vector((x / 15, y / 15, z / 30 + seed)), 3) * 1.2 + steep * 0.3))
        if v in index:
            rock = scale(rock, 1 - 0.45 * concavity(*index[v]))
        colour = rock
        grass = smoothstep(top * 0.3, top * 0.12, z + n * 22) * smoothstep(0.8, 0.5, steep)
        if grass > 0:
            colour = mix(colour, mix(FOREST, ALPINE, clamp(0.5 + n * 2)), grass)
        snow = smoothstep(snow_line - 6, snow_line + 6, z) * smoothstep(0.82, 0.55, steep)
        if snow > 0:
            colour = mix(colour, mix(SNOW, SNOW_SHADE, clamp(steep * 1.6)), snow)
        return colour

    vertex_colour = {}
    bm.normal_update()
    for v in bm.verts:
        vertex_colour[v] = colour_vertex(v, v.normal) if v.co.z > -29 else ROCK_DARK
    return finish(name, bm, lambda f: [vertex_colour[l.vert] for l in f.loops], lambda f: True)


# Trees ---------------------------------------------------------------------------
BARK = srgb(84, 60, 42)
NEEDLES_DARK = srgb(24, 52, 34)
NEEDLES = srgb(46, 88, 50)
NEEDLES_TIP = srgb(92, 132, 70)


def conifer(name, seed, height, tiers=9, segments=15, snow=0.0):
    """A layered pine: drooping, jagged needle skirts around a tapered trunk."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    trunk_top = height * 0.9
    points = [Vector((0, 0, z)) for z in (0, 0.6, height * 0.3, height * 0.6, trunk_top)]
    radii = [height * 0.075, height * 0.05, height * 0.038, height * 0.025, height * 0.01]
    trunk_faces = set()
    before = set(bm.faces)
    add_tube(bm, points, radii, sides=8)
    trunk_faces = set(bm.faces) - before
    tier_of = {}
    for t_index in range(tiers):
        t = t_index / (tiers - 1)
        rim_z = height * (0.17 + 0.72 * t ** 0.93)
        r = height * (0.33 * (1 - t) ** 0.9 + 0.045)
        apex = bm.verts.new((rnd.uniform(-0.1, 0.1), rnd.uniform(-0.1, 0.1), rim_z + height * (0.17 - 0.07 * t)))
        twist = rnd.uniform(0, math.pi * 2)
        mid, rim = [], []
        for k in range(segments):
            angle = twist + 2 * math.pi * k / segments + rnd.uniform(-0.08, 0.08)
            tip = k % 2 == 0
            reach = r * (1.0 if tip else 0.74) * rnd.uniform(0.9, 1.1)
            droop = (0.16 if tip else 0.05) * r
            mid.append(bm.verts.new((math.cos(angle) * reach * 0.52, math.sin(angle) * reach * 0.52, rim_z + height * 0.075 * (1 - t * 0.4))))
            rim.append(bm.verts.new((math.cos(angle) * reach, math.sin(angle) * reach, rim_z - droop)))
        under = bm.verts.new((0, 0, rim_z - r * 0.08))
        faces = []
        for k in range(segments):
            k2 = (k + 1) % segments
            faces.append(bm.faces.new((apex, mid[k], mid[k2])))
            faces.append(bm.faces.new((mid[k], rim[k], rim[k2], mid[k2])))
            faces.append(bm.faces.new((rim[k2], rim[k], under)))
        for f in faces:
            tier_of[f] = (t, rnd.uniform(0.9, 1.1))

    def colour(face):
        if face in trunk_faces:
            return scale(BARK, 0.85 + 0.3 * rnd.random())
        t, tone = tier_of[face]
        centre = face_centre(face)
        radial = clamp(math.hypot(centre.x, centre.y) / (height * 0.3))
        if face.normal.z < -0.2:
            base = scale(NEEDLES_DARK, 0.85)
        else:
            base = mix(NEEDLES, NEEDLES_TIP, clamp(radial * 0.8 + t * 0.35))
        base = scale(base, tone)
        if snow > 0 and face.normal.z > 0.45:
            patch = smoothstep(-0.15, 0.2, fbm(centre * 0.35 + Vector((seed, 0, 0)), 2))
            base = mix(base, SNOW, clamp(snow * smoothstep(0.45, 0.8, face.normal.z) * patch * (0.3 + radial * 0.7)))
        return base

    return finish(name, bm, colour, lambda f: f in trunk_faces)


BIRCH_BARK = srgb(222, 218, 206)
BIRCH_MARK = srgb(40, 38, 36)
OAK_BARK = srgb(92, 70, 50)


def broadleaf(name, seed, height, birch=True):
    """A broadleaf tree: a short bent trunk forking into branches under a wide,
    faceted crown of leaf clusters."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    lean = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * height * 0.03
    fork = Vector((0, 0, height * (0.38 if birch else 0.3))) + lean
    radius = height * (0.035 if birch else 0.055)
    before = set(bm.faces)
    add_tube(bm, [Vector((0, 0, 0)), Vector((0, 0, height * 0.12)) + lean * 0.3, fork], [radius * 1.6, radius * 1.05, radius * 0.9], sides=10)
    clusters = []
    crown_height = height * 0.68
    spread = height * (0.26 if birch else 0.33)
    branches = 5 if birch else 6
    for b in range(branches):
        angle = b * 2 * math.pi / branches + rnd.uniform(-0.35, 0.35)
        out = Vector((math.cos(angle), math.sin(angle), 0))
        end = Vector((0, 0, crown_height + rnd.uniform(-0.08, 0.1) * height)) + out * spread * rnd.uniform(0.65, 1.0) + lean
        bend = fork + (end - fork) * 0.5 + Vector((0, 0, height * 0.05))
        add_tube(bm, [fork, bend, end], [radius * 0.7, radius * 0.45, radius * 0.25], sides=6)
        clusters.append(end)
        clusters.append(fork + (end - fork) * 0.62 + out * spread * 0.15 + Vector((0, 0, height * 0.06)))
    clusters.append(Vector((0, 0, crown_height + height * 0.14)) + lean)
    wood_faces = set(bm.faces) - before
    leaf_tone = {}
    leaf = srgb(118, 152, 58) if birch else srgb(60, 102, 42)
    leaf_light = srgb(178, 202, 96) if birch else srgb(116, 156, 68)
    for c in clusters:
        size = height * rnd.uniform(0.13, 0.18) * (0.95 if birch else 1.15)
        before = set(bm.faces)
        verts = add_ico(bm, c, size, subdivisions=2, squash=(1, 1, 0.78))
        seed3 = rnd.uniform(0, 100)
        for v in verts:
            offset = v.co - Vector(c)
            v.co = Vector(c) + offset * (1 + 0.24 * fbm(offset / size * 1.4 + Vector((seed3, 0, 0)), 3))
        tone = rnd.uniform(0.9, 1.07)
        for f in set(bm.faces) - before:
            leaf_tone[f] = tone
    bm.normal_update()
    crown_low = crown_height - height * 0.2

    def colour(face):
        centre = face_centre(face)
        if face in wood_faces:
            if birch:
                band = fbm(Vector((centre.z * 3.1, seed, 0)), 2) + fbm(Vector((centre.x * 4, centre.y * 4, centre.z * 4)), 2) * 0.4
                return scale(BIRCH_MARK, 1.6) if band > 0.42 else scale(BIRCH_BARK, 0.92 + 0.08 * rnd.random())
            return scale(OAK_BARK, 0.85 + 0.2 * rnd.random())
        # Sunlit top, shaded underside, a hint of depth inside the crown.
        light = clamp(0.3 + face.normal.z * 0.45 + smoothstep(crown_low, crown_height + height * 0.2, centre.z) * 0.35)
        return scale(mix(scale(leaf, 0.66), leaf_light, light), leaf_tone[face])

    return finish(name, bm, colour, lambda f: f in wood_faces)


# Rocks ---------------------------------------------------------------------------
STONE = srgb(124, 122, 116)
STONE_DARK = srgb(80, 78, 76)
MOSS = srgb(84, 112, 46)
LICHEN = srgb(186, 176, 120)


def chisel(bm, rnd, size, cuts):
    """Flattens the rock against random planes: sharp, broken faces."""
    for _ in range(cuts):
        normal = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.4, 1))).normalized()
        point = normal * rnd.uniform(0.62, 0.8) * size
        for v in bm.verts:
            d = (v.co - point).dot(normal)
            if d > 0:
                v.co -= normal * d


def rock(name, seed, dims, mossy=0.5, cuts=7):
    rnd = random.Random(seed)
    bm = bmesh.new()
    add_ico(bm, (0, 0, 0), 1.0, subdivisions=4)
    for v in bm.verts:
        v.co *= 1 + 0.16 * fbm(v.co * 1.7 + Vector((seed, 0, 0)), 4)
    chisel(bm, rnd, 1.0, cuts)
    for v in bm.verts:
        v.co = Vector((v.co.x * dims[0] / 2, v.co.y * dims[1] / 2, max(v.co.z, -0.55) * dims[2] / 2))
    bm.normal_update()
    lowest = min(v.co.z for v in bm.verts)

    def colour(face):
        c = face_centre(face)
        tone = clamp(0.5 + fbm(c * 0.6 + Vector((seed, 1, 2)), 3) * 1.4)
        base = mix(STONE_DARK, STONE, tone)
        base = scale(base, 0.8 + 0.25 * clamp((c.z - lowest) / dims[2]))
        moss = mossy * smoothstep(0.35, 0.85, face.normal.z) * smoothstep(-0.2, 0.25, fbm(c * 0.45 + Vector((0, seed, 0)), 3))
        if moss > 0:
            base = mix(base, scale(MOSS, rnd.uniform(0.85, 1.1)), moss)
        lichen = smoothstep(0.25, 0.4, fbm(c * 1.3 + Vector((seed, 5, 0)), 2))
        return mix(base, LICHEN, lichen * 0.35)

    return finish(name, bm, colour)


def cliff(name, seed, width, depth, height):
    """A rock outcrop: overlapping chiselled masses with weathered ledges and
    grassy shelves."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    masses = [(0.0, 0.0, 1.0, 1.0), (-0.3, 0.1, 0.62, 0.75), (0.32, -0.05, 0.55, 0.62)]
    for ox, oy, sw, sh in masses:
        verts = add_ico(bm, (0, 0, 0), 1.0, subdivisions=3)
        for v in verts:
            v.co *= 1 + 0.14 * fbm(v.co * 1.6 + Vector((seed + ox * 10, oy, 0)), 4)
        for _ in range(9):
            normal = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.2, 1))).normalized()
            point = normal * rnd.uniform(0.6, 0.78)
            for v in verts:
                d = (v.co - point).dot(normal)
                if d > 0:
                    v.co -= normal * d
        for v in verts:
            v.co = Vector((v.co.x * width / 2 * sw + ox * width / 2, v.co.y * depth / 2 * sw + oy * depth / 2, max(v.co.z, -0.4) * height / 1.4 * sh))
            terrace = round(v.co.z / 2.6) * 2.6
            v.co.z += (terrace - v.co.z) * 0.3
    bm.normal_update()
    lowest = min(v.co.z for v in bm.verts)

    def colour(face):
        c = face_centre(face)
        strata = 0.5 + 0.5 * math.sin(c.z * 0.9 + fbm(c / 8 + Vector((seed, 0, 0)), 2) * 3)
        base = mix(srgb(104, 98, 92), srgb(156, 146, 132), clamp(strata * 0.6 + fbm(c / 3, 2) * 0.6 + 0.2))
        base = scale(base, 0.76 + 0.3 * clamp((c.z - lowest) / height))
        grass = smoothstep(0.62, 0.88, face.normal.z) * smoothstep(-0.25, 0.15, fbm(c / 3 + Vector((seed, 0, 0)), 2))
        return mix(base, mix(MOSS, ALPINE, 0.5), grass)

    return finish(name, bm, colour)


# Ground detail ---------------------------------------------------------------------
def bush(name, seed, size):
    rnd = random.Random(seed)
    bm = bmesh.new()
    tones = {}
    for k in range(5):
        angle = k * 2.4 + rnd.uniform(0, 0.5)
        centre = Vector((math.cos(angle) * size * 0.3, math.sin(angle) * size * 0.3, size * rnd.uniform(0.32, 0.5)))
        before = set(bm.faces)
        verts = add_ico(bm, centre, size * rnd.uniform(0.32, 0.45), subdivisions=3, squash=(1, 1, 0.8))
        for v in verts:
            offset = v.co - centre
            v.co = centre + offset * (1 + 0.2 * fbm(offset * 2 + Vector((seed, k, 0)), 2))
        t = rnd.uniform(0.85, 1.1)
        for f in set(bm.faces) - before:
            tones[f] = t
    bm.normal_update()
    leaf, light = srgb(52, 92, 40), srgb(112, 150, 62)

    def colour(face):
        return scale(mix(scale(leaf, 0.75), light, clamp(0.35 + face.normal.z * 0.5 + rnd.uniform(-0.1, 0.1))), tones[face])

    return finish(name, bm, colour)


def flowers(name, seed, petal):
    """A clump of grass blades and small flowers on short stems."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    kinds = {}
    grass = srgb(86, 124, 52)
    for k in range(14):
        angle = rnd.uniform(0, math.pi * 2)
        r = rnd.uniform(0, 1.0)
        base = Vector((math.cos(angle) * r, math.sin(angle) * r, 0))
        tip = base + Vector((rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25), rnd.uniform(0.7, 1.3)))
        before = set(bm.faces)
        add_tube(bm, [base, tip], [0.07, 0.015], sides=3)
        for f in set(bm.faces) - before:
            kinds[f] = ("grass", rnd.uniform(0.8, 1.15))
    for k in range(7):
        angle = rnd.uniform(0, math.pi * 2)
        r = rnd.uniform(0, 0.9)
        base = Vector((math.cos(angle) * r, math.sin(angle) * r, 0))
        top = base + Vector((rnd.uniform(-0.1, 0.1), rnd.uniform(-0.1, 0.1), rnd.uniform(0.9, 1.5)))
        before = set(bm.faces)
        add_tube(bm, [base, top], [0.04, 0.03], sides=3)
        for f in set(bm.faces) - before:
            kinds[f] = ("grass", 0.9)
        before = set(bm.faces)
        add_ico(bm, top, 0.17, subdivisions=1, squash=(1, 1, 0.55))
        for f in set(bm.faces) - before:
            kinds[f] = ("petal", rnd.uniform(0.85, 1.1))

    def colour(face):
        kind, tone = kinds[face]
        return scale(grass if kind == "grass" else petal, tone)

    return finish(name, bm, colour)


def fallen_log(name, seed, length, radius):
    rnd = random.Random(seed)
    bm = bmesh.new()
    points = [Vector((x, 0, radius * 0.92 + math.sin(x * 0.4) * 0.08)) for x in [-length / 2 + length * i / 6 for i in range(7)]]
    ends = set(add_tube(bm, points, [radius * (1 - 0.06 * i) for i in range(7)], sides=14))
    for _ in range(2):
        at = points[rnd.randint(1, 5)]
        add_tube(bm, [at, at + Vector((rnd.uniform(-0.5, 0.5), rnd.choice((-1, 1)) * radius * 1.6, radius * 0.6))], [radius * 0.28, radius * 0.18], sides=6)
    bm.normal_update()
    bark, wood = srgb(86, 62, 44), srgb(196, 160, 112)

    def colour(face):
        if face in ends:
            return wood
        c = face_centre(face)
        base = scale(bark, 0.8 + 0.3 * rnd.random())
        moss = smoothstep(0.4, 0.85, face.normal.z) * smoothstep(-0.1, 0.3, fbm(c * 0.5, 2))
        return mix(base, MOSS, moss * 0.8)

    return finish(name, bm, colour, lambda f: f not in ends)


def stump(name, seed, radius):
    rnd = random.Random(seed)
    bm = bmesh.new()
    _, top = add_tube(bm, [Vector((0, 0, 0)), Vector((0, 0, radius * 0.9)), Vector((0, 0, radius * 1.6))], [radius * 1.25, radius, radius * 0.95], sides=12)
    for k in range(4):
        angle = k * math.pi / 2 + rnd.uniform(-0.3, 0.3)
        out = Vector((math.cos(angle), math.sin(angle), 0))
        add_tube(bm, [out * radius * 0.6 + Vector((0, 0, radius * 0.5)), out * radius * 1.9 + Vector((0, 0, 0.05))], [radius * 0.32, radius * 0.12], sides=6)
    bm.normal_update()
    bark, wood = srgb(80, 58, 40), srgb(204, 168, 118)

    def colour(face):
        if face is top:
            return wood
        return scale(bark, 0.8 + 0.3 * rnd.random())

    return finish(name, bm, colour, lambda f: f is not top)


# The pack --------------------------------------------------------------------------
def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    report = []

    def add(result, spot):
        obj, triangles = result
        obj.location = spot
        report.append((obj.name, triangles, tuple(round(d, 1) for d in obj.dimensions)))
        return obj

    # Backdrop mountains, 300-420 studs across.
    add(mountain("Mountain_A", 3.1, 420, 300, [(-60, 10, 230, 190), (90, -20, 170, 150)]), (0, 0, 0))
    add(mountain("Mountain_B", 7.7, 380, 280, [(20, 0, 260, 200)]), (500, 0, 0))
    add(mountain("Mountain_C", 12.4, 400, 260, [(-100, 0, 150, 150), (40, 20, 200, 170), (150, -10, 140, 120)]), (1000, 0, 0))
    add(mountain("Mountain_D", 21.9, 340, 260, [(0, 0, 190, 180)]), (1500, 0, 0))
    spots = iter((x * 40 - 260, -320 - (i // 14) * 40, 0) for i, x in enumerate(list(range(14)) * 3))
    add(conifer("Pine_A", 1, 26), next(spots))
    add(conifer("Pine_B", 2, 32, tiers=10, segments=16), next(spots))
    add(conifer("Pine_C", 3, 20, tiers=8, segments=14), next(spots))
    add(conifer("Pine_Snow_A", 4, 28, tiers=9, segments=15, snow=1.0), next(spots))
    add(conifer("Pine_Snow_B", 5, 22, tiers=8, segments=14, snow=1.0), next(spots))
    add(broadleaf("Birch_A", 11, 17, birch=True), next(spots))
    add(broadleaf("Birch_B", 12, 20, birch=True), next(spots))
    add(broadleaf("Oak_A", 13, 19, birch=False), next(spots))
    add(rock("Rock_A", 21, (7, 5.5, 4.5)), next(spots))
    add(rock("Rock_B", 22, (4, 3.5, 3.2), mossy=0.8), next(spots))
    add(rock("Rock_C", 23, (12, 9, 6.5), mossy=0.35, cuts=9), next(spots))
    add(rock("Rock_D", 24, (2.4, 2, 1.6), mossy=0.6, cuts=5), next(spots))
    add(cliff("Cliff_A", 31, 34, 18, 22), next(spots))
    add(cliff("Cliff_B", 32, 26, 16, 15), next(spots))
    add(bush("Bush_A", 41, 4.0), next(spots))
    add(bush("Bush_B", 42, 3.0), next(spots))
    add(flowers("Flowers_Yellow", 51, srgb(250, 214, 70)), next(spots))
    add(flowers("Flowers_Purple", 52, srgb(170, 110, 220)), next(spots))
    add(flowers("Flowers_White", 53, srgb(248, 246, 236)), next(spots))
    add(fallen_log("Log_A", 61, 11, 0.9), next(spots))
    add(stump("Stump_A", 62, 1.0), next(spots))
    return report


def export(path):
    """FBX with sRGB vertex colours, Y up, using Roblox's documented Blender
    settings. The game sizes every asset itself, so import scale is harmless."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=False,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        colors_type="SRGB",
        path_mode="COPY",
        embed_textures=True,
        add_leaf_bones=False,
        bake_anim=False,
    )


def manifest(report, path):
    """Authored sizes, for the game's scale calibration and the tests."""
    import json
    sizes = {name: {"triangles": triangles, "size": dims} for name, triangles, dims in report}
    path.write_text(json.dumps(sizes, indent=1) + "\n", encoding="utf-8")


# The pack as game data --------------------------------------------------------------
POSITION_BITS = 12  # positions snap to 1/4095 of the mesh's longest side


def to_srgb_byte(v):
    v = clamp(v)
    return round(255 * (v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055))


def pack_mesh(mesh):
    """One mesh as bytes the game unpacks with src/shared/MeshPack.luau:

        u16 vertices, u16 triangles, u16 colours, u8 flags (1: colour per vertex,
        else per triangle), f32 step, u16 x3 extent (in steps, Roblox axes)
        vertex positions   3 zigzag varints each, delta from the previous vertex
        triangle corners   3 zigzag varints each, delta from the previous corner
        palette            3 bytes (sRGB) per colour
        colour indices     one varint per vertex or per triangle
        smooth flags       one bit per triangle

    Roblox is Y up: Blender (x, y, z) becomes (x, z, -y), a rotation, so the
    counter-clockwise front faces stay the same. Positions are centred on the
    bounding box, which is where a MeshPart puts its origin."""
    import struct
    points = [(v.co.x, v.co.z, -v.co.y) for v in mesh.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    step = struct.unpack("<f", struct.pack("<f", max(high[i] - low[i] for i in range(3)) / (2 ** POSITION_BITS - 1)))[0]
    snapped = [tuple(round((p[i] - low[i]) / step) for i in range(3)) for p in points]
    extent = [max(s[i] for s in snapped) for i in range(3)]

    out = bytearray()

    def varint(n):
        n = n * 2 if n >= 0 else -n * 2 - 1
        while n >= 0x80:
            out.append((n & 0x7F) | 0x80)
            n >>= 7
        out.append(n)

    corners = []
    for poly in mesh.polygons:
        if len(poly.vertices) != 3:
            raise SystemExit(f"{mesh.name} has a face with {len(poly.vertices)} corners")
        layer = mesh.color_attributes["Color"].data
        corners.append([tuple(to_srgb_byte(c) for c in layer[li].color[:3]) for li in poly.loop_indices])
    palette = sorted({c for tri in corners for c in tri})
    index = {c: i for i, c in enumerate(palette)}
    by_vertex = {}
    per_vertex = True
    for poly, tri in zip(mesh.polygons, corners):
        for vi, c in zip(poly.vertices, tri):
            per_vertex = per_vertex and by_vertex.setdefault(vi, c) == c
    if not per_vertex and any(len(set(tri)) > 1 for tri in corners):
        raise SystemExit(f"{mesh.name} mixes colours within a triangle and a vertex")

    out += struct.pack("<HHHBf3H", len(points), len(corners), len(palette), 1 if per_vertex else 0, step, *extent)
    previous = (0, 0, 0)
    for s in snapped:
        for i in range(3):
            varint(s[i] - previous[i])
        previous = s
    last = 0
    for poly in mesh.polygons:
        for vi in poly.vertices:
            varint(vi - last)
            last = vi
    for c in palette:
        out += bytes(c)
    if per_vertex:
        for vi in range(len(points)):
            varint(index[by_vertex.get(vi, palette[0])])
    else:
        for tri in corners:
            varint(index[tri[0]])
    smooth = bytearray((len(corners) + 7) // 8)
    for i, poly in enumerate(mesh.polygons):
        if poly.use_smooth:
            smooth[i // 8] |= 1 << (i % 8)
    out += smooth
    size = tuple(round(extent[i] * step, 3) for i in range(3))
    return bytes(out), size, len(corners)


def game_data(path):
    """Writes the pack as a Luau module, so the game can build the meshes
    itself (EditableMesh) and nothing has to be imported into Studio."""
    import base64
    import zlib
    entries = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        raw, size, triangles = pack_mesh(obj.data)
        packer = zlib.compressobj(9, zlib.DEFLATED, -15, 9)
        packed = packer.compress(raw) + packer.flush()
        text = base64.b64encode(packed).decode("ascii")
        lines = "\n".join(text[i:i + 120] for i in range(0, len(text), 120))
        entries.append(
            f"\t{obj.name} = {{ size = {{ {size[0]:g}, {size[1]:g}, {size[2]:g} }}, triangles = {triangles}, bytes = {len(raw)}, data = [[\n{lines}]] }},\n"
        )
    path.write_text(
        "--!strict\n"
        "-- Generated by art/scenery_assets.py: the Blender scenery pack as mesh data\n"
        "-- the game builds itself with EditableMesh (see src/shared/MeshPack.luau).\n"
        "-- size: authored size in studs (Y up); bytes: unpacked length; data: raw\n"
        "-- deflate in base64. Do not edit by hand: rebuild it from the script.\n"
        "return {\n" + "".join(entries) + "}\n",
        encoding="utf-8",
    )
    return sum(len(e) for e in entries)


if __name__ == "__main__":
    report = build()
    for name, triangles, dims in report:
        print(f"{name:16s} {triangles:6d} tris  {dims}")
    export(ART / "DiamondRushScenery.fbx")
    manifest(report, ART / "manifest.json")
    print("Wrote", ART / "DiamondRushScenery.fbx")
    data = ART.parent / "src/shared/ScenePackData.luau"
    print("Wrote", data, f"({game_data(data) // 1024} KB)")
    if "--no-render" not in sys.argv:
        from preview import render_game_view, render_previews
        render_previews(PREVIEWS)
        # The game's own layout, dumped by: python3 tests/scenery.py --dump
        layout = PREVIEWS / "layout.txt"
        if layout.exists():
            render_game_view(layout, PREVIEWS / "game_view.png")
