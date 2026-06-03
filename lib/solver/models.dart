class Point {
  final int x, y;
  const Point(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

class Point3 implements Comparable<Point3> {
  final int x, y, z;
  const Point3(this.x, this.y, this.z);

  @override
  bool operator ==(Object other) =>
      other is Point3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x, $y, $z)';

  @override
  int compareTo(Point3 other) {
    if (x != other.x) return x - other.x;
    if (y != other.y) return y - other.y;
    return z - other.z;
  }
}

class Piece {
  final int id;
  final List<Point> cells;
  final int startIdx;
  final int endIdx;
  final bool descends;
  final List<int> outputs;

  const Piece({
    required this.id,
    required this.cells,
    required this.startIdx,
    required this.endIdx,
    required this.descends,
    this.outputs = const [],
  });

  bool get flippable => !descends && outputs.isEmpty;

  bool get isSplitter => outputs.isNotEmpty;

  int get zSpan => descends ? 2 : 1;

  Piece flipHorizontal() {
    return Piece(
      id: id,
      cells: cells.map((c) => Point(-c.x, c.y)).toList(),
      startIdx: startIdx,
      endIdx: endIdx,
      descends: descends,
      outputs: List.of(outputs),
    );
  }

  Piece flipVertical() {
    return Piece(
      id: id,
      cells: cells.map((c) => Point(c.x, -c.y)).toList(),
      startIdx: startIdx,
      endIdx: endIdx,
      descends: descends,
      outputs: List.of(outputs),
    );
  }

  Piece rotate90() {
    return Piece(
      id: id,
      cells: cells.map((c) => Point(-c.y, c.x)).toList(),
      startIdx: startIdx,
      endIdx: endIdx,
      descends: descends,
      outputs: List.of(outputs),
    );
  }

  PlacedPiece place(Point3 origin) {
    final ox = origin.x;
    final oy = origin.y;
    final oz = origin.z;

    var placedCells = <Point3>[];
    for (int i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (id == 6 && i != startIdx) {
        placedCells.add(Point3(c.x + ox, c.y + oy, oz - 1));
      } else {
        placedCells.add(Point3(c.x + ox, c.y + oy, oz));
      }
    }

    var endCell = placedCells[endIdx];

    if (descends) {
      endCell = Point3(endCell.x, endCell.y, oz - 1);
      placedCells[endIdx] = endCell;
    }

    var outputCells = outputs.map((i) => placedCells[i]).toList();
    if (descends) {
      outputCells = outputCells
          .map((c) => Point3(c.x, c.y, oz - 1))
          .toList();
    }

    return PlacedPiece(
      pieceId: id,
      cells: placedCells,
      start: placedCells[startIdx],
      end: endCell,
      outputs: outputCells,
      origin: origin,
    );
  }
}

class PlacedPiece {
  final int pieceId;
  final List<Point3> cells;
  final Point3 start;
  final Point3 end;
  final List<Point3> outputs;
  final Point3 origin;

  const PlacedPiece({
    required this.pieceId,
    required this.cells,
    required this.start,
    required this.end,
    required this.outputs,
    required this.origin,
  });

  bool get isSplitter => outputs.isNotEmpty;
}

const List<Piece> INVENTORY = [
  Piece(id: 1, cells: [Point(0, 0), Point(0, 1), Point(0, 2), Point(0, 3)], startIdx: 0, endIdx: 3, descends: false),
  Piece(id: 2, cells: [Point(0, 0), Point(0, 1), Point(-1, 1), Point(-1, 2), Point(-2, 2)], startIdx: 0, endIdx: 4, descends: false),
  Piece(id: 3, cells: [Point(0, 0), Point(0, 1), Point(0, 2), Point(0, 3)], startIdx: 0, endIdx: 3, descends: true),
  Piece(id: 4, cells: [Point(0, 0), Point(1, 0), Point(0, 1), Point(1, 1), Point(0, 2), Point(1, 2), Point(0, 3), Point(1, 3)], startIdx: 0, endIdx: 6, descends: false),
  Piece(id: 5, cells: [Point(0, 0), Point(1, 0), Point(1, -1), Point(2, -1), Point(2, 0), Point(2, 1)], startIdx: 0, endIdx: 5, descends: false),
  Piece(id: 6, cells: [Point(0, 0), Point(-1, 0), Point(-2, 0), Point(1, 0), Point(2, 0)], startIdx: 0, endIdx: 0, descends: false, outputs: [2, 4]),
  Piece(id: 7, cells: [Point(0, 0), Point(-1, 1), Point(0, 1), Point(1, 1), Point(-1, 2), Point(0, 2), Point(1, 2), Point(0, 3)], startIdx: 0, endIdx: 7, descends: true),
  Piece(id: 8, cells: [Point(0, 0), Point(0, 1), Point(-1, 1), Point(-2, 1), Point(-2, 2)], startIdx: 0, endIdx: 4, descends: false),
  Piece(id: 9, cells: [Point(0, 0), Point(0, 1), Point(1, 1), Point(1, 2), Point(2, 2), Point(2, 3)], startIdx: 0, endIdx: 5, descends: false),
  Piece(id: 10, cells: [Point(0, 0), Point(1, 0), Point(2, 0), Point(3, 0), Point(1, 1), Point(2, 1), Point(3, 1), Point(1, 2), Point(2, 2), Point(3, 2)], startIdx: 0, endIdx: 5, descends: true),
  Piece(id: 11, cells: [Point(0, 0), Point(0, 1), Point(1, 1), Point(0, 2), Point(1, 2), Point(1, 3)], startIdx: 0, endIdx: 5, descends: true),
  Piece(id: 12, cells: [Point(0, 0), Point(0, 1), Point(0, 2), Point(1, 2), Point(2, 2), Point(2, 1), Point(2, 0), Point(1, 1)], startIdx: 0, endIdx: 6, descends: false),
  Piece(id: 13, cells: [Point(0, 0), Point(1, 0), Point(0, 1), Point(1, 1), Point(0, 2), Point(1, 2), Point(2, 2)], startIdx: 0, endIdx: 6, descends: false),
  Piece(id: 14, cells: [Point(0, 0), Point(1, 0), Point(1, -1), Point(2, -1), Point(2, 0), Point(3, 0)], startIdx: 0, endIdx: 5, descends: false),
  Piece(id: 15, cells: [Point(0, 0), Point(0, 1), Point(1, 1), Point(0, 2), Point(1, 2), Point(2, 2)], startIdx: 0, endIdx: 5, descends: false),
  Piece(id: 16, cells: [Point(0, 0), Point(1, 0), Point(0, 1), Point(1, 1), Point(0, 2), Point(1, 2)], startIdx: 0, endIdx: 5, descends: false),
  Piece(id: 17, cells: [Point(0, 0), Point(0, 1), Point(0, 2), Point(1, 2), Point(2, 2)], startIdx: 0, endIdx: 4, descends: false),
  Piece(id: 18, cells: [Point(0, 0), Point(0, 1), Point(1, 1), Point(1, 2)], startIdx: 0, endIdx: 3, descends: false),
];

List<Point> getBasePositions(int baseCount) {
  if (baseCount <= 1) {
    return [const Point(0, 0)];
  } else if (baseCount == 2) {
    return [const Point(0, 0), const Point(1, 0)];
  } else if (baseCount == 3) {
    return [const Point(0, 0), const Point(1, 0), const Point(0, 1)];
  } else if (baseCount == 4) {
    return [const Point(0, 0), const Point(1, 0), const Point(0, 1), const Point(1, 1)];
  } else if (baseCount == 5) {
    return [const Point(0, 0), const Point(1, 0), const Point(0, 1), const Point(1, 1), const Point(2, 0)];
  } else if (baseCount == 6) {
    return [const Point(0, 0), const Point(1, 0), const Point(2, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1)];
  } else if (baseCount == 7) {
    return [const Point(0, 0), const Point(1, 0), const Point(2, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(0, 2)];
  } else if (baseCount == 8) {
    return [const Point(0, 0), const Point(1, 0), const Point(2, 0), const Point(0, 1), const Point(1, 1), const Point(2, 1), const Point(0, 2), const Point(1, 2)];
  } else {
    final list = <Point>[];
    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 3; x++) {
        if (list.length < baseCount) {
          list.add(Point(x, y));
        }
      }
    }
    int index = 9;
    while (list.length < baseCount) {
      list.add(Point(index % 3, (index / 3).floor()));
      index++;
    }
    return list;
  }
}
