#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [[ $# -ne 3 || "$(uname -m)" != aarch64 ]]; then
    printf '%s\n' 'Usage on AArch64 Linux: build-tdlib.sh SOURCE BUILD_DIR OUTPUT_DIR' >&2
    exit 2
fi

revision=42e6a5259551178d1dab54a22ad96d14bd906e20
source_dir=$1
build_dir=$2
output_dir=$3

if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" ]] ||
    [[ -n "$(git -C "$source_dir" status --porcelain --untracked-files=all)" ]]; then
    printf 'Use a clean TDLib checkout at %s\n' "$revision" >&2
    exit 1
fi

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DTD_ENABLE_LTO=OFF \
    -DOPENSSL_USE_STATIC_LIBS=ON -DZLIB_USE_STATIC_LIBS=ON
cmake --build "$build_dir" --target tdjson --parallel "${SPGRAM_TDLIB_JOBS:-2}"
library="$build_dir/libtdjson.so"
architecture=$(readelf -h "$library")
if [[ "$architecture" != *AArch64* ]]; then
    printf '%s\n' 'TDLib output does not target AArch64' >&2
    exit 1
fi

versions=$(readelf --version-info "$library")
glibc=$(printf '%s\n' "$versions" | awk '
    { for (i = 1; i <= NF; i++) if ($i ~ /^GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?$/) print substr($i, 7) }
' | sort -V | tail -1)
if [[ -z "$glibc" ]] || [[ "$(printf '%s\n' 2.34 "$glibc" | sort -V | tail -1)" != 2.34 ]]; then
    printf 'TDLib has an unsupported glibc baseline: %s (maximum 2.34)\n' "$glibc" >&2
    exit 1
fi

mkdir -p "$output_dir"
install -m 755 "$library" "$output_dir/libtdjson.so"
{
    printf 'TDLib upstream revision: %s\n' "$revision"
    printf 'Highest referenced glibc ABI: %s\n' "$glibc"
    cmake --version
    readelf -d "$output_dir/libtdjson.so"
    printf '%s\n' "$versions"
} > "$output_dir/tdlib-build.txt"
(
    cd "$output_dir"
    sha256sum libtdjson.so > libtdjson.so.sha256
)
