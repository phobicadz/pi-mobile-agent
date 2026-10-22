# Development Guide

Guide for developing and extending the Pi Mobile Agent.

## Development Environment Setup

### Prerequisites
- Node.js 18+ (check with `node --version`)
- Flutter 3.0+ (check with `flutter --version`)
- Pi CLI installed (check with `pi --version`)
- Git for version control
- Your favorite code editor (VS Code, IntelliJ, etc.)

### IDE Setup

#### VS Code (Recommended)
Extensions to install:
- Flutter (Dart Code)
- ES7+ React/Redux/React-Native snippets
- Better Comments
- REST Client (for testing HTTP endpoints)

#### Android Studio
- Built-in Flutter/Dart support
- Emulator for Android testing

#### Xcode (macOS)
- Required for iOS development
- Install with: `xcode-select --install`

## Backend Development

### Project Structure
```
backend/
├── src/
│   ├── index.ts          # Main server file
│   └── pi-rpc-client.ts  # RPC protocol wrapper
├── dist/                 # Compiled output (generated)
├── package.json          # Dependencies
└── tsconfig.json         # TypeScript config
```

### Running in Development
```bash
cd backend
npm run dev
```

This starts the TypeScript compiler in watch mode and runs the server with automatic restart on file changes.

### Building for Production
```bash
npm run build
npm start
```

### Adding New Commands

1. **Add to PiRpcClient** (src/pi-rpc-client.ts):
```typescript
async newCommand(param: string): Promise<RpcResponse> {
  return this.sendCommand({
    type: "new_command",
    param,
  });
}
```

2. **Add to Express handler** (src/index.ts):
```typescript
case "new_command":
  response = await piClient.newCommand(params.param);
  break;
```

3. **Call from Flutter** (frontend/lib/services/pi_service.dart):
```dart
Future<void> newCommand(String param) async {
  await _sendCommand('new_command', params: {'param': param});
}
```

### Debugging Backend

#### View Logs
Logs are visible in the terminal where you run the server.

#### Test with curl
```bash
curl -X POST http://localhost:3000/api/prompt \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello"}'
```

## Frontend Development

### Project Structure
```
frontend/
├── lib/
│   ├── main.dart                    # Entry point
│   ├── models/                      # Data models
│   ├── services/                    # Business logic
│   ├── providers/                   # State management
│   ├── screens/                     # UI screens
│   ├── widgets/                     # Reusable components
│   └── constants/                   # Config & strings
├── pubspec.yaml                     # Dependencies
```

### Running in Development

```bash
cd frontend

# Run on emulator/device
flutter run

# Hot reload (UI changes only): Press 'r'
# Hot restart (full app): Press 'R'
# Run on web
flutter run -d web-server
```

### File Organization

- **Models** - Data classes and types
- **Services** - API communication
- **Providers** - State management (Provider package)
- **Screens** - Full-page widgets
- **Widgets** - Reusable components

### Adding a New Screen

Create `lib/screens/new_screen.dart` and add route in `main.dart`.

### State Management with Provider

```dart
// In widget
Consumer<MyViewModel>(
  builder: (context, viewModel, _) {
    return Text(viewModel.data);
  },
)

// Call methods
onPressed: () {
  context.read<MyViewModel>().fetchData();
}
```

### Debugging Flutter

```bash
# View logs
flutter logs

# Run with verbose output
flutter run -v

# Analyze code
flutter analyze

# Format code
flutter format lib/
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

### Manual Testing Checklist
- [ ] Start backend
- [ ] Connect app
- [ ] Send prompt
- [ ] Receive response
- [ ] Change model
- [ ] Abort task
- [ ] Test reconnection

## Code Quality

### Formatting

Backend:
```bash
cd backend
npm run format
```

Frontend:
```bash
cd frontend
flutter format lib/
```

### Linting

Backend:
```bash
cd backend
npm run lint
```

Frontend:
```bash
cd frontend
flutter analyze
```

## Deployment

### Backend

Deploy to Render, Railway, or Docker:
```bash
docker build -t pi-mobile-backend ./backend
docker run -p 3000:3000 pi-mobile-backend
```

### Frontend

Android:
```bash
flutter build apk --split-per-abi
```

iOS:
```bash
flutter build ios
```

Web:
```bash
flutter build web
```

## Version Management

### Backend
Update `package.json`:
```json
{
  "version": "1.1.0"
}
```

### Frontend
Update `pubspec.yaml`:
```yaml
version: 1.1.0+1
```

## Git Workflow

```bash
# Create feature branch
git checkout -b feature/name

# Commit changes
git add .
git commit -m "feat: description"

# Push and create PR
git push origin feature/name
```

## Troubleshooting Development

### Backend Won't Start
```bash
# Check if port is in use
lsof -i :3000

# Verify Node version
node --version  # Need 18+

# Reinstall dependencies
rm -rf node_modules
npm install
```

### Flutter Issues
```bash
# Check setup
flutter doctor

# Check devices
flutter devices

# Clear cache
flutter clean
flutter pub get
```

### Dependencies Out of Date
```bash
# Backend
cd backend
npm update

# Frontend
cd frontend
flutter pub upgrade
```

## Getting Help

1. Check documentation in project root
2. Run `flutter doctor` or `npm --version`
3. Check backend logs and app logs
4. Review API_REFERENCE.md and QUICKSTART.md

---

Happy developing! 🚀
