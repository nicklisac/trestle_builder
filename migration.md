# Migration Plan: Python → Dart/Flutter + Three.js WebView

**Goal:** Free web app + paid phone app, single codebase, no server required.

---

## Architecture Target

```
Flutter app (Dart)
├── Solver (Dart) — runs natively or compiled to JS for web
├── UI (Flutter) — buttons, settings, legend, paywall
└── 3D Viewer (Three.js in WebView/iframe)
       └── Receives JSON from Dart, renders track
```

**Phone app:** Flutter + `webview_flutter` plugin embeds Three.js viewer.
**Web app:** Flutter Web + `<iframe>` embeds same Three.js viewer.
**Shared:** Dart solver, Flutter UI code, Three.js viewer HTML/JS.

---

## Phase 1: Dart Solver (Standalone)

Port the solver logic from Python to Dart. Verify parity: same seed → same result.

### 1.1 Data Models (`lib/models.dart`)

- [ ] `Piece` class
  - Fields: `id`, `cells` (List of `(x, y)` offsets), `startIdx`, `endIdx`, `descends`, `outputs`
  - Properties: `flippable`, `isSplitter`, `zSpan`
  - Methods: `flipHorizontal()`, `flipVertical()`, `place(origin)` → `PlacedPiece`
- [ ] `PlacedPiece` class (immutable)
  - Fields: `pieceId`, `cells` (Set of `(x, y, z)`), `start`, `end`, `outputs`, `origin`
  - Property: `isSplitter`
- [ ] `INVENTORY` — List of 18 `Piece` instances, matching `pieces.py` exactly

### 1.2 Validator (`lib/validator.dart`)

- [ ] Constants: `BASE_WIDTH = 10`, `BASE_DEPTH = 5`, `MAX_Z = 8`
- [ ] `Validator` class
  - State: `occupied` (Set), `placed` (List), `towerHeights` (Map)
  - `_inBounds(x, y, z)` → bool
  - `canPlace(piece, sockets)` → `(bool, String)` tuple
  - `place(piece)` — adds to state, updates tower heights at start/end
  - `undo(piece)` — removes from state, re-evaluates tower heights

### 1.3 Solver (`lib/solver.dart`)

- [ ] `getOrientations(piece)` → List of `Piece`
- [ ] `Solver` class
  - Constructor: `inventory`, `timeoutSec`, `maxTowers`, `seed`
  - `timedOut()` → bool
  - `countTowers()` → int
  - `build(sockets)` — top-down backtracking with seeded shuffle
  - `solve()` → List of `PlacedPiece` (scans z=8→1, shuffles x,y per level)
  - `solveDict()` → Map (serializable solution data)
- [ ] `solutionToDict(placed)` — computes piece count, tower count (start/end only), tower map, piece data

### 1.4 Verification

- [ ] Run solver with seeds 1-10 in both Python and Dart
- [ ] Compare: piece count, piece IDs, positions, tower count — must match exactly
- [ ] Edge cases: seed that produces no solution, seed that uses all 18 pieces

---

## Phase 2: Three.js Viewer (Standalone HTML)

Extract and harden the viewer so it works independently of Flask.

### 2.1 Self-Contained Viewer (`viewer.html`)

- [ ] Combine `templates/index.html` + `static/js/viewer.js` into one file
- [ ] Three.js loaded from CDN (r128)
- [ ] Remove all Flask/Python dependencies
- [ ] Viewer accepts solution data via:
  - `postMessage({ solution: {...} })` from parent window
  - OR URL parameter: `?solution=base64_json`
  - OR embedded `<script>` variable: `window.SOLUTION = {...}`

### 2.2 Viewer API

- [ ] `viewer.postMessage({ type: 'render', solution: {...} })` — renders a track
- [ ] `viewer.postMessage({ type: 'clear' })` — clears the scene
- [ ] Viewer posts back: `{ type: 'ready' }` when loaded, `{ type: 'rendered', pieceCount: N }` when done

### 2.3 Testing

- [ ] Load `viewer.html` with a pre-baked JSON solution — verify rendering
- [ ] Load via `postMessage` from a test parent page — verify communication
- [ ] Test all visual elements: base grid, tower risers, thin plates, marble animation, entry/exit markers, splitter alternation

---

## Phase 3: Flutter Web App

Build the Flutter app that ties the solver and viewer together.

### 3.1 Project Setup

- [ ] `flutter create trestle_builder`
- [ ] Add dependencies: `webview_flutter` (mobile), `http` (if needed later)
- [ ] Project structure:
  ```
  trestle_builder/
  ├── lib/
  │   ├── main.dart
  │   ├── solver/          # Dart solver (from Phase 1)
  │   │   ├── models.dart
  │   │   ├── validator.dart
  │   │   └── solver.dart
  │   ├── ui/
  │   │   ├── home_screen.dart
  │   │   ├── viewer_widget.dart
  │   │   └── legend_widget.dart
  │   └── models/
  │       └── solution.dart
  ├── assets/
  │   └── viewer.html      # Three.js viewer (from Phase 2)
  └── pubspec.yaml
  ```

