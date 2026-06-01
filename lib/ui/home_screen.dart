import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/solution.dart';
import '../solver/solver.dart' as ts;
import '../solver/models.dart' as ts_models;
import 'viewer_widget.dart';
import 'legend_widget.dart';
import 'mandatory_widget.dart';
import 'viewer_js_stub.dart' if (dart.library.html) 'viewer_js_web.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _seedController = TextEditingController();
  final _viewerController = TrackViewerController();
  SolutionData? _solution;
  bool _solving = false;
  String? _error;
  List<int> _mandatoryPieces = [];

  Future<SolutionData?> _runSolverAsync(int? seed) async {
    final solver = ts.Solver(
      inventory: ts_models.INVENTORY,
      timeoutSec: 30.0,
      maxTowers: 100,
      seed: seed,
      onProgress: (placed) {
        if (!mounted) return;
        // Build intermediate SolutionData to render on the fly
        final solution = SolutionData(
          seed: seed,
          pieceCount: placed.length,
          towerCount: 0,
          towerMap: const {},
          pieces: placed.map((p) => PieceData(
            pieceId: p.pieceId,
            origin: [p.origin.x, p.origin.y, p.origin.z],
            start: [p.start.x, p.start.y, p.start.z],
            end: [p.end.x, p.end.y, p.end.z],
            outputs: p.outputs.map((o) => [o.x, o.y, o.z]).toList(),
            cells: p.cells.map((c) => [c.x, c.y, c.z]).toList(),
            isSplitter: p.isSplitter,
          )).toList(),
        );
        _viewerController.render(solution, seed: seed);
      },
    );

    setState(() {
      _mandatoryPieces = solver.mandatoryIds;
    });

    if (kIsWeb) {
      sendToViewer({
        'type': 'mandatory_pieces',
        'seed': seed,
        'pieces': solver.mandatoryIds,
      });
    }

    final result = await solver.solveDict();
    if (result['found'] == true && result['solution'] != null) {
      return SolutionData.fromJson(result['solution'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<void> _solve({int? seed}) async {
    if (!mounted) return;
    final resolvedSeed = seed ?? DateTime.now().millisecondsSinceEpoch % 1000000;
    _seedController.text = resolvedSeed.toString();

    setState(() {
      _solving = true;
      _error = null;
      _mandatoryPieces = [];
    });

    await _viewerController.clear();

    try {
      final result = await _runSolverAsync(resolvedSeed);
      if (!mounted) return;

      if (result != null) {
        setState(() {
          _solution = result;
          _solving = false;
          _error = null;
        });
        if (!kIsWeb) {
          await _viewerController.hideUi();
        }
        await _viewerController.render(result, seed: seed);
        if (kIsWeb) {
          sendToViewer({'type': 'solved'});
        }
      } else {
        setState(() {
          _error = 'No solution found. Try another seed.';
          _solving = false;
        });
        if (kIsWeb) {
          sendToViewer({'type': 'solved'});
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error solving. Try again.';
        _solving = false;
      });
      if (kIsWeb) {
        sendToViewer({'type': 'solved'});
      }
    }
  }

  Future<void> _randomSolve() async {
    final seed = DateTime.now().millisecondsSinceEpoch % 1000000;
    _seedController.text = seed.toString();
    await _solve(seed: seed);
  }

  @override
  void initState() {
    super.initState();
    _viewerController.onSolve = _solveWithSeed;
  }

  Future<void> _solveWithSeed({int? seed}) async {
    await _solve(seed: seed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Offstage(
              offstage: kIsWeb,
              child: TrackViewer(controller: _viewerController),
            ),
          ),

          // Top bar
          if (!kIsWeb)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0f0f23).withOpacity(0.95),
                    const Color(0xFF0f0f23).withOpacity(0.7),
                  ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    'Seed',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _seedController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'random',
                        hintStyle: const TextStyle(color: Color(0xFF555555)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFF444444)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFF444444)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: Color(0xFFe94560)),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1a1a2e),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _solving ? null : () {
                      final seed = _seedController.text.isEmpty
                          ? null
                          : int.tryParse(_seedController.text);
                      _solve(seed: seed);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFe94560),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: _solving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Generate'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _solving ? null : _randomSolve,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF533483),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: const Text('Random'),
                  ),
                  const Spacer(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFe94560), fontSize: 13),
                    ),
                ],
              ),
            ),
          ),

          // Mandatory and Legend panels - shown on mobile only (web uses HTML overlay)
          if (_mandatoryPieces.isNotEmpty && !kIsWeb)
            Positioned(
              bottom: 16,
              left: 16,
              child: SizedBox(
                width: 200,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MandatoryWidget(mandatoryIds: _mandatoryPieces),
                    if (_solution != null) ...[
                      const SizedBox(height: 10),
                      LegendWidget(pieces: _solution!.pieces),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
