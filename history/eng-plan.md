# Spatial Terminal Canvas V1 — Engineering Architecture

## 1. Executive summary

V1 is a **native macOS collaborative spatial terminal environment**. The only first-class canvas object is a terminal surface. Spatial state is authoritative, durable, and sequenced by a room service. Terminal IO is **not** sequenced through that room service. Instead, terminal bytes flow on a separate low-latency data plane directly between the client and a server-side PTY session service. Each client renders terminal pixels locally with embedded **full `libghostty`** into offscreen Metal textures, and the canvas renderer composites those textures with a simple Metal quad pipeline. This leans on three proven facts: Figma’s multiplayer service is authoritative for validation, ordering, and conflict resolution; Figma improved durability by adding a journal / write-ahead log beside checkpoints; and Ghostty’s architecture already uses a C-ABI `libghostty` core that the macOS app consumes, with Metal on macOS. Ghostty’s own docs also say `libghostty` is not yet a stable standalone API, so this integration must be treated as a pinned vendor dependency behind a local compatibility layer. ([Figma][1])

The decisive architectural choice is the **dual-plane split**:

- The **control plane** owns room membership, spatial layout, terminal creation and attachment, z-order, resize, control leases, and durability.
- The **data plane** owns PTY input/output byte streams and nothing else.

That split exists to protect typing latency. Panning, moving, resizing, or reordering a terminal may take a control-plane round trip and WAL commit. Keystrokes may not. The room service is allowed to be authoritative and durable because it governs slow-changing spatial truth. The terminal plane must stay direct and thin because it governs human typing and shell feedback.

The renderer is intentionally ordinary. Apple’s guidance emphasizes bandwidth, resolution choices, and minimizing non-opaque overdraw; ProMotion and variable-refresh displays also mean the frame loop must be correct across varying cadences rather than assuming a hard fixed 120 Hz. For V1, the right response is a boring one: keep the terminal scene bounded, keep the compositor simple, reuse textures aggressively, and let most frames merely move and sample existing quads. ([Apple Developer][2])

## 2. Scope, non-goals, and the product boundary

The product boundary is now much narrower than the original research plan:

1. **Platform**
   V1 targets **native macOS on Apple Silicon**. This is the path most aligned with Ghostty’s public macOS + Metal architecture and with the explicit decision to make Metal the source rendering API. Ghostty publicly documents a macOS app that consumes `libghostty` through a C API and uses Metal on macOS; it does not present a stable standalone `libghostty` release, nor does it present iOS/iPadOS embedding as a mature public target. That makes macOS the responsible first platform. This is an inference from the public docs, not a claim that other platforms are impossible. ([Ghostty][3])

2. **Scene model**
   V1 has exactly one durable scene primitive: **TerminalSurface**. There are no arbitrary vector objects, no general document graph, no embedded canvases, no rich text blocks, and no compute-driven text system.

3. **Geometry**
   V1 uses a **flat surface set**, not a general tree. Surfaces are axis-aligned rectangles in world space. The camera supports pan and zoom, but surfaces do not rotate or skew. This is a deliberate simplification: we want the sequencing, durability, and collaboration lessons from Figma, not the full complexity of collaborative tree editing where Figma had to solve cycle rejection and atomic parent/order updates. ([Figma][4])

4. **Rendering**
   V1 uses a **quad compositor**, not a compute scene engine. No Vello-style scene encoding, no GPU BVH, no global text atlas, no shader portability work, no WebGPU, no WGSL, no SPIR-V portability layer.

