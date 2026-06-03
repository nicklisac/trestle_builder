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

void registerWebSolveCallback(WebSolveCallback callback) {
  _window['onViewerMessage'] = ((JSObject data) {
    try {
      final typeAny = data['type'];
      if (typeAny != null && typeAny is JSString) {
        final type = typeAny.toDart;
        if (type == 'solve') {
          final seedAny = data['seed'];
          int? seed;
          if (seedAny != null) {
            if (seedAny is JSNumber) {
              seed = seedAny.toDartInt;
            } else if (seedAny is JSString) {
              seed = int.tryParse(seedAny.toDart);
            }
          }

          int deluxe = 1;
          final dAny = data['deluxe'];
          if (dAny != null) {
            if (dAny is JSNumber) {
              deluxe = dAny.toDartInt;
            } else if (dAny is JSString) {
              deluxe = int.tryParse(dAny.toDart) ?? 1;
            }
          }

          int builder = 0;
          final bAny = data['builder'];
          if (bAny != null) {
            if (bAny is JSNumber) {
              builder = bAny.toDartInt;
            } else if (bAny is JSString) {
              builder = int.tryParse(bAny.toDart) ?? 0;
            }
          }

          int starter = 0;
          final sAny = data['starter'];
          if (sAny != null) {
            if (sAny is JSNumber) {
              starter = sAny.toDartInt;
            } else if (sAny is JSString) {
              starter = int.tryParse(sAny.toDart) ?? 0;
            }
          }

          callback(seed, deluxe, builder, starter);
        }
      }
    } catch (e) {
      // ignore
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

void savePdfFile(List<int> bytes, String filename) {
  try {
    final base64Str = base64Encode(bytes);
    _window.callMethod('downloadPdfFromBase64'.toJS, base64Str.toJS, filename.toJS);
  } catch (e) {
    // ignore
  }
}

