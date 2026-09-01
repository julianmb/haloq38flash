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
