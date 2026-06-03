import 'models.dart';
import 'validator.dart';

class LcgRng {
  int _state;

  LcgRng(int seed) : _state = seed & 0xFFFFFFFF;

  int _next() {
    _state = (((1103515245 * _state) & 0x7FFFFFFF) + 12345) & 0x7FFFFFFF;
    return _state;
  }

  double nextDouble() {
    return _next() / 0x7FFFFFFF;
  }

  void shuffle<T>(List<T> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = _next() % (i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }
}

List<Piece> getOrientations(Piece piece) {
  final candidates = <Piece>[];

  // 4 rotations of the original piece
  var p = piece;
  for (int i = 0; i < 4; i++) {
    candidates.add(p);
    p = p.rotate90();
  }

  if (piece.flippable) {
    // 4 rotations of the flipped piece
    var pFlipped = piece.flipHorizontal();
    for (int i = 0; i < 4; i++) {
      candidates.add(pFlipped);
      pFlipped = pFlipped.rotate90();
    }
  }

  final orientations = <Piece>[];
  final seen = <String>{};

  for (final cand in candidates) {
    // Shift cells so the start cell is exactly at (0, 0)
    final sdx = cand.cells[cand.startIdx].x;
    final sdy = cand.cells[cand.startIdx].y;

    final shiftedCells = cand.cells.map((c) => Point(c.x - sdx, c.y - sdy)).toList();
    // Sort cells for deterministic signature comparison
    shiftedCells.sort((a, b) {
      if (a.x != b.x) return a.x - b.x;
      return a.y - b.y;
    });

    final ex = cand.cells[cand.endIdx].x;
    final ey = cand.cells[cand.endIdx].y;
    final shiftedEnd = Point(ex - sdx, ey - sdy);

    final shiftedOutputs = cand.outputs.map((idx) {
      final outCell = cand.cells[idx];
      return Point(outCell.x - sdx, outCell.y - sdy);
    }).toList();

    // Create a string representation for seen set check
    final cellsSig = shiftedCells.map((c) => '${c.x},${c.y}').join(';');
    final outputsSig = shiftedOutputs.map((o) => '${o.x},${o.y}').join(';');
    final signature = '$cellsSig|${shiftedEnd.x},${shiftedEnd.y}|$outputsSig';

    if (!seen.contains(signature)) {
      seen.add(signature);
      final normalizedCells = cand.cells.map((c) => Point(c.x - sdx, c.y - sdy)).toList();
      orientations.add(Piece(
        id: cand.id,
        cells: normalizedCells,
        startIdx: cand.startIdx,
        endIdx: cand.endIdx,
        descends: cand.descends,
        outputs: List.of(cand.outputs),
      ));
    }
  }

  return orientations;
}

Map<String, dynamic> solutionToDict(List<PlacedPiece> placed) {
  final pieces = <Map<String, dynamic>>[];
  for (final p in placed) {
    pieces.add({
      'piece_id': p.pieceId,
      'origin': [p.origin.x, p.origin.y, p.origin.z],
      'start': [p.start.x, p.start.y, p.start.z],
      'end': [p.end.x, p.end.y, p.end.z],
      'outputs': p.outputs.map((o) => [o.x, o.y, o.z]).toList(),
      'cells': p.cells.map((c) => [c.x, c.y, c.z]).toList(),
      'is_splitter': p.isSplitter,
    });
  }

  final maxZAt = <String, int>{};
  for (final p in placed) {
    for (final pt in [p.start, p.end]) {
      final key = '${pt.x},${pt.y}';
      final current = maxZAt[key] ?? 0;
      maxZAt[key] = pt.z > current ? pt.z : current;
    }
  }

  return {
    'piece_count': placed.length,
    'tower_count': maxZAt.values.fold(0, (a, b) => a + b),
    'tower_map': maxZAt,
    'pieces': pieces,
  };
}

class Solver {
  final List<Piece> inventory;
  final Map<int, int> pieceLimits;
  final int baseWidth;
  final int baseDepth;
  final int maxZ;
  final List<Point> basePositions;
  final int catcherCount;
  final double timeoutSec;
  final int maxTowers;
  final int? seed;
  final LcgRng rng;
  final DateTime startTime;
  late final Validator validator;
  List<PlacedPiece> best = [];
  final Map<int, int> usedCounts = {};
  late final List<Piece> allOriented;
  final void Function(List<PlacedPiece>)? onProgress;
  final void Function(int iteration, int length)? onBestFound;
  final int maxIterations;
  int _iterations = 0;
  DateTime _lastUpdateTime;
  final List<int> mandatoryIds = [];

