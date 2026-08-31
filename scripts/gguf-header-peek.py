#!/usr/bin/env python3
"""Inspect a remote GGUF's metadata + tensor names without downloading the weights.

The interesting part of a GGUF (architecture, block_count, nextn_predict_layers,
tensor names) all lives in the header, which is a few MB even for a 100 GB file.
This range-fetches the first chunk and parses the header directly.

usage:
  scripts/gguf-header-peek.py <hf-repo-id> [filename-substring]
  scripts/gguf-header-peek.py /path/to/local.gguf

examples:
  scripts/gguf-header-peek.py EasiiX/Qwen3.8-Flash-Next-MTP-Strix-Halo-GGUF
  scripts/gguf-header-peek.py unsloth/Qwen3.8-Flash-Next-GGUF Q3_K_XL
"""
import struct
import subprocess
import sys
import tempfile

CHUNK = 96 * 1024 * 1024  # header is dominated by the tokenizer strings

SCALAR_BYTES = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}
SCALAR_FMT = {0: "<B", 1: "<b", 2: "<H", 3: "<h", 4: "<I", 5: "<i",
              6: "<f", 7: "<B", 10: "<Q", 11: "<q", 12: "<d"}
TYPE_NAMES = {0: "u8", 1: "i8", 2: "u16", 3: "i16", 4: "u32", 5: "i32", 6: "f32",
              7: "bool", 8: "str", 9: "arr", 10: "u64", 11: "i64", 12: "f64"}


class Reader:
    def __init__(self, fh):
        self.fh = fh

    def u32(self):
        return struct.unpack("<I", self.fh.read(4))[0]

    def u64(self):
        return struct.unpack("<Q", self.fh.read(8))[0]

    def string(self):
        return self.fh.read(self.u64()).decode("utf-8", "replace")

    def value(self, vtype):
        if vtype == 8:
            return self.string()
        if vtype == 9:
            sub, count = self.u32(), self.u64()
            if count > 32:
                for _ in range(count):
                    self.value(sub)
                return f"<{count} x {TYPE_NAMES.get(sub, sub)}>"
            return [self.value(sub) for _ in range(count)]
        if vtype in SCALAR_BYTES:
            raw = self.fh.read(SCALAR_BYTES[vtype])
            if len(raw) < SCALAR_BYTES[vtype]:
                raise ValueError("truncated header: increase CHUNK")
            if vtype == 7:
                return bool(raw[0])
            return struct.unpack(SCALAR_FMT[vtype], raw)[0]
        raise ValueError(f"unknown gguf value type {vtype}")


def parse(path):
    with open(path, "rb") as fh:
        r = Reader(fh)
        assert fh.read(4) == b"GGUF", "not a GGUF file"
        version, n_tensors, n_kv = r.u32(), r.u64(), r.u64()
        kv = {r.string(): r.value(r.u32()) for _ in range(n_kv)}
        names = []
        for _ in range(n_tensors):
            names.append(r.string())
            r.fh.read(8 * r.u32())  # dims
            r.fh.read(12)           # type + offset
    return version, kv, names


def fetch(repo, want):
    listing = subprocess.run(
        ["curl", "-s", f"https://huggingface.co/api/models/{repo}"],
        capture_output=True, text=True, check=True).stdout
    import json
    files = [s["rfilename"] for s in json.loads(listing)["siblings"]
             if s["rfilename"].endswith(".gguf")]
    matches = [f for f in files if want in f] if want else files
    if not matches:
        raise SystemExit(f"no .gguf matching {want!r} in {repo}")
    name = sorted(matches)[0]
    print(f"repo: {repo}\nfile: {name}  (of {len(files)} gguf files)")
    url = f"https://huggingface.co/{repo}/resolve/main/{name}"
    tmp = tempfile.NamedTemporaryFile(suffix=".gguf", delete=False)
    subprocess.run(["curl", "-sL", "-r", f"0-{CHUNK}", "-o", tmp.name, url], check=True)
    return tmp.name


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    target = sys.argv[1]
    if target.startswith(("http", "/")) and target.endswith(".gguf"):
        path = target if target.startswith("/") else fetch(target, "")
    else:
        path = fetch(target, sys.argv[2] if len(sys.argv) > 2 else "")

    version, kv, names = parse(path)
    arch = kv.get("general.architecture", "?")
    print(f"gguf v{version}  arch={arch}  tensors={len(names)}  kv={len(kv)}")
    print("\n-- key metadata --")
    for k in sorted(kv):
        if k.startswith("tokenizer.") or k.startswith("general."):
            continue
        v = kv[k]
        if isinstance(v, list) and len(v) > 12:
            v = f"{v[:12]} ... (len {len(v)})"
        print(f"   {k:<46} {v}")

    blocks = sorted({n.split(".")[1] for n in names
                     if n.startswith("blk.") and n.split(".")[1].isdigit()})
    print(f"\n-- block indices: {blocks[:12]}{' ...' if len(blocks) > 12 else ''} "
          f"({len(blocks)} total)")
    suffixes = sorted({n.split(".", 2)[2] for n in names
                       if n.startswith("blk.") and len(n.split(".")) > 2})
    print(f"-- per-block suffixes ({len(suffixes)}):")
    for s in suffixes:
        print(f"     {s}")
    other = sorted(n for n in names if not n.startswith("blk."))
    if other:
        print("-- non-block tensors:")
        for n in other:
            print(f"     {n}")


if __name__ == "__main__":
    main()
