import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/solution.dart';
import '../solver/models.dart' show getBasePositions;
import 'viewer_js_stub.dart' if (dart.library.html) 'viewer_js_web.dart';

// ── Piece metadata ────────────────────────────────────────────────────────────

const _pieceColors = {
  1:  Color(0xFF2ECC71),
  2:  Color(0xFFF1C40F),
  3:  Color(0xFFE74C3C),
  4:  Color(0xFFF1C40F),
  5:  Color(0xFFF1C40F),
  6:  Color(0xFFE67E22),
  7:  Color(0xFF9B59B6),
  8:  Color(0xFFE74C3C),
  9:  Color(0xFF3498DB),
  10: Color(0xFF3498DB),
  11: Color(0xFF2ECC71),
  12: Color(0xFFE74C3C),
  13: Color(0xFF2ECC71),
  14: Color(0xFF9B59B6),
  15: Color(0xFFE67E22),
  16: Color(0xFF3498DB),
  17: Color(0xFFE67E22),
  18: Color(0xFF9B59B6),
  19: Color(0xFF95A5A6),
};

const _pieceNames = {
  1:  'Straight (4×1)',
  2:  'Step Corner',
  3:  'Descent Drop',
  4:  'Double Lane',
  5:  'S-Curve Link',
  6:  'Y-Splitter',
  7:  'Drop Funnel',
  8:  'Sharp Turn',
  9:  'Long S-Curve',
  10: '3D Spiral Hill',
  11: 'Spiral Drop',
  12: 'Loop-back U',
  13: 'Corner U-Turn',
  14: 'Double Step Shift',
  15: 'Medium Curve U',
  16: 'Short Straight (3×2)',
  17: 'L-Turn Curve',
  18: 'S-Bend Short',
  19: 'Marble Catcher',
};

Color _pieceColor(int id) => _pieceColors[id] ?? Colors.white;
String _pieceName(int id) => _pieceNames[id] ?? 'Piece $id';

// ── Data model for a single instruction level ─────────────────────────────────

class _InstructionLevel {
  final int z;
  final List<PieceData> newPieces;
  final List<PieceData> prevPieces;
  /// key = "x,y", value = tower height (number of tower blocks)
  final Map<String, int> newTowers;
  final Map<String, int> prevTowers;
  final int baseCount;

  const _InstructionLevel({
    required this.z,
    required this.newPieces,
    required this.prevPieces,
    required this.newTowers,
    required this.prevTowers,
    required this.baseCount,
  });
}

// ── Build instruction levels from solution ────────────────────────────────────

int _pieceLevel(PieceData p) {
  if (p.cells.isEmpty) return p.start[2];
  return p.cells.map((c) => c[2]).reduce(math.min);
}

List<_InstructionLevel> _buildLevels(SolutionData solution) {
  final pieces = solution.pieces;

  // All distinct levels where at least one piece has its lowest point
  final levelSet = pieces.map(_pieceLevel).toSet().toList()..sort();

  return levelSet.map((z) {
    final newPieces = pieces.where((p) => _pieceLevel(p) == z).toList();
    final prevPieces = pieces.where((p) => _pieceLevel(p) < z).toList();

    // Calculate towers for the current level z (max height min(final_height, z))
    final allTowersNow = <String, int>{};
    for (final p in pieces) {
      final towerPoints = p.isSplitter ? p.outputs : [p.start, p.end];
      for (final pt in towerPoints) {
        final key = '${pt[0]},${pt[1]}';
        final h = pt[2];
        if (h > 0) {
          final currentH = math.min(h, z);
          allTowersNow[key] = math.max(allTowersNow[key] ?? 0, currentH);
        }
      }
    }

    // Calculate towers for the previous level z-1 (max height min(final_height, z-1))
    final prevTowersMap = <String, int>{};
    for (final p in pieces) {
      final towerPoints = p.isSplitter ? p.outputs : [p.start, p.end];
      for (final pt in towerPoints) {
        final key = '${pt[0]},${pt[1]}';
        final h = pt[2];
        if (h > 0) {
          final prevH = math.min(h, z - 1);
          prevTowersMap[key] = math.max(prevTowersMap[key] ?? 0, prevH);
        }
      }
    }

    // "New" towers = tower columns that need more blocks at this level step
    final newTowers = <String, int>{};
    for (final entry in allTowersNow.entries) {
      final key = entry.key;
      final hNow = entry.value;
      final hPrev = prevTowersMap[key] ?? 0;
      final diff = hNow - hPrev;
      if (diff > 0) {
        newTowers[key] = diff;
      }
    }

    // Filter prevTowersMap to only keep towers that were already built at previous steps
    final prevTowers = <String, int>{};
    for (final entry in prevTowersMap.entries) {
      if (entry.value > 0) {
        prevTowers[entry.key] = entry.value;
      }
    }

    return _InstructionLevel(
      z: z,
      newPieces: newPieces,
      prevPieces: prevPieces,
      newTowers: newTowers,
      prevTowers: prevTowers,
      baseCount: solution.baseCount,
    );
  }).toList();
}

// ── Outer boundary path for a set of 2D grid cells ───────────────────────────

