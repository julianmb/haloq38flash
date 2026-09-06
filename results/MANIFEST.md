# receipts manifest

every number published in this repo maps to exactly one receipt below.
`results/receipts/` holds verbatim copies of the original run logs, pinned
by sha256. all runs are n=1; same-config mtp spread measured up to ~40%
(56.4 vs 33.5 t/s at 8k across two sweeps) — peaks are peaks, not medians.

engines:
- **daily driver**: `llama.cpp-strix-halo-vulkan` @ `ad914eb` — the docker image
- **merged**: `llamacpp-master` `build-hq38` @ `081edc343` (server fingerprint `b10888-081edc343`)

## readme results table (91g ple quant)

| cell | published | receipt | engine |
|------|-----------|---------|--------|
| 0k plain | 92.5 / 29.9 | `receipts/ple-depth.log` `depth0-plain` | daily |
| 0k mtp | 87.0 / **53.1** | `receipts/ple-depth.log` `depth0-mtp` | daily |
| 8k plain | 480 / 24.1 | `receipts/ple-depth.log` `depth8k-plain` | daily |
| 8k mtp | 458 / **56.4** | `receipts/ple-depth.log` `depth8k-mtp` (badge source) | daily |
| 32k plain | 397 / 20.1 | `receipts/ple-depth.log` `depth32k-plain` | daily |
| 32k mtp | 379 / **30.2** | `receipts/ple-depth.log` `depth32k-mtp` | daily |
| 128k plain | 222 / 11.0 | `receipts/depth128.log` `PLE 91g` block | daily |
| 128k mtp | 214 / **18.6** | `receipts/depth128.log` `PLE 91g` block | daily |
| 256k plain | 139 / 6.2 | `receipts/depth256.log` `depth256k-plain` | daily |
| 256k mtp | 187.2 / **8.0** | `receipts/hq38-256k-mtp-ub512.log` line 31 | merged |

flags: daily rows = `-dev Vulkan0 -ngl 999 -fa on -ub 2048 -ctk q8_0 -ctv q8_0 --temp 0 -n 128`,
bounded contexts (8192/16384/40960/139264/257024), mtp rows add
`-md mtp-...-Q8_0.gguf --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75`.
the 256k mtp cell is the only merged-engine cell: `-ub 512 -b 512 -c 257024
--spec-draft-adaptive --spec-draft-n-min 0 --spec-draft-n-max 7
--override-tensor "per_layer_token_embd=CPU"` — the daily-driver build
swap-dies at 256k mtp (exit 137).

## merged-engine reference sweep (not in readme table)

0k 94.6/29.0 · 70.2/45.7 · 8k 496.9/21.7 · 464.8/27.6 · 32k 400.5/17.7 ·
382.5/23.5 · 128k 266.8/9.0 · 257.2/12.9 · 256k plain 202.9/6.2 —
receipts `receipts/hq38-depth*.log`, summarized in the committed
`results/2026-08-31-merged-engine-256k.md`.

## adaptive MTP sweep (merged engine, --spec-draft-adaptive) — not in readme table

same 91g ple quant, same bounded contexts/fillers as above, but
`--spec-draft-adaptive --spec-draft-n-min 0 --spec-draft-n-max 7 --spec-draft-p-min 0.75`
instead of static `n_max 6`.

| depth | adaptive pp / tg | static ref pp / tg | delta tg | receipt |
|------:|-----------------:|-------------------:|---------:|---------|
| 0k | 66.7 / 37.8 | 70.2 / 45.7 | −17% | `receipts/hq38-adaptive-depth0.log` |
| 8k | 388.8 / 22.5 | 464.8 / 27.6 | −18% | `receipts/hq38-adaptive-depth8k.log` |
| 32k | 277.0 / 21.6 | 382.5 / 23.5 | −8% | `receipts/hq38-adaptive-depth32k.log` |
| 128k | 178.7 / 11.5 | 257.2 / 12.9 | −11% | `receipts/hq38-adaptive-depth128k.log` |

finding: adaptive loses to static `n_max 6` on generic prose at every depth
on this workload. high acceptance ≠ higher throughput when `n_min 0` drafts
fewer tokens per cycle. treated as honest negative result — not shipped as
a recommendation for prose.

## n=3 variance A/B — complete (24/24 runs, n=3 per cell)

`bench-n3-ab.sh` on 91g ple, same fillers/bounded contexts as above, but
`n=3` repeats per cell to bound same-config spread.

