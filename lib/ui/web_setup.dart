import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

@JS()
external JSObject get window;

@JS('document.createElement')
external JSObject createElement(String tag);

void setupWebApp() {
  if (!kIsWeb) return;
  
  SchedulerBinding.instance.addPostFrameCallback((_) {
    try {
      // Find all Flutter canvas elements and make them non-interactive
      // except where Flutter UI widgets are
      final canvas = window['flutterCanvas'] as JSObject?;
      if (canvas != null) {
        final style = canvas['style'] as JSObject?;
        if (style != null) {
          style['pointerEvents'] = 'none'.toJS;
        }
      }
    } catch (e) {
      debugPrint('Web setup error: $e');
    }
  });
}