/// Returns a Path containing all boundary edges of the given cell set.
/// Boundary edge = an edge between a cell IN the set and one NOT in the set.
/// [inset] shrinks each edge inward from the cell boundary.
Path _outerBoundaryPath(
  Set<(int, int)> cells,
  double cellSize,
  double originX,
  double originY, {
  double inset = 0.0,
}) {
  final path = Path();

  for (final (cx, cy) in cells) {
    final x0 = originX + cx * cellSize + inset;
    final y0 = originY + cy * cellSize + inset;
    final x1 = originX + (cx + 1) * cellSize - inset;
    final y1 = originY + (cy + 1) * cellSize - inset;

    // Top edge
    if (!cells.contains((cx, cy - 1))) {
      path.moveTo(x0, y0);
      path.lineTo(x1, y0);
    }
    // Bottom edge
    if (!cells.contains((cx, cy + 1))) {
      path.moveTo(x0, y1);
      path.lineTo(x1, y1);
    }
    // Left edge
    if (!cells.contains((cx - 1, cy))) {
      path.moveTo(x0, y0);
      path.lineTo(x0, y1);
    }
    // Right edge
    if (!cells.contains((cx + 1, cy))) {
      path.moveTo(x1, y0);
      path.lineTo(x1, y1);
    }
  }
  return path;
}

List<int> _getStartDirection(PieceData p) {
  if (p.cells.isEmpty) return [0, 1];
  final sx = p.start[0];
  final sy = p.start[1];

  int startIdx = -1;
  for (int i = 0; i < p.cells.length; i++) {
    if (p.cells[i][0] == sx && p.cells[i][1] == sy) {
      startIdx = i;
      break;
    }
  }

  if (startIdx != -1) {
    for (int i = startIdx + 1; i < p.cells.length; i++) {
      final cxVal = p.cells[i][0];
      final cyVal = p.cells[i][1];
      final dx = cxVal - sx;
      final dy = cyVal - sy;
      if ((dx.abs() + dy.abs()) == 1) {
        return [dx, dy];
      }
    }
    for (int i = startIdx - 1; i >= 0; i--) {
      final cxVal = p.cells[i][0];
      final cyVal = p.cells[i][1];
      final dx = cxVal - sx;
      final dy = cyVal - sy;
      if ((dx.abs() + dy.abs()) == 1) {
        return [dx, dy];
      }
    }
  }

  // Fallback: point towards the end of the piece
  final ex = p.end[0];
  final ey = p.end[1];
  final dx = ex - sx;
  final dy = ey - sy;
  if (dx.abs() > dy.abs()) {
    return [dx.sign, 0];
  } else if (dy.abs() > dx.abs()) {
    return [0, dy.sign];
  }
  return [0, 1];
}

// ── Custom Painter ────────────────────────────────────────────────────────────

class _DiagramPainter extends CustomPainter {
  final _InstructionLevel level;
  final int gridMinX;
  final int gridMaxX;
  final int gridMinY;
  final int gridMaxY;
  final int baseMinX;
  final int baseMaxX;
  final int baseMinY;
  final int baseMaxY;

  _DiagramPainter({
    required this.level,
    required this.gridMinX,
    required this.gridMaxX,
    required this.gridMinY,
    required this.gridMaxY,
    required this.baseMinX,
    required this.baseMaxX,
    required this.baseMinY,
    required this.baseMaxY,
  });


