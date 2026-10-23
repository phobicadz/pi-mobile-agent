// Configuration constants for the Flutter app

import 'dart:ui';

class AppConfig {
  // Server configuration
  static const String defaultServerUrl = 'ws://192.168.1.100:3000';
  static const String localEmulatorUrl = 'ws://10.0.2.2:3000';
  static const String localSimulatorUrl = 'ws://localhost:3000';
  
  // Connection settings
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration reconnectDelay = Duration(seconds: 5);
  static const int maxReconnectAttempts = 10;
  
  // UI settings
  static const int maxEventsToDisplay = 100;
  static const int messagePageSize = 50;
  static const Duration animationDuration = Duration(milliseconds: 300);
  
  // API endpoints
  static const String healthEndpoint = '/health';
  static const String modelsEndpoint = '/api/models';
  static const String stateEndpoint = '/api/state';
  static const String promptEndpoint = '/api/prompt';
}

class AppTheme {
  // Colors
  static const primaryColor = Color(0xFF2196F3);
  static const secondaryColor = Color(0xFF1976D2);
  static const accentColor = Color(0xFFFF5722);
  
  // Typography
  static const defaultFontFamily = 'JetBrainsMono';
  static const codeFontFamily = 'JetBrainsMono';
  
  // Spacing
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 12.0;
}

class AppStrings {
  // Connection status
  static const String connected = 'Connected';
  static const String disconnected = 'Disconnected';
  static const String connecting = 'Connecting to Pi Backend...';
  
  // Actions
  static const String send = 'Send';
  static const String abort = 'Abort';
  static const String selectModel = 'Select a model';
  
  // Messages
  static const String hintText = 'Enter a prompt or command...';
  static const String loadingModels = 'Loading models...';
  static const String failedToLoadModels = 'Failed to load models';
  static const String failedToConnect = 'Failed to connect to backend';
  static const String connectionError = 'Connection error';
}