  Solver({
    required this.inventory,
    required this.pieceLimits,
    required this.basePositions,
    required this.catcherCount,
    this.maxZ = 14,
    this.timeoutSec = 60.0,
    this.maxIterations = 10000,
    this.maxTowers = 100,
    this.seed,
    this.onProgress,
    this.onBestFound,
  })  : baseWidth = _computeWidth(basePositions),
        baseDepth = _computeDepth(basePositions),
        rng = LcgRng(seed ?? DateTime.now().millisecondsSinceEpoch % 1000000),
        startTime = DateTime.now(),
        _lastUpdateTime = DateTime.now() {
    validator = Validator(basePositions: basePositions, maxZ: maxZ);
    allOriented = <Piece>[];
    for (final piece in inventory) {
      for (final orient in getOrientations(piece)) {
        allOriented.add(orient);
      }
    }
    rng.shuffle(allOriented);

    // Select 5 unique mandatory piece IDs deterministically based on seed
    final allIds = inventory.where((p) => (pieceLimits[p.id] ?? 0) > 0).map((p) => p.id).toList();
    rng.shuffle(allIds);
    final takeCount = allIds.length < 5 ? allIds.length : 5;
    mandatoryIds.addAll(allIds.take(takeCount));
  }

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

  bool timedOut() {
    if (_iterations >= maxIterations) return true;
    return DateTime.now().difference(startTime).inMilliseconds > timeoutSec * 1000;
  }

  int countTowers() {
    return validator.towerHeights.values.fold(0, (a, b) => a + b);
  }

  Future<void> build(List<Point3> sockets) async {
    if (timedOut()) return;

    _iterations++;
    if (_iterations % 50 == 0) {
      await Future.delayed(Duration.zero);
      final now = DateTime.now();
      if (now.difference(_lastUpdateTime).inMilliseconds > 200) {
        _lastUpdateTime = now;
        if (onProgress != null) {
          onProgress!(List.of(validator.placed));
        }
      }
    }

    if (sockets.isEmpty) {
      // Check if all mandatory pieces are included in the placement!
      final containsAllMandatory = mandatoryIds.every((id) => (usedCounts[id] ?? 0) > 0);

      // Relaxed catcher constraint: require at least 1 catcher, up to the total catcherCount
      final placedCatchers = validator.placed.where((p) => p.pieceId == 19).length;
      final usesEnoughCatchers = placedCatchers >= 1 && placedCatchers <= catcherCount;

      if (containsAllMandatory && usesEnoughCatchers && validator.placed.length > best.length) {
        best = List.of(validator.placed);
        if (onBestFound != null) {
          onBestFound!(_iterations, best.length);
        }
      }
      return;
    }

    final socket = sockets[0];
    final sx = socket.x;
    final sy = socket.y;
    final sz = socket.z;

    if (sz == 0) {
      // Find all valid catcher placements at (sx, sy, 0)
      final directions = const [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1)];
      for (final dir in directions) {
        final cx1 = sx + dir.x;
        final cy1 = sy + dir.y;
        final cx2 = sx + 2 * dir.x;
        final cy2 = sy + 2 * dir.y;

        // 1. Collision check
        final cell0 = Point3(sx, sy, 0);
        final cell1 = Point3(cx1, cy1, 0);
        final cell2 = Point3(cx2, cy2, 0);
        if (validator.occupied.contains(cell0)) continue;

        bool hasCollision = false;
        if (cx1 >= 0 && cx1 < baseWidth && cy1 >= 0 && cy1 < baseDepth) {
          if (validator.occupied.contains(cell1)) hasCollision = true;
        }
        if (cx2 >= 0 && cx2 < baseWidth && cy2 >= 0 && cy2 < baseDepth) {
          if (validator.occupied.contains(cell2)) hasCollision = true;
        }
        if (hasCollision) continue;

        // 2. Support tower check for the bowl cells (only if inside base bounds and on active base!)
        bool towerCollision = false;
        if (cx1 >= 0 && cx1 < baseWidth && cy1 >= 0 && cy1 < baseDepth && validator.isOnBase(cx1, cy1)) {
          if (validator.towerHeights.containsKey(Point(cx1, cy1))) towerCollision = true;
        }
        if (cx2 >= 0 && cx2 < baseWidth && cy2 >= 0 && cy2 < baseDepth && validator.isOnBase(cx2, cy2)) {
          if (validator.towerHeights.containsKey(Point(cx2, cy2))) towerCollision = true;
        }
        if (towerCollision) continue;

        // 3. Overlap/above check (no track pieces directly above the bowl cells if inside base bounds and on active base)
        bool blockedAbove = false;
        for (final p in validator.placed) {
          for (final cell in p.cells) {
            if (cx1 >= 0 && cx1 < baseWidth && cy1 >= 0 && cy1 < baseDepth && validator.isOnBase(cx1, cy1)) {
              if (cell.x == cx1 && cell.y == cy1 && cell.z > 0) {
                blockedAbove = true;
                break;
              }
            }
            if (cx2 >= 0 && cx2 < baseWidth && cy2 >= 0 && cy2 < baseDepth && validator.isOnBase(cx2, cy2)) {
              if (cell.x == cx2 && cell.y == cy2 && cell.z > 0) {
                blockedAbove = true;
                break;
              }
            }
          }
          if (blockedAbove) break;
        }
        if (blockedAbove) continue;

        // Place catcher
        final catcher = PlacedPiece(
          pieceId: 19,
          cells: [cell0, cell1, cell2],
          start: cell0,
          end: cell2,
          outputs: const [],
          origin: cell0,
        );

        validator.place(catcher);
        await build(sockets.sublist(1));
        validator.undo(catcher);
      }
      // If we couldn't place any catcher at this exit, this branch is physically impossible, so we backtrack!
      return;
    }

