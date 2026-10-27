import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'client_diagnostics_native.dart'
    if (dart.library.js_interop) 'client_diagnostics_web.dart' as impl;

/// Report what the page and Flutter each think the screen is.
///
/// A gap at the bottom of the screen *and* taps landing on the wrong widget is
/// the signature of the two disagreeing: the browser laid the page out at one
/// size while Flutter is drawing and hit-testing at another. Nothing inside the
/// app can see that from the outside, and a desktop browser never shows it, so
/// the numbers are sent over the existing socket and the backend logs them (the
/// `client_metrics` command). Reading them off the service log is what makes a
/// phone-only layout bug diagnosable without a screenshot.
void installClientDiagnostics(void Function(Map<String, dynamic> sample) onSample) {
  _Diagnostics(onSample).start();
}

class _Diagnostics extends WidgetsBindingObserver {
  _Diagnostics(this._onSample);

  final void Function(Map<String, dynamic>) _onSample;

  int _samples = 0;
  bool _coalescing = false;

  /// Enough to catch a page that settles at the wrong size after load, a
  /// rotation, or a keyboard opening, without filling the log.
  static const int _maxSamples = 24;
  static const List<Duration> _settledSamples = [
    Duration(milliseconds: 600),
    Duration(seconds: 3),
  ];

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _emit();
    // The app rewrites the viewport meta at startup, which is exactly the kind
    // of change a browser applies asynchronously: the state after it has settled
    // is the one that matters, not the state at first paint.
    for (final delay in _settledSamples) {
      Timer(delay, _emit);
    }
  }

  @override
  void didChangeMetrics() {
    // Opening the on-screen keyboard fires this many times a second.
    if (_coalescing) return;
    _coalescing = true;
    Timer(const Duration(milliseconds: 400), () {
      _coalescing = false;
      _emit();
    });
  }

  void _emit() {
    if (_samples >= _maxSamples) return;
    _samples++;
    _onSample({
      'n': _samples,
      ..._flutterView(),
      ...impl.browserMetrics(),
    });
  }
}

/// What Flutter's own view reports: the surface it draws and hit-tests on.
Map<String, dynamic> _flutterView() {
  final view = ui.PlatformDispatcher.instance.implicitView;
  if (view == null) return {'flutter': 'no view'};
  final dpr = view.devicePixelRatio;
  return {
    'flutter': {
      'physical': '${view.physicalSize.width}x${view.physicalSize.height}',
      'logical': '${(view.physicalSize.width / dpr).toStringAsFixed(1)}x'
          '${(view.physicalSize.height / dpr).toStringAsFixed(1)}',
      'dpr': dpr,
      'paddingBottom': view.viewPadding.bottom,
      'insetsBottom': view.viewInsets.bottom,
    },
  };
}
