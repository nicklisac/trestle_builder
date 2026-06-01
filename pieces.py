from dataclasses import dataclass, field


@dataclass
class Piece:
    id: int
    cells: list[tuple[int, int]]       # (x, y) offsets from start, x=right+, y=down+
    start_idx: int                     # index into cells list
    end_idx: int                       # index into cells list
    descends: bool                     # end is one Z level below start
    outputs: list[int] = field(default_factory=list)  # for splitters: indices of output cells

    @property
    def flippable(self) -> bool:
        return not self.descends and len(self.outputs) == 0

    @property
    def is_splitter(self) -> bool:
        return len(self.outputs) > 0

    @property
    def z_span(self) -> int:
        return 2 if self.descends else 1

    def flip_horizontal(self) -> "Piece":
        return Piece(
            id=self.id,
            cells=[(-x, y) for x, y in self.cells],
            start_idx=self.start_idx,
            end_idx=self.end_idx,
            descends=self.descends,
            outputs=self.outputs.copy(),
        )

    def flip_vertical(self) -> "Piece":
        return Piece(
            id=self.id,
            cells=[(x, -y) for x, y in self.cells],
            start_idx=self.start_idx,
            end_idx=self.end_idx,
            descends=self.descends,
            outputs=self.outputs.copy(),
        )

    def place(self, origin: tuple[int, int, int]) -> "PlacedPiece":
        """Place this piece at grid origin (x, y, z)."""
        ox, oy, oz = origin
        placed_cells = [(x + ox, y + oy, oz) for x, y in self.cells]
        end_cell = placed_cells[self.end_idx]

        if self.descends:
            end_z = oz - 1
            end_cell = (end_cell[0], end_cell[1], end_z)
            placed_cells[self.end_idx] = end_cell

        output_cells = [placed_cells[i] for i in self.outputs]
        if self.descends:
            output_cells = [(c[0], c[1], oz - 1) for c in output_cells]

        return PlacedPiece(
            piece_id=self.id,
            cells=frozenset(placed_cells),
            start=placed_cells[self.start_idx],
            end=end_cell,
            outputs=output_cells,
            origin=origin,
        )


@dataclass(frozen=True)
class PlacedPiece:
    piece_id: int
    cells: frozenset[tuple[int, int, int]]
    start: tuple[int, int, int]
    end: tuple[int, int, int]
    outputs: list[tuple[int, int, int]]
    origin: tuple[int, int, int]

    @property
    def is_splitter(self) -> bool:
        return len(self.outputs) > 0


INVENTORY: list[Piece] = [
    # 1: 1x4 straight, same level
    Piece(id=1, cells=[(0, 0), (0, 1), (0, 2), (0, 3)], start_idx=0, end_idx=3, descends=False),

    # 2: staggered zigzag d>l>d>l, same level
    Piece(id=2, cells=[(0, 0), (0, 1), (-1, 1), (-1, 2), (-2, 2)], start_idx=0, end_idx=4, descends=False),

    # 3: 1x4 straight, descends
    Piece(id=3, cells=[(0, 0), (0, 1), (0, 2), (0, 3)], start_idx=0, end_idx=3, descends=True),

    # 4: 2x4 rectangle, same level
    Piece(id=4, cells=[(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2), (0, 3), (1, 3)], start_idx=0, end_idx=6, descends=False),

    # 5: r>u>r>d>d, same level
    Piece(id=5, cells=[(0, 0), (1, 0), (1, -1), (2, -1), (2, 0), (2, 1)], start_idx=0, end_idx=5, descends=False),

    # 6: horizontal splitter, 5 wide, center start, l>l and r>r, outputs descend
    Piece(id=6, cells=[(0, 0), (-1, 0), (-2, 0), (1, 0), (2, 0)], start_idx=0, end_idx=0, descends=False, outputs=[2, 4]),

    # 7: cross/plus with 2 full middle rows, descends
    Piece(id=7, cells=[(0, 0), (-1, 1), (0, 1), (1, 1), (-1, 2), (0, 2), (1, 2), (0, 3)], start_idx=0, end_idx=7, descends=True),

    # 8: d>l>l>d, same level
    Piece(id=8, cells=[(0, 0), (0, 1), (-1, 1), (-2, 1), (-2, 2)], start_idx=0, end_idx=4, descends=False),

    # 9: d>r>d>r>d, same level
    Piece(id=9, cells=[(0, 0), (0, 1), (1, 1), (1, 2), (2, 2), (2, 3)], start_idx=0, end_idx=5, descends=False),

    # 10: stem + 3x3 funnel, empties middle-right, descends
    Piece(id=10, cells=[(0, 2), (1, 2), (2, 2), (3, 2), (1, 1), (2, 1), (3, 1), (1, 0), (2, 0), (3, 0)], start_idx=0, end_idx=5, descends=True),

    # 11: 2x4 shape, descends
    Piece(id=11, cells=[(0, 0), (0, 1), (1, 1), (0, 2), (1, 2), (1, 3)], start_idx=0, end_idx=5, descends=True),

    # 12: U-shape, 3x3 with center cell filled
    Piece(id=12, cells=[(0, 0), (0, 1), (0, 2), (1, 2), (2, 2), (2, 1), (2, 0), (1, 1)], start_idx=0, end_idx=6, descends=False),

    # 13: L-shape with extra column, 3x3
    Piece(id=13, cells=[(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2), (2, 2)], start_idx=0, end_idx=6, descends=False),

    # 14: r>u>r>d>r, same level
    Piece(id=14, cells=[(0, 0), (1, 0), (1, -1), (2, -1), (2, 0), (3, 0)], start_idx=0, end_idx=5, descends=False),

    # 15: curved L with extra blocked cell
    Piece(id=15, cells=[(0, 0), (0, 1), (1, 1), (0, 2), (1, 2), (2, 2)], start_idx=0, end_idx=5, descends=False),

    # 16: 2x3 rectangle, same level (confirmed correct)
    Piece(id=16, cells=[(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2)], start_idx=0, end_idx=5, descends=False),

    # 17: L-shape, same level (confirmed correct)
    Piece(id=17, cells=[(0, 0), (0, 1), (0, 2), (1, 2), (2, 2)], start_idx=0, end_idx=4, descends=False),

    # 18: d>r>d, same level
    Piece(id=18, cells=[(0, 0), (0, 1), (1, 1), (1, 2)], start_idx=0, end_idx=3, descends=False),
]
