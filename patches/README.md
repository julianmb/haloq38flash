# patches — retired

`0001-mtp-recurrent-rollback-qwen4exp.patch` added recurrent-state rollback
slots for MTP speculative decoding on `LLM_ARCH_QWEN4EXP`.

**Status (2026-09-23): retired, do not apply.** Upstream landed the same
fix as `qwen4exp: support recurrent state rollback (#28123)`, carried into
the halo-box engine via the 2026-09-15 sync. The pinned engine
(`Dockerfile`, `scripts/build-engine-unified.sh` → halo-box `8c1c282ec`)
already contains it and more (strided-tail copy matching the fused decode
paths). `build-engine-unified.sh` asserts its presence
(`TAG_RECURRENT_ROLLBACK_SPLITS`) at build time.

Kept for provenance only.
