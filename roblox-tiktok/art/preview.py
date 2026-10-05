"""Preview renders of the scenery pack (Cycles, CPU), for checking the look
without opening Roblox Studio. Called by scenery_assets.py after building."""
import math
import random
from pathlib import Path

import bpy  # noqa: F401  (must load before mathutils)
from mathutils import Vector


def _sky(strength=0.12, sun_elevation=34, sun_rotation=215):
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    nodes = world.node_tree.nodes
    nodes.clear()
    sky = nodes.new("ShaderNodeTexSky")
    # Blender 5 calls the physical sky MULTIPLE_SCATTERING; Blender 4 called it NISHITA.
    kinds = [item.identifier for item in sky.bl_rna.properties["sky_type"].enum_items]
    sky.sky_type = "MULTIPLE_SCATTERING" if "MULTIPLE_SCATTERING" in kinds else "NISHITA"
    sky.sun_elevation = math.radians(sun_elevation)
    sky.sun_rotation = math.radians(sun_rotation)
    sky.altitude = 900
    sky.sun_disc = False
    background = nodes.new("ShaderNodeBackground")
    background.inputs["Strength"].default_value = strength
    out = nodes.new("ShaderNodeOutputWorld")
    world.node_tree.links.new(sky.outputs["Color"], background.inputs["Color"])
    world.node_tree.links.new(background.outputs["Background"], out.inputs["Surface"])
    bpy.context.scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.5
    sun.data.angle = math.radians(1.5)
    sun.data.color = (1.0, 0.94, 0.86)
    sun.rotation_euler = (math.radians(90 - sun_elevation), 0, math.radians(sun_rotation + 90))
    bpy.context.scene.collection.objects.link(sun)


def _ground(size, colour, z=0.0, name="Ground"):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    plane = bpy.context.active_object
    plane.name = name
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    bsdf.inputs["Roughness"].default_value = 0.95
    plane.data.materials.append(mat)
    return plane


def _camera(location, target, lens=30):
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = lens
    cam.data.clip_end = 5000
    cam.location = location
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def _render(path, width=1280, height=720, samples=48):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def _place(name, location, yaw=0.0, scale=1.0):
    source = bpy.data.objects[name]
    copy = source.copy()
    copy.location = location
    copy.rotation_euler = (0, 0, yaw)
    copy.scale = (scale, scale, scale)
    copy.hide_render = False
    bpy.context.scene.collection.objects.link(copy)
    return copy


def render_previews(folder):
    folder.mkdir(exist_ok=True)
    scene = bpy.context.scene
    originals = [o for o in scene.objects if o.type == "MESH"]
    for obj in originals:
        obj.hide_render = True

    # 1. A line-up of the props and trees.
    _sky()
    _ground(600, (0.16, 0.24, 0.09))
    row = ["Pine_A", "Pine_B", "Pine_Snow_A", "Birch_A", "Oak_A", "Bush_A", "Rock_C", "Rock_A", "Cliff_B", "Log_A", "Stump_A", "Flowers_Yellow", "Flowers_Purple"]
    x = -70
    placed = []
    for name in row:
        width = bpy.data.objects[name].dimensions.x
        x += width / 2 + 2
        placed.append(_place(name, (x, 0, 0)))
        x += width / 2 + 2
    middle = (x - 70) / 2
    _camera((middle, -(x + 70) * 0.68, 11), (middle, 0, 9), lens=30)
    _render(folder / "assets.png", width=1600, height=560)
    for obj in placed:
        bpy.data.objects.remove(obj)

    # 2. The valley as seen from the camp: mountain ring, forest, meadow, rocks.
    rnd = random.Random(5)
    for i, name in enumerate(["Mountain_A", "Mountain_B", "Mountain_C", "Mountain_D", "Mountain_B", "Mountain_A", "Mountain_C"]):
        angle = math.radians(-60 + i * 22 + rnd.uniform(-5, 5))
        distance = rnd.uniform(380, 460)
        _place(name, (math.sin(angle) * distance, math.cos(angle) * distance, -8), yaw=-angle + rnd.uniform(-0.3, 0.3))
    # A stand-in for the rock mountain the players dig.
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=26, depth=22, location=(0, 60, 11))
    stand_in = bpy.context.active_object
    mat = bpy.data.materials.new("Dig")
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.2, 0.19, 0.17, 1)
    stand_in.data.materials.append(mat)
    for i in range(110):
        angle = rnd.uniform(-1.4, 1.4)
        distance = rnd.uniform(110, 330)
        name = rnd.choice(["Pine_A", "Pine_B", "Pine_C", "Pine_A", "Pine_Snow_A" if distance > 240 else "Pine_C"])
        _place(name, (math.sin(angle) * distance, 60 + math.cos(angle) * distance, 0), rnd.uniform(0, 6.3), rnd.uniform(0.8, 1.25))
    for i in range(10):
        _place(rnd.choice(["Birch_A", "Birch_B", "Oak_A"]), (rnd.uniform(-90, 90), rnd.uniform(-10, 40), 0), rnd.uniform(0, 6.3), rnd.uniform(0.85, 1.1))
    for i in range(16):
        _place(rnd.choice(["Rock_A", "Rock_B", "Rock_C", "Bush_A", "Bush_B"]), (rnd.uniform(-80, 80), rnd.uniform(-20, 50), -0.6), rnd.uniform(0, 6.3), rnd.uniform(0.8, 1.3))
    for i in range(60):
        _place(rnd.choice(["Flowers_Yellow", "Flowers_Purple", "Flowers_White"]), (rnd.uniform(-40, 40), rnd.uniform(-30, 25), 0), rnd.uniform(0, 6.3), rnd.uniform(0.9, 1.4))
    _place("Cliff_A", (-70, 140, -2), 0.6)
    _place("Log_A", (14, -18, 0), 1.1)
    _camera((0, -60, 6), (0, 200, 40), lens=24)
    _render(folder / "valley.png", samples=40)
    for obj in originals:
        obj.hide_render = False


