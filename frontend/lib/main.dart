import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/pi_service.dart';
import 'providers/pi_view_model.dart';
import 'screens/home_screen.dart';
import 'providers/appearance_controller.dart';
import 'utils/browser_viewport.dart';
import 'utils/client_diagnostics.dart';

/// Resolves the backend WebSocket URL for the platform the app runs on.
///
/// Override with:
///   flutter run --dart-define=SERVER_URL=ws://192.168.1.150:3000
/// When served over the web (including Safari on iPhone/iPad) the app talks to
/// the same host that served the page, so localhost/127.0.0.1/LAN IPs all work
/// without a rebuild.
String resolveServerUrl() {
  const configured = String.fromEnvironment('SERVER_URL');
  if (configured.isNotEmpty) return configured;

  const configuredPort = String.fromEnvironment('SERVER_PORT');
  final port = int.tryParse(configuredPort) ?? 3000;

  if (kIsWeb) {
    final host = Uri.base.host;
    if (host.isNotEmpty) return 'ws://$host:$port';
  }

  // Native builds cannot discover the host, so a LAN address must be supplied.
  return 'ws://127.0.0.1:$port';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On the web the browser owns the safe areas, not Flutter. This is what makes
  // the page run the full length of a phone screen - see
  // utils/browser_viewport.dart. On native platforms it reports nothing.
  final safeArea = useBrowserSafeArea();
  final service = PiService(serverUrl: resolveServerUrl());
  service.connect();
  // Send what the browser and Flutter each think the screen is, with the safe
  // areas the app is actually laying out under. The backend logs it, so a layout
  // problem that only appears on a phone can be read off the service log.
  installClientDiagnostics((sample) {
    unawaited(service.sendClientMetrics({
      ...sample,
      'appliedInsets': {
        'top': safeArea.value.top,
        'right': safeArea.value.right,
        'bottom': safeArea.value.bottom,
        'left': safeArea.value.left,
      },
    }));
  });
  // Restored before the first frame, so the app does not open at one size and
  // theme and then change to another.
  final appearance = AppearanceController();
  await appearance.restore();

  // Provided above MyApp rather than inside it: MyApp is what builds
  // MaterialApp, and MaterialApp is the thing that has to be told which theme
  // to build with.
  runApp(
    ChangeNotifierProvider<AppearanceController>.value(
      value: appearance,
      child: MyApp(service: service, safeArea: safeArea),
    ),
  );
}

class MyApp extends StatelessWidget {
  final PiService service;

  /// Safe areas the browser was asked to cover, or empty on native platforms
  /// where the platform already reports them to Flutter.
  final ValueNotifier<EdgeInsets> safeArea;

  MyApp({super.key, required this.service, ValueNotifier<EdgeInsets>? safeArea})
      : safeArea = safeArea ?? ValueNotifier<EdgeInsets>(EdgeInsets.zero);

  @override
  Widget build(BuildContext context) {
    // The theme is watched here because this is the widget that builds
    // MaterialApp, and themeMode is a property of MaterialApp - not of anything
    // below it. A toggle deeper in the tree could change the colours of a
    // screen but not the theme the screens are built from.
    final themeMode = context.watch<AppearanceController>().themeMode;

    return MultiProvider(
      providers: [
        Provider<PiService>.value(value: service),
        ChangeNotifierProvider(
          create: (context) => PiViewModel(
            piService: context.read<PiService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Pi Agent',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: themeMode,
        home: const HomeScreen(),
        builder: (context, child) {
          // Paint the page behind the canvas with the theme that is actually in
          // force right now.
          //
          // On iOS the canvas can end up shorter than the screen it is drawn on
          // (see web/index.html), and whatever is left over is the browser's to
          // paint - white by default, which is a band across the bottom of a
          // phone. This is the part of that gap the app can still account for:
          // make it the colour the app paints its own bottom edge with, and there
          // is nothing there for the eye to find.
          //
          // The builder is the one place in the app with both the theme and the
          // page in reach, and it re-runs when the theme changes - including when
          // the phone's own appearance changes while the app is following it. A
          // DOM write during build is not something to be casual about, but this
          // one is idempotent and it is the only moment the page is guaranteed to
          // be painted before the frame that sits on it.
          paintPageBehindCanvas(Theme.of(context).scaffoldBackgroundColor);
          return applyBrowserSafeArea(context, child, safeArea);
        },
      ),
    );
  }
}
