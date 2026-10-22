# Quick Start Guide

## 1. Backend Setup (5 minutes)

```bash
# Navigate to backend directory
cd pi-mobile-agent/backend

# Install dependencies
npm install

# Create .env file
cat > .env << EOF
PORT=3000
PI_PROVIDER=anthropic
EOF

# Start the server
npm run dev
```

You should see:
```
Server listening on port 3000
WebSocket: ws://localhost:3000
HTTP API: http://localhost:3000/api
Starting Pi in RPC mode...
Pi RPC client initialized
```

## 2. Frontend Setup (5 minutes)

The app resolves the backend URL automatically:

- **Web (including Safari on iPhone/iPad):** it connects to the same host that
  served the page, so `localhost` on your desktop and your LAN IP on a phone both
  work with no rebuild.
- **Native iOS/Android:** pass the backend address with `--dart-define` (see below).

Override either way with:
```bash
flutter run --dart-define=SERVER_URL=ws://192.168.1.100:3000
```

### iPhone / iPad — easiest path (no Mac needed)

The backend serves the built web app on the same port, so a phone just opens a URL.

```bash
cd pi-mobile-agent/frontend
flutter build web          # output: frontend/build/web (backend serves this automatically)

# Find your machine's IP
# Windows: ipconfig (look for IPv4 Address)
# macOS/Linux: ifconfig | grep "inet " | grep -v 127
# Example: 192.168.1.100
```

Then on the iPhone/iPad, on the **same Wi-Fi**, open Safari at:
```
http://192.168.1.100:3000
```
Use **Add to Home Screen** if you want an app-like icon.

### Native iOS / Android app

Building for iOS requires macOS with Xcode; Android needs the Android toolchain.

```bash
cd pi-mobile-agent/frontend
flutter pub get
flutter run --dart-define=SERVER_URL=ws://192.168.1.100:3000
```

`frontend/ios/Runner/Info.plist` already allows plain `ws://` (App Transport
Security exception) so the app can reach a LAN backend.

### Android Emulator Special Setup

Android emulator has a special IP for the host:
```bash
flutter run --dart-define=SERVER_URL=ws://10.0.2.2:3000
```

### iOS Simulator

iOS simulator can reach localhost, which is the default for native builds:
```bash
flutter run
```

## 3. Test the Connection

### In Flutter App
- You should see "Connected" status in top right
- Events from Pi will appear in the chat

### From Terminal
```bash
# Check backend health
curl http://localhost:3000/health

# Should output:
# {"status":"ok","pi_connected":true}

# Send a test prompt via HTTP
curl -X POST http://localhost:3000/api/prompt \
  -H "Content-Type: application/json" \
  -d '{"message": "What is 2+2?"}'
```

## 4. Verify Pi is Working

Try sending a prompt from the app:
1. Type: "List the files in the current directory"
2. Press Send
3. Watch as Pi agent:
   - 🔧 Calls bash tool to list files
   - 📝 Streams response to your phone in real-time
   - ✓ Completes and shows final message

## Common Issues

### "Failed to connect"
- [ ] Backend running? `npm run dev`
- [ ] Opening the right address? On a phone use `http://<your-machine-ip>:3000`, not localhost
- [ ] For a native app, did you pass `--dart-define=SERVER_URL=ws://<ip>:3000`?
- [ ] Firewall blocking port 3000?
- [ ] Device on same network as computer?

### "Pi client not initialized"
- [ ] Pi CLI installed? `pi --version`
- [ ] Check backend logs for errors
- [ ] Try restarting backend: `Ctrl+C` then `npm run dev`

### App connects but no response
- [ ] Pi logged in? Run `pi /login` in terminal
- [ ] Model configured? `pi /models`
- [ ] Check backend logs for RPC errors
- [ ] Try aborting and sending new prompt

## Next Steps

1. **Explore Commands**:
   - Send: "Create a Flutter counter app"
   - Send: "Fix this bug: [paste code]"
   - Send: "Review my repository"

2. **Try Different Tasks**:
   - Code generation
   - Bug fixing
   - Documentation
   - Testing and reviews

3. **Customize**:
   - Modify UI colors in `theme` settings
   - Add custom buttons for frequent prompts
   - Create prompt templates
   - Add dark mode

4. **Extend Features**:
   - Add file browser for context
   - Build prompt library
   - Add session management
   - Integrate with other tools

## Debugging

### See Backend Logs
```bash
# Already visible in terminal where you ran `npm run dev`
# Look for:
# - Connection messages
# - Pi events
# - Command responses
```

### See Flutter Logs
```bash
# In Flutter console (where you ran flutter run)
# Or: flutter logs
```

### Monitor Network Traffic
- Use browser DevTools (if using web)
- Use Charles Proxy or similar for network inspection
- Add logging to `lib/services/pi_service.dart`

## Performance Tips

- Start with small prompts to test
- Use abort button if Pi takes too long
- Monitor backend CPU/memory usage
- Close other apps to free resources

## What's Next?

Once everything works:
1. Build real apps and fix real bugs from your phone
2. Add custom UI for your workflow
3. Create prompt templates for common tasks
4. Build a team version with authentication
5. Deploy backend to cloud for remote access

Enjoy building! 🚀
