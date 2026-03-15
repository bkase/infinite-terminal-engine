# Collaborative Render Profiles

Authority:

- `host/DemoApp/Resources/RenderProfiles.json`

Current canonical profile:

- `collab-pragmata-v1`
- Regular/Bold/Italic assets: local PragmataPro Mono `09`
- Geometry contract at `14pt`: `cellWidth=7`, `lineHeight=16`, `padding=(10, 10)`, `titlebarHeight=28`

Validation rules:

- The host loads and validates every profile at startup.
- Missing local PragmataPro files fail closed with an explicit render-profile error overlay.
- Metric drift between the local PragmataPro asset and the manifest fails closed instead of silently changing collaborative geometry.

Local setup:

- Place `PragmataPro_Mono_R_09.ttf`, `PragmataPro_Mono_B_09.ttf`, and `PragmataPro_Mono_I_09.ttf` in `host/DemoApp/Resources/Fonts/`.
- These files are intentionally gitignored and must not be checked in.

Deterministic sizing:

- Surface pixel width = `ceil(((cols * cellWidth) + paddingX * 2) * backingScale)`
- Surface pixel height = `ceil(((rows * lineHeight) + paddingY * 2 + titlebarHeight) * backingScale)`

Test coverage:

- `host/Tests/DemoAppTests/RenderProfileTests.swift` loads all profiles, validates metric drift detection, and checks deterministic size derivation.
