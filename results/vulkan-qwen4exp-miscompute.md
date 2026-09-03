# blessed-Vulkan qwen4exp miscompute (2026-09-03)

status: **confirmed, isolated to the Vulkan backend**. the port and the
model code are exonerated.

## evidence (same prompt, same model, temp 0, seed 0)

prompt (48 tokens, chat-formatted fibonacci instruction with empty think
block) → `Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf` (91G):

| engine | backend | result |
|--------|---------|--------|
| build-hq38 (old master) | Nathan Vulkan | clean `def fibonacci` + docstring, 269 tokens |
| ROCmFPX-official 22496778e + port | CPU (`-ngl 0`) | clean `def fibonacci` + docstring, 400 tokens @ 13.3 t/s |
| ROCmFPX-official 22496778e + port | Vulkan | rambling garbage (`def get_nm`, arithmetic nonsense, CJK stutter) |
| ROCmFPX-official 22496778e pristine (port stashed) | Vulkan | byte-comparable garbage (port exonerated) |

same 48 prompt tokens in all runs → not tokenization, not template, not
sampling (`--reasoning off` changes nothing). first-token divergence ⇒
structural logit difference, not FP rounding.

## suspect

new `MUL_MAT_ID f16-B` Vulkan path (logged as engaged on every blessed run).
old Nathan Vulkan kernels + CPU both compute correctly. likely a wrong-result
bug for qwen4exp shapes (fused GDN / HC mixer / indexer matmuls), not a
precision issue.

## impact on this repo

- all published vulkan numbers stay on the daily-driver engine (`ad914eb`)
  — verified clean. the blessed build is CPU-only until the kernel bug is
  found.
- the strict 0-diff proof below was run on CPU for exactly this reason.
- short filler continuations on blessed-Vulkan can *look* sane (16 tokens);
  do not trust short outputs — the corruption shows at instruction scale.

## strict 0-diff proof (CPU, coherent output)

- plain: 400 tokens @ 13.3 t/s, coherent (`def fibonacci` + docstring)
- strict (`--spec-mtp-strict-qwen`, original blk.48 sidecar, strict banner
  active, draft model loaded): 400 tokens @ 12.9 tok/s, coherent
- `diff oracle-cpu-plain.txt oracle-cpu-strict.txt` → **0 lines**,
  both 1473 bytes.
- receipts: `oracle-cpu-plain.json/.txt`, `oracle-cpu-strict.json/.txt`,
  `oracle-cpu-strict-server.log`, `oracle-cpu-diff.log` (empty).
- note: strict uses serial target verification (no acceleration expected;
  exactness is the claim, and it holds).
