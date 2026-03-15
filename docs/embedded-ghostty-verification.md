# Embedded Ghostty Verification Matrix

This matrix captures the current Step 1 verification state for embedded Ghostty behavior in the host shell.

## Automated coverage

| Behavior | Coverage | Notes |
| --- | --- | --- |
| Adapter init / render / resize / shutdown | `scripts/test-ghostty-surface-adapter.sh` | Uses the embedded mock-loopback shell path. |
| Texture publish / swap | `TerminalTexturePublisherTests` + self-test | Front texture stays stable until publish completion and resizes swap only after a new-size publish. |
| Keyboard translation smoke | `InputNormalizerTests` | Covers printable keys, special keys, and bracketed/unbracketed paste payloads. |
| Selection copy smoke | `GhosttySurfaceSelfTest` | Uses `select_all`, reads the embedded selection, and copies it to the macOS pasteboard. |
| Paste-request smoke | `GhosttySurfaceSelfTest` | Uses `paste_from_clipboard` through the embedded binding action and validates loopback echo. |
| IME anchor exposure | `GhosttySurfaceSelfTest` | Verifies `ghostty_surface_ime_point` is reachable through the adapter. |
| Cursor / timer redraw smoke | `GhosttySurfaceSelfTest` | Verifies published texture generations advance under adapter tick/render activity. |

## Manual checks

These still require hands-on validation on an Apple Silicon machine because they depend on native services that are not reliable to automate in this repo:

| Behavior | Manual check |
| --- | --- |
| IME composition | Confirm marked-text composition, candidate windows, commit, and cancel flows in the embedded terminal view. |
| Password prompt / secure-input-adjacent flows | Confirm focus, typing, and paste behavior remain sane in a password prompt such as `sudo -k && sudo true`. |
| Cursor blink fidelity | Confirm the visible cursor continues to blink and redraws remain smooth when the terminal is idle. |
| Clipboard confirmation UX | Confirm host pasteboard reads/writes behave acceptably for real user copy/paste flows. |

## Current status

- The embedded path now has automated smoke coverage for selection, host-mediated clipboard copy/paste, resize-safe publishing, and IME anchor plumbing.
- IME composition and secure-input-adjacent behavior are documented as manual sign-off items and should not be treated as implicitly verified by the automated lane alone.
