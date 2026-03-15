# Collaborative Render Profiles

Authority:

- `host/DemoApp/Resources/RenderProfiles.json`

Current canonical profile:

- `collab-pragmata-v1`
- Regular/Bold/Italic assets: PragmataPro Mono `09`
- Geometry contract at `14pt`: `cellWidth=7`, `lineHeight=16`, `padding=(10, 10)`, `titlebarHeight=28`

Validation rules:

- The host loads and validates every profile at startup.
- Missing font files fail closed with an explicit render-profile error overlay.
- Metric drift between the bundled PragmataPro asset and the manifest fails closed instead of silently changing collaborative geometry.

Deterministic sizing:

- Surface pixel width = `ceil(((cols * cellWidth) + paddingX * 2) * backingScale)`
- Surface pixel height = `ceil(((rows * lineHeight) + paddingY * 2 + titlebarHeight) * backingScale)`

Test coverage:

- `host/Tests/DemoAppTests/RenderProfileTests.swift` loads all profiles, validates metric drift detection, and checks deterministic size derivation.
