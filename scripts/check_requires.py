#!/usr/bin/env python3
"""Static sanity checks with no Luau runtime: every require(script...) and Shared.X path
resolves in the Rojo tree, and every Remotes.get("Name") is a declared remote."""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOUNTS = {"src/shared": "Shared", "src/server": "Server", "src/client": "Client", "tests": "Tests"}

def inst_name(fname):
    for ext in (".server.luau", ".client.luau", ".luau"):
        if fname.endswith(ext):
            return fname[: -len(ext)]
    return fname

# Build instance tree: path tuple -> True; and map file -> instance path
nodes, file_inst = set(), {}
for mount, top in MOUNTS.items():
    base = os.path.join(ROOT, mount)
    if not os.path.isdir(base):
        continue
    for dirpath, dirs, files in os.walk(base):
        rel = os.path.relpath(dirpath, base)
        parts = [] if rel == "." else rel.split(os.sep)
        dir_inst = (top, *parts)
        nodes.add(dir_inst)
        for f in files:
            if not f.endswith(".luau"):
                continue
            n = inst_name(f)
            inst = dir_inst if n == "init" else (*dir_inst, n)
            nodes.add(inst)
            file_inst[os.path.join(dirpath, f)] = (inst, n == "init")

remotes = set(re.findall(r'^\s*"(\w+)",', open(os.path.join(ROOT, "src/shared/Remotes.luau")).read(), re.M))
errors = 0
for path, (inst, is_init) in file_inst.items():
    src = open(path).read()
    for m in re.finditer(r"require\((script(?:\.\w+)+)\)", src):
        chain = m.group(1).split(".")[1:]
        cur = list(inst)
        for c in chain:
            if c == "Parent":
                cur.pop()
            else:
                cur.append(c)
        if tuple(cur) not in nodes:
            print(f"{os.path.relpath(path, ROOT)}: unresolved {m.group(1)} -> {'/'.join(cur)}"); errors += 1
    for m in re.finditer(r"require\(Shared((?:\.\w+)+)\)|require\(ReplicatedStorage(?::WaitForChild\(\"Shared\"\)|\.Shared)((?:\.\w+)+)\)", src):
        chain = (m.group(1) or m.group(2)).split(".")[1:]
        if ("Shared", *chain) not in nodes:
            print(f"{os.path.relpath(path, ROOT)}: unresolved Shared.{'.'.join(chain)}"); errors += 1
    for m in re.finditer(r'Remotes\.get\("(\w+)"\)', src):
        if m.group(1) not in remotes:
            print(f"{os.path.relpath(path, ROOT)}: unknown remote {m.group(1)}"); errors += 1
print("OK" if errors == 0 else f"{errors} problem(s)")
sys.exit(1 if errors else 0)