| engine | depth | mode | tg median | tg spread | pp median |
|--------|-------|------|-----------|-----------|-----------|
| daily | 8k | plain | 24.0 | 23.9–24.1 | 413.9 |
| daily | 8k | mtp | 33.8 | 33.8–34.3 | 395.3 |
| daily | 128k | plain | 9.8 | 9.6–9.9 | 186.9 |
| daily | 128k | mtp | 13.5 | 13.3–13.7 | 180.4 |
| merged | 8k | plain | 22.0 | 22.0–22.2 | 408.5 |
| merged | 8k | mtp | 27.4 | 26.9–27.4 | 386.0 |
| merged | 128k | plain | 8.6 | 7.8–9.2 | 184.2 |
| merged | 128k | mtp | 12.7 | 12.6–12.7 | 177.8 |

finding: daily driver is consistently faster than merged on tg (e.g. 33.8
vs 27.4 at 8k mtp, 13.5 vs 12.7 at 128k mtp), but both show tight spread at
8k and wider at 128k (merged plain 7.8–9.2). receipts `results/n3-*.log`
+ `.mem.log` (24 logs, all with `Generation`).

## nathan df1671a03 rebench — mixed, do not switch yet

`llama.cpp-strix-halo-vulkan-df1671` @ `df1671a03` (kv-cache scan opts,
qwen4exp indexer fixes, vulkan tuning) vs `ad914eb` n=3 medians, same
91g ple / fillers / flags. receipts `results/nathan-df1671-*.log`.

| cell | df1671a03 pp / tg | ad914eb median | delta |
|------|-------------------|----------------|-------|
| 8k plain | 586.5 / 25.9 | 413.9 / 24.0 | pp +42%, tg +8% |
| 8k mtp | 509.1 / 25.6, 513.5 / 28.9 (n=2) | 395.3 / 33.8 | pp +29%, tg −15–24% |
| 128k plain | 367.1 / 9.9 | 186.9 / 9.8 | pp +96%, tg +1% |
| 128k mtp | killed, swap 0→1.7 GB cliff | 180.4 / 13.5 | FAIL |

findings: prefill massively faster (kv-cache scan opts deliver as
advertised); MTP decode regressed at 8k (both runs below the old tight
33.8–34.3 band — thermal confound possible after hours of sustained load,
needs interleaved A/B); 128k MTP swap cliff (0→358 MB→1.7 GB in 60 s,
guard kill) is a hard memory regression (`ad914eb` ran clean).
verdict: do not switch daily driver yet; file upstream with receipts.

## gain probes — reddit-sourced flags, all negative or blocked (2026-09-04)

probes chasing stereohype/digamma claims from the StrixHalo post. receipts
`results/probe-*`.

| probe | result | verdict |
|-------|--------|---------|
| `-b 8192` prefill (2x 8k plain) | 398.7, 410.7 pp / 23.7, 23.8 tg vs 413.9 / 24.0 ref | no gain, at/below reference |
| unsloth shared MTP sidecar (2.79G) | load fails: `token_embd.weight not found` on ad914eb | needs shared-embedding loader (myhacsint b10685 has it); only 1.1G saving vs our 3.9G, parked |
| blessed-Vulkan + `--reasoning-effort medium --reasoning-budget 2048` | reasoning_content itself is gibberish, content empty | kernel-miscompute theory stands |

the third probe kills the cheap explanation for the blessed-Vulkan garbage:
with the reasoning budget pinned to 2048 the corruption shows up inside
the model's own thinking text, so it is a Vulkan compute-path defect, not
thinking-budget dynamics. stereohype's flags remain correct practice for
serving healthy builds (they prevent empty content) but do not fix ours.

## nathan ea35c5066 validation — regression confirmed, still do not switch

`llama.cpp-strix-halo-vulkan-ea35c5` @ `ea35c5066` (stale-KV zeroing, FA
dequant layout fix, deterministic top-k) vs same references. receipts
`results/ea35c5-*.log`.

| test | ea35c5066 pp / tg | reference | verdict |
|------|-------------------|-----------|---------|
| 8k mtp n=6 (n=3) | 506–530 / **29.1, 29.1, 29.0** | 33.8–34.3 | −14%, regression stands |
| 128k mtp n=6 | killed, swap 0→1.3 GB→3.2 GB | 180.4 / 13.5 | FAIL, worse trajectory |
| 8k mtp n=5 | 528.0 / 26.1 | n=6 29.1 | n=6 stays |
| 8k mtp+ngram | 501.7 / 29.0 | n=6 29.1 | no gain from stacking |

