// Stub for non-web platforms
void sendToViewer(Map<String, dynamic> msg) {}
void hideViewerIframe() {}
void showViewerIframe() {}

typedef WebSolveCallback = void Function(int? seed, int deluxe, int builder, int starter);
typedef WebReadyCallback = void Function();
void registerWebCallbacks({
  required WebSolveCallback onSolve,
  required WebReadyCallback onReady,
}) {}

typedef WebInstructionsCallback = void Function();
void registerWebInstructionsCallback(WebInstructionsCallback callback) {}


void savePdfFile(List<int> bytes, String filename) {}

void enableGenerateButton() {}

void saveLastSeed(int seed) {}
int? getLastSeed() => null;

int getSavedDeluxe() => 1;
int getSavedBuilder() => 0;
int getSavedStarter() => 0;
void saveLastSolution(String solutionJson) {}
String? getLastSolution() => null;

