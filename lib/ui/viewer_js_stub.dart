// Stub for non-web platforms
void sendToViewer(Map<String, dynamic> msg) {}
void hideViewerIframe() {}
void showViewerIframe() {}

typedef WebSolveCallback = void Function(int? seed);
void registerWebSolveCallback(WebSolveCallback callback) {}

typedef WebInstructionsCallback = void Function();
void registerWebInstructionsCallback(WebInstructionsCallback callback) {}