findings: the determinism fixes work (three identical 29.1s — variance
gone), which sharpens rather than excuses the regression: −14% vs the old
band is now a clean signal, thermal confound largely excluded by
repeatability. 128k memory blowup is worse than df1671a03 (3.2 GB vs
1.7 GB). n=6 beats n=5 here (differs from Unsloth/stereohype setups —
engine-specific); ngram stacking adds nothing.
verdict: do not switch; the MTP decode + 128k memory regressions are real
and belong in the upstream issue with these receipts.

## tier1 gain session — sidecar quant / draft tuning / kv / threads (2026-09-04)

all on daily driver `ad914eb`. receipts `results/tier1-*`.

**acceptance (first measurement on ad914eb):** 25/29 = **86.2%** at 8k
(Q8_0 sidecar, n_max 6, p_min 0.75) — reproduced identically twice.
merged engine measured 92.4%; the daily driver has less draft headroom.

**sidecar quant matrix (8k mtp, n_max 6):**

| sidecar | size | tg | verdict |
|---|---|---|---|
| Q8_0 (current) | 3.9G | 33.8 | reference |
| Q4_K | 2.6G | 26.1, 32.1 | **−14%, rejected** — acceptance drop beats bandwidth saving |
| Q5_K | 2.9G | 34.2 | par (within spread) |

the bandwidth model predicted big Q4_K gains; empirically false —
acceptance sensitivity dominates. sidecar stays Q8_0.

**draft tuning on Q5_K (8k mtp):** n7 25.1, n8 28.7 — deeper drafts lose,
n=6 confirmed a third time; p_min 0.70 → 34.6, 0.80 → 32.2 (noise). the
8k cell is tuned out: every variant lands 32–35.

**q4_0 KV:** ppl **4.2912 ±0.025** — statistically identical to the
q8_0-KV PLE baseline (4.2932), zero quality cost. but 128k **mtp** with
q4_0 KV swap-killed on ad914eb (745 MB cliff <5 min) where q8_0 KV runs
clean at 13.5 — the Vulkan q4_0-KV + MTP path allocates big at depth
(mechanism uninvestigated). verdict: fine for quality-bound/non-MTP use,
not usable with MTP at depth.

**ubatch 4096 @ 128k plain:** 184.8 / 9.8 vs 186.9 / 9.8 — no gain.

**thread sweep (8k plain):** t2 333.0/24.0 · t4 395.8/23.9 · t8
462.8/23.8 · t16 503.3/23.5 — pp scales with threads (t16 +27%), tg flat.
follow-ups: 8k mtp t16 470.1/32.7 (pp +19%, tg par); 128k plain t16
**267.1/9.7 (+43% pp vs 186.9)**, tg par.
**verdict: `-t 16` is the prefill knob the daily driver was missing** —
use it for ingestion/warm-cache rebuilds; decode is indifferent. Nathan
df1671a03's prefill (+96% → 367.1) still beats it (+43% → 267.1), so the
engine switch stays blocked on his MTP regression, not on prefill.

## local artifact cleanup (2026-09-04)

M2 published to hf (julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF) and
byte-verified: sha256 `0eaaf06a8e226cb5…` = remote lfs oid. deleted
locally: F16 (329.7g — the f16-ppl ground-truth parked item retires with
it; regeneration path = official fp8 + our converter), ROCmFP4_FAST
(113.1g, parked plugin experiment), sidecar variants Q4_K/Q5_K/shared-Q8_0
(8.1g, receipts in tier1 above), M2 local copy (114.6g). ssd2: 43g free →
**609g free**. remaining local: PLE 91g, static 116g, sidecar Q8_0 3.9g,
imatrix 0.5g, mmproj 0.8g.

## ppl suite — wiki.test.raw, ctx 2048, `llama-perplexity` (vulkan, f16 kv)

| quant | PPL | file | receipt |
|-------|-----|------|---------|
| M2 (imatrix, PLE Q8_0) | 4.2809 ±0.025 | 115G | `receipts/ppl-m2.log` |
| PLE (IQ4_NL on 51B PLE) | 4.2932 ±0.025 | 91G | `receipts/ppl-ple.log` |
| static (no PLE cut) | 4.5221 ±0.026 | 116G | `receipts/ppl-static.log` |

