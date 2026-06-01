// Web-specific setup to allow pointer events to pass through Flutter canvas to iframe
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/widgets.dart';

@JS('document')
external JSObject getDocument();

@JS('canvas')
external JSObject getCanvas();

void setupPointerPassthrough() {
  try {
    final canvas = getCanvas();
    // Allow pointer events to pass through canvas to the iframe behind
    // but only in areas where Flutter isn't rendering UI
    final style = canvas['style'] as JSObject?;
    if (style != null) {
      style['pointerEvents'] = 'none'.toJS;
    }
  } catch (e) {
    debugPrint('Failed to setup pointer passthrough: $e');
  }
}
