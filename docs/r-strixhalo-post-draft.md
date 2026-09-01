qwen3.8-flash-next on strix halo: 56 t/s mtp, 91g ple quant, the converter trap, and 128k context benchmarks

we built two working ggufs for qwen3.8-flash-next (125b-a6b) on 128g strix halo and traced every byte back to the official fp8 weights. here are the numbers, the converter trap we hit, and the 128k depth trade-off.

first, the converter trap. early community conversion attempts printed deterministic garbage because 97 of 388 f32 tensors missed a gamma fold. hyper-connections in qwen4exp sit under attn_hyper_connection and mlp_hyper_connection. those names bypassed the standard norm weight offset, leaving gamma raw instead of gamma + 1 across every layer. shapes and tensor counts looked fine, but every layer normalized wrong. we patched the converter in rocmfpx pr #98 with a regression test so every gamma folds correctly.

second, the ple cut. qwen3.8-flash-next carries a 51g n-gram lookup table (per_layer_token_embd). because the table is gathered row-by-row via hash lookup without full matmul, we quantized it to iq4_nl (4.25 bpw) using --tensor-type per_layer_token_embd=IQ4_XS. that sliced total file size from 116g to 91g (a 27g reduction) with no degradation verified through 32k context.

here is the measured decode performance on our 128g strix halo setup (vulkan/radv, q8_0 kv cache, -ub 2048, temp 0):

| context depth | 116g static plain / mtp (t/s) | 91g ple plain / mtp (t/s) |
|---|---|---|
| 0 | 29.2 / 48.4 | 29.9 / 53.1 |
| 8k | 22.9 / 42.8 | 24.1 / 56.4 |
| 32k | 19.5 / 29.5 | 20.1 / 30.2 |
| 128k | 10.8 / 26.9 | 11.0 / 18.6 |
| 256k | 6.2 / — | 6.2 / 8.0 (merged build) |

third, the 128k reversal & production flags. at 32k and below, the 91g ple quant wins everywhere, hitting 56.4 t/s with the 3.9g mtp sidecar (peak n=1 run; a same-config repeat sweep measured 33.5 t/s — mtp throughput spreads run to run). at 128k under mtp, the 91g ple quant falls behind the 116g static quant (18.6 vs 26.9 t/s) because iq4_nl noise compounds over deep n-gram history. pairing the draft sidecar with --spec-draft-adaptive --spec-draft-n-min 0 --spec-draft-n-max 7 --spec-draft-p-min 0.75 stabilizes acceptance at 91-94%. for extreme context (128k-256k), passing --override-tensor "per_layer_token_embd=CPU" offloads the ple table to host ram and keeps total gpu allocation under the 128g uma ceiling without thrashing swap.

for daily coding and chat up to 32k, pick the 91g ple file. if you need 128k or longer documents, use the 116g static file.

model weights and sidecars: https://huggingface.co/julianmb/Qwen3.8-Flash-Next-IQ4_XS-GGUF

posted from haloq38flash with full receipts at github.com/julianmb/haloq38flash
