import 'package:flutter/material.dart';

class MandatoryWidget extends StatelessWidget {
  final List<int> mandatoryIds;

  const MandatoryWidget({super.key, required this.mandatoryIds});

  Color _pieceColor(int pieceId) {
    const colors = {
      1: Color(0xFF2ECC71),  // Green
      2: Color(0xFF3498DB),  // Blue
      3: Color(0xFFE74C3C),  // Red
      4: Color(0xFFF1C40F),  // Yellow
      5: Color(0xFFF1C40F),  // Yellow
      6: Color(0xFFE67E22),  // Orange
      7: Color(0xFF9B59B6),  // Purple
      8: Color(0xFFE74C3C),  // Red
      9: Color(0xFF3498DB),  // Blue
      10: Color(0xFF3498DB), // Blue
      11: Color(0xFF2ECC71), // Green
      12: Color(0xFFE74C3C), // Red
      13: Color(0xFF2ECC71), // Green
      14: Color(0xFF9B59B6), // Purple
      15: Color(0xFFE67E22), // Orange
      16: Color(0xFF3498DB), // Blue
      17: Color(0xFFE67E22), // Orange
      18: Color(0xFF9B59B6), // Purple
    };
    return colors[pieceId] ?? Colors.white;
  }

  String _pieceName(int pieceId) {
    const names = {
      1: "Straight (4x1)",
      2: "Step Corner",
      3: "Descent Drop",
      4: "Double Lane",
      5: "S-Curve Link",
      6: "Y-Splitter",
      7: "Drop Funnel",
      8: "Sharp Turn",
      9: "Long S-Curve",
      10: "3D Spiral Hill",
      11: "Spiral Drop",
      12: "Loop-back U",
      13: "Corner U-Turn",
      14: "Double Step Shift",
      15: "Medium Curve U",
      16: "Short Straight (3x2)",
      17: "L-Turn Curve",
      18: "S-Bend Short",
    };
    return names[pieceId] ?? "Piece $pieceId";
  }

  @override
  Widget build(BuildContext context) {
    if (mandatoryIds.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f0f23).withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFe94560).withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: Color(0xFFe94560), size: 14),
              const SizedBox(width: 6),
              const Text(
                'MANDATORY PUZZLE',
                style: TextStyle(
                  color: Color(0xFFe94560),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...mandatoryIds.map((id) {
            final color = _pieceColor(id);
            final name = _pieceName(id);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'P$id',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            offset: Offset(0, 1),
                            blurRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: Color(0xFFeeeeee), fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
