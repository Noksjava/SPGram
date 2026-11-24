#!/bin/bash
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d /opt/system/Tools/PortMaster ]; then
  controlfolder=/opt/system/Tools/PortMaster
elif [ -d /opt/tools/PortMaster ]; then
  controlfolder=/opt/tools/PortMaster
elif [ -d "$XDG_DATA_HOME/PortMaster" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
elif [ -f /userdata/system/.local/share/PortMaster/control.txt ]; then
  controlfolder=/userdata/system/.local/share/PortMaster
else
  controlfolder=/roms/ports/PortMaster
fi
source "$controlfolder/control.txt" || exit 1
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls
GAMEDIR="$(cd -- "$(dirname -- "$0")" && pwd)/telegramsp"
CONFDIR="$GAMEDIR/conf"
umask 077
mkdir -p "$CONFDIR" || exit 1
cd "$CONFDIR" || exit 1
exec > "$CONFDIR/launcher.log" 2>&1
printf 'Architecture: %s\n' "$(uname -m)"
if command -v getconf >/dev/null 2>&1; then
  getconf GNU_LIBC_VERSION
fi
export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export TG_CONFIG="$CONFDIR/telegram.conf"
if [ -x "$GAMEDIR/runtime/ffmpeg" ] && "$GAMEDIR/runtime/ffmpeg" -version >/dev/null 2>&1; then
  export SPGRAM_FFMPEG="$GAMEDIR/runtime/ffmpeg"
  printf '%s\n' 'Video runtime: bundled FFmpeg.'
elif command -v ffmpeg >/dev/null 2>&1; then
  printf '%s\n' 'Video runtime: firmware FFmpeg.'
else
  export SPGRAM_NO_FFMPEG=1
  printf '%s\n' 'Video playback unavailable: ffmpeg was not found.'
fi
if ! source "$controlfolder/runtimes/love_11.5/love.txt" || [ ! -x "$LOVE_BINARY" ]; then
  printf '%s\n' 'Required PortMaster runtime is unavailable.'
  pm_finish
  exit 1
fi
$GPTOKEYB "$LOVE_GPTK" &
pm_platform_helper "$LOVE_BINARY"
if command -v python3 >/dev/null 2>&1 &&
    python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))'; then
  python3 "$GAMEDIR/updater.py" --port "$GAMEDIR" run -- env "LD_LIBRARY_PATH=$RUNTIME_DIR/libs.$DEVICE_ARCH:$LD_LIBRARY_PATH" "$LOVE_BINARY"
else
  $LOVE_RUN "$GAMEDIR/gamedata" >/dev/null 2>&1
fi
result=$?
printf 'SPgram exited with status %s\n' "$result"
pm_finish
exit "$result"