`M2` wins, `PLE` is statistically tied (+0.012, <0.5σ) for 24 GB saved,
both crush `static` (+0.24, ~9σ). corpus `wiki.test.raw` (1.29 MB from
smerity, not the imatrix `corpus.txt`) — 145 chunks. bug `invalid
argument: 2048` fixed by removing `-ub` from `bench-ppl-quants.sh`.

## warm checkpoint bench — prompt cache reuse (official build)

`ROCmFPX/build-rocmfpx` with `--cache-ram 8192` (your `0ef57fb` fix active).

| prompt | cold prompt_ms | warm prompt_ms | speedup | cache hit | receipt |
|--------|----------------|----------------|---------|-----------|---------|
| 128k truncated (80k chars, 13,334 tokens) | 30,910 | 607 | **50.9×** | 13,330 cached, 4 reprocessed | `warm-128k-*.json` |
| 128k full (786kB filler, 131,073 tokens) | 437,943 | 683 | **640×** | 131,069 cached, 4 reprocessed | `receipts/warm-full-128k-full-*.json` |
| 256k full (1.53 MB filler, 255,718 tokens) | 994,466 | 736 | **1351×** | 255,714 cached, 4 reprocessed | `results/warm-full-256k-full-*.json` |

256k is the headline: cold 994s → warm 0.74s (first attempt died at 188k
tokens on a 300s wrapper timeout — operator error, not engine; reran with
a 2400s cap). warm cost is ~constant (~0.6–0.7s) while cold scales with
context, so the ratio grows with depth.

## r/strixhalo draft — static 116g column

| cell | published | receipt |
|------|-----------|---------|
| 128k mtp | 26.9 | `receipts/depth128.log` `static 116g` block |
| 0 / 8k / 32k mtp | 48.4 / 42.8 / 29.5 | **no receipt — pending re-baseline** |

the overnight static sweep measured 50.0 / 32.5 / 28.2 / 17.4
(`results/2026-08-31-overnight-quant-bench.md`); until the draft column is
re-baselined, treat 48.4/42.8/29.5 as unverified.

## overnight quant bench (2026-08-31)

all STATIC/PLE/M2 sweep numbers → `results/2026-08-31-overnight-quant-bench.md`
+ raw logs tarball `2026-08-31-overnight-quant-bench-logs.tar.gz`
(sha256 `aec23e327a5d9637d6e11cb8e78d081dda35dcef7dd9951b112ffb1e3a236482`).

## root-caused claims

- **"greedy-oracle validated"**: plain vs mtp n=6 diverged by 3 regions in
  ~1000 chars at temp 0 — one docstring-line omission and one reordering of
  two valid statements. root cause: batch-shape fp rounding flips the
  target's own argmax at near-tie branches (drafts are target-verified;
  divergence is never unverified draft text). 92.4% acceptance (219/237),
  semantically equivalent output. full analysis:
  `results/oracle-diff-analysis.md`.
- **strict-mtp bit-exact (NEW, valid proof)**: `--spec-mtp-strict-qwen` on
  the ported blessed build, CPU backend, coherent fibonacci prompt, temp 0,
  seed 0 — plain 400 tokens @ 13.3 t/s vs strict 400 tokens @ 12.9 t/s,
  `diff` **0 lines** (both 1473 bytes). receipts `oracle-cpu-*.json/.txt`,
  `oracle-cpu-strict-server.log`, `oracle-cpu-diff.log` (empty). strict uses
  serial target verification (exactness, not speed).
- **blessed-Vulkan qwen4exp miscompute (NEW)**: same prompt/model gives
  clean code on CPU and old-Nathan-Vulkan but rambling garbage on
  blessed-Vulkan (suspect: f16-B MMID path). port and model code
  exonerated (pristine build behaves identically). all published vulkan
  numbers stay on `ad914eb`. full analysis:
  `results/vulkan-qwen4exp-miscompute.md`.

## ROCmFPX upstream integration @ 28b92f576 — Vulkan miscompute FIXED, strict-MTP on GPU (2026-09-06)

official/main landed qwen4exp split-PLE + native MTP upstream (PR #21,
`6390402e6`, adaptation `e811481023` credited, JJJYmmm MTP lineage) plus
PR #20 (RDNA3 HIP MMQ) and PR #18 (vulkan-fa-splitk). our uncommitted
local port was stashed as superseded. two builds of the same tree:
build-official (vulkan) and build-hip (gfx1151 HIP, ROCm 7.2.3), both
build 11541. receipts `results/28b9-*`.

