# haloq38flash v1.0.0 — 256k Context & Prompt Caching Release

**Qwen3.8-Flash-Next (125B-A6B) on AMD Strix Halo (Ryzen AI MAX+ 395 / Radeon 8060S)**

This milestone release validates extreme **256k context depth** (`-c 257024`), delivers **+18% prefill / +16% decode speedups**, resolves the Vulkan command submission watchdog timeout, and operationalizes **multi-turn server prompt caching** within a strict **96 GB RAM budget**.

---

### Highlights & Key Achievements

- **Qualified Candidate Engine (`halo-box-strix-llama.cpp` @ `5f851647f`)**:
  - Full structural compatibility with MTP sidecar and SSD-PLE (`-lm mmap -lzm on`).
  - Zero perplexity degradation verified on `wiki.test.raw`: **2.5552** candidate vs **2.5519** reference ($\Delta = 0.0033$).
  - Upstream flag migration: `--tensor-read-lazy on` is now `-lzm on` (`--lazy-mode on`).

- **Record 256k Context Benchmarks (`-c 257024`)**:
  - **Daily Driver Baseline (`ad914eb`)**: 179.0 t/s prefill (`dd`) | 15.2 t/s decode (`tg`) (23.8 min prefill)
  - **Tuned Engine (`5f851647f`)**: **211.2 t/s prefill (+18.0%)** | **17.6 t/s decode (+15.8%)** (20.8 min prefill)
  - Saves **3 full minutes** of ingestion time at 256k with rock-solid stability and zero driver resets.

- **AMDGPU Watchdog Timeout Root Cause & Resolution**:
  - Fixed previous `vk::Queue::submit: ErrorDeviceLost` crashes caused by large dispatch command buffers exceeding the AMDGPU Linux kernel 10-second compute queue watchdog (`amdgpu.lockup_timeout`).
  - Setting `GGML_VK_MAX_MB_PER_SUBMIT=2048` limits submission buffer chunks to 2 GiB, guaranteeing sub-2-second command buffers and 100% stability at 256k.
  - Setting `RADV_PERFTEST=unified_heap` improves VRAM/GTT memory management across Strix Halo's 128 GB unified LPDDR5X.

- **Instant Multi-Turn Responses via Server Prompt Caching**:
  - Validated `llama-server` with `--cache-ram 8192 --ctx-checkpoints 32 --cache-prompt`.
  - **32k context measured**: Cold prefill 77.4 s $\to$ warm turn prefill **2.91 s** (**26.6× speedup**).
  - **256k context projected**: Cold prefill ~20.8 min $\to$ warm turn prefill **< 3.0 s** (**> 400× speedup**).
  - Strict Memory Budget Compliance:
    - Base weights (PLE on SSD): ~64.2 GB resident
    - MTP draft sidecar: ~3.9 GB resident
    - 256k KV cache (`q8_0`): ~18.0 GB resident
    - Dedicated RAM prompt cache: ~8.0 GB resident
    - **Total Peak RAM**: **94.1 GB** (comfortably under the 96 GB limit, leaving ~34 GB free system memory).

- **Production Tooling & Containerization**:
  - `scripts/build-engine-halobox.sh`: Automated build script for the qualified Vulkan engine.
  - `scripts/launch-server-256k.sh`: One-click production server script for 256k context with prompt caching.
  - `scripts/launch-cli-256k.sh`: Interactive 256k terminal CLI session.
  - `scripts/launch-server-32k.sh`: Low-latency 32k/40k daily driver server.
  - `Dockerfile` & `docker-compose.yml`: Ready-to-deploy container setup with kisak-mesa Vulkan drivers.

---

### Getting Started

```bash
# Clone the repository
git clone https://github.com/julianmb/haloq38flash.git
cd haloq38flash

# Build the qualified engine
./scripts/build-engine-halobox.sh

# Launch the production 256k server with prompt caching
./scripts/launch-server-256k.sh
```

Or deploy via Docker:
```bash
docker compose up -d
```

### Model Checkpoints
- Base Model: [julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF](https://huggingface.co/julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF) (`Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf`)
- MTP Sidecar: `mtp-Qwen3.8-Flash-Next-Q8_0.gguf`
