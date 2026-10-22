import 'package:flutter/material.dart';

// Example of how to add more UI screens to the app

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _serverController;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: 'ws://192.168.1.100:3000');
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server Configuration
            Text(
              'Server Configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverController,
              decoration: InputDecoration(
                labelText: 'Backend WebSocket URL',
                hintText: 'ws://192.168.1.100:3000',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // App Information
            Text(
              'About',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('App Version'),
              subtitle: const Text('1.0.0'),
              leading: const Icon(Icons.info),
            ),
            ListTile(
              title: const Text('Build'),
              subtitle: const Text('1'),
              leading: const Icon(Icons.build),
            ),
            const SizedBox(height: 24),

            // Advanced Settings
            Text(
              'Advanced',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Auto-reconnect'),
              value: true,
              onChanged: (bool value) {
                // Implementation
              },
              secondary: const Icon(Icons.signal_cellular_connected_no_internet_4_bar),
            ),
            SwitchListTile(
              title: const Text('Enable Logging'),
              value: false,
              onChanged: (bool value) {
                // Implementation
              },
              secondary: const Icon(Icons.description),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings saved')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
