// Web-specific JS bridge using dart:js_interop
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

@JS('_sendToViewer')
external void _sendToViewerJs(JSObject msg);

void sendToViewer(Map<String, dynamic> msg) {
  try {
    _sendToViewerJs(msg.jsify() as JSObject);
  } catch (_) {}
  try {
    _window.callMethod('postMessage'.toJS, msg.jsify(), '*'.toJS);
  } catch (_) {}
}

void hideViewerIframe() {
  try {
    final doc = _window['document'] as JSObject;
    final iframe = doc.callMethod('getElementById'.toJS, 'viewer-iframe'.toJS) as JSObject?;
    if (iframe != null) {
      (iframe['style'] as JSObject)['zIndex'] = '-1'.toJS;
    }
  } catch (_) {}
}

void showViewerIframe() {
  try {
    final doc = _window['document'] as JSObject;
    final iframe = doc.callMethod('getElementById'.toJS, 'viewer-iframe'.toJS) as JSObject?;
    if (iframe != null) {
      (iframe['style'] as JSObject)['zIndex'] = '1'.toJS;
    }
  } catch (_) {}
}

typedef WebSolveCallback = void Function(int? seed, int deluxe, int builder, int starter);
typedef WebInstructionsCallback = void Function();

typedef WebReadyCallback = void Function();

void registerWebCallbacks({
  required WebSolveCallback onSolve,
  required WebReadyCallback onReady,
}) {
  _window['onViewerMessage'] = ((JSObject data) {
    try {
      final typeAny = data['type'];
      if (typeAny != null && typeAny.isA<JSString>()) {
        final type = (typeAny as JSString).toDart;
        if (type == 'solve') {
          final seedAny = data['seed'];
          int? seed;
          if (seedAny != null) {
            if (seedAny.isA<JSNumber>()) {
              seed = (seedAny as JSNumber).toDartInt;
            } else if (seedAny.isA<JSString>()) {
              seed = int.tryParse((seedAny as JSString).toDart);
            }
          }

          int deluxe = 1;
          final dAny = data['deluxe'];
          if (dAny != null) {
            if (dAny.isA<JSNumber>()) {
              deluxe = (dAny as JSNumber).toDartInt;
            } else if (dAny.isA<JSString>()) {
              deluxe = int.tryParse((dAny as JSString).toDart) ?? 1;
            }
          }

          int builder = 0;
          final bAny = data['builder'];
          if (bAny != null) {
            if (bAny.isA<JSNumber>()) {
              builder = (bAny as JSNumber).toDartInt;
            } else if (bAny.isA<JSString>()) {
              builder = int.tryParse((bAny as JSString).toDart) ?? 0;
            }
          }

          int starter = 0;
          final sAny = data['starter'];
          if (sAny != null) {
            if (sAny.isA<JSNumber>()) {
              starter = (sAny as JSNumber).toDartInt;
            } else if (sAny.isA<JSString>()) {
              starter = int.tryParse((sAny as JSString).toDart) ?? 0;
            }
          }

          onSolve(seed, deluxe, builder, starter);
        } else if (type == 'ready') {
          onReady();
        }
      }
    } catch (e, stack) {
      print("Exception in onViewerMessage callback: $e\n$stack");
    }
  }).toJS;
}


void registerWebInstructionsCallback(WebInstructionsCallback callback) {
  _window['onFlutterInstructions'] = (() {
    try {
      callback();
    } catch (_) {}
  }).toJS;
}

void enableGenerateButton() {
  try {
    _window.callMethod('enableGenerateButton'.toJS);
  } catch (_) {}
}

void savePdfFile(List<int> bytes, String filename) {
  try {
    final base64Str = base64Encode(bytes);
    _window.callMethod('downloadPdfFromBase64'.toJS, base64Str.toJS, filename.toJS);
  } catch (e) {
    // ignore
  }
}

void saveLastSeed(int seed) {
  try {
    final storage = _window['localStorage'] as JSObject?;
    if (storage != null) {
      storage.callMethod('setItem'.toJS, 'trestle_last_seed'.toJS, seed.toString().toJS);
    }
  } catch (_) {}
}

int? getLastSeed() {
  try {
    final storage = _window['localStorage'] as JSObject?;
    if (storage != null) {
      final val = storage.callMethod('getItem'.toJS, 'trestle_last_seed'.toJS) as JSString?;
      if (val != null) {
        return int.tryParse(val.toDart);
      }
    }
  } catch (_) {}
  return null;
}

int getSavedDeluxe() {
  try {
    final storage = _window['localStorage'] as JSObject?;
    if (storage != null) {
      final val = storage.callMethod('getItem'.toJS, 'trestle_deluxe'.toJS) as JSString?;
      if (val != null) return int.tryParse(val.toDart) ?? 1;
    }
  } catch (_) {}
  return 1;
}

int getSavedBuilder() {
  try {
    final storage = _window['localStorage'] as JSObject?;
    if (storage != null) {
      final val = storage.callMethod('getItem'.toJS, 'trestle_builder'.toJS) as JSString?;
      if (val != null) return int.tryParse(val.toDart) ?? 0;
    }
  } catch (_) {}
  return 0;
}

int getSavedStarter() {
  try {
    final storage = _window['localStorage'] as JSObject?;
    if (storage != null) {
      final val = storage.callMethod('getItem'.toJS, 'trestle_starter'.toJS) as JSString?;
      if (val != null) return int.tryParse(val.toDart) ?? 0;
    }
  } catch (_) {}
  return 0;
}

void saveLastSolution(String solutionJson) {
  try {
    final storage = _window['localStorage'] as JSObject?;
    if (storage != null) {
      storage.callMethod('setItem'.toJS, 'trestle_last_solution'.toJS, solutionJson.toJS);
    }
  } catch (_) {}
}

String? getLastSolution() {
  try {
    final storage = _window['localStorage'] as JSObject?;
    if (storage != null) {
      final val = storage.callMethod('getItem'.toJS, 'trestle_last_solution'.toJS) as JSString?;
      if (val != null) {
        return val.toDart;
      }
    }
  } catch (_) {}
  return null;
}

