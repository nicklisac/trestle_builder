import 'package:flutter/material.dart';
import '../models/solution.dart';

class LegendWidget extends StatelessWidget {
  final List<PieceData> pieces;

  const LegendWidget({super.key, required this.pieces});

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

  @override
  Widget build(BuildContext context) {
    if (pieces.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f0f23).withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFe94560).withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(maxHeight: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PIECES',
            style: TextStyle(
              color: Color(0xFFe94560),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: pieces.length,
              itemBuilder: (context, index) {
                final p = pieces[index];
                final color = _pieceColor(p.pieceId);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'P${p.pieceId}${p.tag}  z=${p.zLevel}',
                        style: const TextStyle(color: Color(0xFFcccccc), fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
