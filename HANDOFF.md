# Tressel Track Builder — Master Handoff Document

**Updated:** 2026-05-31

## PROJECT GOAL

Build a web app that generates working Tressel Track marble run designs from a user's piece inventory, within constraints (base size, tower count).

\---

## 1\. WHAT WE HAVE

### Piece Inventory (18 pieces, encoded in pieces.py)

* **Coordinate System:** (x, y, z) system: x=right+, y=down+, z=up+. Relative to start cell.
* **Piece Structure:** Each piece stores: `cells\[]`, `start\_idx`, `end\_idx`, `descends`, and `outputs\[]` (exclusively for splitters).
* **Inventory Mix:** 12 same-level pieces, 4 descending pieces (IDs 3, 7, 10, 11), 1 splitter (ID 6), and 1 special piece (ID 14).
* **Transformations:** Flippable pieces generate 4 distinct orientations (original + H-flip + V-flip + HV-flip).
* **Descending Mechanics:** Descending pieces are NOT flippable. Their internal geometry is designed so the exit end drops exactly one Z level below the track body.

### Data Models (pieces.py)

* `Piece`: Canonical definition holding relative cell offsets and structural behavior.
* `PlacedPiece`: A frozen, absolute (x, y, z) instantiation of a piece after grid placement.
* `piece.place(origin)`: Computes and returns a `PlacedPiece` mapped to absolute grid coordinates.
* `piece.flip\_horizontal() / flip\_vertical()`: Returns a new `Piece` instance with inverted relative cell coordinates.

### Validator (validator.py)

* **Grid Bounds:** `BASE\_WIDTH = 10`, `BASE\_DEPTH = 5` (representing two 5x5 base plates positioned side-by-side).
* **State Management:** Tracks occupied grid cells, validating bounds and spatial collisions.
* `can\_place(piece, allowed\_overlaps)`: Inspects coordinates, explicitly allowing overlaps strictly at connection sockets.

### Render (render.py)

* Outputs per-level piece lists, connection path tracing, and tower point breakdowns.

\---

## 2\. CORE MECHANICS \& PHYSICAL GROUND TRUTH

To ensure the tracking engine matches the real-world physics of the toy, the following structural constraints must be strictly enforced by the solver and validator:

* **Mandatory Step-Down Drop:** At **every single connection** between pieces (where Piece A's exit socket feeds into Piece B's entry socket), there is a mandatory **-1 step-down drop** in height. The marble physically drops down exactly 1 tower-piece riser height as it transitions from one piece to the next.
* **Height Transition Behavior:**

  * **Flat Pieces:** The body and end cell sit at level Z. Because of the step-down rule, the *next* piece's socket must be generated at Z - 1.
  * **Descending Pieces:** The piece body sits at level Z, but its internal geometry drops its end cell to Z - 1. Applying the step-down rule means the *next* piece's socket must be generated at Z - 2.
* **Path Length Ceiling:** Because the maximum grid ceiling is hardcoded to `MAX\_Z = 8`, an individual linear track branch can contain a maximum of 8 pieces before running out of altitude and hitting the ground (Z = 0). High piece-count configurations (such as the target 15-piece layout) **must** utilize the splitter (Piece 6) to branch the run into parallel streams.

\---

## 3\. ARCHITECTURAL REDESIGN \& PROBLEM SOLUTIONS

### Solution for Problems #1 \& #2: Top-Down Backtracking Solver

The original bottom-up search algorithm caused parallel "disconnected islands" because it failed to calculate gravity drops correctly. The solver is being flipped to a **Top-Down Search (Option B)**.

* **Uniform Placement Logic:** Instead of complex reverse-calculations for descending pieces, a top-down approach makes placement uniform. For *any* piece orientation, the solver simply anchors the piece's absolute `start\_idx` cell directly onto the active open socket.
* **Socket Propagation:** When a piece is successfully placed, its active socket is popped from the tracking stack. If it is a standard piece, a new socket is appended at `(end\_x, end\_y, end\_z - 1)`. If it is a splitter, two parallel sockets are appended, both stepping down 1 unit below their respective output cells.

### Solution for Problem #3: Splitter Infinite Loop Fix

* **Visited Tracking:** The path tracer in `render.py` must maintain a `visited` set of piece IDs during evaluation. Re-encountering an ID breaks the evaluation loop.
* **Splitter Routing:** The engine must explicitly iterate through and follow the coordinates in the splitter's `outputs` array instead of looking for a single `end` coordinate.

### Solution for Problem #4: Support Tower Footprints

* **Scoping Rule:** Tower blocks are only required directly underneath piece `start` and `end` connection points, not under every single body cell.
* **Upgrading the Validator:** The tracker previously had a major blind spot: it only checked if a piece's body collided with other *tracks*. It completely missed cases where a lower track's body sliced horizontally through an upper track's vertical support column. The validator now tracks an explicit 2D map (`self.tower\_heights`) to prevent this column clipping.

\---

## 4\. REFERENCE IMPLEMENTATION SNIPPETS

### Upgraded Tower \& Clipping Detection (`validator.py`)

