import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/solution.dart';
import '../solver/solver.dart' as ts;
import '../solver/models.dart' as ts_models;
import 'viewer_widget.dart';
import 'legend_widget.dart';
import 'mandatory_widget.dart';
import 'instructions_overlay.dart';
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
  bool _showInstructions = false;

  int _deluxeCount = 1;
  int _builderCount = 0;
  int _starterCount = 0;

  Map<int, int> _computePieceLimits() {
    final limits = <int, int>{};
    for (int i = 1; i <= 18; i++) {
      limits[i] = 0;
    }
    if (_deluxeCount > 0) {
      for (int i = 1; i <= 18; i++) {
        limits[i] = (limits[i] ?? 0) + _deluxeCount * 1;
      }
    }
    if (_builderCount > 0) {
      final builderPieces = [17, 15, 18, 12, 5, 13, 10, 9, 3, 4];
      for (final id in builderPieces) {
        limits[id] = (limits[id] ?? 0) + _builderCount * 1;
      }
    }
    if (_starterCount > 0) {
      final starterPieces = [2, 14, 15, 16, 8, 1];
      for (final id in starterPieces) {
        limits[id] = (limits[id] ?? 0) + _starterCount * 1;
      }
    }
    return limits;
  }

  Future<SolutionData?> _runSolverAsync(int? seed) async {
    int currentSeed = seed ?? DateTime.now().millisecondsSinceEpoch % 1000000;

    final limits = _computePieceLimits();
    final baseCount = _deluxeCount * 2 + _builderCount * 1 + _starterCount * 1;
    final activeBaseCount = baseCount > 0 ? baseCount : 2;
    final maxTowers = _deluxeCount * 90 + _builderCount * 45 + _starterCount * 30;
    final activeMaxTowers = maxTowers > 0 ? maxTowers : 90;

    final totalPieces = limits.values.fold(0, (a, b) => a + b);
    final calculatedIterations = (totalPieces / 10).ceil() * 4000;
    final activeMaxIterations = calculatedIterations.clamp(5000, 10000);
    final dynamicTimeout = (activeMaxIterations / 10000) * 3.0;
    final activeMaxZ = totalPieces.clamp(2, 30);
    int currentMaxZ = activeMaxZ;
    bool decreasing = true;
    final minAllowedZ = activeMaxZ > 15 ? 15 : (activeMaxZ > 5 ? 5 : 2);

    while (mounted) {
      final solver = ts.Solver(
        inventory: ts_models.INVENTORY,
        pieceLimits: limits,
        basePositions: ts_models.getBasePositions(activeBaseCount),
        catcherCount: _deluxeCount * 2 + _builderCount * 1 + _starterCount * 1,
        maxZ: currentMaxZ,
        timeoutSec: dynamicTimeout, // Dynamic back-up safety time limit per seed
        maxIterations: activeMaxIterations, // Dynamic iterations: 5000 per 10 pieces in play
        maxTowers: activeMaxTowers,
        seed: currentSeed,
        onProgress: (placed) {
          if (!mounted) return;
          // Build intermediate SolutionData to render on the fly
          final solution = SolutionData(
            seed: currentSeed,
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
            baseCount: activeBaseCount,
          );
          _viewerController.render(solution, seed: currentSeed);
        },
      );

      setState(() {
        _mandatoryPieces = solver.mandatoryIds;
      });

      if (kIsWeb) {
        sendToViewer({
          'type': 'mandatory_pieces',
          'seed': currentSeed,
          'pieces': solver.mandatoryIds,
        });
      }

      final result = await solver.solveDict();
      if (result['found'] == true && result['solution'] != null) {
        // Solution successfully found! Update the controller to reflect the seed that worked
        _seedController.text = currentSeed.toString();
        final solMap = Map<String, dynamic>.from(result['solution'] as Map);
        solMap['base_count'] = activeBaseCount;
        return SolutionData.fromJson(solMap);
      }

      // No solution found in activeMaxIterations. Let's discard and reseed!
      debugPrint('Seed $currentSeed had no solution in $activeMaxIterations iterations at height $currentMaxZ. Reseeding...');
      currentSeed = DateTime.now().millisecondsSinceEpoch % 1000000;

      // Oscillate seed height wave!
      if (decreasing) {
        if (currentMaxZ > minAllowedZ) {
          currentMaxZ--;
        } else {
          decreasing = false;
          currentMaxZ = (minAllowedZ + 1).clamp(minAllowedZ, activeMaxZ);
        }
      } else {
        if (currentMaxZ < activeMaxZ) {
          currentMaxZ++;
        } else {
          decreasing = true;
          currentMaxZ = (activeMaxZ - 1).clamp(minAllowedZ, activeMaxZ);
        }
      }

      await Future.delayed(Duration.zero); // Prevent locking the UI thread
    }
    return null;
  }

  Future<void> _solve({int? seed, int? deluxe, int? builder, int? starter}) async {
    if (!mounted) return;
    final resolvedSeed = seed ?? DateTime.now().millisecondsSinceEpoch % 1000000;
    _seedController.text = resolvedSeed.toString();

    setState(() {
      if (deluxe != null) _deluxeCount = deluxe;
      if (builder != null) _builderCount = builder;
      if (starter != null) _starterCount = starter;

      _solving = true;
      _error = null;
      _mandatoryPieces = [];
      _showInstructions = false;
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
    if (kIsWeb) {
      registerWebInstructionsCallback(() {
        if (mounted && _solution != null) {
          setState(() => _showInstructions = true);
        }
      });
    }
  }

  Future<void> _solveWithSeed({int? seed, int deluxe = 1, int builder = 0, int starter = 0}) async {
    await _solve(seed: seed, deluxe: deluxe, builder: builder, starter: starter);
  }

  void _showInventoryDialog() {
    int tempDeluxe = _deluxeCount;
    int tempBuilder = _builderCount;
    int tempStarter = _starterCount;

    final origBaseCount = _deluxeCount * 2 + _builderCount * 1 + _starterCount * 1;
    final origActiveBaseCount = origBaseCount > 0 ? origBaseCount : 2;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget buildCounter(String label, int value, String desc, void Function(int) onChanged) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            desc,
                            style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: value > 0 ? () => setDialogState(() => onChanged(value - 1)) : null,
                          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFe94560)),
                        ),
                        Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Text(
                            '$value',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setDialogState(() => onChanged(value + 1)),
                          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0f9b0f)),
                        ),
                      ],
                    )
                  ],
                ),
              );
            }

            final tempBaseCount = tempDeluxe * 2 + tempBuilder * 1 + tempStarter * 1;
            final tempActiveBaseCount = tempBaseCount > 0 ? tempBaseCount : 2;

            return Dialog(
              backgroundColor: const Color(0xFF0f0f23),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFe94560), width: 1.5),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TRACK CONFIGURATION',
                        style: TextStyle(
                          color: Color(0xFFe94560),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Combine sets to expand building base grid and piece inventory dynamically.',
                        style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                      ),
                      const Divider(color: Color(0xFF2d2d44), height: 24),
                      buildCounter(
                        'Deluxe Set',
                        tempDeluxe,
                        '90 Towers, 2 Bases, 2 Catchers, 1 Start, all 18 pieces',
                        (v) {
                          tempDeluxe = v;
                          final bc = tempDeluxe * 2 + tempBuilder * 1 + tempStarter * 1;
                          final abc = bc > 0 ? bc : 2;
                          _viewerController.updateBases(abc);
                        },
                      ),
                      buildCounter(
                        'Builder Set',
                        tempBuilder,
                        '45 Towers, 1 Base, 1 Catcher, 1 Start, 10 selected pieces',
                        (v) {
                          tempBuilder = v;
                          final bc = tempDeluxe * 2 + tempBuilder * 1 + tempStarter * 1;
                          final abc = bc > 0 ? bc : 2;
                          _viewerController.updateBases(abc);
                        },
                      ),
                      buildCounter(
                        'Starter Set',
                        tempStarter,
                        '30 Towers, 1 Base, 1 Catcher, 1 Start, 6 selected pieces',
                        (v) {
                          tempStarter = v;
                          final bc = tempDeluxe * 2 + tempBuilder * 1 + tempStarter * 1;
                          final abc = bc > 0 ? bc : 2;
                          _viewerController.updateBases(abc);
                        },
                      ),
                      const Divider(color: Color(0xFF2d2d44), height: 24),
                      // Summary info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Grid Size:',
                            style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                          ),
                          Text(
                            '${tempActiveBaseCount * 5} x 5',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Max Support Towers:',
                            style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                          ),
                          Text(
                            '${tempDeluxe * 90 + tempBuilder * 45 + tempStarter * 30}',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              _viewerController.updateBases(origActiveBaseCount);
                              Navigator.pop(context);
                            },
                            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFe94560),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _deluxeCount = tempDeluxe;
                                _builderCount = tempBuilder;
                                _starterCount = tempStarter;
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _solving ? null : _showInventoryDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a1a2e),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF444444)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    child: const Text('Track Config'),
                  ),
                  const SizedBox(width: 8),
                  if (_solution != null)
                    ElevatedButton(
                      onPressed: () => setState(() => _showInstructions = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0f9b0f),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      child: const Text('Instructions'),
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

          // Instructions overlay — shown when user taps Instructions button
          if (_showInstructions && _solution != null)
            Positioned.fill(
              child: InstructionsOverlay(
                solution: _solution!,
                onClose: () => setState(() => _showInstructions = false),
              ),
            ),
        ],
      ),
    );
  }
}
