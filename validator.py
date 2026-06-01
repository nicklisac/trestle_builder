from pieces import PlacedPiece


BASE_WIDTH = 10  # two 5x5 bases side-by-side
BASE_DEPTH = 5
MAX_Z = 8


class Validator:
    def __init__(self):
        self.occupied: set[tuple[int, int, int]] = set()
        self.placed: list[PlacedPiece] = []
        # Tracks the highest vertical tower riser stack at a given (x, y) column
        self.tower_heights: dict[tuple[int, int], int] = {}

    def _in_bounds(self, x: int, y: int, z: int) -> bool:
        return 0 <= x < BASE_WIDTH and 0 <= y < BASE_DEPTH and 0 <= z <= MAX_Z

    def can_place(self, piece: PlacedPiece, sockets: set[tuple[int, int, int]] | None = None) -> tuple[bool, str]:
        if sockets is None:
            sockets = set()

        for cell in piece.cells:
            x, y, z = cell
            if not self._in_bounds(x, y, z):
                return False, f"Out of bounds: {cell}"
            if cell in self.occupied and cell not in sockets:
                return False, f"Cell collision with another track: {cell}"

            # CRITICAL PHYSICAL CHECK: Prevent track body from slicing through a support column
            if z <= self.tower_heights.get((x, y), -1):
                if cell not in sockets:
                    return False, f"Collision with vertical support tower column at ({x},{y},{z})"

        return True, "OK"

    def place(self, piece: PlacedPiece) -> None:
        self.occupied.update(piece.cells)
        self.placed.append(piece)
        # Record tower support column heights strictly at the start and end footprints
        for sx, sy, sz in [piece.start, piece.end]:
            self.tower_heights[(sx, sy)] = max(self.tower_heights.get((sx, sy), -1), sz)

    def undo(self, piece: PlacedPiece) -> None:
        self.occupied.difference_update(piece.cells)
        self.placed.remove(piece)
        # Re-evaluate column heights for the affected coordinates
        for sx, sy in [(piece.start[0], piece.start[1]), (piece.end[0], piece.end[1])]:
            heights = [max(p.start[2], p.end[2]) for p in self.placed if (p.start[0] == sx and p.start[1] == sy) or (p.end[0] == sx and p.end[1] == sy)]
            if heights:
                self.tower_heights[(sx, sy)] = max(heights)
            else:
                self.tower_heights.pop((sx, sy), None)
