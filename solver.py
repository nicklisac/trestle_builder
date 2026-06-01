from pieces import INVENTORY, Piece, PlacedPiece
from validator import Validator, BASE_WIDTH, BASE_DEPTH
import time
import random


def get_orientations(piece: Piece) -> list[Piece]:
    orientations = [piece]
    if piece.flippable:
        orientations.append(piece.flip_horizontal())
        orientations.append(piece.flip_vertical())
        orientations.append(piece.flip_horizontal().flip_vertical())
    return orientations


def solution_to_dict(placed: list[PlacedPiece]) -> dict:
    """Convert placed pieces to a serializable dict for web app consumption."""
    pieces = []
    for p in placed:
        pieces.append({
            "piece_id": p.piece_id,
            "origin": list(p.origin),
            "start": list(p.start),
            "end": list(p.end),
            "outputs": [list(o) for o in p.outputs],
            "cells": [list(c) for c in p.cells],
            "is_splitter": p.is_splitter,
        })

    # Compute tower heights strictly from start/end support positions
    max_z_at = {}
    for p in placed:
        for sx, sy, sz in [p.start, p.end]:
            key = f"{sx},{sy}"
            max_z_at[key] = max(max_z_at.get(key, 0), sz)

    return {
        "piece_count": len(placed),
        "tower_count": sum(max_z_at.values()),
        "tower_map": max_z_at,
        "pieces": pieces,
    }


class Solver:
    def __init__(self, inventory, timeout_sec=60.0, max_towers=100, seed=None):
        self.inventory = inventory
        self.timeout = timeout_sec
        self.max_towers = max_towers
        self.seed = seed
        self.rng = random.Random(seed)
        self.start_time = time.time()
        self.validator = Validator()
        self.best = []
        self.used_ids = set()
        self.all_oriented = []

        for piece in inventory:
            for orient in get_orientations(piece):
                self.all_oriented.append(orient)

        # Shuffle orientations with seed for variety across runs
        self.rng.shuffle(self.all_oriented)

    def timed_out(self):
        return time.time() - self.start_time > self.timeout

    def count_towers(self):
        return sum(self.validator.tower_heights.values())

    def build(self, sockets: list[tuple[int, int, int]]):
        if self.timed_out():
            return

        # Track best whenever we have no more sockets to fill
        if not sockets:
            if len(self.validator.placed) > len(self.best):
                self.best = list(self.validator.placed)
            return

        socket = sockets[0]
        sx, sy, sz = socket

        # Branch Termination: gravity stream hits the floor
        if sz == 0:
            self.build(sockets[1:])
            return

        for oriented in self.all_oriented:
            if oriented.id in self.used_ids:
                continue

            # TOP-DOWN PLACEMENT: Align piece entry cell over the socket
            sdx, sdy = oriented.cells[oriented.start_idx]
            origin = (sx - sdx, sy - sdy, sz)
            piece = oriented.place(origin)

            ok, _ = self.validator.can_place(piece, {socket})
            if not ok:
                continue

            self.validator.place(piece)
            if self.count_towers() <= self.max_towers:
                self.used_ids.add(piece.piece_id)

                # Derive child sockets with mandatory -1 gravity drop
                next_sockets = list(sockets[1:])
                if piece.is_splitter:
                    next_sockets.extend([(ax, ay, az - 1) for ax, ay, az in piece.outputs])
                else:
                    next_sockets.append((piece.end[0], piece.end[1], piece.end[2] - 1))

                self.build(next_sockets)
                self.used_ids.remove(piece.piece_id)

            self.validator.undo(piece)

    def solve(self) -> list[PlacedPiece]:
        for start_z in range(8, 0, -1):
            grid_positions = [(ox, oy) for ox in range(BASE_WIDTH) for oy in range(BASE_DEPTH)]
            self.rng.shuffle(grid_positions)

            for ox, oy in grid_positions:
                if self.timed_out():
                    break
                initial_sockets = [(ox, oy, start_z)]
                self.build(initial_sockets)

            if self.best:
                return self.best

        return self.best

    def solve_dict(self) -> dict:
        """Solve and return structured data for web app."""
        placed = self.solve()
        return {
            "seed": self.seed,
            "found": len(placed) > 0,
            "solution": solution_to_dict(placed) if placed else None,
        }


if __name__ == "__main__":
    import sys
    import json

    seed = int(sys.argv[1]) if len(sys.argv) > 1 else None
    print(f"Base: {BASE_WIDTH}x{BASE_DEPTH}, Max towers: 100, Seed: {seed}")
    print("Solving...")

    solver = Solver(INVENTORY, timeout_sec=30.0, max_towers=100, seed=seed)
    result = solver.solve()

    if result:
        print(f"\nResult: {len(result)} pieces, {solver.count_towers()} support towers\n")
        for p in result:
            tag = ""
            if p.is_splitter:
                tag = " [SPLITTER]"
            elif p.end[2] != p.start[2]:
                tag = f" [DESC z{p.start[2]}->z{p.end[2]}]"
            print(f"  P{p.piece_id:2d}: z={p.origin[2]}  s={p.start}  e={p.end}{tag}")

        print("\n--- JSON output ---")
        print(json.dumps(solver.solve_dict(), indent=2))
    else:
        print("No solution found.")