# The game's own layout -------------------------------------------------------------
TERRAIN_COLOURS = {
    "Material.Grass": (102, 126, 64), "Material.LeafyGrass": (86, 110, 56), "Material.Ground": (112, 94, 70),
    "Material.Mud": (84, 72, 58), "Material.Rock": (116, 116, 112), "Material.Snow": (238, 242, 247),
    "Material.Water": (46, 92, 96),
}
def _linear(rgb):
    return tuple(((v / 255 + 0.055) / 1.055) ** 2.4 if v / 255 > 0.04045 else v / 255 / 12.92 for v in rgb)


def _haze_materials(colour=(0.58, 0.68, 0.8), near=120.0, far=1100.0, amount=0.62):
    """Fakes Roblox's atmosphere: far surfaces fade into a bright blue haze."""
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        tree = mat.node_tree
        bsdf = tree.nodes.get("Principled BSDF")
        out = tree.nodes.get("Material Output")
        if bsdf is None or out is None or tree.nodes.get("Haze"):
            continue
        camera = tree.nodes.new("ShaderNodeCameraData")
        ramp = tree.nodes.new("ShaderNodeMapRange")
        ramp.inputs["From Min"].default_value = near
        ramp.inputs["From Max"].default_value = far
        ramp.inputs["To Max"].default_value = amount
        emission = tree.nodes.new("ShaderNodeEmission")
        emission.name = "Haze"
        emission.inputs["Color"].default_value = (*colour, 1)
        mixer = tree.nodes.new("ShaderNodeMixShader")
        tree.links.new(camera.outputs["View Distance"], ramp.inputs["Value"])
        tree.links.new(ramp.outputs["Result"], mixer.inputs["Fac"])
        tree.links.new(bsdf.outputs["BSDF"], mixer.inputs[1])
        tree.links.new(emission.outputs["Emission"], mixer.inputs[2])
        tree.links.new(mixer.outputs["Shader"], out.inputs["Surface"])