**qwen4exp coherence (oracle prompt, temp 0, n 256):**

| test | backend | verdict |
|---|---|---|
| plain | Vulkan | **COHERENT** — the 22496778e-era Vulkan garbage is gone |
| plain | HIP | COHERENT |
| strict MTP | Vulkan | COHERENT, 35.8 t/s, 182/239 accepted (76.2%) |
| strict MTP | HIP | COHERENT, 31.9 t/s, 166/226 accepted (73.5%) |

strict outputs diverge across backends at char 386 (both valid English) —
strict guarantees within-backend exactness vs non-spec greedy, not
cross-backend identity. note: `--spec-mtp-strict-qwen` is server-gated in
this build (`.set_examples({LLAMA_EXAMPLE_SERVER})`) — llama-cli rejects
it; strict tests must run via llama-server (-np 1).

**decode cells (HIP build, ROCBLAS_USE_HIPBLASLT=1, -t 4):**

| cell | HIP @ 28b92f576 | Vulkan t4 ref |
|---|---|---|
| 8k plain | 482.6 / 21.0 | 413.9 / 24.0 (pp +17%, tg −12.5%) |
| 8k mtp | 433.3 / 21.7 | 395.3 / 33.8 (pp +10%, tg −36%) |
| 128k mtp | hangs at load 3/3 | 180.4 / 13.5 |

128k mtp on HIP: deterministic load stall — process frozen ~3.8 GB RSS,
zero output (not even device enumeration), guard-killed at 150 s in all
three attempts. 8k cells run clean on the same binary; classified as a
HIP load-path bug at depth, not investigated further.

verdict: daily driver stays Vulkan (tg + decode wins everywhere). HIP
prefill is faster (hipBLASLt) but decode/MTP much weaker and deep-MTP
unusable on this build. the real win: the blessed engine is fully healthy
— the port-PR decision is moot (upstream did it, credited), and strict-MTP
is now a working GPU feature instead of a CPU-only exactness proof.

## CIRU comparison probes (2026-09-06)

CIRU v2.0 (`jcbtc/Qwen3.8-Flash-CIRU-STRIX-IU4`) is a custom ROCm 10
runtime + mixed-precision package (FP8-exact NVMe-paged PLE, QSA top-k
GPU admission, F16 target KV, p-min 0), not stock llama.cpp. their
receipts beat ours at 128k prefill (232.95 vs 186.9) and on fidelity
(mean KL 0.03045 vs BF16); we beat them on 8k prefill (413.9 median /
504 @ -t16 vs 370.4), 8k tg (24.0 vs 19.2) and 128k tg (9.8 vs 6.75).
two adoption probes on our driver, both negative:

| probe | result | verdict |
|---|---|---|
| f16 KV @ 128k plain | 179.1 / 9.8 vs q8_0 186.9 / 9.8 | no gain — their deep-prefill edge is indexer kernels, not KV type |
| p-min 0 @ 8k mtp | 364.6 / 24.0 vs p0.75 395.3 / 33.8 | −29% tg — full-accept drafting wastes verify batches on our 86% acceptance |

their package download started for a head-to-head on this box
(`/mnt/ssd2/models/ciru-iu4`). NPU assessed and parked: XDNA2 stack
(accel0 + lemonade present) serves a fixed arch list — no qwen4exp path
— and the NPU shares the same UMA bandwidth, so no decode advantage for
this model.

update: CIRU package removed per size decision (127G) — head-to-head
cancelled, analysis kept. CIRU download dir deleted 2026-09-06.

## indexer audit — Vulkan declines the qwen4exp top-k (K=2048) at all depths (2026-09-06)

qwen4exp's sparse attention selects per layer per ubatch via
`build_qsa_top_k` → `ggml_top_k` over the full cache width. the Vulkan
backend's `supports_op` gate computes `min_pipeline = log2(K)+1` against
`num_topk_pipelines = 11` — with the model's `indexer.top_k = 2048`,
min_pipeline = 12 ≥ 11 → **declined, always** (the code even comments "we
could potentially support larger... not clear if this is needed" — for
qwen4exp it is needed, 48 layers × every ubatch). the MoE K=256 top-k runs
fine on Vulkan; only the indexer width is declined.

