# Getting Started Checklist

## Prerequisites ✅
- [ ] Node.js 18+ installed
- [ ] Flutter 3.0+ installed
- [ ] Pi CLI installed (`npm install -g @earendil-works/pi-coding-agent`)
- [ ] Python 3.8+ available (for some Pi tools)
- [ ] Git (for version control)

## Initial Setup

### 1. Backend Setup (10 minutes)
- [ ] Navigate to `pi-mobile-agent/backend`
- [ ] Copy `.env.example` to `.env`
- [ ] Edit `.env`:
  - [ ] Set `PI_PROVIDER` (anthropic, openai, etc.)
  - [ ] Set `PI_MODEL` to your preferred model
  - [ ] Set `PORT` if 3000 conflicts
- [ ] Run `npm install`
- [ ] Verify Pi login: Run `pi /login` in terminal
- [ ] Test backend start: `npm run dev`
- [ ] Confirm server message: "Server listening on port 3000"
- [ ] Check `/health` endpoint: `curl http://localhost:3000/health`
- [ ] Keep backend running in terminal

### 2. Network Configuration
- [ ] Find your machine's local IP:
  - **macOS/Linux**: `ifconfig | grep "inet " | grep -v 127`
  - **Windows**: `ipconfig` (look for IPv4 under your adapter)
  - **Example**: `192.168.1.100`
- [ ] Note your IP address: `_________________`
- [ ] Ensure phone/emulator on same WiFi network
- [ ] Test phone can reach your computer: `ping <your-ip>`

### 3. Frontend Setup (10 minutes)

#### For Physical Device or Emulator
- [ ] Navigate to `pi-mobile-agent/frontend`
- [ ] Run `flutter pub get`
- [ ] Open `lib/main.dart`
- [ ] Update line in `MyApp`:
  ```dart
  const serverUrl = 'ws://YOUR_IP:3000';  // Replace YOUR_IP
  ```
  **My IP is**: `_________________`
- [ ] Save file
- [ ] Connect device or start emulator
- [ ] Run `flutter run`
- [ ] App should start and show "Connected"

#### For Android Emulator (Special Case)
- [ ] Use this URL instead:
  ```dart
  const serverUrl = 'ws://10.0.2.2:3000';
  ```
- [ ] Save and run `flutter run`

#### For iOS Simulator
- [ ] Use this URL:
  ```dart
  const serverUrl = 'ws://localhost:3000';
  ```
- [ ] Make sure backend is running on same Mac
- [ ] Run `flutter run -d macos` or for simulator

## Verification

### Check Backend
- [ ] Backend terminal shows "Pi RPC client initialized"
- [ ] No error messages in backend logs
- [ ] `curl http://localhost:3000/health` returns `{"status":"ok","pi_connected":true}`

### Check Frontend
- [ ] App displays "Connected" in top right (green)
- [ ] No error messages on app start
- [ ] Can see app UI (input field, model selector)

### Test Communication
- [ ] Open app
- [ ] See connection status: **Connected** ✓
- [ ] Type prompt: "Hello, what is Pi?"
- [ ] Click Send button
- [ ] Wait 2-3 seconds for response
- [ ] See message appear in chat
- [ ] Backend logs show activity

## First Real Task

Once everything connects:

1. **Try a Simple Task**:
   ```
   Prompt: "What files are in the current directory?"
   ```
   Expected: Directory listing appears in app

2. **Try Code Generation**:
   ```
   Prompt: "Create a simple Hello World program in Python"
   ```
   Expected: Python code appears in app

3. **Try Bug Fixing**:
   ```
   Prompt: "Fix this bug: [paste your code]"
   ```
   Expected: Fixed code with explanation

## Customization

### Update Server IP
- [ ] Updated in `lib/main.dart`
- [ ] Tested connection works
- [ ] Device reconnects after IP change

### Customize Appearance
- [ ] Edit colors in `lib/constants/app_constants.dart`
- [ ] Update `MyApp` theme in `lib/main.dart`
- [ ] Test dark mode works: System Settings → Display

### Add Custom Prompts
- [ ] Consider adding quick action buttons in HomeScreen
- [ ] Store frequently used prompts as text constants

## Deployment (Optional)

### For Testing on Multiple Devices
- [ ] Make sure all devices on same network
- [ ] Use same backend IP for all
- [ ] Each device connects independently

### For Cloud Deployment
- [ ] Deploy backend to cloud service (Railway, Render, etc.)
- [ ] Update `serverUrl` to cloud domain
- [ ] Use WSS (secure WebSocket) in production
- [ ] Add authentication to backend

## Troubleshooting

### Backend Won't Start
- [ ] Check error message carefully
- [ ] Verify Pi is installed: `pi --version`
- [ ] Check if port 3000 is in use: `lsof -i :3000`
- [ ] Try different port: Change `PORT` in `.env`

### App Won't Connect
- [ ] Verify IP is correct in `lib/main.dart`
- [ ] Ping computer from device: `ping <your-ip>`
- [ ] Check firewall allows port 3000
- [ ] Try local emulator URL if using emulator
- [ ] Restart both backend and app

### No Response to Prompts
- [ ] Check backend logs for errors
- [ ] Verify Pi is logged in: `pi /login`
- [ ] Try simple prompt: "Hello"
- [ ] Check model is set correctly
- [ ] Look for token limit errors in logs

### App Crashes
- [ ] Check Flutter logs: `flutter logs`
- [ ] Rebuild app: `flutter clean && flutter pub get && flutter run`
- [ ] Update Flutter: `flutter upgrade`

## Tips & Tricks

### Monitor Backend Activity
```bash
# In backend terminal, watch for:
# "New WebSocket client connected"
# "Executing command prompt"
# "Pi RPC event: message_update"
```

### Watch App Logs
```bash
# In separate terminal:
flutter logs
# Shows all print() statements from app
```

### Fast Development
- [ ] Use hot reload for UI changes: Press `r` in terminal
- [ ] Use hot restart for service changes: Press `R`
- [ ] Clear app cache if weird state: `flutter clean`

### Performance
- [ ] Close unnecessary background apps
- [ ] Monitor backend CPU/memory
- [ ] Keep prompts reasonably sized
- [ ] Use abort button if task hangs

## What's Next?

After getting everything working:

1. **Explore Features**:
   - [ ] Change models in dropdown
   - [ ] Send multi-line prompts
   - [ ] Try abort button
   - [ ] Scroll through message history

2. **Build Real Projects**:
   - [ ] Create Flutter apps
   - [ ] Fix bugs in your code
   - [ ] Generate documentation
   - [ ] Review pull requests

3. **Customize for Workflow**:
   - [ ] Add custom buttons for common tasks
   - [ ] Create prompt templates
   - [ ] Implement session management
   - [ ] Add file upload/context

4. **Extend Backend**:
   - [ ] Add HTTP POST endpoints
   - [ ] Custom command handlers
   - [ ] Database integration
   - [ ] Authentication

## Useful Resources

- **Pi Documentation**: https://pi.dev
- **Pi RPC Protocol**: https://pi.dev/docs/rpc
- **Flutter Docs**: https://flutter.dev
- **WebSocket in Flutter**: https://pub.dev/packages/web_socket_channel
- **Provider Package**: https://pub.dev/packages/provider

## Need Help?

- Check logs in both backend and app
- Review `QUICKSTART.md` for common issues
- Check `PROJECT_STRUCTURE.md` for architecture
- Run `pi --help` for Pi CLI options
- Run `flutter doctor` for Flutter setup issues

---

**You're ready to build! 🚀**

Start with a simple prompt and iterate from there. Good luck!