```python
class Validator:
    def \_\_init\_\_(self):
        self.occupied: set\[tuple\[int, int, int]] = set()
        self.placed: list\[PlacedPiece] = \[]
        # Tracks the highest vertical tower riser stack at a given (x, y) column
        self.tower\_heights: dict\[tuple\[int, int], int] = {}

    def \_in\_bounds(self, x: int, y: int, z: int) -> bool:
        return 0 <= x < 10 and 0 <= y < 5 and 0 <= z <= 8

    def can\_place(self, piece: PlacedPiece, sockets: set\[tuple\[int, int, int]] | None = None) -> tuple\[bool, str]:
        if sockets is None:
            sockets = set()

        for cell in piece.cells:
            x, y, z = cell
            if not self.\_in\_bounds(x, y, z):
                return False, f"Out of bounds: {cell}"
            if cell in self.occupied and cell not in sockets:
                return False, f"Cell collision with another track: {cell}"
            
            # CRITICAL PHYSICAL CHECK: Prevent track body from slicing through a support column
            if z <= self.tower\_heights.get((x, y), -1):
                if cell not in sockets: # Allow shared vertical connection points
                    return False, f"Collision with vertical support tower column at ({x},{y},{z})"

        return True, "OK"

    def place(self, piece: PlacedPiece) -> None:
        self.occupied.update(piece.cells)
        self.placed.append(piece)
        # Record tower support column heights strictly at the start and end footprints
        for sx, sy, sz in \[piece.start, piece.end]:
            self.tower\_heights\[(sx, sy)] = max(self.tower\_heights.get((sx, sy), -1), sz)

    def undo(self, piece: PlacedPiece) -> None:
        self.occupied.difference\_update(piece.cells)
        self.placed.remove(piece)
        # Re-evaluate column heights for the affected coordinates
        for sx, sy in \[(piece.start\[0], piece.start\[1]), (piece.end\[0], piece.end\[1])]:
            heights = \[max(p.start\[2], p.end\[2]) for p in self.placed if (p.start\[0] == sx and p.start\[1] == sy) or (p.end\[0] == sx and p.end\[1] == sy)]
            if heights:
                self.tower\_heights\[(sx, sy)] = max(heights)
            else:
                self.tower\_heights.pop((sx, sy), None)
```

### Refactored Top-Down Solver Engine (`solver.py`)

```python
class Solver:
    def \_\_init\_\_(self, inventory, max\_towers=100):
        self.inventory = inventory
        self.max\_towers = max\_towers
        self.validator = Validator()
        self.best = \[]
        self.used\_ids = set()
        self.all\_oriented = \[] # Populated with all valid orientations via get\_orientations()
        
    def count\_towers(self) -> int:
        # Correctly aggregates tower counts exclusively from support locations
        return sum(self.validator.tower\_heights.values())

    def build(self, sockets: list\[tuple\[int, int, int]]):
        if not sockets:
            if len(self.validator.placed) > len(self.best):
                self.best = list(self.validator.placed)
            return

        # Pop current target socket
        socket = sockets\[0]
        sx, sy, sz = socket

        # Branch Termination: If a gravity stream successfully hits the floor, that branch is done
        if sz == 0:
            self.build(sockets\[1:])
            return

        for oriented in self.all\_oriented:
            if oriented.id in self.used\_ids:
                continue

            # TOP-DOWN PLACEMENT UNIFORMITY: Align piece entry cell right over the socket
            sdx, sdy = oriented.cells\[oriented.start\_idx]
            origin = (sx - sdx, sy - sdy, sz)
            piece = oriented.place(origin)

            ok, \_ = self.validator.can\_place(piece, {socket})
            if not ok:
                continue

            self.validator.place(piece)
            if self.count\_towers() <= self.max\_towers:
                self.used\_ids.add(piece.piece\_id)
                
                # Derive child sockets by applying the mandatory -1 physical gravity drop
                next\_sockets = list(sockets\[1:])
                if piece.is\_splitter:
                    next\_sockets.extend(\[(ax, ay, az - 1) for ax, ay, az in piece.outputs])
                else:
                    next\_sockets.append((piece.end\[0], piece.end\[1], piece.end\[2] - 1))

                self.build(next\_sockets)
                self.used\_ids.remove(piece.piece\_id)

            self.validator.undo(piece)

    def solve(self):
        # Scan descending from highest possible grid tier to find optimal builds
        for start\_z in range(8, 0, -1):
            for ox in range(10):
                for oy in range(5):
                    initial\_sockets = \[(ox, oy, start\_z)]
                    self.build(initial\_sockets)
                    if self.best:
                        return self.best
        return self.best
```

\---

## 5\. RELEVANT FILE DIRECTORY

* `pieces.py`: Core token inventories, cell structural arrays, spatial data structures, and flipping transformations.
* `validator.py`: Absolute bounding-box, coordinate tracking, grid collision, and support column checking routines.
* `solver.py`: Top-down backtracking search engine optimization script.
* `render.py`: ASCII run visualizations and layout path-tracing engine.
* `visualize.py`: Geometric shape map rendering vector script.
* `pieces\_diagram.txt`: Verified reference structural schematics for all 18 inventory items.
* `Goal.txt`: High-level operational track baseline goals.

\---

## 6\. IMMEDIATELY REQUIRED ACTIONS FOR CODING MODEL

1. **Refactor `solver.py`:** Entirely strip out the old bottom-up socket stack routine and replace it with the unified top-down algorithm.
2. **Re-architect `validator.py`:** Inject the `self.tower\_heights` tracking dictionary and add the vertical clearance constraint inside `can\_place`.
3. **Patch `render.py` Trace Loops:** Apply a standard local tracking array checking for previously parsed piece IDs inside the splitter network traversal loops to eliminate execution hangs.

