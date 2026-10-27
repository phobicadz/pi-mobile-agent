import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/pi_service.dart';
import 'providers/pi_view_model.dart';
import 'screens/home_screen.dart';
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
  runApp(MyApp(service: service, safeArea: safeArea));
}

class MyApp extends StatelessWidget {
  final PiService service;

  /// Safe areas the browser was asked to cover, or empty on native platforms
  /// where the platform already reports them to Flutter.
  final ValueNotifier<EdgeInsets> safeArea;

  MyApp(
      {super.key,
      required this.service,
      ValueNotifier<EdgeInsets>? safeArea})
      : safeArea = safeArea ?? ValueNotifier<EdgeInsets>(EdgeInsets.zero);

  @override
  Widget build(BuildContext context) {
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
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
        builder: (context, child) =>
            applyBrowserSafeArea(context, child, safeArea),
      ),
    );
  }
}