5. **Collaboration model**
   V1 is **authoritative-server multiplayer**, not peer-to-peer and not fully local-first. The user experience should still be immediate for local spatial interactions, but durable truth for the room comes from the server. The local-first literature is useful as a warning and as UI inspiration; it is not the authority model we are choosing here. ([Martin Kleppmann's Website][5])

6. **Terminal semantics**
   V1 uses **full `libghostty` on the client** for terminal emulation and rendering. We are not building a custom terminal engine, not extracting glyph runs for the compositor, and not reimplementing Ghostty’s behavior.

7. **Scale target**
   V1 is optimized for **tens of terminals per room**, not thousands. The working ceiling is approximately **50 surfaces**. That ceiling is not an aspiration; it is a design constraint that lets us move culling to the CPU, keep all visible textures resident, and avoid premature GPU scene machinery.

## 3. Core architectural thesis

The whole system reduces to one sentence:

**Use an authoritative durable room kernel for spatial state, a direct PTY byte-stream data plane for terminal state, embedded full `libghostty` instances as local pixel producers, and a simple native Metal texture compositor as the only renderer.**

Every other decision follows from that sentence.

The consequences are important:

- The room log is the source of truth for **what exists and where it is**.
- The PTY session is the source of truth for **what the terminal process emits**.
- The local Ghostty adapter is the source of truth for **how those bytes become pixels on this client**.
- The Metal compositor is only the source of truth for **the final screen image this frame**.

That separation keeps durability, interactive latency, and rendering complexity from collapsing into a single knot.

## 4. System topology

The runtime is composed of four major subsystems:

### 4.1 Client application

The native client contains:

- `CanvasHost`
- `RoomClient`
- `InputRouter`
- `GhosttySurfaceAdapter[N]`
- `SurfaceManager`
- `MetalCompositor`
- `PresenceClient`
- `ControlLeaseClient`

`CanvasHost` owns the main window, camera, native chrome, and the Metal view. `RoomClient` speaks to the authoritative room service. `InputRouter` decides whether an event belongs to the control plane or the data plane. `GhosttySurfaceAdapter` wraps one embedded `libghostty` instance per attached terminal surface. `SurfaceManager` stores the flat scene in data-oriented arrays. `MetalCompositor` draws offscreen terminal textures to the screen.

### 4.2 Room service

The room service contains:

- `RoomGateway`
- `RoomActor`
- `RoomJournal`
- `RoomSnapshotStore`
- `PresenceHub`
- `ControlLeaseRegistry`

Each room is a single-writer actor. The actor is authoritative for surface creation, deletion, movement, resize, z-order, and control-lease assignment. It persists accepted operations to a WAL / journal and periodically writes snapshots, following the same broad durability pattern Figma describes for its multiplayer service. Figma’s public write-up is particularly relevant here: an authoritative in-memory multiplayer service is fast, but without a journal it leaves too much durability risk between checkpoints. ([Figma][1])

### 4.3 Terminal session service

The terminal session service contains:

- `TerminalGateway`
- `SessionDirectory`
- `SessionActor`
- `PTYBackend`
- `SubscriberFanout`
- `BootstrapProvider`

Each terminal session is also a single-writer actor. It owns the authoritative server-side PTY process or multiplexer-backed session, the live subscriber set, the output sequence counter, and the current control lease holder.

The critical product requirement for this service is **late-join bootstrap**. A new client cannot be forced to have watched a terminal from the instant it was created. Therefore the PTY backend must be able to emit a **bootstrap redraw** for a newly subscribing client, then continue with live bytes. This can be implemented with a tmux-like backend, a custom daemon, or a future state-mirror utility. The client still only consumes bytes.

### 4.4 Storage

V1 storage is intentionally mundane:

- `room_ops(room_id, room_seq, op_id, client_id, ts, payload)`
- `room_snapshots(room_id, room_seq, checksum, state_blob, ts)`
- `terminal_sessions(session_id, room_id, surface_id, status, cols, rows, bootstrap_policy, ts)`
- `control_leases(session_id, holder_user_id, lease_epoch, expires_at)`

A relational database such as Postgres is sufficient for V1 because room state is small. There is no reason to introduce exotic storage for a flat set of ~50 terminal surfaces.

## 5. Authority boundaries and state classes

The most important clarification in the revised design is that **not all state belongs in the room**.

| State class                 | Examples                                                                          | Authority                  | Durability                      |
| --------------------------- | --------------------------------------------------------------------------------- | -------------------------- | ------------------------------- |
| Durable room state          | surface existence, position, `cols/rows`, z-order, session attachment, profile ID | Room actor                 | WAL + snapshots                 |
| Ephemeral shared room state | presence cursor, viewport, selected surface, control lease display                | Room actor or presence hub | No durable persistence required |
| Terminal session state      | PTY process, output byte order, exit status, bootstrap redraw source              | Session actor              | Session-local durability policy |
| Local derived state         | Metal textures, visible list, cull results, local hover, cached mip state         | Client                     | Not durable                     |

This split is the precise answer to the “input latency vs sequencer” concern. A terminal keystroke is not room state. A terminal move is.

## 6. The flat room model

The original plan still carried some of the shape of a general collaborative editor. That is no longer necessary. V1 does **not** need a tree. It needs a flat ordered surface set.

### 6.1 Durable room schema

A room snapshot may be modeled as:

```text
RoomState {
  room_id: UUID
  room_seq: u64
  surfaces: [TerminalSurface]
  render_profiles: [TerminalRenderProfile]
}
```

Each surface is:

```text
TerminalSurface {
  surface_id: UUID
  session_id: UUID?          // null while provisioning
  x_world: f64
  y_world: f64
  cols: u16
  rows: u16
  stack_rank: u16            // authoritative total order
  profile_id: u16
  title: String?
  state: enum {
    Provisioning,
    Attached,
    Disconnected,
    Error,
    Closing
  }
  created_by: UserId
  created_at_ms: u64
}
```

Each render profile is:

```text
TerminalRenderProfile {
  profile_id: u16
  font_asset_id: String
  font_size_pt: f32
  line_height_mult: f32
  cell_width_pt: f32
  cell_height_pt: f32
  padding_x_pt: f32
  padding_y_pt: f32
  titlebar_height_pt: f32
  theme_id: String
  ligatures: bool
}
```

### 6.2 Why `cols` and `rows` are durable

The key change here is that terminal size is authoritative in **cells**, not arbitrary pixels.

That solves several collaboration problems at once:

- all viewers see the same logical terminal size;
- PTY resize semantics are deterministic;
- late-join clients know the canonical session dimensions;
- multiple viewers cannot silently diverge because of different local font metrics.

The outer rectangle in world space is derived from `cols`, `rows`, and the canonical render profile. Resizing is therefore cell-snapped. During an interactive resize drag, the client may preview the frame continuously, but the durable operation is “resize to 132x40”, not “resize to 918.3 points wide”.

### 6.3 Canonical render profiles are mandatory

Because rendering is client-side, **font and metric drift would otherwise break visual consistency**. Ghostty on macOS uses CoreText and native platform rendering, which is good for quality, but it also means you cannot rely on each client’s arbitrary local font configuration if you want deterministic collaborative layout. ([GitHub][6])

Therefore V1 requires:

- bundled canonical monospaced font assets;
- profile IDs stored in room state;
- fixed terminal paddings and chrome metrics;
- no per-user overrides for collaborative surfaces.

If a font asset is unavailable or invalid, the surface fails closed and displays an explicit error rather than silently falling back to different metrics.

## 7. Control plane architecture

### 7.1 Room actor model

Each room is a single-threaded logical actor. Its responsibilities are:

- validate operations;
- assign monotonically increasing `room_seq`;
- apply state transitions;
- persist journal entries;
- broadcast accepted operations;
- trigger side effects toward the terminal service;
- serve snapshots and replay.

The Figma model matters here: the multiplayer service is authoritative, in-memory, validates and orders updates, and uses durability mechanisms to protect against loss between checkpoints. That is the exact class of problem we are solving for spatial state. ([Figma][1])

### 7.2 Operation set

The durable operation vocabulary is intentionally small:

```text
CreateSurface(surface_id, x, y, cols, rows, profile_id, terminal_template)
MoveSurface(surface_id, x, y)
ResizeSurface(surface_id, cols, rows)
SetStackRank(surface_id, target_rank)
CloseSurface(surface_id)
SetSurfaceTitle(surface_id, title)
AttachSession(surface_id, session_id)
DetachSession(surface_id)
AcquireControl(session_id)
ReleaseControl(session_id)
```

Notably absent:

- no glyph updates;
- no text edits;
- no terminal output diffs;
- no texture state;
- no camera state in WAL;
- no transient hover state.

### 7.3 Optimistic local application

Spatial interactions should still feel immediate. The control-plane algorithm is:

1. Client generates `op_id`.
2. Client applies the op locally to its predicted room state.
3. Client sends the op to the room service.
4. Server validates and assigns `room_seq`.
5. Server broadcasts accepted op or returns rejection.
6. Client reconciles by rebasing pending optimistic ops onto the authoritative stream.

This borrows the responsiveness lesson from local-first systems while still keeping the server as durable authority for room truth. Local-first literature frames the alternative explicitly: in a server-centric model, the server is the authoritative copy; in a local-first model, the device copy is primary. V1 chooses the former for shared spatial state. ([Martin Kleppmann's Website][5])

### 7.4 Durability

Room durability follows a simple pattern:

- Every accepted op is appended to `room_ops`.
- Periodically, or after `N` ops, the room writes `room_snapshots`.
- Snapshot records include the `room_seq` they correspond to.
- On recovery: load latest snapshot, then replay journal entries with `room_seq > snapshot_seq`.

This is directly analogous to the Figma journal + checkpoint design: authoritative in-memory state remains fast, but the journal shrinks the loss window and makes recovery deterministic. ([Figma][1])

### 7.5 Reorder semantics

Because the room is flat and bounded, `stack_rank` can be handled simply:

- maintain a dense 0..N-1 total order;
- on reorder, rewrite ranks of affected surfaces;
- persist the resulting order.

There is no need for fractional indexing in V1. Figma needed more complex ordering machinery because of collaborative trees and fine-grained property concurrency. We do not.

### 7.6 Presence and viewport

Per-user camera position, collaborator cursor, and local selection are **not durable room truth**. They are presence state. The room service may relay them, but it does not persist them in the WAL. This keeps the journal clean and replayable.

### 7.7 Formal invariants

TLA+ belongs here, but not before Step 1 and Step 2 prove the Ghostty/Metal boundary. Once the renderer path is real, TLA+ should model:

- `room_seq` monotonicity;
- uniqueness of `surface_id`;
- total order over `stack_rank`;
- one session attached per surface;
- at most one active control lease per session;
- idempotent op replay by `op_id`;
- snapshot replay equivalence.

The formal model should cover the control plane only. The data plane is a streaming system with different concerns.

## 8. Data plane architecture

### 8.1 The hard rule

**Terminal keystrokes, paste, mouse reporting, and shell IO do not pass through the room sequencer.**

That is the most important correction from the feedback.

If terminal keystrokes had to wait for room ordering, WAL append, validation, and broadcast, typing would inherit the latency profile of the control plane. That would destroy the terminal feel.

### 8.2 Session actor model

Each terminal session is represented by a `SessionActor`:

```text
SessionActor {
  session_id: UUID
  room_id: UUID
  surface_id: UUID
  cols: u16
  rows: u16
  control_holder: UserId?
  lease_epoch: u64
  output_seq: u64
  subscribers: Map<ClientId, Subscriber>
  backend: PTYBackend
  status: enum {Provisioning, Running, Exited, Failed}
}
```

The session actor is authoritative for:

- PTY lifecycle;
- byte output ordering per session;
- current session size;
- subscriber set;
- control-holder validation;
- bootstrap redraw on subscribe.

### 8.3 Bootstrapping new subscribers

This is the central data-plane requirement.

When a client subscribes to a terminal session, the server must provide:

1. a **bootstrap redraw** that reconstructs current terminal state on a fresh local `libghostty` instance;
2. a stream anchor, `output_seq_boot`;
3. the ordered live byte stream after that point.

The client algorithm is:

1. create empty `GhosttySurfaceAdapter(profile, cols, rows)`;
2. feed bootstrap bytes;
3. subscribe to live output at `output_seq_boot + 1`;
4. continue normal streaming.

The implementation behind “bootstrap redraw” is deliberately abstract in the architecture. A tmux-like multiplexer, a custom PTY daemon, or a future state mirror is acceptable. What matters is the observable guarantee: new viewers can join an existing session and receive a coherent byte-stream bootstrap followed by live bytes.

### 8.4 Session transport

For V1, use **a dedicated WebSocket per subscribed terminal session**. That keeps the mental model consistent with the feedback and simplifies per-session backpressure, teardown, auth, and diagnostics. A future multiplexed transport is possible, but it is not worth the first-round complexity.

Data-plane messages are binary and session-local:

```text
C->S  Auth(token, session_id, lease_epoch)
C->S  InputBytes(client_input_seq, bytes)
S->C  Bootstrap(output_seq_start, output_seq_end, bytes)
S->C  Output(output_seq_start, bytes)
S->C  Status(status, exit_code?)
S->C  LeaseRevoked(lease_epoch)
```

Because the underlying transport is reliable and ordered, `output_seq` exists mainly for reconnect logic, observability, and sanity checks.

### 8.5 Input translation belongs to Ghostty

A terminal does not just forward raw keyboard events. Special keys, mouse reporting, bracketed paste, application cursor mode, kitty keyboard protocol, and similar behaviors depend on terminal state. That state already lives in the local Ghostty instance because it is consuming the server’s output bytes.

Therefore the client pipeline is:

1. native key / text / mouse event enters `InputRouter`;
2. if the event targets terminal content, it is delivered to `GhosttySurfaceAdapter`;
3. the adapter translates it into output bytes according to current terminal mode;
4. those bytes are sent directly to the session WebSocket.

This is a crucial requirement for the embedding layer. If the public `libghostty` API does not expose enough input-translation surface, we must carry a vendored fork or compatibility shim. `libghostty` publicly claims terminal emulation, font handling, and rendering capabilities, but the API is not yet documented as stable. ([Ghostty][3])

### 8.6 Control leases

To avoid multi-user typing chaos, V1 enforces **one writer per terminal session**.

The protocol is:

- user clicks or explicitly requests control;
- client sends `AcquireControl(session_id)` through the room control plane;
- room actor grants lease if free, increments `lease_epoch`, broadcasts lease owner;
- data-plane input is accepted only if the session WebSocket is authenticated with the current `lease_epoch`.

The lease itself is control-plane state because it is shared room behavior. The resulting keystrokes are data-plane traffic.

### 8.7 Resize semantics

Resizing is split cleanly:

- drag and preview are local UI behavior;
- authoritative resize is a control-plane op;
- PTY `winsize` changes only after authoritative commit.

The algorithm is:

1. User drags edge or corner.
2. Client previews snapped `cols/rows`.
3. Client sends `ResizeSurface(surface_id, cols, rows)`.
4. Room actor accepts and persists.
5. Room actor emits a side-effect command to `SessionActor`.
6. Session actor updates PTY size.
7. PTY-backed application redraws.
8. Clients receive output bytes and rerender.

This avoids resize thrash, keeps the room authoritative, and prevents transient client-only terminal dimensions from diverging.

### 8.8 Synchronized terminal updates

Ghostty’s docs note that terminal applications such as Neovim use synchronized rendering to avoid tearing across updates. That means the byte stream must be preserved exactly per session and never interleaved or reordered with other sessions. The data plane is therefore strictly per-session ordered. ([Ghostty][3])

## 9. Client architecture in detail

### 9.1 Main subsystems

The client process contains five hot-path managers:

- `RoomReplica`
- `SurfaceManager`
- `GhosttyManager`
- `InputRouter`
- `FrameScheduler`

`RoomReplica` stores the current authoritative room state plus pending optimistic ops. `SurfaceManager` stores the flat scene in SoA form. `GhosttyManager` owns the adapter instances and texture front/back sets. `InputRouter` arbitrates control vs terminal events. `FrameScheduler` decides when to redraw the Metal view.

### 9.2 Data-oriented storage

Because N is bounded and the scene is flat, SoA is the right storage shape:

```text
ids:            [SurfaceId]
session_ids:    [SessionId]
x_world:        [f64]
y_world:        [f64]
cols:           [u16]
rows:           [u16]
profile_id:     [u16]
stack_rank:     [u16]
flags:          [u32]
index_of:       HashMap<SurfaceId, usize>
draw_order:     [usize]
```

This layout makes CPU culling, hit-testing, snapshot serialization, and rank rewrites trivial.

### 9.3 Threads and queues

V1 should use a conservative threading model:

- Main/UI thread:
  - native window events
  - camera updates
  - high-level state changes

- Room network queue:
  - WebSocket receive/send
  - optimistic reconciliation

- Session network queues:
  - one per subscribed terminal session, or a small pooled reactor

- Ghostty worker queue:
  - inbound byte ingestion
  - surface-local render scheduling

- Metal submission queue:
  - owns the command queue and all command-buffer commits

The single most important rendering rule is: **one subsystem owns Metal submission**. Even if work is prepared elsewhere, command-buffer creation and commit should be serialized through one render authority in V1. That removes an entire class of queue-ordering bugs.

## 10. The Ghostty embedding layer

### 10.1 Why this is the first prototype

This is the highest-risk unknown. Ghostty’s public docs confirm that `libghostty` exists, that the macOS app consumes it through a C API, and that `libghostty` is not yet a stable public standalone API. What the docs do **not** publicly promise is a ready-made, stable offscreen render-to-user-`MTLTexture` embedding path with all of the APIs a spatial terminal canvas needs. That is why the Ghostty bridge must come first. ([Ghostty][3])

### 10.2 Required adapter contract

The local compatibility layer should present a narrow host-side interface:

```text
GhosttySurfaceAdapter {
  init(profile_id, cols, rows, metal_device, backing_scale)
  ingest_output(bytes)
  handle_key(native_key_event) -> bytes[]
  handle_text_input(text) -> bytes[]
  handle_mouse(native_mouse_event) -> bytes[]?
  resize(cols, rows, backing_scale)
  tick(now_ms)                 // for cursor blink / timers
  request_render()
  latest_front_texture() -> TextureHandle?
  latest_texture_generation() -> u64
  selection_state() -> LocalSelection
  copy_to_clipboard()
  paste_request() -> bytes[]
  shutdown()
}
```

The host should never know Ghostty internals. It only knows that the adapter consumes PTY output, produces PTY input, and publishes rendered textures.

### 10.3 Offscreen rendering requirement

The preferred path is:

- Ghostty renders into application-managed offscreen `MTLTexture` targets;
- no hidden windows;
- no `CAMetalLayer` capture hacks in the steady-state architecture.

If direct render-to-texture is unavailable, fallback order is:

1. **Preferred fallback:** Ghostty renders into an offscreen layer-like surface controlled by the adapter, then blits into compositor-owned textures.
2. **Last-resort prototype fallback:** hidden window/layer capture used only to prove terminal semantics, never as shipping architecture.

The project should not proceed beyond Step 1 unless at least the preferred path or preferred fallback is shown to work reliably.

### 10.4 Native integration risks that must be proven

Ghostty’s public docs highlight native platform integrations on macOS, including secure input and other native behaviors. Offscreen embedding changes the host environment substantially. Step 1 must prove the following behaviors in embedded mode, not assume them: keyboard translation, mouse reporting, copy/paste, selection, IME/text input, cursor blink, resize, and secure-input-adjacent behaviors for password prompts. ([Ghostty][3])

### 10.5 Vendoring policy

Because `libghostty` is not yet a stable standalone API, V1 should use:

- a pinned Ghostty commit;
- a narrow internal wrapper crate/module;
- zero raw `libghostty` calls outside that wrapper;
- a compatibility test suite that runs against the pinned commit.

That wrapper is part of the core product, not an incidental helper.

## 11. Metal compositor architecture

### 11.1 Renderer shape

The compositor is a straightforward graphics pipeline:

1. build visible surface list on CPU;
2. write one instance record per visible terminal quad;
3. bind terminal textures;
4. issue instanced quad draws;
5. draw minimal overlays (selection outline, control-owner badge, drop shadow if enabled);
6. present.

No compute pipeline is required for V1.

### 11.2 Geometry model

Each visible surface produces one rectangle:

```text
InstanceData {
  screen_x0, screen_y0
  screen_x1, screen_y1
  uv_x0, uv_y0
  uv_x1, uv_y1
  opacity
  clip_rect
  layer_flags
  texture_index
}
```

Terminals are axis-aligned. That allows:

- trivial hit-testing;
- trivial clipping;
- trivial CPU frustum rejection;
- trivial z sort.

### 11.3 Opaque and translucent passes

The feedback correctly points out that overlapping translucent quads can become bandwidth-heavy even at N=50. Apple’s own performance guidance emphasizes minimizing non-opaque overdraw. Therefore V1 should architecturally prefer **opaque terminal bodies**. ([Apple Developer][2])

The pass structure should be:

- **Pass A:** opaque terminal bodies, front-to-back or batched by z;
- **Pass B:** optional translucent overlays only if needed.

If per-surface translucency is optional, keep it off by default. Do not make window backgrounds half-transparent in V1.

### 11.4 CPU culling and occlusion

For N≈50, CPU-side culling is enough:

1. compute view rect in world space;
2. iterate SoA arrays;
3. reject surfaces outside view rect;
4. sort survivors by `stack_rank`;
5. optionally perform conservative opaque occlusion skip.

The occlusion algorithm can be simple:

- walk surfaces front-to-back;
- maintain a coarse covered region of opaque rectangles;
- skip any surface fully covered by earlier opaque surfaces;
- do not attempt partial rectangle splitting in V1.

This is cheap, deterministic, and easy to debug.

### 11.5 Frame pacing

The compositor must be display-cadence aware rather than fixed-120 ideology driven. Apple’s public guidance on ProMotion and variable-refresh-rate displays explicitly emphasizes dynamic timing and correct pacing under multiple effective frame rates. V1 therefore targets “draw when needed, draw smoothly, and reuse previous terminal textures whenever terminal content has not changed.” ([Apple Developer][7])

### 11.6 Draw scheduling

The client should redraw when any of the following occurs:

- camera changed;
- surface position/order changed;
- a surface published a new front texture;
- a Ghostty surface timer fired (cursor blink, etc.);
- selection/control overlay changed.

When nothing changes, the Metal view should idle.

## 12. Texture ownership, synchronization, and queue discipline

### 12.1 The steady-state rule

The compositor must never sample a texture that Ghostty is still writing.

The simplest correct V1 solution is:

- **shared Metal command queue** owned by the client render subsystem;
- **double-buffered textures per terminal surface**;
- compositor samples only the current **front** texture;
- Ghostty renders only into the current **back** texture;
- front/back swap only after GPU completion.

This design largely sidesteps explicit fence usage in steady state.

### 12.2 Per-surface texture state

Each surface owns:

```text
SurfaceTextureState {
  front_tex: MTLTexture?
  back_tex: MTLTexture?
  spare_tex: MTLTexture?    // optional during resize/realloc
  front_generation: u64
  back_generation: u64
  front_ready: bool
  resize_pending: bool
}
```

### 12.3 Publish protocol

The publish path is:

1. Ghostty adapter encodes render into `back_tex`.
2. Command buffer is committed through the render authority.
3. A command-buffer completion handler marks `back_tex` ready.
4. On the CPU, atomically swap `front_tex <-> back_tex`.
5. Increment `front_generation`.
6. Request a compositor redraw.

Apple documents command-buffer completion handlers precisely for CPU-side notifications when GPU work is complete, which is exactly what we need here. ([Apple Developer][8])

### 12.4 Why a shared queue first

Apple’s resource synchronization guidance says to coordinate conflicting accesses with barriers, fences, or events, and Apple separately documents fences and event-based synchronization for queue/pipeline dependencies. Those are real tools, but a V1 that can avoid cross-queue ownership should avoid it. Shared queue plus double buffering is easier to reason about than multiple queues plus explicit producer/consumer synchronization. ([Apple Developer][9])

### 12.5 When to use fences or events

Use explicit Metal synchronization only if the Ghostty integration forces it.

Guideline:

- **Same queue, same resource, ordered passes:** prefer queue ordering or `MTLFence` if truly necessary.
- **Different queues or forced producer/consumer dependencies:** use the event/barrier mechanism appropriate to the platform and queue model.
- **If a queue dependency is causing the compositor to stall:** do not block the compositor waiting for a terminal update. Compose from the previous front texture and let the new frame land next tick.

The performance principle is simple: **staleness beats stalls** for terminal surfaces. Seeing the previous terminal frame for one extra display interval is acceptable. Freezing the whole canvas is not.

### 12.6 Resize synchronization

Resize is the exceptional case:

1. authoritative `cols/rows` changes arrive;
2. adapter allocates new front/back textures sized for the new grid and backing scale;
3. old front texture remains valid for composition until the first new-size render completes;
4. after first publish, old textures are released.

This avoids blanking on resize.

## 13. Texture sizing, zoom policy, and VRAM budgeting

### 13.1 Canonical sizing

For a surface with profile metrics:

```text
surface_width_pt  = cols * cell_width_pt  + 2*padding_x_pt
surface_height_pt = rows * cell_height_pt + 2*padding_y_pt + titlebar_height_pt
texture_width_px  = round(surface_width_pt  * device_backing_scale)
texture_height_px = round(surface_height_pt * device_backing_scale)
```

The texture is sized for canonical terminal layout, not for arbitrary camera zoom.

### 13.2 Zoom policy

V1 zoom policy is intentionally simple:

- zooming **out** uses bilinear filtering;
- optional mipmaps are allowed only if memory budget permits;
- zooming **in** initially magnifies the texture geometrically;
- if high zoom-in proves visually unacceptable, add threshold-based rerasterization later.

This keeps V1 honest: the camera is not yet a semantic zoom system.

### 13.3 Memory formula

For `BGRA8`-class textures, approximate memory per surface is:

```text
bytes = width_px * height_px * 4 * buffer_count * mip_factor
```

Where:

- `buffer_count = 2` for front/back;
- `mip_factor ≈ 1.0` without mips;
- `mip_factor ≈ 4/3` with full mip chains.

### 13.4 Example budgets

These are straightforward engineering estimates:

| Texture size | 1 texture | 2 textures | 2 textures + mips | 50 surfaces, 2 textures | 50 surfaces, 2 textures + mips |
| ------------ | --------: | ---------: | ----------------: | ----------------------: | -----------------------------: |
| 1280×800     |    3.9 MB |     7.8 MB |           10.4 MB |                390.6 MB |                       520.8 MB |
| 1600×1000    |    6.1 MB |    12.2 MB |           16.3 MB |                610.4 MB |                       813.8 MB |
| 1920×1200    |    8.8 MB |    17.6 MB |           23.4 MB |                878.9 MB |                      1171.9 MB |
| 2048×1280    |   10.0 MB |    20.0 MB |           26.7 MB |               1000.0 MB |                      1333.3 MB |

The practical consequence is obvious: **mipmaps cannot be default-on for every large terminal surface in V1**. They should be off initially, or enabled selectively only for large, frequently minified surfaces.

### 13.5 Product-level constraints from the budget

From the table above, V1 should enforce these limits:

- room ceiling ≈ 50 surfaces;
- bundled terminal profiles only;
- opaque backgrounds by default;
- mipmaps off initially;
- no giant arbitrarily resizable surfaces without quota;
- evict or downscale offscreen textures only after real measurements show need.

Apple’s own performance guidance reinforces that memory bandwidth and overdraw are first-order costs in Metal apps. ([Apple Developer][2])

## 14. Input routing in detail

### 14.1 Gesture arbitration

Every pointer and keyboard event passes through one routing function:

```text
route(event):
  target = hit_test_topmost_surface(event.position)
  if target == none:
      return CanvasControlPlane
  if event.position in surface_chrome(target):
      return SurfaceControlPlane(target)
  else:
      return TerminalDataPlane(target)
```

### 14.2 Control-plane inputs

These include:

- camera pan/zoom;
- surface drag;
- surface resize;
- surface reorder;
- control-lease request;
- close/open actions.

These are optimistic locally, then sequenced.

### 14.3 Data-plane inputs

These include:

- typing;
- paste;
- terminal-local mouse reporting;
- wheel events when terminal content owns scroll;
- bracketed paste;
- escape-sequence-generating special keys.

These go to Ghostty first for translation, then directly to the PTY session.

### 14.4 Clipboard and selection

Selection is local terminal state. Copy/paste are host-mediated conveniences. The control plane should not persist or sequence clipboard contents or selection ranges.

### 14.5 IME and text services

IME is a Step 1 gating item, not a Phase 7 afterthought. If offscreen embedding breaks native text composition, the product cannot claim to be a serious terminal environment. This must be proven in the Ghostty bridge prototype.

## 15. Room-service side effects and reconciliation

A useful way to think about the room actor is that it owns **desired spatial truth**, while the terminal service owns **actual PTY execution**.

Examples:

### 15.1 Create surface

1. Client sends `CreateSurface`.
2. Room actor persists surface in `Provisioning`.
3. Room actor emits `StartSession(surface_id, cols, rows, profile/template)` side effect.
4. Terminal service creates session.
5. Room actor receives success callback and persists `AttachSession(surface_id, session_id)`.

If terminal creation fails, the surface remains in durable room state as `Error` rather than disappearing.

### 15.2 Resize surface

1. Room actor persists new `cols/rows`.
2. Side effect sent to `SessionActor`.
3. Session actor resizes PTY backend.
4. Clients eventually receive redraw bytes.

The room log records what size the session **should** be, even if the side effect temporarily lags.

### 15.3 Close surface

1. Room actor persists removal.
2. Side effect closes or detaches session according to session policy.
3. Session actor tears down subscribers.

This pattern makes the room log the desired configuration ledger.

## 16. Networking and reconnect behavior

### 16.1 Room reconnect

On room reconnect:

1. client requests latest room snapshot and tail ops after known `room_seq`;
2. room sends snapshot or replay;
3. client reconstructs `RoomReplica`;
4. client reissues presence and control-lease subscriptions.

### 16.2 Session reconnect

On PTY session reconnect:

1. client authenticates with session token;
2. server emits bootstrap redraw and live stream anchor;
3. client constructs fresh Ghostty adapter and replays bootstrap;
4. client resumes live output.

### 16.3 Failure isolation

The control plane and data plane must fail independently.

Examples:

- room WebSocket drops, PTY session remains up:
  - terminal stays visible and interactive only if control lease remains valid and policy permits;
  - spatial edits are paused.

- PTY session drops, room remains up:
  - surface stays in place and displays disconnected/error overlay;
  - collaboration on spatial layout continues.

- one Ghostty adapter fails:
  - one surface degrades; canvas remains alive.

This is another benefit of the dual-plane split.

## 17. Performance goals

The performance goals must be phrased precisely:

1. **Typing path**
   From keystroke dispatch to bytes on the PTY socket should avoid control-plane serialization entirely.

2. **Compositor path**
   Camera motion and surface movement should remain smooth because they mostly reuse existing textures.

3. **Terminal update path**
   Hot terminals rerender only when bytes arrive or local timers fire.

4. **Room path**
   Spatial state must be replayable and crash-recoverable, even if it is slower than the terminal data path.

Ghostty’s public performance claims are encouraging—it uses Metal on macOS and describes competitive performance with a dedicated IO thread—but those claims are for Ghostty as a terminal emulator, not for 50 simultaneous hot embedded surfaces. Therefore the architecture must measure rather than assume. ([GitHub][6])

## 18. Prototyping and execution order

The feedback is right: the previous phase order hid the biggest risk too late. The execution order should be this instead.

| Step  | Deliverable                                 | Why it comes first                                                                                                 | Exit criteria                                                                                                                                              |
| ----- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1** | **Ghostty Metal Bridge**                    | This is the make-or-break dependency. If embedded offscreen Ghostty is not viable, the whole architecture changes. | One embedded surface renders to offscreen Metal; keyboard, mouse, paste, resize, and selection work; front/back texture publish works without stalling UI. |
| **2** | **N=50 Quad Compositor**                    | Proves the renderer and memory/bandwidth budget before collaboration work.                                         | 50 dummy textures pan/zoom smoothly; CPU culling, z-order, and optional occlusion skip behave correctly; frame pacing remains stable.                      |
| **3** | **Room Sequencer + WAL + TLA+**             | Once rendering is real, specify and build authoritative durable spatial state.                                     | deterministic replay; snapshot recovery; optimistic move/resize/reorder; TLA+ covers sequence/order/idempotence invariants.                                |
| **4** | **Networking + Multiplayer + PTY Sessions** | After both rendering and room durability are real, connect them over the network.                                  | multi-client shared room; control leases; terminal subscribe/bootstrap/live stream; disconnect/reconnect and recovery paths work.                          |

There is no Phase 8. The deferred research track is explicitly removed from the V1 architecture.

## 19. Detailed acceptance criteria for each step

### 19.1 Step 1 — Ghostty Metal Bridge

This step is successful only if all of the following are true:

- client can instantiate embedded full `libghostty`;
- output bytes can be fed from a mock PTY source;
- a rendered terminal image lands in an offscreen texture;
- the compositor can sample that texture without race artifacts;
- the adapter can translate keyboard input into PTY bytes;
- mouse reporting and text selection work;
- resize to new `cols/rows` works;
- cursor blink and timers work without full continuous redraw;
- no hidden-window architecture is required in the shipping path.

### 19.2 Step 2 — N=50 Compositor

This step is successful only if:

- 50 surfaces with representative sizes fit within acceptable memory budget;
- the visible-list builder and hit-test path are correct;
- camera pan/zoom are smooth;
- heavy overlap does not collapse due to overdraw;
- optional opaque occlusion skip behaves deterministically;
- texture publish / swap from many surfaces does not stall the frame loop.

### 19.3 Step 3 — Room Sequencer

This step is successful only if:

- every accepted op lands durably in the journal;
- snapshot + replay reconstructs identical room state;
- optimistic clients converge correctly after accept or reject;
- reordering and resize remain deterministic;
- control leases are unique and recoverable across reconnects;
- model checking covers the small state machine.

### 19.4 Step 4 — Networked PTY integration

This step is successful only if:

- multiple clients can view the same terminal surface;
- only one client at a time can type into it;
- new subscribers receive a coherent bootstrap redraw;
- disconnect/reconnect does not corrupt terminal state;
- spatial edits and terminal bytes can proceed independently.

## 20. Observability

This system will be hard to debug without very deliberate instrumentation.

### 20.1 Metrics

At minimum collect:

- `room_op_apply_ms`
- `room_journal_append_ms`
- `room_snapshot_write_ms`
- `room_recovery_ms`
- `pty_input_to_first_output_ms`
- `pty_bytes_out_per_sec`
- `ghostty_render_ms`
- `surface_texture_publish_ms`
- `visible_surface_count`
- `occluded_surface_count`
- `texture_memory_mb`
- `compositor_frame_ms`
- `missed_present_count`
- `lease_conflict_count`
- `session_bootstrap_ms`

### 20.2 Structured logs

Every operation and session event should carry:

- `room_id`
- `surface_id`
- `session_id`
- `client_id`
- `op_id`
- `room_seq`
- `output_seq`

### 20.3 Replay tooling

Two replay tools are mandatory:

1. **Room replay** from snapshot + journal.
2. **Session replay** from bootstrap bytes + live output log.

If a bug cannot be replayed offline, debugging it will be miserable.

## 21. Security and isolation

Because the product runs server-side PTYs, the server architecture matters:

- session workers must run with per-session resource limits;
- auth tokens for PTY sockets must be short-lived and scoped to one session;
- only the current control lease holder may send input bytes;
- room membership must gate session subscription;
- clipboard and paste behavior should be explicit and auditable.

This is standard systems hygiene, but here it directly affects both product trust and operational safety.

## 22. Main risks and mitigations

### 22.1 Risk: `libghostty` offscreen embedding is harder than expected

**Mitigation:** make it Step 1; use a pinned vendor fork; define a strict adapter boundary; do not build room logic first.

### 22.2 Risk: client-side rendering diverges across machines

**Mitigation:** canonical render profiles, bundled fonts, deterministic `cols/rows`, no per-user font overrides for collaborative surfaces.

### 22.3 Risk: terminal bootstrap for late join is incomplete

**Mitigation:** require a bootstrap-capable session backend from day one; do not hand-wave this as future work.

### 22.4 Risk: overlapping quads hit bandwidth limits

**Mitigation:** opaque surfaces by default, no gratuitous translucency, optional conservative occlusion skip, mipmaps off by default.

### 22.5 Risk: room sequencer and PTY session manager drift

**Mitigation:** treat room state as desired configuration and reconcile session side effects idempotently.

### 22.6 Risk: `libghostty` API churn

**Mitigation:** pinned commit, wrapper-only access, CI compatibility tests.

## 23. Final architecture statement

The V1 system should be built as a **macOS-native, Metal-first, dual-plane collaborative terminal canvas**:

- a **flat, durable, authoritative room model** for spatial state;
- **direct PTY byte streams** for terminal IO;
- **full embedded `libghostty` instances** as local terminal engines and pixel producers;
- a **simple quad compositor** for final presentation;
- **CPU culling and conservative occlusion** instead of GPU spatial indexing;
- **shared-queue, double-buffered texture ownership** instead of complex multi-queue synchronization;
- **Ghostty bridge and compositor prototypes first**, before room formalization and multiplayer wiring.

That architecture is bounded enough to ship, specific enough to build, and narrow enough to keep the project out of rendering-research quicksand while still leaving room for later evolution.

[1]: https://www.figma.com/blog/making-multiplayer-more-reliable/ "Making multiplayer more reliable | Figma Blog"
[2]: https://developer.apple.com/la/videos/play/wwdc2019/606/?time=16 "Delivering Optimized Metal Apps and Games - WWDC19 - Videos - Apple Developer"
[3]: https://ghostty.org/docs/about "About Ghostty"
[4]: https://www.figma.com/blog/how-figmas-multiplayer-technology-works/ "How Figma’s multiplayer technology works | Figma Blog"
[5]: https://martin.kleppmann.com/papers/local-first.pdf "Local-First Software:You Own Your Data, in spite of the Cloud"
[6]: https://github.com/ghostty-org/ghostty "GitHub - ghostty-org/ghostty:  Ghostty is a fast, feature-rich, and cross-platform terminal emulator that uses platform-native UI and GPU acceleration. · GitHub"
[7]: https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays?utm_source=chatgpt.com "Optimizing iPhone and iPad apps to support ProMotion ..."
[8]: https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler%28_%3A%29?utm_source=chatgpt.com "addCompletedHandler(_:) | Apple Developer Documentation"
[9]: https://developer.apple.com/documentation/Metal/resource-synchronization?utm_source=chatgpt.com "Resource synchronization | Apple Developer Documentation"
