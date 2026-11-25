#!/usr/bin/env python3
"""Build FragileFreight.rbxlx from src/ without Rojo (mirrors default.project.json).

Usage: python3 scripts/build_rbxlx.py [output.rbxlx]
Rojo is still the recommended workflow; this is for opening the game in Studio quickly.
"""
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ref_counter = 0


def ref():
    global ref_counter
    ref_counter += 1
    return f"RBX{ref_counter:08X}"


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, children="", source=None):
    props = f'<string name="Name">{escape(name)}</string>'
    if source is not None:
        props += f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
    return f'<Item class="{cls}" referent="{ref()}"><Properties>{props}</Properties>{children}</Item>'


def script_class(filename, local):
    if filename.endswith(".server.luau"):
        return "Script"
    if filename.endswith(".client.luau"):
        return "LocalScript"
    return "ModuleScript"


def strip_ext(filename):
    for ext in (".server.luau", ".client.luau", ".luau"):
        if filename.endswith(ext):
            return filename[: -len(ext)]
    return filename


def build_dir(path, name, local=False):
    """A folder becomes a Folder, or the script in its init.*.luau with the rest as children."""
    entries = sorted(os.listdir(path))
    init = next((e for e in entries if strip_ext(e) == "init" and e.endswith(".luau")), None)
    children = ""
    for e in entries:
        full = os.path.join(path, e)
        if e == init:
            continue
        if os.path.isdir(full):
            children += build_dir(full, e, local)
        elif e.endswith(".luau"):
            with open(full, encoding="utf-8") as f:
                children += item(script_class(e, local), strip_ext(e), source=f.read())
    if init:
        with open(os.path.join(path, init), encoding="utf-8") as f:
            return item(script_class(init, local), name, children, source=f.read())
    return item("Folder", name, children)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "FragileFreight.rbxlx")
    src = os.path.join(ROOT, "src")
    body = (
        item("Workspace", "Workspace")
        + item("ReplicatedStorage", "ReplicatedStorage", build_dir(os.path.join(src, "shared"), "Shared"))
        + item("ServerScriptService", "ServerScriptService", build_dir(os.path.join(src, "server"), "Server"))
        + item(
            "StarterPlayer",
            "StarterPlayer",
            item("StarterPlayerScripts", "StarterPlayerScripts", build_dir(os.path.join(src, "client"), "Client", True)),
        )
    )
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        + body
        + "</roblox>\n"
    )
    with open(out, "w", encoding="utf-8") as f:
        f.write(xml)
    print("wrote", out)


if __name__ == "__main__":
    main()