def _vertex_mesh(name, verts, faces, colours):
    import bmesh
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in verts]
    colour_of = {v: colours[i] for i, v in enumerate(vs)}
    layer = bm.loops.layers.float_color.new("Color")
    for face in faces:
        f = bm.faces.new([vs[i] for i in face])
        f.smooth = True
        for loop in f.loops:
            loop[layer] = (*colour_of[loop.vert], 1)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.color_attributes.active_color = mesh.color_attributes["Color"]
    mesh.materials.append(bpy.data.materials["VertexColour"])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render_game_view(layout_path, out_path):
    """Rebuilds the valley exactly as the game lays it out (from the scenery
    test's dump) and renders it from the camp's spawn point."""
    from mathutils import Matrix
    scene = bpy.context.scene
    for obj in list(scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj)
    templates = {o.name: o for o in scene.objects if o.type == "MESH"}
    for obj in templates.values():
        obj.hide_render = True
    convert = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    columns = {}
    meshes = []
    for line in Path(layout_path).read_text().splitlines():
        parts = line.split()
        if parts[0] == "GROUND":
            x, z = (float(v) for v in parts[1].split(","))
            columns[(x, z)] = (float(parts[2]), parts[3])
        elif parts[0] == "MESH":
            meshes.append((parts[1], [float(v) for v in parts[2:]]))
    # Terrain as one smooth vertex-coloured grid on the 4-stud columns.
    xs = sorted({k[0] for k in columns})
    zs = sorted({k[1] for k in columns})
    index, verts, colours = {}, [], []
    rnd = random.Random(3)
    for x in xs:
        for z in zs:
            height, material = columns.get((x, z), (0.0, "Material.Grass"))
            if material == "Material.Water":
                height = -1.0
            index[(x, z)] = len(verts)
            verts.append((x, -z, height))
            tint = 0.92 + 0.12 * rnd.random()
            colours.append(tuple(c * tint for c in _linear(TERRAIN_COLOURS.get(material, (102, 126, 64)))))
    faces = []
    for i in range(len(xs) - 1):
        for j in range(len(zs) - 1):
            faces.append((index[(xs[i], zs[j])], index[(xs[i + 1], zs[j])], index[(xs[i + 1], zs[j + 1])], index[(xs[i], zs[j + 1])]))
    _vertex_mesh("Terrain", verts, faces, colours)
    _ground(4000, _linear((102, 126, 64)), z=-0.5, name="Plains")
    # Every placed pack mesh, with the game's position, rotation and size.
    for name, values in meshes:
        template = templates[name]
        position = Vector(values[0:3])
        rotation = Matrix((values[3:6], values[6:9], values[9:12]))
        size_x = values[12]
        scale = size_x / template.dimensions.x
        centre = sum((Vector(c) for c in template.bound_box), Vector()) / 8
        world = Matrix.Translation(convert @ position) @ (convert @ rotation @ convert.inverted()).to_4x4() \
            @ Matrix.Scale(scale, 4) @ Matrix.Translation(-centre)
        copy = template.copy()
        copy.matrix_world = world
        copy.hide_render = False
        scene.collection.objects.link(copy)
    # Stand-ins for the game's own pieces: the rock mountain and the two boards.
    cone_verts, cone_colours, cone_faces = [], [], []
    rings, segments = 12, 48
    for r in range(rings + 1):
        t = r / rings
        for k in range(segments):
            a = 2 * math.pi * k / segments
            radius = 26.4 * (1 - t) ** 1.05 + 0.3
            wobble = 1 + 0.06 * math.sin(a * 5 + t * 7)
            cone_verts.append((math.cos(a) * radius * wobble, math.sin(a) * radius * wobble, 22 * t))
            colour = (96, 124, 60) if t < 0.18 else (238, 242, 246) if t > 0.66 else (126, 120, 112)
            cone_colours.append(_linear(colour))
    for r in range(rings):
        for k in range(segments):
            a, b = r * segments + k, r * segments + (k + 1) % segments
            cone_faces.append((a, b, b + segments, a + segments))
    _vertex_mesh("DigMountain", cone_verts, cone_faces, cone_colours)
    for side, trim in ((-1, (36, 92, 204)), (1, (196, 36, 44))):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(side * 30.6, 81, 30))
        board = bpy.context.active_object
        board.scale = (36, 1.2, 28)
        board.rotation_euler = (0, 0, -side * 0.2)
        mat = bpy.data.materials.new(f"Board{side}")
        mat.use_nodes = True
        mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (*_linear(trim), 1)
        board.data.materials.append(mat)
    _sky(sun_elevation=36, sun_rotation=200)
    _haze_materials()
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(70)
    cam.data.clip_end = 6000
    cam.location = (0, -56.4, 5.5)
    cam.rotation_euler = (Vector((0, 0, 16)) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    _render(out_path, samples=48)
