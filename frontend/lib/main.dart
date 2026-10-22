import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/pi_service.dart';
import 'providers/pi_view_model.dart';
import 'screens/home_screen.dart';

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
  runApp(MyApp(serverUrl: resolveServerUrl()));
}

class MyApp extends StatelessWidget {
  final String serverUrl;

  MyApp({super.key, required this.serverUrl});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) {
          final service = PiService(serverUrl: serverUrl);
          service.connect();
          return service;
        }),
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
      ),
    );
  }
}
