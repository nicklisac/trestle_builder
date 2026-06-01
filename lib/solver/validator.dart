import 'models.dart';

const int BASE_WIDTH = 10;
const int BASE_DEPTH = 5;
const int MAX_Z = 14;

class Validator {
  final Set<Point3> occupied = {};
  final List<PlacedPiece> placed = [];
  final Map<Point, int> towerHeights = {};

  bool _inBounds(int x, int y, int z) {
    return x >= 0 && x < BASE_WIDTH && y >= 0 && y < BASE_DEPTH && z >= 0 && z <= MAX_Z;
  }

  (bool, String) canPlace(PlacedPiece piece, [Set<Point3>? sockets]) {
    final allowed = sockets ?? <Point3>{};

    for (final cell in piece.cells) {
      if (!_inBounds(cell.x, cell.y, cell.z)) {
        return (false, 'Out of bounds: ${cell.toString()}');
      }
      if (occupied.contains(cell) && !allowed.contains(cell)) {
        return (false, 'Cell collision with another track: ${cell.toString()}');
      }

      final key = Point(cell.x, cell.y);
      final towerH = towerHeights[key] ?? -1;
      if (cell.z <= towerH && !allowed.contains(cell)) {
        final isEndpoint = (cell == piece.start || cell == piece.end || piece.outputs.contains(cell));
        if (!isEndpoint) {
          return (false, 'Collision: track middle cell at (${cell.x},${cell.y},${cell.z}) passes through support tower column of height $towerH');
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
