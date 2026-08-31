#!/usr/bin/env bash
# A/B speculative decoding with MTP on the Nathanw1014 strix-halo-vulkan build.
#
# Runs the same greedy prompt with and without the MTP draft and diffs the text.
# At temp 0 the two must be identical (a "greedy identity oracle"): any
# divergence means the draft path is corrupting state.
#
# Uses the ORIGINAL sidecar (block_count = 49, blk.48), not the renumbered
# -blk0 one -- the runtime selects the trailing block itself.
# See results/2026-08-29-post-reboot-validation.md §6b.
#
# Tool notes: llama-cli, not llama-completion (the latter's parser rejects -md);
# -st is required or cli sits in an interactive loop printing "> " forever.
#
# usage: scripts/mtp-test-strix-halo-vulkan.sh [plain|mtp|both]
#        NMAX=2,4,6 scripts/mtp-test-strix-halo-vulkan.sh mtp   # sweep depths
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
TARGET=${TARGET:-/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS.gguf}
DRAFT=${DRAFT:-/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf}
OUT=${OUT:-/home/user/source/haloq38flash/results}
# long-form prompt: the model emits EOS early on short factual ones, which makes
# the tok/s figure meaningless
PROMPT="Write a Python function that computes the nth Fibonacci number using memoization, with a docstring, type hints, and a short example. Then explain how the memoization cache works."
CTX=8192
NPRED=512
NMAX_LIST=${NMAX:-6}

run() {
    local tag=$1; shift
    local log=$OUT/${TAGPREFIX:-}shv-$tag.log
    /usr/bin/time -v timeout 1800 "$BIN/llama-cli" \
        -m "$TARGET" "$@" \
        -dev Vulkan0 -ngl 999 -c "$CTX" -fa on -ub 2048 \
        -p "$PROMPT" -n "$NPRED" --temp 0 -no-cnv -st --simple-io > "$log" 2>&1
    local rc=$?
    # generated text sits between the "> " echo and the timing line
    awk '/^> /{f=1} /^\[ Prompt:/{f=0} f' "$log" > "$OUT/${TAGPREFIX:-}shv-$tag.txt"
    printf '%-16s exit=%s  %s  (%s bytes of output)\n' "$tag" "$rc" \
        "$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1)" \
        "$(wc -c < "$OUT/shv-$tag.txt")"
}

case ${1:-both} in
    plain) run plain ;;
    mtp)
        for n in ${NMAX_LIST//,/ }; do
            run mtp-n$n -md "$DRAFT" --spec-type draft-mtp \
                --spec-draft-n-max "$n" --spec-draft-p-min 0.75
        done ;;
    both)
        run plain
        for n in ${NMAX_LIST//,/ }; do
            run mtp-n$n -md "$DRAFT" --spec-type draft-mtp \
                --spec-draft-n-max "$n" --spec-draft-p-min 0.75
            if diff -q "$OUT/shv-plain.txt" "$OUT/shv-mtp-n$n.txt" > /dev/null; then
                echo "                 greedy identity n=$n: PASS"
            else
                echo "                 greedy identity n=$n: FAIL"
                diff "$OUT/shv-plain.txt" "$OUT/shv-mtp-n$n.txt" | head -10
            fi
        done ;;
    *) echo "usage: $0 [plain|mtp|both]" ; exit 1 ;;
esac
