import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/solution.dart';
import 'viewer_js_stub.dart' if (dart.library.html) 'viewer_js_web.dart';

typedef SolveCallback = Future<void> Function({int? seed, int deluxe, int builder, int starter});

class ViewerMessage {
  final String type;
  final int? pieceCount;
  final int? towerCount;
  const ViewerMessage({required this.type, this.pieceCount, this.towerCount});
}

class TrackViewerController {
  final Completer<void> _ready = Completer();
  WebViewController? _webviewController;
  SolveCallback? onSolve;

  Future<void> get ready => _ready.future;

  void _setController(WebViewController ctrl) {
    _webviewController = ctrl;
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<void> render(SolutionData solution, {int? seed}) async {
    await ready;
    if (kIsWeb) {
      _sendToViewer({'type': 'render', 'solution': solution.toJson(), 'seed': seed});
    } else if (_webviewController != null) {
      final js = '''
        (function() {
          var msg = {
            type: 'render',
            solution: ${jsonEncode(solution.toJson())},
            seed: ${seed ?? 'null'}
          };
          window.postMessage(msg, '*');
        })();
      ''';
      await _webviewController!.runJavaScript(js);
    }
  }

  Future<void> updateBases(int baseCount) async {
    await ready;
    if (kIsWeb) {
      _sendToViewer({'type': 'update-bases', 'baseCount': baseCount});
    } else if (_webviewController != null) {
      final js = '''
        (function() {
          var msg = {
            type: 'update-bases',
            baseCount: $baseCount
          };
          window.postMessage(msg, '*');
        })();
      ''';
      await _webviewController!.runJavaScript(js);
    }
  }

  Future<void> clear() async {
    await ready;
    if (kIsWeb) {
      _sendToViewer({'type': 'clear'});
    } else {
      await _webviewController?.runJavaScript(
        '(function(){window.postMessage({type:"clear"},"*");})();',
      );
    }
  }

  Future<void> hideUi() async {
    if (kIsWeb) {
      _sendToViewer({'type': 'hide-ui'});
    } else {
      await _webviewController?.runJavaScript(
        '(function(){window.postMessage({type:"hide-ui"},"*");})();',
      );
    }
  }

  Future<void> showUi() async {
    if (kIsWeb) {
      _sendToViewer({'type': 'show-ui'});
    } else {
      await _webviewController?.runJavaScript(
        '(function(){window.postMessage({type:"show-ui"},"*");})();',
      );
    }
  }

  static void _sendToViewer(Map<String, dynamic> msg) {
    sendToViewer(msg);
  }
}

class TrackViewer extends StatefulWidget {
  final TrackViewerController? controller;
  const TrackViewer({super.key, this.controller});

  @override
  State<TrackViewer> createState() => TrackViewerState();
}

class TrackViewerState extends State<TrackViewer> {
  late final TrackViewerController controller;
  WebViewController? _webviewController;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? TrackViewerController();

    if (!kIsWeb) {
      _webviewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel('ViewerBridge', onMessageReceived: (JavaScriptMessage msg) async {
          try {
            final data = jsonDecode(msg.message);
            if (data['type'] == 'ready' && !controller._ready.isCompleted) {
              controller._ready.complete();
            } else if (data['type'] == 'solve') {
              final seed = data['seed'];
              final deluxe = data['deluxe'] != null ? data['deluxe'] as int : 1;
              final builder = data['builder'] != null ? data['builder'] as int : 0;
              final starter = data['starter'] != null ? data['starter'] as int : 0;
              await controller.onSolve?.call(
                seed: seed != null ? seed as int : null,
                deluxe: deluxe,
                builder: builder,
                starter: starter,
              );
            }
          } catch (_) {}
        })
        ..loadFlutterAsset('web/viewer.html');

      controller._setController(_webviewController!);
    } else {
      registerWebCallbacks(
        onSolve: (seed, deluxe, builder, starter) {
          controller.onSolve?.call(seed: seed, deluxe: deluxe, builder: builder, starter: starter);
        },
        onReady: () {
          if (!controller._ready.isCompleted) {
            controller._ready.complete();
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    } else if (_webviewController != null) {
      return WebViewWidget(controller: _webviewController!);
    } else {
      return const Center(child: CircularProgressIndicator());
    }
  }
}
