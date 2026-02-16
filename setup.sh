#!/bin/bash
set -e

echo "🎙️ VoiceScribe - Setup"
echo "======================"

# --- 1. Clone & build whisper.cpp ---
WHISPER_DIR="./libs/whisper.cpp"

if [ ! -d "$WHISPER_DIR" ]; then
    echo ""
    echo "📦 Cloning whisper.cpp..."
    mkdir -p libs
    git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
else
    echo "📦 whisper.cpp already cloned, pulling latest..."
    cd "$WHISPER_DIR" && git pull && cd ../..
fi

echo ""
echo "🔨 Building whisper.cpp..."
cd "$WHISPER_DIR"

# Build with Metal (Apple Silicon GPU acceleration) + CoreML
cmake -B build \
    -DWHISPER_METAL=ON \
    -DWHISPER_COREML=OFF \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release

cmake --build build --config Release -j$(sysctl -n hw.ncpu)

cd ../..

echo ""
echo "✅ whisper.cpp built successfully"

# --- 2. Download Whisper model ---
MODEL_DIR="./Models"
mkdir -p "$MODEL_DIR"

# Default: large-v3-turbo (best speed/quality ratio)
# Options: tiny, base, small, medium, large-v3, large-v3-turbo
MODEL_SIZE="${1:-large-v3-turbo}"
MODEL_FILE="ggml-${MODEL_SIZE}.bin"

if [ ! -f "$MODEL_DIR/$MODEL_FILE" ]; then
    echo "📥 Downloading Whisper model: $MODEL_SIZE..."
    echo "   (This may take a few minutes depending on model size)"
    
    # Use the whisper.cpp download script
    bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_SIZE"
    mv "$WHISPER_DIR/models/$MODEL_FILE" "$MODEL_DIR/"
    
    echo "✅ Model downloaded to $MODEL_DIR/$MODEL_FILE"
else
    echo "✅ Model already exists: $MODEL_DIR/$MODEL_FILE"
fi

# --- 3. Summary ---
echo ""
echo "========================================"
echo "✅ Setup complete!"
echo ""
echo "Library:  $WHISPER_DIR/build/src/libwhisper.dylib"
echo "Header:   $WHISPER_DIR/include/whisper.h"
echo "Model:    $MODEL_DIR/$MODEL_FILE"
echo ""
echo "Next steps:"
echo "  1. Open Xcode → File → New → Project → macOS → App"
echo "  2. Name it 'VoiceScribe', Interface: SwiftUI, Language: Swift"
echo "  3. Copy all files from VoiceScribe/ into your Xcode project"
echo "  4. Add the bridging header (see README.md)"
echo "  5. Link libwhisper.dylib (see README.md)"
echo "  6. Build & Run 🚀"
echo "========================================"
