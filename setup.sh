#!/bin/bash
set -e

echo "🚀 Pi Mobile Agent Setup"
echo "========================"
echo ""

# Check prerequisites
echo "✓ Checking prerequisites..."

if ! command -v pi &> /dev/null; then
    echo "❌ Pi CLI not found. Install with:"
    echo "   npm install -g @earendil-works/pi-coding-agent"
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Install from https://nodejs.org"
    exit 1
fi

if ! command -v flutter &> /dev/null; then
    echo "⚠️  Flutter not found in PATH (optional for backend)"
    echo "   You can still run the backend without Flutter locally"
fi

echo "✓ Prerequisites check passed"
echo ""

# Setup backend
echo "📦 Setting up backend..."
cd backend
cp .env.example .env

if [ ! -d "node_modules" ]; then
    npm install
fi

echo "✓ Backend setup complete"
echo ""

# Setup frontend
echo "📱 Setting up frontend..."
cd ../frontend

if ! command -v flutter &> /dev/null; then
    echo "⚠️  Skipping Flutter setup (not installed)"
    cd ..
else
    flutter pub get
    echo "✓ Frontend dependencies installed"
    echo ""
fi

cd ..

# Display next steps
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo ""
echo "1. Configure your Pi provider:"
echo "   Edit backend/.env and set your API credentials"
echo "   Or run: pi /login"
echo ""
echo "2. Start the backend:"
echo "   cd backend && npm run dev"
echo ""
echo "3. In another terminal, update Flutter app with your server IP:"
echo "   Edit frontend/lib/main.dart"
echo "   Replace '192.168.1.100' with your machine's IP"
echo ""
echo "4. Run the Flutter app:"
echo "   cd frontend && flutter run"
echo ""
echo "Need help? See QUICKSTART.md"
