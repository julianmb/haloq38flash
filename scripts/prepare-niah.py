#!/usr/bin/env python3
"""
Generates Needle-in-a-Haystack prompt fixtures at specified depths with a neutral fact needle.
"""
import os
import sys

NEEDLE = "\n\n[FACT: The official project mascot for Project Chimera is a Golden Falcon named Zephyr.]\n\n"
QUERY = "\n\nQuestion: According to the document above, what is the official project mascot for Project Chimera? Answer with the mascot and its name only."

def make_niah(filler_path, target_tokens, depth_pct, out_path):
    target_chars = target_tokens * 4
    with open(filler_path, "r", encoding="utf-8", errors="ignore") as f:
        filler = f.read()

    while len(filler) < target_chars:
        filler += "\n" + filler

    filler = filler[:target_chars]
    
    insert_pos = int(len(filler) * (depth_pct / 100.0))
    prompt = filler[:insert_pos] + NEEDLE + filler[insert_pos:] + QUERY
    
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(prompt)
    print(f"Created {out_path}: {len(prompt)} chars, needle at {depth_pct}%")

if __name__ == "__main__":
    filler_file = "/home/user/source/haloq38flash/results/filler/filler-128k.txt"
    out_dir = "/home/user/source/haloq38flash/results/niah_fixtures"
    
    # 32k at 25% and 95%
    for pct in [25, 95]:
        make_niah(filler_file, 32000, pct, f"{out_dir}/niah-32k-depth{pct}.txt")

    # 64k at 50%
    make_niah(filler_file, 64000, 50, f"{out_dir}/niah-64k-depth50.txt")