### 3.2 Viewer Widget (`viewer_widget.dart`)

- [ ] Mobile: `WebView` from `webview_flutter` plugin
  - Load `viewer.html` from assets
  - `javascriptChannels` for bidirectional communication
- [ ] Web: `<iframe>` loading `viewer.html`
  - `window.postMessage` for communication
- [ ] Abstract interface: `TrackViewer` with `render(solution)`, `clear()`
- [ ] Platform-specific implementations: `MobileTrackViewer`, `WebTrackViewer`

### 3.3 Home Screen (`home_screen.dart`)

- [ ] Seed input field (optional, defaults to random)
- [ ] "Generate" button — runs solver, passes result to viewer
- [ ] "Random Seed" button — generates random seed, solves, renders
- [ ] Stats display: piece count, tower count, seed value
- [ ] Loading indicator during solve
- [ ] Error handling: no solution found, timeout

### 3.4 Legend Widget (`legend_widget.dart`)

- [ ] Color-coded piece list (matching Three.js colors)
- [ ] Piece tags: [SPLIT], [DESC]
- [ ] Z-level for each piece
- [ ] Chain info panel showing connection flow

### 3.5 Solver Integration

- [ ] Import Dart solver from Phase 1
- [ ] Run solver on a compute isolate (avoid UI blocking)
- [ ] Convert `SolutionData` → JSON → pass to viewer via `postMessage`
- [ ] Handle solver timeout gracefully

### 3.6 Testing

- [ ] Run on Chrome (Flutter Web) — verify solve + render
- [ ] Run on iOS simulator — verify WebView + render
- [ ] Run on Android emulator — verify WebView + render
- [ ] Compare rendered tracks against Python version for same seeds

---

## Phase 4: Polish & Distribution

### 4.1 Visual Polish

- [ ] Piece highlighting on hover/tap (viewer receives piece ID, highlights in 3D)
- [ ] Camera presets: top-down, isometric, side view
- [ ] Smooth camera transitions between presets
- [ ] Piece info tooltip on hover (piece ID, z-level, type)

### 4.2 User Experience

- [ ] "Save track" — export solution JSON or screenshot
- [ ] "Share" — generate URL with seed encoded: `app.com/?seed=12345`
- [ ] History: recently generated tracks (localStorage)
- [ ] Settings: max towers, timeout, piece filters

### 4.3 Web Deployment

- [ ] Build: `flutter build web --release`
- [ ] Host on: GitHub Pages, Netlify, or Vercel
- [ ] SEO: meta tags, Open Graph, favicon
- [ ] PWA: add manifest.json for installable web app

### 4.4 Phone App Distribution

- [ ] App Store / Play Store listings
- [ ] App icons, splash screens
- [ ] In-app purchase for paid version (if freemium model)
- [ ] Versioning and update strategy

### 4.5 Performance

- [ ] Solver benchmark: measure solve time across seeds
- [ ] Viewer optimization: geometry instancing for tower risers
- [ ] Lazy load Three.js (don't block initial render)
- [ ] Memory profiling on mobile devices

---

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| 3D engine | Three.js (via WebView) | Battle-tested, massive ecosystem, better than Dart alternatives |
| Solver language | Dart | Runs natively on mobile, compiles to JS for web, single language |
| Communication | postMessage / JS channels | Standard, works on all platforms |
| Web deployment | Flutter Web | Same codebase as mobile, no separate web app needed |
| Server | None | All computation client-side, no backend costs |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| `webview_flutter` bugs on some Android devices | Viewer doesn't load | Fallback to loading viewer in external browser |
| Flutter Web performance with heavy JS | Slow on low-end devices | Lazy load Three.js, optimize geometry |
| Solver timeout on large inventories | Bad UX | Progressive timeout, show partial results |
| Three.js CDN unavailable | Viewer broken | Bundle Three.js locally as fallback |

---

## File Inventory (Current Python Repo)

| File | Purpose | Migration Target |
|------|---------|-----------------|
| `pieces.py` | Piece definitions, transforms | `lib/solver/models.dart` |
| `validator.py` | Collision, bounds, tower tracking | `lib/solver/validator.dart` |
| `solver.py` | Backtracking solver, seeded shuffle | `lib/solver/solver.dart` |
| `render.py` | ASCII output (text) | Discard (replaced by 3D viewer) |
| `static/js/viewer.js` | Three.js 3D rendering | `assets/viewer.html` (inlined) |
| `templates/index.html` | Flask template + CSS | `assets/viewer.html` (merged) |
| `app.py` | Flask server | Discard (no server needed) |
| `run.py` | CLI runner | Discard (replaced by Flutter app) |
| `visualize.py` | Piece diagram generator | Discard (not needed) |
