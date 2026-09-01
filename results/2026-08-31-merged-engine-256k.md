# Merged engine 256k validation receipt — 2026-08-31

Run 2026-09-01 AEST on 128 GiB Strix Halo. Engine: `build-hq38/bin/llama-cli`, build `b10888-081edc343` (binary size `1.4M`); target: 91 GiB `Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf`; MTP: 3.9 GiB Q8_0 sidecar. Every launch used `timeout -k 30 2400`, a preflight `free -h` plus exact-name process check, `oom_score_adj=500`, and 30-second `VmRSS`/`VmSwap` sampling. The build exposes the requested lazy option as `--lazy-mode auto` rather than `--tensor-read-lazy auto`.

## 256k MTP generation

| context / prompt | result | generation grep | lazy grep | peak process RSS / swap |
|---|---|---|---|---:|
| 257,024 / 255,718 tokens | **ABORTED, no timing** | no `Generation: ... t/s` match | no match in non-verbose run log | 847,512 / 110,788 KiB |

The run held `VmSwap: 0 kB` for 32 samples through 15:15:22, then sampled 29,152 and 110,788 KiB at 15:15:52/15:16:22. The mandatory two-sample guard killed PID 89526 and recorded `requires lazy PLE (swap >8GiB)` / exit 137. Therefore the missing 256k MTP number is **not validated**. Lazy PLE itself is proven active by the verbose oracle grep: `tensor per_layer_token_embd.weight (size = 27465 MiB) lazy read enabled` in both oracle logs.

## Greedy identity oracle (`--reasoning off`, `-n 2048`)

| path | generation | graphs reused | identity |
|---|---:|---:|---|
| plain | 26.9 t/s | 290 | **FAIL** |
| MTP n=6 | 40.2 t/s | 20 | **FAIL — 28 unified-diff lines** |

The archived `results/hq38-oracle.diff` shows a real greedy divergence: MTP omits the docstring's `Raises` section and moves the negative-input check below memo initialization. The archive also contains the extracted `hq38-oracle-{plain,mtp-n6}.txt` outputs; this does not satisfy the expected zero diff.

## PLE depth sweep

Cells are prompt / generation tokens per second, from the exact grep lines in `results/hq38-depth<depth>-<mode>.log`.

| depth | bounded context | plain pp / tg | MTP n=6 pp / tg |
|---:|---:|---:|---:|
| 0 | 8,192 | 94.6 / 29.0 | 70.2 / 45.7 |
| 8k | 16,384 | 496.9 / 21.7 | 464.8 / 27.6 |
| 32k | 40,960 | 400.5 / 17.7 | 382.5 / 23.5 |
| 128k | 139,264 | 266.8 / 9.0 | 257.2 / 12.9 |
| 256k | 257,024 | 202.9 / 6.2 | **aborted; no timing** |

## Memory receipt

| leg | peak VmRSS KiB | peak VmSwap KiB | exit |
|---|---:|---:|---:|
| oracle plain / MTP | 405,892 / 671,072 | 0 / 0 | 0 / 0 |
| 0 plain / MTP | 35,280 / 666,392 | 0 / 0 | 0 / 0 |
| 8k plain / MTP | 289,416 / 431,820 | 0 / 0 | 0 / 0 |
| 32k plain / MTP | 317,404 / 710,288 | 0 / 0 | 0 / 0 |
| 128k plain / MTP | 490,400 / 1,616,636 | 0 / 0 | 0 / 0 |
| 256k plain / MTP | 628,088 / 847,512 | 0 / 110,788 | 0 / 137 (guard) |

Raw evidence is committed as `2026-08-31-merged-engine-256k-logs.tar.gz`
(`sha256:32605f52753545fdc258f7ffe79ff10e0764286e445ab897341464b2e6985951`):
all `hq38-*.log`/memory traces, both oracle texts and their diff, the guard log,
and matrix status. No two GPU jobs overlapped; every preflight recorded
`llama-cli=0 llama-server=0` before launch.
