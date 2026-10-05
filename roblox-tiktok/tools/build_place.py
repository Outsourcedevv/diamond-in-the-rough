"""Builds DiamondRushTikTok.rbxlx from default.project.json and src/.

Equivalent to `rojo build -o DiamondRushTikTok.rbxlx` for this project, without
needing Rojo installed. Run from anywhere:  python3 tools/build_place.py
Pass --check to fail (exit 1) when the committed place file is out of date.
"""
import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
PLACE = ROOT / "DiamondRushTikTok.rbxlx"

# Property types for the handful of non-string properties the project sets.
# Some properties are saved under a different name than the scripting API uses.
ENUMS = {
    "Technology": {"Voxel": 1, "ShadowMap": 3, "Future": 4},
    "LightingStyle": {"Realistic": 0, "Soft": 1},
}
SERIALIZED_AS = {("MaterialService", "Use2022Materials"): "Use2022MaterialsXml"}
FLOATS = {"GrassLength"}


def prop_xml(class_name, name, value):
    name = SERIALIZED_AS.get((class_name, name), name)
    if isinstance(value, bool):
        return f'<bool name="{name}">{"true" if value else "false"}</bool>'
    if name in ENUMS:
        return f'<token name="{name}">{ENUMS[name][value]}</token>'
    if name in FLOATS or isinstance(value, float):
        return f'<float name="{name}">{value}</float>'
    if isinstance(value, int):
        return f'<int name="{name}">{value}</int>'
    return f'<string name="{name}">{escape(value)}</string>'


def script_node(path: Path, name: str):
    stem = path.name[: -len(".luau")]
    if stem.endswith(".server"):
        class_name, props = "Script", [("RunContext", None)]
    elif stem.endswith(".client"):
        class_name, props = "LocalScript", []
    else:
        class_name, props = "ModuleScript", []
    source = path.read_text(encoding="utf-8")
    if "]]>" in source:
        raise SystemExit(f"{path} contains ']]>', which cannot be stored in CDATA")
    return {"class": class_name, "name": name, "props": props, "source": source, "children": []}


def dir_node(path: Path, name: str):
    init = [p for p in path.iterdir() if p.name in ("init.luau", "init.server.luau", "init.client.luau")]
    node = script_node(init[0], name) if init else {"class": "Folder", "name": name, "props": [], "children": []}
    for child in sorted(path.iterdir(), key=lambda p: p.name):
        if child in init:
            continue
        if child.is_dir():
            node["children"].append(dir_node(child, child.name))
        elif child.name.endswith(".luau"):
            base = child.name[: -len(".luau")]
            for suffix in (".server", ".client"):
                if base.endswith(suffix):
                    base = base[: -len(suffix)]
            node["children"].append(script_node(child, base))
    node["children"].sort(key=lambda n: n["name"])
    return node


def tree_node(name, spec):
    if "$path" in spec:
        node = dir_node(ROOT / spec["$path"], name)
    else:
        node = {"class": spec.get("$className", name), "name": name, "props": [], "children": []}
    for key, value in spec.get("$properties", {}).items():
        node["props"].append((key, value))
    for key in sorted(k for k in spec if not k.startswith("$")):
        node["children"].append(tree_node(key, spec[key]))
    return node


def render(node, depth, counter, out):
    pad = "  " * depth
    out.append(f'{pad}<Item class="{node["class"]}" referent="{counter[0]}">')
    counter[0] += 1
    out.append(f"{pad}  <Properties>")
    out.append(f'{pad}    <string name="Name">{escape(node["name"])}</string>')
    if node["class"] == "Workspace":
        out.append(f'{pad}    <bool name="NeedsPivotMigration">false</bool>')
    for key, value in node["props"]:
        if key == "RunContext":
            out.append(f'{pad}    <token name="RunContext">0</token>')
        else:
            out.append(f"{pad}    {prop_xml(node['class'], key, value)}")
    if "source" in node:
        out.append(f'{pad}    <string name="Source"><![CDATA[{node["source"]}]]></string>')
    out.append(f"{pad}  </Properties>")
    for child in node["children"]:
        render(child, depth + 1, counter, out)
    out.append(f"{pad}</Item>")


def build() -> str:
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    out = ['<roblox version="4">']
    counter = [0]
    for key in sorted(k for k in tree if not k.startswith("$")):
        render(tree_node(key, tree[key]), 1, counter, out)
    out.append("</roblox>")
    return "\n".join(out)


def sourcemap() -> dict:
    """A Rojo-style sourcemap, for luau-lsp type checking."""
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))

    def convert(node, spec_path=None):
        out = {"name": node["name"], "className": node["class"], "children": [convert(c) for c in node["children"]]}
        if "path" in node:
            out["filePaths"] = [node["path"]]
        return out

    def with_paths(node, path: Path):
        # Attach source paths so the checker can map modules to files.
        if path.is_dir():
            init = [p for p in path.iterdir() if p.name in ("init.luau", "init.server.luau", "init.client.luau")]
            if init:
                node["path"] = str(init[0].relative_to(ROOT))
            for child in node["children"]:
                for candidate in path.iterdir():
                    base = candidate.name.split(".")[0]
                    if base == child["name"] and candidate not in init:
                        with_paths(child, candidate)
        else:
            node["path"] = str(path.relative_to(ROOT))

    def walk(name, spec):
        if "$path" in spec:
            node = dir_node(ROOT / spec["$path"], name)
            with_paths(node, ROOT / spec["$path"])
            return node
        children = [walk(k, spec[k]) for k in sorted(k for k in spec if not k.startswith("$"))]
        return {"class": spec.get("$className", name), "name": name, "children": children}

    tree = project["tree"]
    root = {"name": project["name"], "class": "DataModel", "children": [walk(k, tree[k]) for k in sorted(k for k in tree if not k.startswith("$"))]}
    return convert(root)


if __name__ == "__main__":
    if "--sourcemap" in sys.argv:
        (ROOT / "sourcemap.json").write_text(json.dumps(sourcemap(), indent=1), encoding="utf-8")
        print("Wrote sourcemap.json")
        sys.exit(0)
    text = build()
    if "--check" in sys.argv:
        if PLACE.read_text(encoding="utf-8") != text:
            print("DiamondRushTikTok.rbxlx is out of date: run python3 tools/build_place.py")
            sys.exit(1)
        print("DiamondRushTikTok.rbxlx is up to date")
    else:
        PLACE.write_text(text, encoding="utf-8", newline="\n")
        print(f"Wrote {PLACE.name} ({len(text):,} bytes)")
