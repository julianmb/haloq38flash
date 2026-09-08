# PENDING UPSTREAM ISSUES - DRAFT, NOT FILED
#
# These texts await explicit user approval before posting.
# Do not file automatically. Targets: Nathanw1014/llama.cpp, ROCmFPX/ROCmFPX.
# Preserved here from /tmp (tmp is wiped periodically).

# ISSUE 1 → Nathanw1014/llama.cpp (branch strix-halo-vulkan)

Title: MTP decode regression on strix-halo-vulkan + qwen4exp indexer top-k (K=2048) declined by Vulkan backend

## environment
- box: Ryzen AI MAX+ 395 / Radeon 8060S, 128 GB UMA, Mesa 26.1.7 (kisak), Ubuntu 24.04
- model: Qwen3.8-Flash-Next 125B-A6B (qwen4exp), IQ4_XS-PLE 91G + Q8_0 MTP sidecar
- flags (all runs): `-dev Vulkan0 -ngl 999 -fa on -ub 2048 -ctk q8_0 -ctv q8_0 -t 4 -n 128 --temp 0 --reasoning off -st --simple-io`, MTP adds `-md <sidecar> --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75`
- full receipts: https://github.com/julianmb/haloq38flash/blob/public-clean/results/MANIFEST.md (`results/nathan-df1671-*.log`, `results/ea35c5-*.log`, `results/profile-8k-prefill.log`)

## finding 1: MTP decode regressed after ad914eb
8k mtp tg, same model/fillers/flags:

| commit | result | vs ad914eb band 33.8–34.3 (n=3) |
|---|---|---|
| ad914eb65 (baseline) | 33.8, 33.8, 34.3 | — |
| df1671a03 | 25.6, 28.9 (n=2) | −15 to −24% |
| ea35c5066 | 29.1, 29.1, 29.0 (n=3) | −14% |

the ea35c5066 triple is perfectly repeatable (your determinism fixes work),
which excludes the thermal/stale-KV excuse and leaves a clean −14% signal.
prefill on the new commits is much faster (+42% @8k, +96% @128k — the
kv-cache scan opts deliver), so this is specifically a decode/MTP-path
regression. n_max 6 still beats 5 (26.1) on the new builds; ngram stacking
adds nothing (29.0 vs 29.1).

128k mtp also fails on the new builds where ad914eb runs clean at 13.5:
df1671a03 swap-cliffed 0→1.7 GB in 60 s; ea35c5066 worse at 0→1.3→3.2 GB
(swap-guard kills, exact-PID, VmSwap sampled every 30 s).

## finding 2: Vulkan declines the qwen4exp indexer top-k (K=2048) at all depths
qwen4exp selects per layer per ubatch via `build_qsa_top_k` → `ggml_top_k`
over the full cache width. `ggml-vulkan.cpp` `supports_op` gates TOP_K on
`min_pipeline = log2(K)+1 < num_topk_pipelines (11)`. the model metadata
says `indexer.top_k = 2048` → min_pipeline = 12 ≥ 11 → declined, always
(the code comments "we could potentially support larger... not clear if
this is needed" — for qwen4exp it is needed, 48 layers × every ubatch).

evidence: a full 8k prefill profile with `GGML_VK_PERF_LOGGER=1`
(14.6 s of Vulkan work, pp 409.8 ≈ my median so representative) contains
**zero** indexer-width TOP_K executions — ~192 expected calls, only the six
tiny MoE K=256 lines (MoE routing works fine; only the indexer width is
declined). 8k breakdown is matmul-dominated (MUL_MAT 33% + MUL_MAT_ID 22%).

this independently matches CIRU's "GPU admission for long QSA top-k" fix
direction on their ROCm stack. happy to test any candidate kernel here —
same box, same model, same harness.

---

# ISSUE 2 → ROCmFPX/ROCmFPX (official/main @ 28b92f576)

Title: qwen4exp hangs at startup with -c 139264 on Vulkan (8k/64k clean)

## environment
- box: Ryzen AI MAX+ 395 / Radeon 8060S, 128 GB UMA, Mesa 26.1.7, Ubuntu 24.04
- build: official/main @ 28b92f576 (PR #21 integration), build-official, Vulkan
- model: Qwen3.8-Flash-Next IQ4_XS-PLE 91G (+ Q8_0 sidecar for mtp)
- flags: `-dev Vulkan0 -ngl 999 -fa on -ub 2048 -ctk q8_0 -ctv q8_0 -t 4 -n 128 --temp 0 --reasoning off -st --simple-io`, MTP adds sidecar + draft-mtp n6/p0.75
- receipts: https://github.com/julianmb/haloq38flash/blob/public-clean/results/MANIFEST.md (`results/blessed-*`)

## results
| ctx | result |
|---|---|
| -c 16384 (8k filler) | plain 400.8/24.2, mtp 392.8/26.3 — clean |
| -c 65536 (32k filler) | plain 389.5/20.2 — clean |
| -c 139264 (128k filler) | **startup hang 2/2, both plain and mtp** |

the 128k failure is a startup hang, not a memory cliff: zero output (not
even "loading model"), RSS 0.4–0.8 GB at kill, no output for 150 s in both
modes. the same binary runs clean minutes earlier at -c 65536 and -c 16384.
threshold sits between 64k and 139k ctx — smells like a giant upfront
allocation (FA split-k scratch? QSA inputs sized to full ctx?) stalling the
Vulkan allocator or the split estimator. the same flags/model/box run 128k
clean on llama.cpp-strix-halo-vulkan @ ad914eb (186.9/9.8 plain,
180.4/13.5 mtp), so it is tree-specific, not environmental.

side note: 8k mtp tg trails that engine by ~22% (26.3 vs 33.8, outside any
same-config spread measured) — possibly related to the integration's MTP
path, flagging in case it shares a root cause.
