// Web-specific JS bridge using dart:js_interop
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

typedef WebSolveCallback = void Function(int? seed);

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
          callback(seed);
        }
      }
    } catch (e) {
      // ignore
    }
  }).toJS;
}
