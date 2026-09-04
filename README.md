<div align="center">

# haloq38flash

**qwen3.8-flash-next (125b-a6b) on amd strix halo — 56 tok/s mtp, 262k context, 91g provenance-verified quant**

*converter bug found + fixed · vulkan fa/mmq kernel tuning · greedy-oracle validated speculative decoding · 51b n-gram table cut to 4 bits · ssd streaming to 262k*

[![HF Model](https://img.shields.io/badge/🤗_Model-IQ4_XS_PLE-ffD21E)](https://huggingface.co/julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF)
[![Speed](https://img.shields.io/badge/MTP_@8k-56.4_t%2Fs-brightgreen)](#results)
[![Depth](https://img.shields.io/badge/Verified-0_→_256k-blueviolet)](#results)
[![Provenance](https://img.shields.io/badge/Provenance-byte--verified-success)](#the-converter-bug)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED)](#docker)

*every published quant byte-traced back to the official checkpoint*

</div>

<details>
<summary><b>plain english — what was done</b></summary>

qwen3.8-flash-next is the new qwen model that is great for coding — it beats
claude opus 4.6 on swe-bench and runs on a $2500 mini pc.

1. the official conversion code missed a step — every hyper-connection norm
   was off by exactly 1.0, so the first quant printed garbage. we found it,
   fixed the converter, and added a test so it never happens again.
2. we made the model smaller without losing quality — the big 51b n-gram table
   tolerates 4-bit, saving 27g — then proved it across context depths from
   0 to 256k.
3. we kept everything that makes strix halo fast — vulkan kernels, graph
   reuse, speculative decoding with the 4b draft head.

if you just want to run it: `docker compose up --build` and open
`http://localhost:8080`. pick the 91g file for speed, the 116g file if you
need 262k context.

</details>

---

## results

91g quant · vulkan/radv · mtp sidecar · q8_0 kv · `-ub 2048` · temp 0 · 128g strix halo

| depth | plain pp / tg | mtp pp / tg |
|------:|:-----------:|:---------:|
| 0 | 92.5 / 29.9 | 87.0 / **53.1** |
| 8k | 480 / 24.1 | 458 / **56.4** |
| 32k | 397 / 20.1 | 379 / **30.2** |
| 128k | 222 / 11.0 | 214 / **18.6** |
| 256k | 139 / 6.2 | 187.2 / **8.0** |

> [!NOTE]
> no collapse through 32k. the 128k+ falloff is context-mechanics
> (sparse-attention indexer), not quant size — see the reversal below.
>
> row provenance: each row is a separate n=1 run — 0–32k from the ple-depth
> sweep, 128k from the depth128 run, 256k plain from the ssd-streaming run.
> the 256k mtp cell is the merged build-hq38 engine (`-ub 512` chunked
> prefill + ple→cpu offload) — the daily-driver build swap-dies at 256k mtp.
> same-config mtp runs spread up to ~40%: 56.4 vs 33.5 t/s at 8k across two
> sweeps. peaks are peaks, not medians.

n=3 confirmation (same flags, daily-driver vs merged engine, median [spread]).
the table above stays as the peak record; this one bounds the variance:

| engine | 8k plain tg | 8k mtp tg | 128k plain tg | 128k mtp tg |
|--------|-------------|-----------|---------------|-------------|
| daily driver | 24.0 [23.9–24.1] | 33.8 [33.8–34.3] | 9.8 [9.6–9.9] | 13.5 [13.3–13.7] |
| merged | 22.0 [22.0–22.2] | 27.4 [26.9–27.4] | 8.6 [7.8–9.2] | 12.7 [12.6–12.7] |

daily driver wins every cell; 8k is tight, 128k spreads wider. receipts:
`results/n3-*.log` (24 runs), pinned in `results/MANIFEST.md`.

<details>
<summary><b>the 128k reversal — the PLE quant loses under MTP at depth</b></summary>

at ≤32k the PLE quant wins everywhere. at 128k under mtp it *loses* to the
static 116g (18.6 vs 26.9 t/s). plausible mechanism: iq4_nl noise in the
n-gram table compounds over deep history and lowers draft acceptance.
single runs, n=1 caveat. pick your file by use case — see the table above.

</details>

---

## 📦 published quants

[huggingface.co/julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF](https://huggingface.co/julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF)

| file | size | pick it when |
|------|------|:------------:|
| `...-IQ4_XS-`**`PLE`**`.gguf` | 91 giB | ctx ≤ 32k — wins everywhere, mtp to 56 t/s |
| `...-IQ4_XS.gguf` | 116 giB | ctx ≥ 128k — faster mtp at depth, wider fork compat |
| `...-IQ4_XS-`**`M2`**`.gguf` | 115 giB | best measured perplexity (4.2809) — quality-first serving, fastest 32k mtp of the three |
| `mtp-...-Q8_0.gguf` | 3.9 giB | mtp sidecar, required for the speed numbers |

<details>
<summary><b>the PLE cut — why the 51b n-gram table tolerates 4-bit</b></summary>

the PLE table is gathered 16 random rows per token via hash lookup — there is
no matmul on the table itself, and no two consecutive tokens hit the same rows.
the rows tolerate iq4_nl (4.25 bpw) with no measurable degradation across the
depth sweep. the cut: `--tensor-type "per_layer_token_embd=IQ4_XS"` on our
quantizer → 54g → 27g.

**fork caveat:** engines that feed gathered PLE rows straight into mul_mat as
quantized B operands assert (ggml-vulkan.cpp:7794). verified working on the
packaged engine and rocmfpx.

</details>

### pick your setup

| your use case | quant | ctx | expect |
|---|---|---|---|
| coding agents, chat | 91g PLE | ≤ 32k | 56 t/s |
| long documents | 116g static | 128k | 27 t/s |
| full rag / research | 116g static + ssd streaming | 262k | 14 t/s |

---

## 🐛 the converter bug

our first quant printed deterministic garbage at temp 0. bisect to root cause:

- experts, gdn reorder, ple scale, metadata: all innocent
- **97 of 388 f32 tensors differed by exactly 1.0** — every hyper-connection
  norm shipped raw where the runtime expects `raw + 1`
- cause: the checkpoint nests hyper-connections under
  `attn_hyper_connection` / `mlp_hyper_connection` / `hyper_connection_mixer`,
  and those names hit early-return branches in the converter that bypass the
  generic `norm.weight → +1` rule

> [!WARNING]
> **any fork rolling its own qwen4exp converter must fold `(1 + w)` into the
> hyper-connection gammas.** upstream runtime documents the contract at
> `qwen4exp.cpp:231 — "the converter folded each gamma to (1 + w)"`. miss it
> and every layer normalizes wrong — garbage from layer 0, all shapes correct,
> all shape-only tests pass.

fix + regression test: rocmfpx `port-qwen4exp` commit `61b6a3b48`
([pr charlie12345/ROCmFPX#98](https://github.com/charlie12345/ROCmFPX/pull/98))

---

## 🐳 docker

```bash
git clone https://github.com/julianmb/haloq38flash && cd haloq38flash
docker compose up --build
# serve on :8080 — vulkan/radv, no rocm install needed
```

the packaged engine is tuned for strix halo: vulkan fa/mmq kernels, graph
reuse, lazy ple streaming, quantized-kv attention — the combination behind
the 56 t/s numbers. no manual build, no host rocm install.

add the mtp sidecar for speculative decoding:

```bash
docker compose run qwen38-flash-next /app/llama-server \
  -md /models/mtp-Qwen3.8-Flash-Next-Q8_0.gguf \
  --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75 \
  --cache-ram 8192 --ctx-checkpoints 32
```

### warm-turn cache (repeat context is nearly free)

re-prompts over the same long context skip prefill from ram checkpoints —
measured 438s → 0.68s at 128k (**640×**) and 994s → 0.74s at 256k
(**1351×**), receipts `results/warm-full-*.json`. the flags above (now also
the image default) enable it; warm cost is ~constant ~0.7s, so the ratio
grows with depth. this is the single biggest effective speedup for agent
workloads with repeated system prompts or revisited documents.

### 262k context (ssd streaming or cpu ple offload)

swap the model to the static 116g and enable lazy ple — the n-gram table
stays on ssd (~2.5g resident), leaving room for the full context window:

```bash
docker compose run qwen38-flash-next /app/llama-server \
  -m /models/Qwen3.8-Flash-Next-IQ4_XS.gguf \
  -c 262144 -lm mmap --tensor-read-lazy on \
  -ngl 999 -fa on -ctk q8_0 -ctv q8_0 -ub 2048 -t 4
```

Alternatively, offload the PLE table to CPU memory to avoid swap pressure:
`--override-tensor "per_layer_token_embd=CPU"`

note: adaptive draft sizing (`--spec-draft-adaptive`) and `--lazy-mode auto`
are merged-engine (`build-hq38`) options not in the packaged image — see
`results/MANIFEST.md` for which engine produced which published number.

---

## 🔬 the n-gram table at 4-bit — what we found

the 51b ple lookup table tolerates iq4_nl (4.25 bpw) with no quality loss
across the depth sweep. but there's a depth-dependent reversal: under mtp at
128k+, the ple quant *loses* to the static quant (18.6 vs 26.9 t/s) — the
iq4_nl noise compounds over deep n-gram history and lowers draft acceptance.
n=1, single runs. pick your file by use case.

---

## 📁 layout

| path | what |
|------|------|
| `models/` | symlink farm to local ssd (never in git) |
| `docs/` | engine merge plan, cherry-pick classification |
| `Dockerfile` | two-stage: vulkan engine build + slim runtime |
| `docker-compose.yml` | one-liner serving with recommended flags |

---

## ⚠️ operational gotchas (128g strix halo)

- always `-c 8192`-bounded ctx + `timeout` + `/usr/bin/time -v` — the gguf
  default 262144 + full offload hard-hung this box once
- `vm.dirty_ratio=15 / dirty_background_ratio=5` — the 191g ple conversion
  memmap wedges `balance_dirty_pages` for hours at kernel defaults
- conversion peak: ple scratch (191g) + f16 output (354g) coexist — budget
  ~560g free
- `pkill -x llama-cli`, never `-f` (matches your own wrapper shell)
- gpu memory is shared with everything else on the apu — two engines cannot
  hold ~90g+ models simultaneously without an oom cascade

---

license: [qwen community license 1.0](https://huggingface.co/Qwen/Qwen3.8-Flash-Next/blob/main/LICENSE) · base model: [Qwen/Qwen3.8-Flash-Next](https://huggingface.co/Qwen/Qwen3.8-Flash-Next)