evidence: full 8k prefill profile (`GGML_VK_PERF_LOGGER=1`,
`results/profile-8k-prefill.log`, 14.6 s of Vulkan work, pp 409.8 ≈ the
413.9 median so the profiled run is representative) contains **zero**
indexer-width TOP_K executions — ~192 expected calls, only the six tiny
MoE K=256 lines. 8k breakdown is matmul-dominated (MUL_MAT 33% +
MUL_MAT_ID 22%, FA 5%, GDN 3.6%).

this matches CIRU's independently-named fix ("GPU admission for long QSA
top-k") — same mechanism, their runtime admits what ours declines. the fix
is backend/kernel work (raise the top-k pipeline range — Nathan/upstream
territory), not flags: consistent with every no-gain flag probe (-ub 4096,
-b 8192, n_max, p-min).

tooling note: the vk perf logger itself is unusable at prefill scale —
`GGML_VK_PERF_LOGGER=1` triggers instant multi-GB host swap (22 GB in
<60 s at 32k, swap-killed the 128k run too), a logger artifact not model
behavior. receipts `profile-128k/32k-prefill.log(.mem.log)`. do not retry;
the 8k profile is the keeper.

## blessed depth sweep @ 28b92f576 — healthy at ≤64k ctx, startup hang at 128k (2026-09-06)

ROCmFPX-official build-official (vulkan), same flags/fillers as the n3
suite, -t 4. receipts `results/blessed-*`.

| cell | blessed @ 28b92f576 | ad914eb ref |
|---|---|---|
| 8k plain | 400.8 / 24.2 | 413.9 / 24.0 — par |
| 8k mtp | 392.8 / 26.3 | 395.3 / 33.8 — **tg −22%** |
| 32k content @ c=65536 | 389.5 / 20.2 | ~397 / ~20 — par |
| 128k ctx (-c 139264) | startup hang 2/2 | 186.9 / 9.8 plain, 180.4 / 13.5 mtp |

the 128k failure is a startup hang, not a memory cliff: zero output (not
even "loading model"), RSS 0.4–0.8 GB at kill, HANG detector fired at
150 s in both modes. the same binary runs clean minutes earlier at
-c 65536 and -c 16384. threshold sits between 64k and 139k ctx — likely
a giant upfront allocation (FA split-k scratch? QSA inputs sized to full
ctx?) stalling the Vulkan allocator or the split estimator.

verdict: daily driver stays `ad914eb` by a wide margin — blessed trails
at 8k MTP and cannot start at 128k ctx at all. the engine-switch question
is closed until upstream fixes both.

## sha256 pins

| receipt | sha256 (first 16) |
|---------|-------------------|
| `ple-depth.log` | `118eb998abfe736e` |
| `depth128.log` | `eefe56460acd5f2d` |
| `depth256.log` | `04ebcd9e3fc68259` |
| `hq38-256k-mtp-ub512.log` | `d6663a275f23f6c2` |
| `hq38-256k-mtp-ub512.mem.log` | `cd6f2023f0b3b021` |
| `hq38-depth0-plain.log` | `49190279cb64b66c` |
| `hq38-depth0-mtp.log` | `5cc5a7f4a76d4c5f` |
| `hq38-depth8k-plain.log` | `91fdf878acb68591` |
| `hq38-depth8k-mtp.log` | `bb8906d0ffd9f3d3` |
| `hq38-depth32k-plain.log` | `1d44b574d953e302` |
| `hq38-depth32k-mtp.log` | `ff95fad0286ddff7` |
| `hq38-depth128k-plain.log` | `edf695976a26c219` |
| `hq38-depth128k-mtp.log` | `7fe8a82d7e241896` |
| `hq38-depth256k-plain.log` | `b8200ba47f94ad59` |
| `hq38-adaptive-depth0.log` | `420efff78243bdee` |
| `hq38-adaptive-depth0.mem.log` | `8dee2d23580503fd` |
| `hq38-adaptive-depth8k.log` | `0b6433d963066df0` |
| `hq38-adaptive-depth8k.mem.log` | `e388f0b7abc3d942` |
| `hq38-adaptive-depth32k.log` | `01f2d1a0d3374d25` |
| `hq38-adaptive-depth32k.mem.log` | `6edd80e481fcd4bb` |
| `hq38-adaptive-depth128k.log` | `cb37ddd3535ed1e3` |
| `hq38-adaptive-depth128k.mem.log` | `43e1421de5c991f9` |
