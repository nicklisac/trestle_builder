class SolutionData {
  final int? seed;
  final int pieceCount;
  final int towerCount;
  final Map<String, int> towerMap;
  final List<PieceData> pieces;
  final int baseCount;

  const SolutionData({
    this.seed,
    required this.pieceCount,
    required this.towerCount,
    required this.towerMap,
    required this.pieces,
    this.baseCount = 2,
  });

  factory SolutionData.fromJson(Map<String, dynamic> json) {
    return SolutionData(
      seed: json['seed'] != null ? (json['seed'] as int).toInt() : null,
      pieceCount: json['piece_count'] as int,
      towerCount: json['tower_count'] as int,
      towerMap: Map<String, int>.from(json['tower_map'] as Map),
      pieces: (json['pieces'] as List).map((p) => PieceData.fromJson(p as Map<String, dynamic>)).toList(),
      baseCount: json['base_count'] != null ? json['base_count'] as int : 2,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'piece_count': pieceCount,
      'tower_count': towerCount,
      'tower_map': towerMap,
      'pieces': pieces.map((p) => p.toJson()).toList(),
      'base_count': baseCount,
    };
  }
}

class PieceData {
  final int pieceId;
  final List<int> origin;
  final List<int> start;
  final List<int> end;
  final List<List<int>> outputs;
  final List<List<int>> cells;
  final bool isSplitter;

  const PieceData({
    required this.pieceId,
    required this.origin,
    required this.start,
    required this.end,
    required this.outputs,
    required this.cells,
    required this.isSplitter,
  });

  factory PieceData.fromJson(Map<String, dynamic> json) {
    return PieceData(
      pieceId: json['piece_id'] as int,
      origin: List<int>.from(json['origin'] as List),
      start: List<int>.from(json['start'] as List),
      end: List<int>.from(json['end'] as List),
      outputs: (json['outputs'] as List).map((o) => List<int>.from(o as List)).toList(),
      cells: (json['cells'] as List).map((c) => List<int>.from(c as List)).toList(),
      isSplitter: json['is_splitter'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'piece_id': pieceId,
      'origin': origin,
      'start': start,
      'end': end,
      'outputs': outputs,
      'cells': cells,
      'is_splitter': isSplitter,
    };
  }

  String get tag {
    if (isSplitter) return '[SPLIT]';
    if (end[2] != start[2]) return '[DESC]';
    return '';
  }

  int get zLevel => origin[2];
}
