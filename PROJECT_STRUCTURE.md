# Project Structure

## Backend (`./backend`)

```
backend/
├── src/
│   ├── index.ts              # Main server (Express + WebSocket)
│   └── pi-rpc-client.ts      # Pi RPC protocol wrapper
├── dist/                     # Compiled JavaScript (generated)
├── package.json              # Node.js dependencies
├── tsconfig.json             # TypeScript configuration
├── Dockerfile                # Docker image definition
├── .env.example              # Environment variables template
└── .env                       # Environment variables (gitignored)
```

### Key Files

- **`index.ts`**: Main Express server
  - WebSocket connection handler
  - HTTP API endpoints
  - Pi RPC client initialization
  - Event forwarding to clients

- **`pi-rpc-client.ts`**: Pi RPC protocol wrapper
  - Manages stdin/stdout with Pi subprocess
  - Correlates request IDs with responses
  - Emits events from Pi agent
  - Command methods (prompt, getState, setModel, etc.)

## Frontend (`./frontend`)

```
frontend/
├── lib/
│   ├── main.dart                        # App entry point
│   ├── models/
│   │   └── pi_models.dart              # Data models (PiState, PiMessage, PiEvent)
│   ├── services/
│   │   └── pi_service.dart             # WebSocket service & communication
│   ├── providers/
│   │   └── pi_view_model.dart          # State management (Provider package)
│   ├── screens/
│   │   └── home_screen.dart            # Main chat screen
│   ├── widgets/
│   │   ├── chat_bubble.dart            # Individual message bubble
│   │   └── model_selector.dart         # Model dropdown selector
│   └── constants/
│       └── app_constants.dart          # Configuration & strings
├── pubspec.yaml                         # Flutter dependencies
├── pubspec.lock                         # Locked dependency versions
├── android/                             # Android platform code
├── ios/                                 # iOS platform code
├── web/                                 # Web platform code
└── test/                                # Unit & widget tests
```

### Key Files

- **`main.dart`**: App entry point
  - Initializes PiService
  - Sets up Provider
  - Applies theme
  - Routes to HomeScreen

- **`models/pi_models.dart`**: Data models
  - `PiState`: Current agent state
  - `PiMessage`: Chat messages
  - `PiTool`: Tool invocations
  - `PiModel`: Available models
  - `PiEvent`: Agent events

- **`services/pi_service.dart`**: WebSocket communication
  - Manages WebSocket connection
  - Sends/receives commands
  - Auto-reconnection logic
  - Event streaming

- **`providers/pi_view_model.dart`**: State management
  - Wraps PiService
  - Manages local state (events, models, error)
  - Methods for user actions (submitPrompt, setModel, etc.)
  - Notifies UI listeners on changes

- **`screens/home_screen.dart`**: Main UI
  - Chat message display
  - Input field
  - Model selector
  - Connection status
  - Event streaming UI

- **`widgets/chat_bubble.dart`**: Message display
  - Formats different event types
  - Markdown rendering
  - Syntax highlighting support

- **`widgets/model_selector.dart`**: Model selection UI
  - Dropdown with available models
  - Current model display

## Communication Flow

```
User Types Prompt
       ↓
HomeScreen.submitPrompt()
       ↓
PiViewModel.submitPrompt()
       ↓
PiService.sendCommand("prompt", {message})
       ↓
WebSocket sends JSON
       ↓
Backend receives message
       ↓
PiRpcClient.sendCommand() writes to Pi stdin
       ↓
Pi processes command (bash, file operations, etc.)
       ↓
Pi writes response to stdout
       ↓
PiRpcClient parses and emits events
       ↓
Backend forwards to all WebSocket clients
       ↓
Flutter receives via PiService.events stream
       ↓
PiViewModel notifies listeners
       ↓
HomeScreen rebuilds and displays response
```

## Development Workflow

### Backend Changes
1. Modify TypeScript in `backend/src/`
2. Restart server: `npm run dev` (auto-recompiles)
3. Changes take effect immediately for new WebSocket connections

### Frontend Changes
1. Modify Dart in `frontend/lib/`
2. Use hot reload: `r` in terminal (for UI only)
3. Use hot restart: `R` for service/model changes
4. Full restart: Stop and `flutter run` for dependency changes

## Adding New Features

### Add a New Command (Backend)

1. Add method to `PiRpcClient`:
```typescript
async setBranch(name: string): Promise<RpcResponse> {
  return this.sendCommand({
    type: "set_branch",
    name,
  });
}
```

2. Add HTTP endpoint or WebSocket handler in `index.ts`:
```typescript
if (command === "set_branch") {
  response = await piClient.setBranch(params.name);
}
```

### Add UI for New Command (Frontend)

1. Add method to `PiViewModel`:
```dart
Future<void> setBranch(String name) async {
  await piService.sendCommand("set_branch", params: {"name": name});
}
```

2. Add widget to UI:
```dart
TextField(
  onSubmitted: (name) => viewModel.setBranch(name),
)
```

## Testing

### Backend Tests
```bash
cd backend
npm test
```

### Frontend Tests
```bash
cd frontend
flutter test
```

### Manual Testing
1. Start backend: `npm run dev`
2. Start frontend: `flutter run`
3. Monitor backend logs for RPC messages
4. Monitor Flutter logs with `flutter logs`

## Building for Production

### Backend
```bash
cd backend
npm run build
docker build -t pi-mobile-backend .
docker run -p 3000:3000 pi-mobile-backend
```

### Frontend (Android)
```bash
cd frontend
flutter build apk --split-per-abi
# APKs in: build/app/outputs/flutter-apk/
```

### Frontend (iOS)
```bash
cd frontend
flutter build ios
# Open in Xcode: ios/Runner.xcworkspace
```

### Frontend (Web)
```bash
cd frontend
flutter build web
# Deploy build/web/ to hosting service
```
