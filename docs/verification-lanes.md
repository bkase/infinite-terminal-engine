# Verification Lanes

The project now has four canonical verification entrypoints:

- `scripts/verify-fast.sh`: authoritative fast gate used by `scripts/verify-commit.sh` and the pre-commit hook
- `scripts/verify-slow.sh`: expanded release-readiness lane with observability, N=50 stress, multiplayer, replay, security, packaging, and release build checks
- `scripts/verify-soak.sh`: bounded reconnect/session-churn lane; set `ITE_SOAK_ITERATIONS` to tune the repeat count
- `scripts/verify-demo.sh`: demo signoff lane that runs the slow lane plus the real DemoApp startup self-test

## Retained evidence

Each lane writes retained logs and a summary under:

```text
artifacts/verification-lanes/<lane>/<run-id>/
```

Every run keeps:

- `transcripts/checks.jsonl`: per-step pass/fail rollup with retained log paths
- `summaries/summary.json`: lane status and step counts
- `logs/*.log`: captured stdout/stderr for each verification step

This keeps the fast hook focused while giving slow/soak/demo runs retained evidence instead of only console scrollback.

## Expected usage

Use these lanes in order:

1. `scripts/verify-fast.sh`
2. `scripts/verify-slow.sh`
3. `scripts/verify-demo.sh`

Run `scripts/verify-soak.sh` when you need bounded reconnect churn evidence before a demo or release cut.
