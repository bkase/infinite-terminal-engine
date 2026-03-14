# Demo Signoff

Automated gate:

- `scripts/verify-demo.sh`

Manual checklist on Apple Silicon:

- Launch the app from a clean checkout with `swift run DemoApp`.
- Confirm the canvas appears and continuously redraws.
- Pan with normal scroll input.
- Zoom with pinch and with `Option` + scroll fallback.
- Resize the window repeatedly and confirm rendering stays live.
- Verify the stats pill updates and remains sane during interaction.
- Confirm `host/DemoApp/Resources/rect_fill.metallib` and `host/DemoApp/Resources/libengine.dylib` exist after staging.
- Leave the app running for several minutes and confirm it remains responsive.
