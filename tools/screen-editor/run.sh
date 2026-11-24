#!/bin/sh
cd "$(dirname "$0")" || exit 1
if [ ! -x target/release/screen-editor ]; then
    echo "Building screen-editor..."
    cargo build --release || exit 1
fi
exec ./target/release/screen-editor