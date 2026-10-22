@echo off
setlocal enabledelayedexpansion

echo 🚀 Pi Mobile Agent Setup
echo ========================
echo.

REM Check prerequisites
echo ✓ Checking prerequisites...

where pi >nul 2>nul
if errorlevel 1 (
    echo ❌ Pi CLI not found. Install with:
    echo    npm install -g @earendil-works/pi-coding-agent
    exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
    echo ❌ Node.js not found. Install from https://nodejs.org
    exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
    echo ⚠️  Flutter not found in PATH (optional for backend)
) else (
    echo ✓ Flutter found
)

echo ✓ Prerequisites check passed
echo.

REM Setup backend
echo 📦 Setting up backend...
cd backend

if not exist .env (
    copy .env.example .env
    echo ✓ Created .env file (please update with your credentials)
)

if not exist node_modules (
    call npm install
) else (
    echo ✓ Dependencies already installed
)

echo ✓ Backend setup complete
echo.

REM Setup frontend
echo 📱 Setting up frontend...
cd ..\frontend

where flutter >nul 2>nul
if errorlevel 1 (
    echo ⚠️  Flutter not installed, skipping frontend setup
    cd ..
    goto :display_next
)

call flutter pub get
echo ✓ Frontend dependencies installed
echo.

cd ..

:display_next
echo ✅ Setup complete!
echo.
echo Next steps:
echo.
echo 1. Configure your Pi provider:
echo    Edit backend\.env and set your API credentials
echo    Or run: pi /login
echo.
echo 2. Start the backend:
echo    cd backend && npm run dev
echo.
echo 3. In another terminal, update Flutter app with your server IP:
echo    Edit frontend\lib\main.dart
echo    Replace '192.168.1.100' with your machine's IP
echo.
echo 4. Run the Flutter app:
echo    cd frontend && flutter run
echo.
echo Need help? See QUICKSTART.md
echo.
pause
