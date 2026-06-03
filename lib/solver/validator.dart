import 'models.dart';

class Validator {
  final int baseWidth;
  final int baseDepth;
  final int maxZ;
  final List<Point> basePositions;

  final Set<Point3> occupied = {};
  final List<PlacedPiece> placed = [];
  final Map<Point, int> towerHeights = {};

  Validator({
    required this.basePositions,
    this.maxZ = 14,
  })  : baseWidth = _computeWidth(basePositions),
        baseDepth = _computeDepth(basePositions);

  static int _computeWidth(List<Point> basePositions) {
    int maxCols = 0;
    for (final pos in basePositions) {
      if (pos.x > maxCols) maxCols = pos.x;
    }
    return (maxCols + 1) * 5;
  }

  static int _computeDepth(List<Point> basePositions) {
    int maxRows = 0;
    for (final pos in basePositions) {
      if (pos.y > maxRows) maxRows = pos.y;
    }
    return (maxRows + 1) * 5;
  }

  bool isOnBase(int x, int y) {
    final bx = (x / 5).floor();
    final by = (y / 5).floor();
    return basePositions.any((bp) => bp.x == bx && bp.y == by);
  }

  bool _inBounds(int x, int y, int z) {
    return x >= 0 && x < baseWidth && y >= 0 && y < baseDepth && z >= 0 && z <= maxZ;
  }

  (bool, String) canPlace(PlacedPiece piece, [Set<Point3>? sockets]) {
    final allowed = sockets ?? <Point3>{};

    for (final cell in piece.cells) {
      final isConnector = (cell == piece.start || cell == piece.end || piece.outputs.contains(cell));

      if (isConnector) {
        // Connector cells must be strictly in bounds AND strictly on a base plate
        if (!_inBounds(cell.x, cell.y, cell.z) || !isOnBase(cell.x, cell.y)) {
          return (false, 'Connector cell at ${cell.toString()} is not on an active base plate');
        }
      } else {
        // Non-connector track cells can go off the edge, but Z must be in bounds
        if (cell.z < 0 || cell.z > maxZ) {
          return (false, 'Z out of bounds: ${cell.toString()}');
        }
      }

      if (occupied.contains(cell) && !allowed.contains(cell)) {
        return (false, 'Cell collision with another track: ${cell.toString()}');
      }

      if (cell.x >= 0 && cell.x < baseWidth && cell.y >= 0 && cell.y < baseDepth) {
        final key = Point(cell.x, cell.y);
        final towerH = towerHeights[key] ?? -1;
        if (cell.z <= towerH && !allowed.contains(cell)) {
          if (!isConnector) {
            return (false, 'Collision: track middle cell at (${cell.x},${cell.y},${cell.z}) passes through support tower column of height $towerH');
          }
        }
      }
    }

    // Piece 10 end point constraint exception:
    // 1. If the piece being placed is Piece 10, make sure it is not placed under an existing tower at its end point
    if (piece.pieceId == 10) {
      final ep = piece.end;
      for (final placedPiece in placed) {
        for (final pt in [placedPiece.start, placedPiece.end, ...placedPiece.outputs]) {
          if (pt.x == ep.x && pt.y == ep.y && pt.z > ep.z) {
            return (false, 'Constraint collision: Piece 10 end point at (${ep.x},${ep.y},${ep.z}) cannot support towers above it (collision with tower at (${pt.x},${pt.y},${pt.z}))');
          }
        }
      }
    }
    // 2. If the piece being placed wants to place a tower above an existing Piece 10 end point in the same column
    for (final placedPiece in placed) {
      if (placedPiece.pieceId == 10) {
        final ep = placedPiece.end;
        for (final pt in [piece.start, piece.end, ...piece.outputs]) {
          if (pt.x == ep.x && pt.y == ep.y && pt.z > ep.z) {
            return (false, 'Constraint collision: Piece 10 end point at (${ep.x},${ep.y},${ep.z}) cannot support towers above it (attempted tower height ${pt.z})');
          }
        }
      }
    }

    return (true, 'OK');
  }

  void place(PlacedPiece piece) {
    occupied.addAll(piece.cells);
    placed.add(piece);

    for (final pt in [piece.start, piece.end]) {
      final key = Point(pt.x, pt.y);
      final current = towerHeights[key] ?? -1;
      towerHeights[key] = current > pt.z ? current : pt.z;
    }
  }

  void undo(PlacedPiece piece) {
    occupied.removeAll(piece.cells);
    placed.remove(piece);

    final keys = [
      Point(piece.start.x, piece.start.y),
      Point(piece.end.x, piece.end.y),
    ];

    for (final key in keys) {
      final heights = <int>[];
      for (final p in placed) {
        final sKey = Point(p.start.x, p.start.y);
        final eKey = Point(p.end.x, p.end.y);
        if (sKey == key || eKey == key) {
          heights.add(p.start.z > p.end.z ? p.start.z : p.end.z);
        }
      }
      if (heights.isNotEmpty) {
        towerHeights[key] = heights.reduce((a, b) => a > b ? a : b);
      } else {
        towerHeights.remove(key);
      }
    }
  }
}
