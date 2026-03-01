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

# --- 3. Build voxtral.c (static library) ---
VOXTRAL_DIR="./libs/voxtral.c"

if [ ! -d "$VOXTRAL_DIR" ]; then
    echo ""
    echo "📦 Cloning voxtral.c..."
    mkdir -p libs
    git clone https://github.com/antirez/voxtral.c.git "$VOXTRAL_DIR"
else
    echo "📦 voxtral.c already cloned, pulling latest..."
    cd "$VOXTRAL_DIR" && git pull && cd ../..
fi

echo ""
echo "🔨 Building voxtral.c (static library)..."
mkdir -p "$VOXTRAL_DIR/build"

# Generate embedded Metal shaders header
if [ -f "$VOXTRAL_DIR/voxtral_shaders.metal" ]; then
    echo "   Embedding Metal shaders..."
    xxd -i voxtral_shaders.metal > voxtral_shaders_source.h
fi 2>/dev/null || true

# Compile each .c and .m file (excluding main.c and inspect_weights.c)
VOXTRAL_OBJS=""
VOXTRAL_FLAGS="-O2 -DUSE_BLAS -DUSE_METAL -DACCELERATE_NEW_LAPACK -I$VOXTRAL_DIR"

cd "$VOXTRAL_DIR"
for src in *.c; do
    [ "$src" = "main.c" ] && continue
    [ "$src" = "inspect_weights.c" ] && continue
    obj="build/$(basename "$src" .c).o"
    echo "   Compiling $src..."
    clang $VOXTRAL_FLAGS -c "$src" -o "$obj"
    VOXTRAL_OBJS="$VOXTRAL_OBJS $obj"
done
for src in *.m; do
    obj="build/$(basename "$src" .m).o"
    echo "   Compiling $src..."
    clang $VOXTRAL_FLAGS -fobjc-arc -c "$src" -o "$obj" \
        -framework Foundation -framework Metal -framework MetalPerformanceShaders -framework MetalPerformanceShadersGraph
    VOXTRAL_OBJS="$VOXTRAL_OBJS $obj"
done

echo "   Archiving libvoxtral.a..."
ar rcs build/libvoxtral.a $VOXTRAL_OBJS
cd ../..

echo "✅ voxtral.c built: $VOXTRAL_DIR/build/libvoxtral.a"

# --- 4. Download Voxtral model (optional: ./setup.sh voxtral) ---
if [ "${1:-}" = "voxtral" ] || [ "${2:-}" = "voxtral" ]; then
    echo ""
    echo "📥 Downloading Voxtral model (~8.9 Go)..."
    VOXTRAL_MODEL_DIR="./Models/voxtral-model"
    if [ ! -f "$VOXTRAL_MODEL_DIR/consolidated.safetensors" ]; then
        mkdir -p "$VOXTRAL_MODEL_DIR"
        cd "$VOXTRAL_DIR"
        if [ -f "download_model.sh" ]; then
            bash download_model.sh
            # Move downloaded model files to Models/voxtral-model/
            if [ -d "model" ]; then
                cp -r model/* "../../$VOXTRAL_MODEL_DIR/"
            fi
        else
            echo "⚠️  download_model.sh not found in voxtral.c — download manually"
        fi
        cd ../..
        echo "✅ Voxtral model downloaded to $VOXTRAL_MODEL_DIR/"
    else
        echo "✅ Voxtral model already exists: $VOXTRAL_MODEL_DIR/"
    fi
fi

# --- 5. Summary ---
echo ""
echo "========================================"
echo "✅ Setup complete!"
echo ""
echo "Whisper:  $WHISPER_DIR/build/src/libwhisper.dylib"
echo "Voxtral:  $VOXTRAL_DIR/build/libvoxtral.a"
echo "Model:    $MODEL_DIR/$MODEL_FILE"
echo ""
echo "Next steps:"
echo "  1. xcodegen generate"
echo "  2. Build & Run 🚀"
echo ""
echo "To download the Voxtral model (~8.9 Go):"
echo "  ./setup.sh voxtral"
echo "========================================"
