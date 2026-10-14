#!/usr/bin/env bash
# Builds whisper.cpp (Metal, embedded shaders) as static libs into vendor/whisper.
set -euo pipefail
VERSION="${WHISPER_VERSION:-v1.9.5}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/whisper.cpp"
OUT="$ROOT/vendor/whisper"

if [ ! -d "$SRC" ]; then
  git clone --depth 1 --branch "$VERSION" https://github.com/ggml-org/whisper.cpp "$SRC"
fi

cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_BLAS=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DCMAKE_INSTALL_PREFIX="$OUT"
cmake --build "$SRC/build" --config Release -j "$(sysctl -n hw.ncpu)"
cmake --install "$SRC/build"
echo "whisper.cpp $VERSION installed to $OUT"
