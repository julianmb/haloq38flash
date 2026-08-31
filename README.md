<div align="center">

# haloq38flash

**qwen3.8-flash-next on amd strix halo — 91g quant, 56 tok/s, 262k context**

[![HF Model](https://img.shields.io/badge/🤗_Model-IQ4_XS_PLE-ffD21E)](https://huggingface.co/julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF)
[![Speed](https://img.shields.io/badge/MTP_@8k-56.4_t%2Fs-brightgreen)](#results)
[![Depth](https://img.shields.io/badge/Verified-0_→_256k-blueviolet)](#results)
[![Provenance](https://img.shields.io/badge/Provenance-byte--verified-success)](#the-converter-bug)
[![Docker](https://img.shields.io/badge/Docker-ready-2496ED)](#docker)

*every published quant byte-traced back to the official checkpoint*

</div>

---

## results

91g quant · vulkan/radv · mtp sidecar · q8_0 kv · `-ub 2048` · temp 0 · 128g strix halo

| depth | plain pp / tg | mtp pp / tg |
|------:|:-----------:|:---------:|
| 0 | 92.5 / 29.9 | 87.0 / **53.1** |
| 8k | 480 / 24.1 | 458 / **56.4** |
| 32k | 397 / 20.1 | 379 / **30.2** |
| 128k | 222 / 11.0 | 214 / 18.6 |
| 256k | 139 / 6.2 | — |

> [!NOTE]
> no collapse through 32k. the 128k+ falloff is context-mechanics
> (sparse-attention indexer), not quant size — see the reversal below.

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
  --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75
```

### 262k context (ssd streaming)

swap the model to the static 116g and enable lazy ple — the n-gram table
stays on ssd (~2.5g resident), leaving room for the full context window:

```bash
docker compose run qwen38-flash-next /app/llama-server \
  -m /models/Qwen3.8-Flash-Next-IQ4_XS.gguf \
  -c 262144 -lm mmap --tensor-read-lazy on \
  -ngl 999 -fa on -ctk q8_0 -ctv q8_0 -ub 2048 -t 4
```

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
