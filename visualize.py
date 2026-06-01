from pieces import INVENTORY, Piece


def render_piece(piece: Piece) -> str:
    cells = piece.cells
    if not cells:
        return ""

    xs = [x for x, y in cells]
    ys = [y for x, y in cells]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)

    width = max_x - min_x + 1
    height = max_y - min_y + 1

    grid = [["." for _ in range(width)] for _ in range(height)]

    for i, (x, y) in enumerate(cells):
        gx = x - min_x
        gy = y - min_y
        if i == piece.start_idx and i not in piece.outputs:
            grid[gy][gx] = "S"
        elif i in piece.outputs:
            grid[gy][gx] = "E"
        elif i == piece.end_idx and not piece.is_splitter:
            grid[gy][gx] = "E"
        elif grid[gy][gx] == ".":
            grid[gy][gx] = "#"

    lines = []
    tag = ""
    if piece.descends:
        tag = " [DESCENDS]"
    if piece.is_splitter:
        tag = " [SPLITTER]"
    lines.append(f"--- Piece {piece.id}{tag} ---")

    for row in grid:
        lines.append("|" + "|".join(row) + "|")

    lines.append(f"  cells={(str)(cells)}")
    lines.append(f"  S=idx{piece.start_idx} E=idx{piece.end_idx}" + (f" outs={piece.outputs}" if piece.outputs else ""))
    lines.append("")

    return "\n".join(lines)


if __name__ == "__main__":
    output = ""
    for piece in INVENTORY:
        output += render_piece(piece) + "\n"

    with open("pieces_diagram.txt", "w") as f:
        f.write(output)

    print(output)
    print("Saved to pieces_diagram.txt")
