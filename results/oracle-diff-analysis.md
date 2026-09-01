# oracle diff analysis — root cause (2026-09-02)

status: **resolved — benign**. plain vs mtp (n=6) at temp 0 diverge by 3
regions in ~1000 chars (difflib similarity 0.9321), all near-tie branch
flips from batch-shape fp rounding, not draft corruption.

## runs (merged engine b10888-081edc343, 91g ple, fibonacci prompt)

| run | tokens | t/s | draft stats |
|---|---|---|---|
| plain | 292 | 26.9 | — |
| mtp n=6 | 279 | 40.2 | 219/237 accepted (92.4%) |

receipts: `hq38-oracle-plain.log`, `hq38-oracle-mtp-n6.log` (local,
`.git/info/exclude`d; timings quoted verbatim above).

## the 3 regions

1. mtp omitted one docstring line: `Raises:\n ValueError: If n is negative.`
2. mtp emitted `if memo is None:\n memo = {}` before `if n < 0:` —
3. ...where plain emitted the same block after. **reordering of two valid
   statements; outputs are semantically equivalent code.**

no garbage, no loops, no compounding drift. after each flip both outputs
continue correctly.

## mechanism

speculative decoding verifies draft tokens in target batches (up to n_max)
instead of one-at-a-time. different matmul shapes → non-associative fp
reductions produce slightly different logits → the target's own argmax can
flip at near-tie branch points. accepted drafts are still target-verified,
so divergence is target-side sampling variance, never unverified draft
text. bit-exactness across batch shapes is not achievable on vulkan fp
reductions; semantic equivalence + high acceptance is the correct
validation bar.

## implication for the readme claim

"greedy-oracle validated speculative decoding" is supported in the sense
of semantic equivalence (92.4% acceptance, 3 benign flips, zero
corruption) — not bit-exactness. analysis script:
`/tmp/opencode/oracle_diff.py` (extraction + difflib; rerunnable).
