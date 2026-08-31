# engine cherry-pick plan — nathan/strix-halo-vulkan → ggml-org master

date: 2026-08-31. base for counting: merge-base `9f0d017ef` (#27235 era).
nathan branch tip: `ad914eb65`. #27742 landed in master as squash `6c84c7d5d`.
nathan's branch = the #27742 development history + his strix-halo patch stack +
three master merges he already did + the qwen4exp runtime continued past the
squash point.

## counts

- 175 commits on `6c84c7d5d..nathan/strix-halo-vulkan` (reverse order in
  `docs/nathan-175-commits.txt`)
- ~40 of them are the #27742 development history — **skip**, master's squash
  `6c84c7d5d` already carries that content
- ~8 are master commits that reached his branch via his three master merges
  (muse glimmer #26841/#26879, motif-3, dspark #27508, kv-cell #27762) —
  **skip**, master has them
- 4 are CI/toolbox release plumbing — **skip** (fork-specific)
- ~10 are merge commits — **skip** (resolved by the one big merge below)
- **~115 genuine candidates**, grouped below

## recommendation: one merge, not 115 cherry-picks

the qwen4exp runtime commits and the vulkan shader stack interleave (the
sparse-FA shaders are prerequisites for the qwen4exp QSA gather path; the FACP
refactor renames classes the later commits use). piecemeal cherry-picking
breaks the build between commits. instead:

```
git checkout -b haloq38flash-engine ggml-org/master   # or origin/master
git merge nathan/strix-halo-vulkan
# resolve conflicts once: ggml-vulkan mostly takes THEIRS (the perf stack),
# src/llama*.cpp mixed, everything else master
cmake -B build -DGGML_VULKAN=ON && cmake --build build -j 24
```

nathan already merged master into his branch three times
(`aaf4fba83`, `b7b85da9c`, `f94fad0e8`/`add19980d`) — the reverse merge is the
same operation he proved works, and conflicts concentrate in the files he owns.

## group A — vulkan fa/mmq perf stack (~45, oldest first)

the coopmat1 FA rework, dequant-once scratch, contiguized KV, mul_mat_id tile
probes, f16-B path, q5_K/q4_K scale caches, wave32, LDS pad tuning, the six
env-gated perf flags now default-on. cherry-pick as a block, oldest first;
`acd14737e FACP` and `892924042 single source of truth` are the load-bearing
refactors the later ones sit on. skip `681675530` (marked NEGATIVE result).

## group B — dsv4 lightning indexer + sparse fa gather (~25)

`890550c0a` indexer kernels + indexed sparse FA, `5dfc01ff6` gather-to-compact
decode, the sparse prefill split/tile/cache cluster, quantised K/V inside the
gathers (`8b66f91c6`, `7b63cbd6b`, `6b2cade31`), small-batch union
(`8115df4c7`..`31202f9df`). written for deepseek v4, powers qwen4exp's QSA the
same way. NOTE: `b65c360c7` fixes multi-sequence — keep.

## group c — fused hyper-connection ops + command buffers (~5)

`2041049a4` fused HC pre/comb/post (the 3550→2800 dispatch win),
`e709b949e` command buffers bounded by memory traffic,
`18239a695` perf-logger flush, `0f80b884d`/`8a8fee776` UMA copy path.

## group d — hip/"ggml-cuda" rdna3.5 tuning (~12)

`64e5c14f1` kernel tuning, `f074165ae` quantized-KV FA, MMQ tile tuning
(`71ac6c1d9`, `f70839f9a`, `86e3f34fc`), Q8_1 activation cache (`a649f1634`),
WMMA indexer (`8209c8954`), tiled FA (`e88b92eff`), GDN tune (`910f0f25d`),
NaN fix (`4ea44eef2`), tests (`b1282d2af`, `6e7b355cb`). named ggml-cuda
because the hip backend rides the cuda code paths.

## group e — qwen4exp runtime past the squash point (~25)

what master's squash does NOT have:
- `be71d63c9` quantized KV cache in the QSA attention path (the q8_0 kv fix
  our rocmfpx build lacks)
- `631b9ffb1` decode-graph reuse + host-side PLE gather (graphs reused 68 vs 0)
- `354390810` + `39817c476` NextN/MTP draft: sidecar AND in-file loading
- `f32aca1c1`/`79c2d2cad`/`3849d54b8`/`d763facad`/`fdf96fcea` indexer cache in
  llama_memory_hybrid_idx, slots, names
- `87f31259a`/`c04b3ff4b`/`8f58c2f0a` PLE history per context + iterator fix
- `05f6575ab`/`25a796300`/`cdd2e47ae` indexer cache save/restore + slots
- `c1d5b2d0e`/`bd92a90c4`/`671203688` random-access mmap advice for the
  gather table (the ple-ssd-streaming primitive)
- `024b7ad93` QSA bias per block, `7073ae357` hparams shrink,
  `1486f6b88` non-unified KV in QSA, `a80d678ad` image placeholder hash,
  `562cb00bc`/`42d976771` tensor-split segments, `d6f65ff28` graph budget
- quantizer: `7a4d5960d` PLE streaming (independently written — same fix as
  our banding), `9e2d2eb84` --tensor-type names the PLE (the flag the 91g
  quant used), `5beb9965b` f16 fallback for odd ncols,
  `5096585d6` exact output buffer
- tests: `171ddb8df`/`086457e7b`/`77953f1e1`

## group f — speculative decoding fixes (~10)

the 7-bug stack behind "spec decode works end to end":
`53fd8b48c` GDN state graph order, `9c5d899ff`/`f25eefeaf`/`a17e8432b`
MTP rollback full checkpoints (apply→revert→reapply), `08a325524`
checkpoints on device, `0eb528051` draft trimming for mtmd,
`64e2b680a` dflash cache alignment, `397ef7c72` no_vocab special tokens.

## group g — optional, other archs (~10, default skip)

dspark bailingmoe3 (`2586f6edd`), dflash2 (`015f09c8a`/`0b0f35d0e`),
motif-3 (`4c7f96093`/`be54e2891`/`a359e55c9`) — only if wanted; they ride
along in the merge anyway.

## verification after the merge

1. build vulkan, zero errors
2. our depth bench on the 91g quant: 0/8k/32k/128k — expect >= the nathanw1014
   numbers (29.9/24.1/20.1 plain, 53.1/56.4/18.6 mtp) plus master's 771 commits
3. greedy oracle: with `39817c476` spec decode + the rollback fixes, the
   6-line divergence on our current engine should close (his fork is the one
   the 7-bug fix stack was written for)
4. lazy ple: `--tensor-read-lazy auto` must log "lazy read enabled" for
   per_layer_token_embd — the load_mode=none hardcode does not exist on
   master's path
5. then 256k mtp: no thrash expected (66g resident with lazy ple)

## candidates for upstreaming after validation

radix/sparse top-k fa, fused hc epilogs, gdn concat fix, the q8_0-kv-in-qsa
fix, the lazy ple plumbing, the converter trap note (hc norms).
