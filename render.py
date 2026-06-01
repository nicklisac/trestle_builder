from pieces import INVENTORY
from solver import Solver


def render_readable(placed):
    if not placed:
        print("No solution.")
        return

    max_z_at = {}
    for p in placed:
        for cell in p.cells:
            x, y, z = cell
            max_z_at[(x, y)] = max(max_z_at.get((x, y), 0), z)
    total_towers = sum(max_z_at.values())

    z_levels = sorted(set(p.origin[2] for p in placed))
    max_z = max(z_levels)

    print("=" * 60)
    print(f"  {len(placed)} pieces | {total_towers} tower cubes | {max_z + 1} levels")
    print("=" * 60)

    # Per-level overview
    print(f"\nLEVELS (z=0 is base/bottom, z={max_z} is top/entry):\n")
    for z in range(max_z, -1, -1):
        z_pieces = [p for p in placed if p.origin[2] == z]
        if z_pieces:
            pids = ", ".join(f"P{p.piece_id}" for p in z_pieces)
            print(f"  z={z}:  {pids}")

    # Connection chain
    print(f"\nCONNECTIONS (ball flows top to bottom):\n")

    # With mandatory -1 gravity drop, next piece's start is at (end_x, end_y, end_z - 1)
    # Build lookup: expected socket -> piece
    start_lookup = {}
    for p in placed:
        start_lookup[p.start] = p

    # Find entry piece(s): no other piece feeds into this piece's start socket
    all_next_sockets = set()
    for p in placed:
        all_next_sockets.add((p.end[0], p.end[1], p.end[2] - 1))
        if p.is_splitter:
            for out in p.outputs:
                all_next_sockets.add((out[0], out[1], out[2] - 1))
    entry = [p for p in placed if p.start not in all_next_sockets]

    def trace_chain(start_piece, visited, indent=""):
        current = start_piece
        steps = 0
        while steps < len(placed):
            steps += 1
            if current.piece_id in visited:
                print(f"{indent}P{current.piece_id} [ALREADY VISITED]")
                break
            visited.add(current.piece_id)

            if current.is_splitter:
                print(f"{indent}P{current.piece_id}(z={current.origin[2]}) >> SPLITTER")
                for out in current.outputs:
                    socket = (out[0], out[1], out[2] - 1)
                    next_p = start_lookup.get(socket)
                    if next_p and next_p.piece_id not in visited:
                        print(f"{indent}  \\-> branch:")
                        trace_chain(next_p, visited, indent + "      ")
                return
            else:
                socket = (current.end[0], current.end[1], current.end[2] - 1)
                next_p = start_lookup.get(socket)
                if next_p is None:
                    print(f"{indent}P{current.piece_id}(z={current.origin[2]}) >> EXIT (z={current.end[2]})")
                    return
                if next_p.piece_id in visited:
                    print(f"{indent}P{current.piece_id}(z={current.origin[2]}) >> P{next_p.piece_id} [LOOP]")
                    return
                arrow = "[DOWN]" if current.end[2] != next_p.start[2] else "-->"
                print(f"{indent}P{current.piece_id}(z={current.origin[2]}) {arrow} P{next_p.piece_id}(z={next_p.origin[2]})")
                current = next_p

    for e in entry:
        print(f"  ENTRY >> P{e.piece_id} (z={e.origin[2]})")
        visited = set()
        trace_chain(e, visited, "  ")

    # Tower columns
    tall_towers = {k: v for k, v in max_z_at.items() if v >= 3}
    print(f"\nTOWER COLUMNS ({len(max_z_at)} total, {len(tall_towers)} at 3+ cubes high):")
    for (x, y), h in sorted(tall_towers.items()):
        print(f"  ({x},{y}): {h} cubes")


if __name__ == "__main__":
    import sys
    sys.setrecursionlimit(100)
    solver = Solver(INVENTORY, timeout_sec=15.0)
    result = solver.solve()
    render_readable(result)
