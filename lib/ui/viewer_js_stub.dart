// Stub for non-web platforms
void sendToViewer(Map<String, dynamic> msg) {}
void hideViewerIframe() {}
void showViewerIframe() {}

typedef WebSolveCallback = void Function(int? seed, int deluxe, int builder, int starter);
void registerWebSolveCallback(WebSolveCallback callback) {}

typedef WebInstructionsCallback = void Function();
void registerWebInstructionsCallback(WebInstructionsCallback callback) {}

void savePdfFile(List<int> bytes, String filename) {}

