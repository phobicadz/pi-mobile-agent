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
void installClientDiagnostics(
    void Function(Map<String, dynamic> sample) onSample) {
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
    final flutter = _flutterView();
    final browser = impl.browserMetrics();
    _reportUnpaintedHost(flutter, browser);
    _onSample({'n': _samples, ...flutter, ...browser});
  }

  /// The height of Flutter's host element minus the height of the canvas drawn
  /// inside it.
  ///
  /// That difference is a band of the screen the app never paints, which the
  /// browser fills with the page's own background - and it is invisible to every
  /// other number here, because they compare the host with the viewport, which
  /// agree with each other perfectly while both disagree with the canvas.
  ///
  /// Assumes the canvas starts at the top of its host, which is how the engine
  /// lays it out: a shortfall therefore sits at the bottom.
  void _reportUnpaintedHost(
      Map<String, dynamic> flutter, Map<String, dynamic> browser) {
    // Both are nested: the sample is {'flutter': {...}, 'browser': {...}}, and
    // reading a key off the outer map finds nothing. The compiler spotted that
    // this could never produce a number and removed the whole calculation.
    final canvas = _number(flutter['flutter'], 'logicalHeight');
    final host = _number(browser['browser'], 'hostHeight');
    if (canvas == null || host == null || host <= 0) return;
    final gap = host - canvas;
    (browser['browser'] as Map<String, dynamic>)['unpaintedHostHeight'] =
        gap < 0 ? 0.0 : gap;
  }

  /// A number out of one of the reported sections, or null when the section is
  /// not there or does not hold a number - both of them report a plain string
  /// instead when there is nothing to measure.
  static double? _number(Object? section, String key) {
    if (section is! Map) return null;
    final value = section[key];
    return value is num ? value.toDouble() : null;
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
      'logicalHeight': view.physicalSize.height / dpr,
      'dpr': dpr,
      'paddingBottom': view.viewPadding.bottom,
      'insetsBottom': view.viewInsets.bottom,
    },
  };
}
