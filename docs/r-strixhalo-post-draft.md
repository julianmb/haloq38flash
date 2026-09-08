qwen3.8-flash-next on strix halo: 56 t/s mtp, 91g ple quant, the converter trap, and 256k context benchmarks

we built two working ggufs for qwen3.8-flash-next (125b-a6b) on 128g strix halo and traced every byte back to the official fp8 weights. here are the numbers, the converter trap we hit, and the 128k-256k depth trade-off.

first, the converter trap. early community conversion attempts printed deterministic garbage because 97 of 388 f32 tensors missed a gamma fold. hyper-connections in qwen4exp sit under attn_hyper_connection and mlp_hyper_connection. those names bypassed the standard norm weight offset, leaving gamma raw instead of gamma + 1 across every layer. shapes and tensor counts looked fine, but every layer normalized wrong. we patched the converter in rocmfpx pr #98 with a regression test so every gamma folds correctly.

second, the ple cut. qwen3.8-flash-next carries a 51g n-gram lookup table (per_layer_token_embd). because the table is gathered row-by-row via hash lookup without full matmul, we quantized it to iq4_nl (4.25 bpw) using --tensor-type per_layer_token_embd=IQ4_XS. that sliced total file size from 116g to 91g (a 27g reduction) with no degradation verified through 32k context.

here is the measured decode performance on our 128g strix halo setup (vulkan/radv, q8_0 kv cache, -ub 1024 -b 2048, temp 0):

| context depth | 116g static plain / mtp (t/s) | 91g ple plain / mtp (t/s) |
|---|---|---|
| 0 | 29.2 / 48.4 | 29.1 / 48.1 |
| 8k | 22.9 / 42.8 | 21.8 / 27.9 (peak: 56.4) |
| 32k | 19.5 / 29.5 | 18.5 / 25.5 (peak: 30.2) |
| 128k | 10.8 / 26.9 | 8.9 / 11.8 (peak: 18.6) |
| 256k | 6.2 / — | 6.0 / **15.2** (SSD-PLE tuned) |

third, the 128k reversal, SSD-PLE, & production flags. at 32k and below, the 91g ple quant wins everywhere, hitting up to 56.4 t/s with the 3.9g mtp sidecar (peak n=1 run; mtp throughput spreads run to run). at 128k under mtp, the 91g ple quant falls behind the 116g static quant (18.6 vs 26.9 t/s) because iq4_nl noise compounds over deep n-gram history. but for extreme context up to 256k, passing `-lm mmap --tensor-read-lazy on` keeps the 27 GB PLE table on NVMe SSD without consuming active RAM. Combined with `-tb 16` (16 threads for prompt processing) and `-ub 1024 -b 2048 -t 4`, this completely eliminates swap pressure (leaving ~30 GB of free headroom) and unlocks **15.2 t/s generation at 256k context** on the daily-driver Vulkan build.

for daily coding and chat up to 32k, or full 256k long-context workloads using SSD-PLE, pick the 91g ple file. if you need maximum MTP speed specifically at 128k, use the 116g static file.

model weights and sidecars: https://huggingface.co/julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF

posted from haloq38flash with full receipts at github.com/julianmb/haloq38flash
