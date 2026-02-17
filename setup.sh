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

# Default: distil-large-v3 (6x faster than large-v3, ~1% WER difference)
# Options: tiny, base, small, medium, large-v3, large-v3-turbo, distil-large-v3
MODEL_SIZE="${1:-distil-large-v3}"
MODEL_FILE="ggml-${MODEL_SIZE}.bin"

if [ ! -f "$MODEL_DIR/$MODEL_FILE" ]; then
    echo "📥 Downloading Whisper model: $MODEL_SIZE..."
    echo "   (This may take a few minutes depending on model size)"

    if [ "$MODEL_SIZE" = "distil-large-v3" ]; then
        # Distil-Whisper: 6x faster, <1% WER difference vs large-v3
        echo "   → Distil-Whisper: 6x faster, <1% WER difference vs large-v3"
        bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_SIZE"
        if [ -f "$WHISPER_DIR/models/$MODEL_FILE" ]; then
            mv "$WHISPER_DIR/models/$MODEL_FILE" "$MODEL_DIR/"
        else
            echo "⚠️  distil-large-v3 not found. Falling back to large-v3-turbo..."
            MODEL_SIZE="large-v3-turbo"
            MODEL_FILE="ggml-${MODEL_SIZE}.bin"
            bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_SIZE"
            mv "$WHISPER_DIR/models/$MODEL_FILE" "$MODEL_DIR/"
        fi
    else
        # Use the whisper.cpp download script
        bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_SIZE"
        mv "$WHISPER_DIR/models/$MODEL_FILE" "$MODEL_DIR/"
    fi

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
echo "Model fallback chain (best → fallback):"
echo "  1. distil-large-v3  (6x faster, recommended)"
echo "  2. large-v3-turbo   (best quality/speed balance)"
echo "  3. large-v3         (highest quality)"
echo "  4. medium           (good quality, moderate speed)"
echo "  5. small / base / tiny (fast, lower quality)"
echo ""
echo "To download additional models:"
echo "  ./setup.sh large-v3-turbo"
echo "  ./setup.sh medium"
echo ""
echo "Language detection: set to 'auto' by default."
echo "  The app will auto-detect French, English, and 90+ languages."
echo "========================================"
