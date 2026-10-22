# Pi Mobile Agent

A Flutter mobile frontend for controlling the Pi coding agent from your phone. Send prompts, monitor task progress, and manage models all from a clean, intuitive interface.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                     │
│              (iOS/Android/Web compatible)                 │
│  - Chat interface                                         │
│  - Model selection                                        │
│  - Real-time event streaming                             │
└────────────────────────┬─────────────────────────────────┘
                         │ WebSocket (ws://)
                         ▼
┌──────────────────────────────────────────────────────────┐
│              Node.js Backend Server                       │
│  - Express HTTP API                                      │
│  - WebSocket server                                      │
│  - Pi RPC client wrapper                                 │
└────────────────────────┬─────────────────────────────────┘
                         │ JSONL protocol
                         ▼
┌──────────────────────────────────────────────────────────┐
│                   Pi RPC Subprocess                       │
│  - Runs Pi agent in RPC mode                            │
│  - stdin/stdout communication                            │
│  - File access, tool execution                           │
└──────────────────────────────────────────────────────────┘
```

## Backend Setup

### Prerequisites
- Node.js 18+
- Pi agent installed (`npm install -g @earendil-works/pi-coding-agent`)
- Credentials configured (`pi /login` inside Pi)

### Installation

```bash
cd pi-mobile-agent/backend
npm install
```

### Environment Variables

Create `.env`:
```env
PORT=3000
PI_PROVIDER=anthropic  # or your provider
PI_MODEL=claude-3-5-sonnet-20241022
```

### Running the Backend

```bash
# Development
npm run dev

# Production
npm run build
npm start
```

The server will start on `http://localhost:3000` with:
- **WebSocket**: `ws://localhost:3000`
- **HTTP API**: `http://localhost:3000/api`
- **Health check**: `http://localhost:3000/health`

## Frontend Setup

### Prerequisites
- Flutter 3.0+ installed
- Xcode (macOS), Android Studio (Linux/Windows), or web development setup

### Installation

```bash
cd pi-mobile-agent/frontend
flutter pub get
```

### Configuration

The app resolves the backend URL automatically. For web builds (including Safari
on iPhone/iPad) it connects to the same host that served the page, so no
configuration is needed. For native builds, pass the backend address:

```bash
flutter run --dart-define=SERVER_URL=ws://192.168.1.100:3000
```

For local development:
- **Android Emulator**: `--dart-define=SERVER_URL=ws://10.0.2.2:3000` (special alias for host)
- **iOS Simulator**: default `ws://127.0.0.1:3000` works
- **iPhone/iPad (no Mac)**: `flutter build web`, then open `http://YOUR_COMPUTER_IP:3000` in Safari — the backend serves the web build on the same port as the WebSocket
- **Physical device (native app)**: `--dart-define=SERVER_URL=ws://YOUR_COMPUTER_IP:3000`

### Running

```bash
# Run on connected device/emulator
flutter run

# Run on web (Chrome)
flutter run -d web-server

# Build the web app (served by the backend at http://<your-ip>:3000)
flutter build web

# Build APK (Android)
flutter build apk --split-per-abi

# Build IPA (iOS, requires macOS/Xcode)
flutter build ios
```

## API Reference

### WebSocket Messages

#### Send Prompt
```json
{
  "id": "unique-request-id",
  "command": "prompt",
  "message": "Build a Flutter app that..."
}
```

#### Get Current State
```json
{
  "id": "unique-request-id",
  "command": "get_state"
}
```

#### Set Model
```json
{
  "id": "unique-request-id",
  "command": "set_model",
  "model": "claude-3-5-sonnet-20241022"
}
```

#### Abort Current Task
```json
{
  "id": "unique-request-id",
  "command": "abort"
}
```

#### Get Available Models
```json
{
  "id": "unique-request-id",
  "command": "get_available_models"
}
```

### Server Response Format
```json
{
  "id": "unique-request-id",
  "type": "response",
  "command": "prompt",
  "success": true,
  "data": {
    "disposition": "started"
  }
}
```

### Event Stream
Events stream continuously as the Pi agent works:
```json
{
  "type": "pi_event",
  "event": {
    "type": "message_update",
    "assistantMessageEvent": {
      "type": "text_delta",
      "delta": "Here's what I did..."
    }
  }
}
```

## Features

### Current
- ✅ Send prompts to Pi agent
- ✅ Real-time streaming of agent responses
- ✅ View all events/messages
- ✅ Model selection
- ✅ Abort running tasks
- ✅ Connection status indicator
- ✅ Auto-reconnection
- ✅ Error handling and display
- ✅ Works on iOS, Android, Web
- ✅ Resume previous sessions (history button, like `/resume` in the Pi TUI)

### Future Enhancements
- [ ] Fork sessions
- [ ] File browser for context
- [ ] Thinking level selection
- [ ] Dark mode polish
- [ ] Offline caching
- [ ] Push notifications for task completion
- [ ] Custom themes
- [ ] Voice input
- [ ] Code syntax highlighting in chat
- [ ] Copy/share responses
- [ ] Prompt history/favorites
- [ ] Multi-agent coordination

## Extending the Frontend

### Adding New Commands

1. Add to `PiService`:
```dart
Future<Map<String, dynamic>> setThinkingLevel(String level) async {
  return _sendCommand('set_thinking_level', 
    params: {'thinkingLevel': level});
}
```

2. Add to `PiViewModel`:
```dart
Future<void> changeThinkingLevel(String level) async {
  try {
    await piService.setThinkingLevel(level);
    notifyListeners();
  } catch (e) {
    _error = 'Failed: $e';
    notifyListeners();
  }
}
```

3. Add to UI:
```dart
DropdownButton<String>(
  value: currentLevel,
  items: ['low', 'medium', 'high']
    .map((level) => DropdownMenuItem(
      value: level,
      child: Text(level),
    ))
    .toList(),
  onChanged: viewModel.changeThinkingLevel,
)
```

### Adding New Event Types

Update `ChatBubble` in `lib/widgets/chat_bubble.dart`:
```dart
} else if (type == 'my_new_event') {
  displayText = '✨ New event occurred';
  icon = Icons.stars;
}
```

## Backend Extending

### Adding Custom Tools

Modify `backend/src/index.ts` to wrap Pi's tool API:

```typescript
async function addCustomTool(toolName: string, toolDefinition: any) {
  // Add to Pi's available tools
  // This requires extending the RPC protocol or creating a custom endpoint
}
```

### Adding HTTP Endpoints

```typescript
app.post("/api/custom-command", async (req, res) => {
  try {
    const result = await piClient.sendCommand({
      type: "custom_command",
      ...req.body,
    });
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});
```

## Troubleshooting

### Connection Issues

1. **Backend not reachable**: Check firewall, server running, correct IP
2. **CORS errors**: Already handled in backend with `cors()`
3. **Auto-reconnect failing**: Check backend logs, restart Pi process

```bash
# Test connection
curl http://localhost:3000/health
```

### WebSocket Errors

```
WebSocket error: connection refused
```
- Backend not running: `npm run dev`
- Wrong IP in Flutter app: Update `serverUrl`
- Port blocked: Check firewall

### Flutter App Issues

```bash
# Clean build
flutter clean
flutter pub get
flutter run

# Enable verbose logging
flutter run -v

# Check device connectivity
flutter devices
```

## Development Tips

1. **Fast iteration**: 
   - Hot reload works for UI changes: `r` in terminal
   - Restart app for service changes: `R` in terminal

2. **Testing**: Use backend's HTTP endpoints:
```bash
curl -X POST http://localhost:3000/api/prompt \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello Pi"}'
```

3. **Debugging WebSocket**:
   - Backend logs all messages and events
   - Flutter app logs via `print()` statements
   - Monitor network in DevTools

## Performance Considerations

- Keep events history to ~100 items (already limited)
- Stream large responses instead of buffering
- Compress WebSocket frames for bandwidth
- Consider message batching for rapid events

## Security

- Don't expose the backend to the internet without authentication
- Consider adding JWT or API key authentication
- Validate all user input on backend
- Use WSS (WebSocket Secure) in production
- Store credentials securely (backend uses Pi's config)

## Contributing

This is your personal mobile controller! Extend it with:
- Custom layouts
- Integration with other services
- Team collaboration features
- Plugin system

## License

Same as Pi agent

## Resources

- [Pi Documentation](https://pi.dev)
- [Pi RPC Protocol](https://pi.dev/docs/rpc)
- [Flutter Documentation](https://flutter.dev)
- [WebSocket in Flutter](https://pub.dev/packages/web_socket_channel)
