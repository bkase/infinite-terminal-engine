# Host Shell Architecture

`host/DemoApp` is the canonical Step 1 host shell for the spatial terminal project.

## Decision

- Keep DemoApp and evolve it in place.
- Treat it as the real host scaffold, not a throwaway sample.
- Keep embedded Ghostty access behind `GhosttySurfaceAdapter`.

## Current shell shape

- Left pane: Metal canvas scaffold driven by `EngineRuntime`.
- Right pane: embedded Ghostty surface presented through `GhosttyTerminalPane`.
- Host overlays: shell status, adapter status, and published texture generation.

## Why this is the host path

- It loads the staged engine and shader artifacts used by the fast verification lane.
- It mounts the embedded terminal surface through the same adapter contract that later compositor work will consume.
- The existing host smoke path and Ghostty self-test already execute against this target.

## Next step handoff

Step 2 work should build on DemoApp by replacing placeholder canvas composition with real terminal-surface scene management rather than introducing a second host shell.
