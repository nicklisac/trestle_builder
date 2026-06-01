// Stub for non-web platforms
void sendToViewer(Map<String, dynamic> msg) {}

typedef WebSolveCallback = void Function(int? seed);
void registerWebSolveCallback(WebSolveCallback callback) {}
