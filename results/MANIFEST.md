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