  void _drawStartTriangle(
    Canvas canvas,
    PieceData p,
    Color color,
    double cellSize,
    double Function(int) cx,
    double Function(int) cy, {
    bool isWashedOut = false,
  }) {
    final sx = p.start[0];
    final sy = p.start[1];
    final px = cx(sx) + cellSize / 2;
    final py = cy(sy) + cellSize / 2;
    final dir = _getStartDirection(p);
    final dx = dir[0];
    final dy = dir[1];

    final r = cellSize * 0.15;
    final path = Path();
    if (dx == 1 && dy == 0) {
      // Right
      path.moveTo(px + r, py);
      path.lineTo(px - r, py - r * 0.85);
      path.lineTo(px - r, py + r * 0.85);
    } else if (dx == -1 && dy == 0) {
      // Left
      path.moveTo(px - r, py);
      path.lineTo(px + r, py - r * 0.85);
      path.lineTo(px + r, py + r * 0.85);
    } else if (dx == 0 && dy == 1) {
      // Down
      path.moveTo(px, py + r);
      path.lineTo(px - r * 0.85, py - r);
      path.lineTo(px + r * 0.85, py - r);
    } else {
      // Up
      path.moveTo(px, py - r);
      path.lineTo(px - r * 0.85, py + r);
      path.lineTo(px + r * 0.85, py + r);
    }
    path.close();

    final fillPaint = Paint()
      ..color = isWashedOut ? color.withOpacity(0.20) : color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = isWashedOut ? const Color(0x55111111) : const Color(0xFF111111)
      ..strokeWidth = isWashedOut ? 1.0 : 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);
  }

  void _drawEndCircle(
    Canvas canvas,
    int gx,
    int gy,
    Color color,
    double cellSize,
    double Function(int) cx,
    double Function(int) cy, {
    bool isWashedOut = false,
  }) {
    final px = cx(gx) + cellSize / 2;
    final py = cy(gy) + cellSize / 2;
    final cr = cellSize * 0.12;

    final fillPaint = Paint()
      ..color = isWashedOut ? color.withOpacity(0.20) : color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(px, py), cr, fillPaint);

    final strokePaint = Paint()
      ..color = isWashedOut ? const Color(0x55111111) : const Color(0xFF111111)
      ..strokeWidth = isWashedOut ? 1.0 : 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(px, py), cr, strokePaint);

    if (!isWashedOut) {
      final whiteDotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), cr * 0.35, whiteDotPaint);
    }
  }

  void _drawSplitterDiamond(
    Canvas canvas,
    PieceData p,
    Color color,
    double cellSize,
    double Function(int) cx,
    double Function(int) cy,
  ) {
    final sx = p.start[0];
    final sy = p.start[1];
    final px = cx(sx) + cellSize / 2;
    final py = cy(sy) + cellSize / 2;

    final r = cellSize * 0.15;
    final path = Path();
    path.moveTo(px, py - r);
    path.lineTo(px + r, py);
    path.lineTo(px, py + r);
    path.lineTo(px - r, py);
    path.close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cols = gridMaxX - gridMinX + 1;
    final rows = gridMaxY - gridMinY + 1;
    if (cols <= 0 || rows <= 0) return;

    const padding = 16.0;
    final cellW = (size.width - padding * 2) / cols;
    final cellH = (size.height - padding * 2) / rows;
    final cellSize = math.min(cellW, cellH);

    // Sizing tiers (per spec: grid > piece outline > tower)
    final pieceInset = cellSize * 0.05;   // piece outlines 5% smaller than cell
    final towerInset = cellSize * 0.15;   // tower squares 15% inset (another 10% smaller)

    // Centre the grid
    final totalW = cellSize * cols;
    final totalH = cellSize * rows;
    final originX = (size.width - totalW) / 2;
    final originY = (size.height - totalH) / 2;

    // Helper: grid coords → canvas coords (top-left of cell)
    double cx(int gx) => originX + (gx - gridMinX) * cellSize;
    double cy(int gy) => originY + (gy - gridMinY) * cellSize;

    // ── 0. Base Plates Background ───────────────────────────────────────────
    final baseFillPaint = Paint()
      ..color = const Color(0xFFF1F1F4)
      ..style = PaintingStyle.fill;
    final baseBorderPaint = Paint()
      ..color = const Color(0xFFB8B8C8)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final basePositions = getBasePositions(level.baseCount);
    for (final bp in basePositions) {
      final bx = bp.x * 5;
      final by = bp.y * 5;
      canvas.drawRect(
        Rect.fromLTRB(cx(bx), cy(by), cx(bx + 5), cy(by + 5)),
        baseFillPaint,
      );
      canvas.drawRect(
        Rect.fromLTRB(cx(bx), cy(by), cx(bx + 5), cy(by + 5)),
        baseBorderPaint,
      );
    }

    // ── 1. Grid background (only within base plate area) ────────────────────
    final gridLinePaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int gx = baseMinX; gx <= baseMaxX + 1; gx++) {
      canvas.drawLine(
        Offset(cx(gx), cy(baseMinY)),
        Offset(cx(gx), cy(baseMaxY + 1)),
        gridLinePaint,
      );
    }
    for (int gy = baseMinY; gy <= baseMaxY + 1; gy++) {
      canvas.drawLine(
        Offset(cx(baseMinX), cy(gy)),
        Offset(cx(baseMaxX + 1), cy(gy)),
        gridLinePaint,
      );
    }

    // ── 2. Previous-level piece fills (washed out) ──────────────────────────
    for (final p in level.prevPieces) {
      final color = _pieceColor(p.pieceId).withOpacity(0.12);
      final fill = Paint()..color = color..style = PaintingStyle.fill;
      final footprint = p.cells.map((c) => (c[0], c[1])).toSet();
      for (final (gx, gy) in footprint) {
        canvas.drawRect(
          Rect.fromLTWH(
            cx(gx) + pieceInset, cy(gy) + pieceInset,
            cellSize - pieceInset * 2, cellSize - pieceInset * 2,
          ),
          fill,
        );
      }
      // Faint outline for previous pieces
      final prevPiecePaint = Paint()
        ..color = _pieceColor(p.pieceId).withOpacity(0.20)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final prevBoundary = _outerBoundaryPath(
        footprint, cellSize,
        originX - gridMinX * cellSize,
        originY - gridMinY * cellSize,
        inset: pieceInset,
      );
      canvas.drawPath(prevBoundary, prevPiecePaint);
    }

    // ── 3. Previous towers (faint gray rounded squares, 10% smaller, no X) ───
    final prevTowerPaint = Paint()
      ..color = const Color(0xFFBBBBBB)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final key in level.prevTowers.keys) {
      final parts = key.split(',');
      final gx = int.parse(parts[0]);
      final gy = int.parse(parts[1]);
      final tRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx(gx) + towerInset, cy(gy) + towerInset,
          cellSize - towerInset * 2, cellSize - towerInset * 2,
        ),
        Radius.circular(cellSize * 0.10),
      );
      canvas.drawRRect(tRect, prevTowerPaint);
    }

    // ── 4. New piece outlines & indicators (outer boundary in piece color) ───
    for (final p in level.newPieces) {
      final color = _pieceColor(p.pieceId);
      final footprint = p.cells.map((c) => (c[0], c[1])).toSet();

      // Faint fill (inset like the outline)
      final fillPaint = Paint()
        ..color = color.withOpacity(0.12)
        ..style = PaintingStyle.fill;
      for (final (gx, gy) in footprint) {
        canvas.drawRect(
          Rect.fromLTWH(
            cx(gx) + pieceInset, cy(gy) + pieceInset,
            cellSize - pieceInset * 2, cellSize - pieceInset * 2,
          ),
          fillPaint,
        );
      }

      // Bold outer boundary stroke with rounded caps
      final strokePaint = Paint()
        ..color = color
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final boundary = _outerBoundaryPath(
        footprint, cellSize,
        originX - gridMinX * cellSize,
        originY - gridMinY * cellSize,
        inset: pieceInset,
      );
      canvas.drawPath(boundary, strokePaint);

      // Draw start and end indicators for new pieces (bold)
      if (p.isSplitter) {
        // For splitters, draw a diamond in the center, and circles at the outputs (no start triangle or end circle at center)
        _drawSplitterDiamond(canvas, p, color, cellSize, cx, cy);
        for (final out in p.outputs) {
          _drawEndCircle(canvas, out[0], out[1], color, cellSize, cx, cy, isWashedOut: false);
        }
      } else {
        _drawStartTriangle(canvas, p, color, cellSize, cx, cy, isWashedOut: false);
        _drawEndCircle(canvas, p.end[0], p.end[1], color, cellSize, cx, cy, isWashedOut: false);
        for (final out in p.outputs) {
          _drawEndCircle(canvas, out[0], out[1], color, cellSize, cx, cy, isWashedOut: false);
        }

        // For decline shapes, draw a simple black '2' in the bottom-right of the start cell
        if (p.end[2] != p.start[2]) {
          final declineStyle = TextStyle(
            color: const Color(0xFF111111),
            fontSize: (cellSize * 0.28).clamp(8.0, 13.0),
            fontWeight: FontWeight.w900,
          );
          final tp = TextPainter(
            text: TextSpan(text: '2', style: declineStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              cx(p.start[0]) + cellSize - towerInset - tp.width - cellSize * 0.04,
              cy(p.start[1]) + cellSize - towerInset - tp.height - cellSize * 0.03,
            ),
          );
        }
      }
    }

    // ── 5. New towers (bold black rounded outlines, layered on top of track lines, hollow) ──
    final newTowerStroke = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final labelStyle = TextStyle(
      color: const Color(0xFF111111),
      fontSize: (cellSize * 0.28).clamp(8.0, 13.0),
      fontWeight: FontWeight.w900,
    );

    for (final entry in level.newTowers.entries) {
      final parts = entry.key.split(',');
      final gx = int.parse(parts[0]);
      final gy = int.parse(parts[1]);
      final height = entry.value;

      final tRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx(gx) + towerInset, cy(gy) + towerInset,
          cellSize - towerInset * 2, cellSize - towerInset * 2,
        ),
        Radius.circular(cellSize * 0.10),
      );
      canvas.drawRRect(tRRect, newTowerStroke);

      // Height label if > 1 (perfectly centered, using e.g., '2x' or '3x')
      if (height > 1) {
        final tp = TextPainter(
          text: TextSpan(text: '${height}x', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            cx(gx) + (cellSize - tp.width) / 2,
            cy(gy) + (cellSize - tp.height) / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DiagramPainter old) =>
      old.gridMinX != gridMinX ||
      old.gridMaxX != gridMaxX ||
      old.gridMinY != gridMinY ||
      old.gridMaxY != gridMaxY ||
      old.baseMinX != baseMinX ||
      old.baseMaxX != baseMaxX ||
      old.baseMinY != baseMinY ||
      old.baseMaxY != baseMaxY;
}

// ── Main overlay widget ───────────────────────────────────────────────────────

class InstructionsOverlay extends StatefulWidget {
  final SolutionData solution;
  final VoidCallback onClose;

  const InstructionsOverlay({
    super.key,
    required this.solution,
    required this.onClose,
  });

  @override
  State<InstructionsOverlay> createState() => _InstructionsOverlayState();
}

class _InstructionsOverlayState extends State<InstructionsOverlay> {
  late final List<_InstructionLevel> _levels;
  late final ScrollController _scrollController;
  final List<GlobalKey> _levelKeys = [];
  int _activeLevel = 0;

  // Grid bounds across the whole solution
  int _gridMinX = 0, _gridMaxX = 0, _gridMinY = 0, _gridMaxY = 0;
  int _baseMinX = 0, _baseMaxX = 0, _baseMinY = 0, _baseMaxY = 0;

  @override
  void initState() {
    super.initState();
    _levels = _buildLevels(widget.solution);
    _scrollController = ScrollController()..addListener(_onScroll);
    for (var i = 0; i < _levels.length; i++) {
      _levelKeys.add(GlobalKey());
    }
    _computeGridBounds();
    // On web, push the viewer iframe behind the Flutter layer
    if (kIsWeb) hideViewerIframe();
  }

  void _computeGridBounds() {
    final basePositions = getBasePositions(widget.solution.baseCount);
    int baseMinX = 0, baseMaxX = 0, baseMinY = 0, baseMaxY = 0;
    for (final pos in basePositions) {
      final bx = pos.x * 5;
      final by = pos.y * 5;
      final bxEnd = bx + 4;
      final byEnd = by + 4;
      if (bx < baseMinX) baseMinX = bx;
      if (bxEnd > baseMaxX) baseMaxX = bxEnd;
      if (by < baseMinY) baseMinY = by;
      if (byEnd > baseMaxY) baseMaxY = byEnd;
    }
    _baseMinX = baseMinX;
    _baseMaxX = baseMaxX;
    _baseMinY = baseMinY;
    _baseMaxY = baseMaxY;

    int minGX = baseMinX, maxGX = baseMaxX, minGY = baseMinY, maxGY = baseMaxY;
    for (final p in widget.solution.pieces) {
      for (final c in p.cells) {
        if (c[0] < minGX) minGX = c[0];
        if (c[0] > maxGX) maxGX = c[0];
        if (c[1] < minGY) minGY = c[1];
        if (c[1] > maxGY) maxGY = c[1];
      }
      for (final o in p.outputs) {
        if (o[0] < minGX) minGX = o[0];
        if (o[0] > maxGX) maxGX = o[0];
        if (o[1] < minGY) minGY = o[1];
        if (o[1] > maxGY) maxGY = o[1];
      }
    }
    _gridMinX = minGX;
    _gridMaxX = maxGX;
    _gridMinY = minGY;
    _gridMaxY = maxGY;
  }

  @override
  void dispose() {
    if (kIsWeb) showViewerIframe();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Find which level card is most visible
    for (int i = _levels.length - 1; i >= 0; i--) {
      final ctx = _levelKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final pos = box.localToGlobal(Offset.zero);
      if (pos.dy < MediaQuery.of(context).size.height * 0.5) {
        if (_activeLevel != i) {
          setState(() => _activeLevel = i);
        }
        break;
      }
    }
  }

  void _jumpTo(int index) {
    final ctx = _levelKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
    setState(() => _activeLevel = index);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        color: const Color(0xF0080818),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                _buildHeader(),
                _buildJumpBar(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                    child: Column(
                      children: List.generate(_levels.length, (i) => _buildLevelCard(i)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 72, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a1e),
        border: Border(
          bottom: BorderSide(color: const Color(0xFFe94560).withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BUILDING INSTRUCTIONS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Build from bottom up · tap a level to jump',
                  style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Save PDF Button
          _HeaderButton(
            onPressed: _exporting ? null : _exportToPdf,
            icon: Icons.picture_as_pdf,
            loading: _exporting,
          ),
          _HeaderButton(
            onPressed: widget.onClose,
            icon: Icons.close,
            loading: false,
          ),
        ],
      ),
    );
  }


  Widget _buildJumpBar() {
    return Container(
      height: 44,
      color: const Color(0xFF0d0d26),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _levels.length,
        itemBuilder: (context, i) {
          final level = _levels[i];
          final isActive = i == _activeLevel;
          return GestureDetector(
            onTap: () => _jumpTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFe94560)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFFe94560)
                      : Colors.white.withOpacity(0.12),
                ),
              ),
              child: Text(
                level.z == 0 ? 'Base' : 'L${level.z}',
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF888888),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLevelCard(int index) {
    final level = _levels[index];
    final isBase = level.z == 0;

    // Count total new tower blocks for this step
    final totalNewTowerBlocks = level.newTowers.values.fold(0, (sum, val) => sum + val);

    return Container(
      key: _levelKeys[index],
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0f0f2a),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            color: const Color(0xFFe94560).withOpacity(0.08),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFe94560),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'STEP ${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isBase ? 'Ground Level — Catchers & Base' : 'Height Level ${level.z}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  '${level.newPieces.length} piece${level.newPieces.length != 1 ? "s" : ""}',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Diagram
          Container(
            color: const Color(0xFFF7F5F0),
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: (_baseMaxX - _baseMinX + 1) / (_baseMaxY - _baseMinY + 1),
              child: CustomPaint(
                painter: _DiagramPainter(
                  level: level,
                  gridMinX: _gridMinX,
                  gridMaxX: _gridMaxX,
                  gridMinY: _gridMinY,
                  gridMaxY: _gridMaxY,
                  baseMinX: _baseMinX,
                  baseMaxX: _baseMaxX,
                  baseMinY: _baseMinY,
                  baseMaxY: _baseMaxY,
                ),
              ),
            ),
          ),

          // Legend row: new tower key + piece list
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Instructions legend
                Row(
                  children: [
                    Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF888888), width: 1.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Place towers first, then tracks. A number inside a tower indicates how many tower blocks to place.',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'PIECES TO PLACE',
                  style: TextStyle(
                    color: Color(0xFFe94560),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (totalNewTowerBlocks > 0) _towerChip(totalNewTowerBlocks),
                    ...level.newPieces.map((p) => _pieceChip(p)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _towerChip(int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF555555).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF888888).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF555555), width: 1.5),
            ),
            child: const Center(
              child: Text(
                'T',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'Support Towers: $count',
            style: const TextStyle(
              color: Color(0xFFDDDDDD),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pieceChip(PieceData p) {
    final color = _pieceColor(p.pieceId);
    final name = _pieceName(p.pieceId);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text(
                'P${p.pieceId}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            name,
            style: const TextStyle(
              color: Color(0xFFDDDDDD),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  bool _exporting = false;

  Future<void> _exportToPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final pdf = pw.Document();

      for (int index = 0; index < _levels.length; index++) {
        final level = _levels[index];
        final isBase = level.z == 0;
        final totalNewTowerBlocks = level.newTowers.values.fold(0, (sum, val) => sum + val);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header Row
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'TRESTLE TRACK BUILDER',
                            style: pw.TextStyle(
                              color: PdfColor.fromInt(0xFFE94560),
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'STEP ${index + 1} of ${_levels.length}',
                            style: pw.TextStyle(
                              color: PdfColor.fromInt(0xFF111111),
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFE94560),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
                        ),
                        child: pw.Text(
                          isBase ? 'GROUND LEVEL' : 'HEIGHT LEVEL ${level.z}',
                          style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFFFFFFFF),
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),
                  pw.Divider(color: PdfColor.fromInt(0xFFEEEEEE), thickness: 1),
                  pw.SizedBox(height: 16),

                  // Diagram Container
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFF7F5F0),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                          border: pw.Border.all(color: PdfColor.fromInt(0xFFE0DCD3), width: 1),
                        ),
                        padding: const pw.EdgeInsets.all(16),
                        child: pw.AspectRatio(
                          aspectRatio: (_gridMaxX - _gridMinX + 1) / (_gridMaxY - _gridMinY + 1),
                          child: pw.Stack(
                            children: [
                              pw.CustomPaint(
                                size: PdfPoint(500, 500 * (_gridMaxY - _gridMinY + 1) / (_gridMaxX - _gridMinX + 1)),
                                painter: (PdfGraphics canvas, PdfPoint size) {
                                  _paintPdfDiagram(canvas, size, level);
                                },
                              ),
                              ..._buildPdfLabels(level, 500, 500 * (_gridMaxY - _gridMinY + 1) / (_gridMaxX - _gridMinX + 1)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 20),

                  // Legend / Instructions
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 14,
                        height: 14,
                        margin: const pw.EdgeInsets.only(top: 2),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColor.fromInt(0xFF888888), width: 1.5),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Text(
                          'Place towers first, then tracks. A number inside a tower indicates how many tower blocks to place.',
                          style: pw.TextStyle(
                            color: PdfColor.fromInt(0xFF666666),
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),

                  // Pieces to place
                  pw.Text(
                    'PIECES TO PLACE AT THIS STEP',
                    style: pw.TextStyle(
                      color: PdfColor.fromInt(0xFFE94560),
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (totalNewTowerBlocks > 0) _buildPdfTowerChip(totalNewTowerBlocks),
                      ...level.newPieces.map((p) => _buildPdfPieceChip(p)),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      }

      final bytes = await pdf.save();
       final seed = widget.solution.seed ?? 'random';
       savePdfFile(bytes, 'trestle_track_instructions_$seed.pdf');
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save PDF: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  void _paintPdfDiagram(PdfGraphics canvas, PdfPoint size, _InstructionLevel level) {
    final cols = _gridMaxX - _gridMinX + 1;
    final rows = _gridMaxY - _gridMinY + 1;
    if (cols <= 0 || rows <= 0) return;

    final width = size.x;
    final height = size.y;

    const padding = 16.0;
    final cellW = (width - padding * 2) / cols;
    final cellH = (height - padding * 2) / rows;
    final cellSize = math.min(cellW, cellH);

    final pieceInset = cellSize * 0.05;
    final towerInset = cellSize * 0.15;

    final totalW = cellSize * cols;
    final totalH = cellSize * rows;
    final originX = (width - totalW) / 2;
    final originY = (height - totalH) / 2;

    double cx(int gx) => originX + (gx - _gridMinX) * cellSize;
    double cy(int gy) => originY + (gy - _gridMinY) * cellSize;

    double pdfY(double y) => height - y;

    // Helper: draw rect
    void drawPdfRect(double x, double y, double w, double h) {
      canvas.drawRect(x, height - (y + h), w, h);
    }

    // Helper: draw rounded rect
    void drawPdfRRect(double x, double y, double w, double h, double r) {
      canvas.drawRRect(x, height - (y + h), w, h, r, r);
    }

    // Helper: draw ellipse/circle
    void drawPdfCircle(double px, double py, double r) {
      canvas.drawEllipse(px, height - py, r, r);
    }

    // Helper: draw start triangle
    void drawPdfStartTriangle(PieceData p, PdfColor color, {bool isWashedOut = false}) {
      final sx = p.start[0];
      final sy = p.start[1];
      final px = cx(sx) + cellSize / 2;
      final py = cy(sy) + cellSize / 2;
      final dir = _getStartDirection(p);
      final dx = dir[0];
      final dy = dir[1];

      final r = cellSize * 0.15;
      
      void addPath() {
        if (dx == 1 && dy == 0) {
          canvas.moveTo(px + r, height - py);
          canvas.lineTo(px - r, height - (py - r * 0.85));
          canvas.lineTo(px - r, height - (py + r * 0.85));
        } else if (dx == -1 && dy == 0) {
          canvas.moveTo(px - r, height - py);
          canvas.lineTo(px + r, height - (py - r * 0.85));
          canvas.lineTo(px + r, height - (py + r * 0.85));
        } else if (dx == 0 && dy == 1) {
          canvas.moveTo(px, height - (py + r));
          canvas.lineTo(px - r * 0.85, height - (py - r));
          canvas.lineTo(px + r * 0.85, height - (py - r));
        } else {
          canvas.moveTo(px, height - (py - r));
          canvas.lineTo(px - r * 0.85, height - (py + r));
          canvas.lineTo(px + r * 0.85, height - (py + r));
        }
        canvas.closePath();
      }

      addPath();
      final fillColor = isWashedOut ? PdfColor(color.red, color.green, color.blue, 0.20) : color;
      canvas.setFillColor(fillColor);
      canvas.fillPath();

      addPath();
      final strokeColor = isWashedOut ? PdfColor.fromInt(0x55111111) : PdfColor.fromInt(0xFF111111);
      canvas.setStrokeColor(strokeColor);
      canvas.setLineWidth(isWashedOut ? 1.0 : 1.8);
      canvas.setLineCap(PdfLineCap.round);
      canvas.setLineJoin(PdfLineJoin.round);
      canvas.strokePath();
    }

    // Helper: draw end circle
    void drawPdfEndCircle(int gx, int gy, PdfColor color, {bool isWashedOut = false}) {
      final px = cx(gx) + cellSize / 2;
      final py = cy(gy) + cellSize / 2;
      final cr = cellSize * 0.12;

      final fillColor = isWashedOut ? PdfColor(color.red, color.green, color.blue, 0.20) : color;
      canvas.setFillColor(fillColor);
      drawPdfCircle(px, py, cr);
      canvas.fillPath();

      final strokeColor = isWashedOut ? PdfColor.fromInt(0x55111111) : PdfColor.fromInt(0xFF111111);
      canvas.setStrokeColor(strokeColor);
      canvas.setLineWidth(isWashedOut ? 1.0 : 1.8);
      drawPdfCircle(px, py, cr);
      canvas.strokePath();

      if (!isWashedOut) {
        canvas.setFillColor(PdfColor.fromInt(0xFFFFFFFF));
        drawPdfCircle(px, py, cr * 0.35);
        canvas.fillPath();
      }
    }

    // Helper: draw splitter diamond
    void drawPdfSplitterDiamond(PieceData p, PdfColor color) {
      final sx = p.start[0];
      final sy = p.start[1];
      final px = cx(sx) + cellSize / 2;
      final py = cy(sy) + cellSize / 2;

      final r = cellSize * 0.15;
      
      void addPath() {
        canvas.moveTo(px, height - (py - r));
        canvas.lineTo(px + r, height - py);
        canvas.lineTo(px, height - (py + r));
        canvas.lineTo(px - r, height - py);
        canvas.closePath();
      }

      addPath();
      canvas.setFillColor(color);
      canvas.fillPath();

      addPath();
      canvas.setStrokeColor(PdfColor.fromInt(0xFF111111));
      canvas.setLineWidth(1.8);
      canvas.setLineCap(PdfLineCap.round);
      canvas.setLineJoin(PdfLineJoin.round);
      canvas.strokePath();
    }

    // Helper: draw outer boundary path
    void drawPdfOuterBoundary(Set<(int, int)> cells, double inset) {
      for (final (cxVal, cyVal) in cells) {
        final x0 = cx(cxVal) + inset;
        final y0 = cy(cyVal) + inset;
        final x1 = cx(cxVal) + cellSize - inset;
        final y1 = cy(cyVal) + cellSize - inset;

        // Top edge
        if (!cells.contains((cxVal, cyVal - 1))) {
          canvas.moveTo(x0, height - y0);
          canvas.lineTo(x1, height - y0);
        }
        // Bottom edge
        if (!cells.contains((cxVal, cyVal + 1))) {
          canvas.moveTo(x0, height - y1);
          canvas.lineTo(x1, height - y1);
        }
        // Left edge
        if (!cells.contains((cxVal - 1, cyVal))) {
          canvas.moveTo(x0, height - y0);
          canvas.lineTo(x0, height - y1);
        }
        // Right edge
        if (!cells.contains((cxVal + 1, cyVal))) {
          canvas.moveTo(x1, height - y0);
          canvas.lineTo(x1, height - y1);
        }
      }
    }

    // 1. Grid background
    canvas.setLineWidth(1.2);
    canvas.setStrokeColor(PdfColor.fromInt(0xFFCCCCCC));
    canvas.setLineCap(PdfLineCap.round);

    for (int gx = _baseMinX; gx <= _baseMaxX + 1; gx++) {
      canvas.drawLine(cx(gx), pdfY(cy(_baseMinY)), cx(gx), pdfY(cy(_baseMaxY + 1)));
      canvas.strokePath();
    }
    for (int gy = _baseMinY; gy <= _baseMaxY + 1; gy++) {
      canvas.drawLine(cx(_baseMinX), pdfY(cy(gy)), cx(_baseMaxX + 1), pdfY(cy(gy)));
      canvas.strokePath();
    }

    // 2. Previous pieces (washed out - solid blended light pastels)
    for (final p in level.prevPieces) {
      final color = PdfColor.fromInt(_pieceColor(p.pieceId).toARGB32());
      final footprint = p.cells.map((c) => (c[0], c[1])).toSet();

      // Faint mix color (5% original color, 95% white)
      final mixedFill = PdfColor(
        color.red * 0.05 + 0.95,
        color.green * 0.05 + 0.95,
        color.blue * 0.05 + 0.95,
      );
      canvas.setFillColor(mixedFill);
      for (final (gx, gy) in footprint) {
        drawPdfRect(cx(gx) + pieceInset, cy(gy) + pieceInset, cellSize - pieceInset * 2, cellSize - pieceInset * 2);
        canvas.fillPath();
      }

      // Faint mixed stroke (12% original color, 88% white)
      final mixedStroke = PdfColor(
        color.red * 0.12 + 0.88,
        color.green * 0.12 + 0.88,
        color.blue * 0.12 + 0.88,
      );
      canvas.setStrokeColor(mixedStroke);
      canvas.setLineWidth(1.0);
      canvas.setLineCap(PdfLineCap.round);
      canvas.setLineJoin(PdfLineJoin.round);
      drawPdfOuterBoundary(footprint, pieceInset);
      canvas.strokePath();
    }

    // 3. Previous towers
    canvas.setStrokeColor(PdfColor.fromInt(0xFFBBBBBB));
    canvas.setLineWidth(1.2);
    canvas.setLineCap(PdfLineCap.round);
    canvas.setLineJoin(PdfLineJoin.round);

    for (final key in level.prevTowers.keys) {
      final parts = key.split(',');
      final gx = int.parse(parts[0]);
      final gy = int.parse(parts[1]);
      drawPdfRRect(cx(gx) + towerInset, cy(gy) + towerInset, cellSize - towerInset * 2, cellSize - towerInset * 2, cellSize * 0.10);
      canvas.strokePath();
    }

    // 4. New pieces (tracks - drawn below towers)
    for (final p in level.newPieces) {
      final color = PdfColor.fromInt(_pieceColor(p.pieceId).toARGB32());
      final footprint = p.cells.map((c) => (c[0], c[1])).toSet();

      // Faint blend fill (10% original color, 90% white to prevent blocking towers)
      final mixedFill = PdfColor(
        color.red * 0.10 + 0.90,
        color.green * 0.10 + 0.90,
        color.blue * 0.10 + 0.90,
      );
      canvas.setFillColor(mixedFill);
      for (final (gx, gy) in footprint) {
        drawPdfRect(cx(gx) + pieceInset, cy(gy) + pieceInset, cellSize - pieceInset * 2, cellSize - pieceInset * 2);
        canvas.fillPath();
      }

      // Outline in full, bold color
      canvas.setStrokeColor(color);
      canvas.setLineWidth(2.8);
      canvas.setLineCap(PdfLineCap.round);
      canvas.setLineJoin(PdfLineJoin.round);
      drawPdfOuterBoundary(footprint, pieceInset);
      canvas.strokePath();

      // Indicators
      if (p.isSplitter) {
        drawPdfSplitterDiamond(p, color);
        for (final out in p.outputs) {
          drawPdfEndCircle(out[0], out[1], color, isWashedOut: false);
        }
      } else {
        drawPdfStartTriangle(p, color, isWashedOut: false);
        drawPdfEndCircle(p.end[0], p.end[1], color, isWashedOut: false);
        for (final out in p.outputs) {
          drawPdfEndCircle(out[0], out[1], color, isWashedOut: false);
        }
      }
    }

    // 5. New towers (drawn on top as clean, hollow outlines)
    for (final entry in level.newTowers.entries) {
      final parts = entry.key.split(',');
      final gx = int.parse(parts[0]);
      final gy = int.parse(parts[1]);

      // Outlines only (NO black or opaque fill!)
      canvas.setStrokeColor(PdfColor.fromInt(0xFF111111));
      canvas.setLineWidth(2.2);
      canvas.setLineCap(PdfLineCap.round);
      canvas.setLineJoin(PdfLineJoin.round);
      drawPdfRRect(cx(gx) + towerInset, cy(gy) + towerInset, cellSize - towerInset * 2, cellSize - towerInset * 2, cellSize * 0.10);
      canvas.strokePath();
    }
  }

  List<pw.Widget> _buildPdfLabels(_InstructionLevel level, double width, double height) {
    final layout = _PdfLayoutHelper(
      width: width,
      height: height,
      gridMinX: _gridMinX,
      gridMaxX: _gridMaxX,
      gridMinY: _gridMinY,
      gridMaxY: _gridMaxY,
    );


    final widgets = <pw.Widget>[];

    // New towers heights (> 1)
    for (final entry in level.newTowers.entries) {
      final parts = entry.key.split(',');
      final gx = int.parse(parts[0]);
      final gy = int.parse(parts[1]);
      final heightVal = entry.value;

      if (heightVal > 1) {
        widgets.add(
          pw.Positioned(
            left: layout.labelX(gx),
            top: layout.labelY(gy),
            child: pw.SizedBox(
              width: layout.cellSize,
              height: layout.cellSize,
              child: pw.Center(
                child: pw.Text(
                  '${heightVal}x',
                  style: pw.TextStyle(
                    fontSize: (layout.cellSize * 0.28).clamp(8.0, 13.0),
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF111111),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Decline '2' markers
    final towerInset = layout.cellSize * 0.15;
    for (final p in level.newPieces) {
      if (!p.isSplitter && p.end[2] != p.start[2]) {
        final sx = p.start[0];
        final sy = p.start[1];
        widgets.add(
          pw.Positioned(
            left: layout.labelX(sx),
            top: layout.labelY(sy),
            child: pw.SizedBox(
              width: layout.cellSize,
              height: layout.cellSize,
              child: pw.Align(
                alignment: pw.Alignment.bottomRight,
                child: pw.Container(
                  margin: pw.EdgeInsets.only(
                    right: towerInset + layout.cellSize * 0.04,
                    bottom: towerInset + layout.cellSize * 0.03,
                  ),
                  child: pw.Text(
                    '2',
                    style: pw.TextStyle(
                      fontSize: (layout.cellSize * 0.28).clamp(8.0, 13.0),
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF111111),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  pw.Widget _buildPdfTowerChip(int count) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 4, 10, 4),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0x0E555555),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColor.fromInt(0x22888888), width: 1),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 20,
            height: 20,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF333333),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              border: pw.Border.all(color: PdfColor.fromInt(0xFF555555), width: 1),
            ),
            child: pw.Center(
              child: pw.Text(
                'T',
                style: pw.TextStyle(
                  color: PdfColor.fromInt(0xFFFFFFFF),
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            'Support Towers: $count',
            style: pw.TextStyle(
              color: PdfColor.fromInt(0xFF222222),
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfPieceChip(PieceData p) {
    final colorVal = _pieceColor(p.pieceId).toARGB32();
    final color = PdfColor.fromInt(colorVal);
    final name = _pieceName(p.pieceId);
    
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(6, 4, 10, 4),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red, color.green, color.blue, 0.10),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColor(color.red, color.green, color.blue, 0.40), width: 1),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 20,
            height: 20,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Center(
              child: pw.Text(
                'P${p.pieceId}',
                style: pw.TextStyle(
                  color: PdfColor.fromInt(0xFFFFFFFF),
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            name,
            style: pw.TextStyle(
              color: PdfColor.fromInt(0xFF222222),
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfLayoutHelper {
  final double width;
  final double height;
  final int gridMinX;
  final int gridMaxX;
  final int gridMinY;
  final int gridMaxY;

  late final double cellSize;
  late final double originX;
  late final double originY;

  _PdfLayoutHelper({
    required this.width,
    required this.height,
    required this.gridMinX,
    required this.gridMaxX,
    required this.gridMinY,
    required this.gridMaxY,
  }) {
    final cols = gridMaxX - gridMinX + 1;
    final rows = gridMaxY - gridMinY + 1;
    
    const padding = 16.0;
    final cellW = (width - padding * 2) / cols;
    final cellH = (height - padding * 2) / rows;
    cellSize = math.min(cellW, cellH);

    final totalW = cellSize * cols;
    final totalH = cellSize * rows;
    originX = (width - totalW) / 2;
    originY = (height - totalH) / 2;
  }

  double labelX(int gx) => originX + (gx - gridMinX) * cellSize;
  double labelY(int gy) => originY + (gy - gridMinY) * cellSize;
}

class _HeaderButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final bool loading;
  const _HeaderButton({required this.onPressed, required this.icon, required this.loading});

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onPressed != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: _hover
                ? (widget.onPressed != null ? const Color(0xFFe94560).withOpacity(0.2) : Colors.white.withOpacity(0.06))
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hover ? const Color(0xFFe94560).withOpacity(0.5) : Colors.white.withOpacity(0.12),
            ),
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFAAAAAA),
                    ),
                  )
                : Icon(widget.icon, color: const Color(0xFFAAAAAA), size: 18),
          ),
        ),
      ),
    );
  }
}

