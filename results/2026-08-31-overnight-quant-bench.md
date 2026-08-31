# Imatrix / PLE / MTP depth sweep — 2026-08-31 overnight

## Setup and gates

- Quantizer: ROCmFPX banded `llama-quantize`, build 270 (`48a6d39f9`).
- Engine: `/home/user/source/llama.cpp-strix-halo-vulkan/build/bin/llama-cli`, build 1 (`ad914eb`).
- M2 command (no `--tensor-type` override):

  ```text
  /tmp/rocmfpx-quant/build/bin/llama-quantize \
    --imatrix /mnt/ssd2/models/qwen38-flash-next/qwen38-imatrix.dat \
    /mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-F16.gguf \
    /mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-M2.gguf \
    IQ4_XS
  ```

- M2 quant log: 926 imatrix entries, 1,024 chunks; `per_layer_token_embd.weight` remained Q8_0; 194 fallback tensors; 5.56 BPW; 1,779,377 ms.
- Paris gate: pass — `The capital of France is Paris...`; 57.3 s load and 26.94 t/s generation with the bounded `llama-completion -ngl 47 -c 8192` smoke.
- Sidecar dispatch gate: apepojken failed because `output_hc_norm.weight` was absent; the Nathan sidecar (`mtp-Qwen3.8-Flash-Next-Q8_0.gguf`, trailing `blk.48`) passed a 10-token Paris smoke and was used below.
- Depth prompts tokenized to 8,193 / 32,769 / 131,073 / 255,718 tokens. Contexts were explicitly bounded at 8,192 / 16,384 / 40,960 / 139,264 / 257,024; no run used the GGUF 262,144 default.
- Common benchmark flags: `-dev Vulkan0 -ngl 999 -fa on -ub 2048 -ctk q8_0 -ctv q8_0 -n 128 --temp 0 --reasoning off -st --simple-io`. MTP added `-md ...Q8_0.gguf --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75`.

## Artifact sizes

| quant | PLE tensor | bytes | GiB | measured BPW | fallback tensors | Paris |
|---|---|---:|---:|---:|---:|---|
| Static IQ4_XS | Q8_0 | 123,993,034,048 | 115.48 | — | 194 shape fallbacks | previously clean |
| PLE IQ4_XS | IQ4_NL fallback from forced IQ4_XS | 97,444,277,856 | 90.75 | 4.41 | 195 | previously clean, 28.7 t/s |
| M2 imatrix IQ4_XS | Q8_0 | 123,044,400,736 | 114.59 | 5.56 | 194 | pass, 26.94 t/s |

M2 is 25,600,122,880 decimal bytes (23.84 GiB) larger than PLE and 948,633,312 bytes (0.88 GiB) smaller than static. The requested command therefore produced 115G rather than the approximate 104–108G estimate, while matching the expected roughly 25 GB PLE delta.

## Plain depth sweep

Cells are prompt-processing / token-generation tokens per second.

| depth | context | Static 116G | PLE 91G | M2 115G |
|---:|---:|---:|---:|---:|
| 0 | 8,192 | 88.3 / 29.5 | 93.5 / 30.2 | 87.5 / 29.6 |
| 8k | 16,384 | 471.8 / 23.2 | 504.8 / 23.8 | 492.2 / 23.8 |
| 32k | 40,960 | 392.0 / 18.6 | 401.8 / 19.0 | 386.1 / 19.0 |
| 128k | 139,264 | 266.5 / 9.4 | 268.4 / 9.5 | 268.1 / 9.4 |
| 256k | 257,024 | 202.7 / 6.2 | 204.1 / 5.5 | 203.7 / 6.2 |

## MTP depth sweep

| depth | context | Static 116G | PLE 91G | M2 115G |
|---:|---:|---:|---:|---:|
| 0 | 8,192 | 82.0 / 50.0 | 86.7 / 53.9 | 82.3 / 49.4 |
| 8k | 16,384 | 472.9 / 32.5 | 474.9 / 33.5 | 460.5 / 25.1 |
| 32k | 40,960 | 370.4 / 28.2 | 374.2 / 26.7 | 364.8 / 29.1 |
| 128k | 139,264 | 256.6 / 17.4 | 256.4 / 13.5 | 257.7 / 13.3 |
| 256k | 257,024 | resource ceiling, exit 137 | resource ceiling, exit 137 | resource ceiling, exit 137 |

All three 256k MTP attempts exhausted the 33 GiB swap area before producing a timing line. Static and M2 were terminated by the admission guard at less than 4 GiB `MemAvailable` with less than 1 GiB `SwapFree`; PLE had already reached the same exit-137 outcome. Plain 256k remained stable for every quant.

The PLE `-ub` check at 256k plain measured: `ub=512` 194.7 / 6.2, `ub=1024` 193.1 / 6.1, and `ub=2048` 204.1 / 5.5 pp/tg. Thus `ub=2048` improved prefill by 4.8% over 512 in this run, not the claimed 10%; generation was 0.7 t/s slower.

## What each quant changes

**Static 116G.** This is the non-imatrix baseline with the PLE table retained at Q8_0. Its 194 fallback count is dominated by geometry, not an implicit quality policy: 640-column expert-down tensors and 320-column hyper-connection up tensors cannot satisfy IQ4_XS's 256-column divisibility and therefore fall back (predominantly to IQ4_NL). Those same shape fallbacks remain in both imatrix variants, so they do not explain the cross-variant size or depth differences.

**PLE 91G.** This uses the same 926-entry imatrix for supported trunk tensors and explicitly requests `per_layer_token_embd=IQ4_XS`. The 160-column PLE table also cannot satisfy IQ4_XS geometry, so that one deliberate override falls back to IQ4_NL and raises the fallback count from 194 to 195. That 51B-entry table cut, Q8_0 to IQ4_NL, is the real 25.6 GB size lever; the unchanged 640/320-column fallbacks are shape-forced. It wins plain prefill through the sweep and MTP at 0/8k, but its MTP generation trails static at 32k/128k.

**M2 115G.** This applies the same imatrix to the trunk but passes no tensor override, so the 160-column PLE table has no imatrix weights and remains Q8_0. Its fallback count returns to 194, exactly the geometry-forced baseline, while the imatrix-adjusted trunk trims only 0.88 GiB versus static. Its plain depth curve is effectively static; under MTP it is similar at 0/32k, materially worse at 8k, and close to PLE at 128k. This isolates the large file-size change to PLE precision and the smaller static-versus-M2 change to imatrix-guided trunk choices.

## Result receipts

- Committed raw-receipt archive: `results/2026-08-31-overnight-quant-bench-logs.tar.gz` (`sha256:aec23e327a5d9637d6e11cb8e78d081dda35dcef7dd9951b112ffb1e3a236482`). It contains every per-run log, all four exact fillers, both quant logs, sweep summaries, and the 256k MTP memory traces.
- Per-run logs: `results/{STATIC-,PLE-,M2-}shvd-depth{0,8k,32k,128k}-{plain,mtp}.log`.
- 256k plain: `results/STATIC-shvd-depth256k-plain.log`, `results/M2-shvd-depth256k-plain.log`, and `results/PLE-ub2048-depth256k-plain.log`.
- 256k MTP failure receipts: matching `results/*-shvd-depth256k-mtp.log`; memory traces are in `/home/user/overnight/*-shvd-depth256k-mtp-vm.log`.
- Quant and gate receipts: `/home/user/overnight/quant-M2.log`, `results/M2-paris-smoke.log`, and `results/sidecar-smoke-{apejojken,nathan}.log`.
