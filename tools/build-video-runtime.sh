#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$1" && pwd)"
mkdir -p -- "$2"
prefix="$(cd -- "$2" && pwd)"
jobs="${JOBS:-4}"
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
export CPPFLAGS="-I$prefix/include"
export LDFLAGS="-L$prefix/lib"

for library in libogg-1.3.6 libvorbis-1.3.7 libtheora-1.2.0; do
    (
        cd -- "$source_dir/$library"
        ./configure --host=aarch64-linux-musl --prefix="$prefix" --disable-shared \
            --enable-static --disable-examples --disable-oggtest --disable-vorbistest
        if [ "$library" = libtheora-1.2.0 ]; then
            make -C lib -j"$jobs" install
            make -C include install
            make install-pkgconfigDATA
        else
            make -j"$jobs"
            make install
        fi
    )
done

(
    cd -- "$source_dir/zlib-1.4"
    CHOST=aarch64-linux-musl ./configure --static --prefix="$prefix"
    make -j"$jobs" install
)

meson="${MESON:-meson}"
dav1d_build="$source_dir/dav1d-build"
"$meson" setup "$dav1d_build" "$source_dir/dav1d-1.5.5" \
    --cross-file "$DAV1D_CROSS_FILE" --prefix "$prefix" --libdir lib \
    --default-library static --buildtype release -Denable_tools=false -Denable_tests=false
"$meson" compile -C "$dav1d_build" -j "$jobs"
"$meson" install -C "$dav1d_build"

video_decoders=h264,hevc,libdav1d,vp8,vp9,mpeg4,theora,h263,mpeg1video,mpeg2video,mjpeg
video_decoders+=,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,vc1,flv,prores,dvvideo
audio_decoders=aac,aac_latm,opus,vorbis,mp3,mp2,flac,ac3,eac3,alac,wmav1,wmav2,wmapro,speex
audio_decoders+=,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_f32le,adpcm_ima_wav

cd -- "$source_dir/ffmpeg-8.1.2"
./configure --enable-cross-compile --arch=aarch64 --target-os=linux \
    --cc="$CC" --ar="$AR" --ranlib="$RANLIB" \
    --host-cc="${HOSTCC:-cc}" \
    --extra-cflags="-I$prefix/include" --extra-ldflags="-L$prefix/lib -static -s" \
    --pkg-config-flags=--static --disable-everything --disable-autodetect --disable-network \
    --disable-inline-asm \
    --disable-doc --disable-debug --disable-stripping --disable-avdevice --disable-ffplay --disable-ffprobe \
    --enable-ffmpeg --enable-libtheora --enable-libvorbis --enable-libdav1d --enable-zlib \
    --enable-protocol=file,pipe \
    --enable-demuxer=mov,matroska,ogg,avi,mpegts,mpegps,mpegvideo,asf,flv,dv,gif,apng,png_pipe,webp_pipe,wav,aiff,mp3,flac,image2 \
    --enable-parser=gif,h264,hevc,aac,ac3,av1,h263,mpeg4video,mpegvideo,mjpeg,vc1,opus,vp8,vp9,mpegaudio \
    --enable-decoder="$video_decoders,$audio_decoders,gif,apng,png,webp" \
    --enable-muxer=ogg,image2,wav \
    --enable-encoder=libtheora,libvorbis,png,pcm_s16le \
    --enable-filter=scale,fps,aresample,aformat,format,anull,null
make -j"$jobs" ffmpeg
mkdir -p -- "$prefix/bin"
cp -- ffmpeg "$prefix/bin/ffmpeg"
