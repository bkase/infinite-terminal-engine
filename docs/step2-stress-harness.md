# Step 2 Stress Harness

`bd-34g` defines the bounded `N=50` proof for the Step 2 compositor.

## What it measures

- mixed-size `N=50` scene visibility and approximate texture memory
- heavy-overlap occlusion skip behavior
- camera-motion render timing with real Metal quads and dummy textures
- multi-surface publish churn through the front/back publish state machine

## Captured thresholds

- room budget: must remain below [`TextureBudgetPolicy.roomBudgetBytes`](../host/DemoApp/TextureBudgetPolicy.swift)
- mixed-size visible-list build: average below `2000 us`
- camera-motion render: average below `16 ms`
- heavy overlap: `49` of `50` surfaces should be skipped as fully occluded
- publish churn: `50 * 20` publish completions with final generation `20`

These are deliberately conservative local/demo thresholds. They are intended to catch structural regressions before Step 4 multiplies the number of active surfaces and textures.

## Run

```bash
./scripts/test-step2-stress.sh
```

The harness lives in `CompositorStressHarnessTests` and uses the same DemoApp scene/compositor code path that Step 2 depends on.