    final remainingMandatory = mandatoryIds.where((id) => (usedCounts[id] ?? 0) == 0).toSet();
    final firstGroup = <Piece>[];
    final secondGroup = <Piece>[];

    for (final oriented in allOriented) {
      final count = usedCounts[oriented.id] ?? 0;
      final limit = pieceLimits[oriented.id] ?? 0;
      if (count >= limit) continue;
      if (remainingMandatory.contains(oriented.id)) {
        firstGroup.add(oriented);
      } else {
        secondGroup.add(oriented);
      }
    }

    void weightedShuffle(List<Piece> list, int sz) {
      final scored = list.map((piece) {
        final isSplitter = piece.isSplitter;
        final isFunnel = piece.id == 10 || piece.id == 7;
        final double weight;
        if (isSplitter) {
          weight = sz * sz * 10.0;
        } else if (isFunnel) {
          weight = sz * sz * 2.0;
        } else {
          final diff = (maxZ - sz + 1).clamp(1, maxZ);
          weight = diff * diff * 3.0;
        }
        final score = rng.nextDouble() * weight;
        return (piece: piece, score: score);
      }).toList();

      scored.sort((a, b) => b.score.compareTo(a.score));

      list.clear();
      list.addAll(scored.map((item) => item.piece));
    }

    weightedShuffle(firstGroup, sz);
    weightedShuffle(secondGroup, sz);

    final orderedOriented = [...firstGroup, ...secondGroup];

    for (final oriented in orderedOriented) {
      final sdx = oriented.cells[oriented.startIdx].x;
      final sdy = oriented.cells[oriented.startIdx].y;
      final origin = Point3(sx - sdx, sy - sdy, sz);
      final piece = oriented.place(origin);

      final result = validator.canPlace(piece, {socket});
      if (!result.$1) continue;

      validator.place(piece);

      if (countTowers() <= maxTowers) {
        usedCounts[piece.pieceId] = (usedCounts[piece.pieceId] ?? 0) + 1;

        final nextSockets = sockets.sublist(1);
        if (piece.isSplitter) {
          for (final out in piece.outputs) {
            nextSockets.add(Point3(out.x, out.y, out.z - 1));
          }
        } else {
          nextSockets.add(Point3(piece.end.x, piece.end.y, piece.end.z - 1));
        }

        await build(nextSockets);
        usedCounts[piece.pieceId] = (usedCounts[piece.pieceId] ?? 1) - 1;
      }

      validator.undo(piece);
    }
  }

  Future<List<PlacedPiece>> solve() async {
    for (int startZ = maxZ; startZ >= 1; startZ--) {
      final gridPositions = <Point>[];
      for (int ox = 0; ox < baseWidth; ox++) {
        for (int oy = 0; oy < baseDepth; oy++) {
          if (validator.isOnBase(ox, oy)) {
            gridPositions.add(Point(ox, oy));
          }
        }
      }
      rng.shuffle(gridPositions);

      for (final pos in gridPositions) {
        if (timedOut()) break;
        final initialSockets = [Point3(pos.x, pos.y, startZ)];
        await build(initialSockets);
      }

      if (best.isNotEmpty) {
        return List.of(best);
      }
    }

    return List.of(best);
  }

  Future<Map<String, dynamic>> solveDict() async {
    final placed = await solve();
    return {
      'seed': seed,
      'found': placed.isNotEmpty,
      'mandatory_pieces': mandatoryIds,
      'solution': placed.isNotEmpty ? solutionToDict(placed) : null,
    };
  }
}
