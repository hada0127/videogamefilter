#!/bin/bash
set -euo pipefail
source_dir="$(cd "${1:?Pass the pinned Sunshine checkout}" && pwd)"
helper_app="${2:-$HOME/Applications/VGF Sunshine.app}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ssl_prefix="$(brew --prefix openssl@3)"
opus_prefix="$(brew --prefix opus)"
python3 "$script_dir/patch.py" "$source_dir"
cmake -S "$source_dir" -B "$source_dir/build-vgf" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_DOCS=OFF -DBUILD_TESTS=OFF \
  -DSUNSHINE_ENABLE_TRAY=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  "-DCMAKE_INSTALL_PREFIX=$helper_app/Contents/Resources" \
  "-DOPENSSL_INCLUDE_DIR=$ssl_prefix/include" \
  "-DOPENSSL_CRYPTO_LIBRARY=$ssl_prefix/lib/libcrypto.dylib" \
  "-DOPENSSL_SSL_LIBRARY=$ssl_prefix/lib/libssl.dylib" \
  "-DCMAKE_CXX_FLAGS=-I$ssl_prefix/include -I$opus_prefix/include"
cmake --build "$source_dir/build-vgf" -j "${BUILD_JOBS:-4}"
python3 "$script_dir/package.py" "$source_dir" "$helper_app"
