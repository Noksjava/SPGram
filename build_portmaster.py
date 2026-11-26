"""Build the SPgram candidate archive from tracked application files."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
from tempfile import TemporaryDirectory
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

from portmaster.updater import DEFAULT_REPOSITORY, RETROSCROLL_THEMES, UPDATE_KEY, UPDATE_REPOSITORY, allowed_path, read_update_key


ROOT = Path(__file__).resolve().parent
VERSION = re.compile(r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}")
APP = "telegramsp/gamedata/"
TDLIB_REVISION = "42e6a5259551178d1dab54a22ad96d14bd906e20"
ROOT_FILES = {
    "main.lua", "conf.lua", "dkjson.lua", "qr.lua", "lib/libtdjson.so",
    "fonts/AdwaitaSans-Regular.ttf", "fonts/JetBrainsMono_SemiBold.ttf",
    "fonts/NotoEmoji-Regular.ttf", "fonts/SPgramHan-Regular.ttf", "keyboard/pinyin.tsv",
    "licenses/LICENSE.NotoSansSC.txt", "licenses/LICENSE.PinyinData.txt",
    "src/shared/system/keyboard_languages.lua", "src/shared/api/comment_methods.lua",
    "src/features/chat/ui/chat_comments.lua", "sounds/beepo/beepo.wav",
    "icons/emoji/twemoji.png", "icons/emoji/twemoji.txt", "licenses/LICENSE.Twemoji.txt",
    "src/shared/system/performance_trace.lua", "threads/performance_log.lua",
    "src/shared/api/network_recovery.lua", "src/shared/api/wifi_power.lua", "threads/wifi_power.lua",
    "intro/spgram-intro.ogv", "src/shared/ui/startup_intro.lua",
}


def write_archive(archive, entries, executables=()):
    with ZipFile(archive, "w") as zip_file:
        for dest, data in sorted(entries.items()):
            entry = ZipInfo(dest, (2000, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | (0o755 if dest in executables else 0o644)) << 16
            zip_file.writestr(entry, data, compress_type=ZIP_DEFLATED, compresslevel=9)
    with ZipFile(archive) as zip_file:
        if zip_file.testzip():
            raise ValueError("Archive failed CRC validation")
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    (archive.parent / f"{archive.name}.sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="ascii", newline="\n",
    )
    print(f"{archive}: {digest}")
    return {"name": archive.name, "size": archive.stat().st_size, "sha256": digest}


def app_credentials(environment):
    app_id = environment.get("SPGRAM_APP_ID", "")
    app_hash = environment.get("SPGRAM_APP_HASH", "")
    if (not re.fullmatch(r"[1-9][0-9]{0,9}", app_id)
            or int(app_id) > 2147483647 or not re.fullmatch(r"[0-9a-fA-F]{32}", app_hash)):
        raise ValueError("Set SPGRAM_APP_ID and SPGRAM_APP_HASH to the registered app credentials")
    return f"api_id={app_id}\napi_hash={app_hash}\n".encode("ascii")


def package(version, repository, output, include_app_credentials=False, chat_preview=False,
            release_candidate=False, video_runtime=None, update_public_key=None, stable_manifest=False):
    if not VERSION.fullmatch(version):
        raise ValueError("Use a stable X.Y.Z version without leading zeroes")
    if update_public_key is not None and not repository:
        repository = DEFAULT_REPOSITORY
    if repository and not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]*/[a-zA-Z0-9_-][a-zA-Z0-9_.-]*", repository):
        raise ValueError("Expected GitHub owner/repository")
    if stable_manifest and not (repository and update_public_key and release_candidate):
        raise ValueError("Stable metadata requires a repository, trusted update key and full release build")
    bundled = app_credentials(os.environ) if include_app_credentials or release_candidate else None
    index = ["git", "-c", f"safe.directory={ROOT.as_posix()}", "ls-files", "-z"]
    tracked = set(subprocess.check_output(index, cwd=ROOT).decode("utf-8").split("\0"))
    deleted = set(subprocess.check_output([*index, "--deleted"], cwd=ROOT).decode("utf-8").split("\0"))
    tracked.difference_update(deleted)
    wallpaper = f"{RETROSCROLL_THEMES}/wavelenght-tg.png"
    portable_assets = {"icons/app/spgram.png", "icons/app/bouncyarrow.png"}
    portable_assets.update(path.relative_to(ROOT).as_posix() for path in (ROOT / "fonts/retro").glob("*.ttf"))
    portable_assets.update(path.relative_to(ROOT).as_posix() for path in (ROOT / "licenses/retro").glob("*.txt"))
    for path in (ROOT / RETROSCROLL_THEMES).glob("*"):
        if path.is_file() and path.suffix.lower() == ".png":
            name = path.relative_to(ROOT).as_posix()
            if not allowed_path(name):
                raise ValueError(f"Invalid background filename: {path.name}")
            if name != wallpaper:
                portable_assets.add(name)
    sources = {APP + path: path for path in ROOT_FILES | portable_assets}
    if (ROOT / wallpaper).is_file():
        portable_assets.add(wallpaper)
        sources[APP + "res/telegram.png"] = wallpaper
    for path in tracked:
        if path.startswith(("src/", "threads/")) and path.endswith(".lua"):
            parts = PurePosixPath(path).parts
            if any(part.lower() in {"conf", "data", "private", "tdlib_files"} for part in parts):
                raise ValueError(f"Unexpected persistent-storage path: {path}")
            sources[APP + path] = path
    launcher = "SPgram.sh"
    sources.update({
        launcher: f"portmaster/{launcher}",
        "gameinfo.xml": "portmaster/gameinfo.xml",
        "cover.png": "portmaster/cover.png",
        "screenshot.png": "portmaster/screenshot.png",
        "telegramsp/licenses/LICENSE.UPSTREAM.txt": "LICENSE",
        "telegramsp/licenses/LICENSE.TDLib.txt": "licenses/LICENSE.TDLib.txt",
        "telegramsp/updater.py": "portmaster/updater.py",
    })
    name = f"SPgram-PortMaster-v{version}.zip"
    metadata = json.loads((ROOT / "portmaster/port.json").read_text(encoding="utf-8"))
    metadata["name"] = name
    if chat_preview:
        metadata["attr"]["desc"] = "Unofficial client using the Telegram API. Development chat preview."
    elif not release_candidate:
        metadata["attr"]["desc"] = "Unofficial client using the Telegram API. Sign-in and session preview."
    if bundled is None:
        metadata["attr"]["inst"] = "Place your Telegram API credentials in telegramsp/conf/telegram.conf."
    entries = {
        "port.json": (json.dumps(metadata, indent=2) + "\n").encode(),
        APP + "VERSION": (version + "\n").encode(),
        APP + "SIGN_IN_PREVIEW": b"0\n" if release_candidate or chat_preview else b"1\n",
    }
    if update_public_key is not None:
        entries["telegramsp/" + UPDATE_KEY] = read_update_key(update_public_key)
        entries["telegramsp/" + UPDATE_REPOSITORY] = (repository + "\n").encode("ascii")
    for dest, source in sources.items():
        path = ROOT / source
        if not path.is_file() or path.resolve() != path or (source not in tracked and source not in ROOT_FILES and source not in portable_assets):
            raise ValueError(f"Expected a regular application file: {source}")
        data = path.read_bytes()
        if path.suffix in {".sh", ".lua", ".xml", ".txt", ".md", ".py"}:
            data = data.replace(b"\r\n", b"\n")
            if re.search(rb"""(?i)api_hash\s*=\s*["']?[0-9a-f]{32}\b""", data):
                raise ValueError(f"Possible Telegram API hash: {source}")
        entries[dest] = data
    readme = [
        "## SPgram",
        "",
        "SPgram is an unofficial client using the Telegram API.",
        "",
        "### Install",
        "",
        "Copy SPgram.sh and the telegramsp folder to your PortMaster ports folder.",
    ]
    if bundled is not None:
        entries[APP + "app-credentials.ini"] = bundled
        readme.append("Launch SPgram and sign in with your phone number or a QR code.")
    else:
        readme.append("Supply your Telegram app credentials before signing in.")
    readme.extend((
        "", "### Controls", "",
        "Use the D-pad to move. The bottom face button confirms, the right face button goes back, and the top face button opens Options.",
        "Press SELECT to show Controls. Press START on the chat list to open Settings and remap the controls.",
        "", "Maintainer: Noksjava. Based on [archeryfox’s TGmuOS-LOVE](https://github.com/archeryfox/TGmuOS-LOVE).", "",
    ))
    entries["README.md"] = "\n".join(readme).encode("utf-8")
    gameinfo = ET.fromstring(entries["gameinfo.xml"])
    gameinfo.find("game/desc").text = metadata["attr"]["desc"]
    entries["gameinfo.xml"] = ET.tostring(gameinfo, encoding="utf-8", xml_declaration=True)
    elf = entries[APP + "lib/libtdjson.so"]
    if elf[:6] != b"\x7fELF\x02\x01" or int.from_bytes(elf[18:20], "little") != 183:
        raise ValueError("Expected an AArch64 ELF64 TDLib object")
    if b"\0" + TDLIB_REVISION.encode("ascii") + b"\0" not in elf:
        raise ValueError("TDLib binary does not report the pinned upstream revision")
    native = {"tdlib": {"revision": TDLIB_REVISION, "sha256": hashlib.sha256(elf).hexdigest()}}
    executables = {launcher}
    if video_runtime is not None:
        converter = (video_runtime / "ffmpeg").read_bytes()
        if converter[:6] != b"\x7fELF\x02\x01" or converter[18:20] != b"\xb7\x00":
            raise ValueError("Expected an AArch64 ELF64 FFmpeg executable")
        runtime_path = "telegramsp/runtime/ffmpeg"
        entries[runtime_path] = converter
        native["ffmpeg"] = {"sha256": hashlib.sha256(converter).hexdigest()}
        executables.add(runtime_path)
        for notice in ("FFmpeg-LICENSE.txt", "ffmpeg-source.tar.xz"):
            entries[f"telegramsp/licenses/{notice}"] = (video_runtime / notice).read_bytes()

    output.mkdir(parents=True, exist_ok=True)
    asset = write_archive(output / name, entries, executables)
    update_name = f"SPgram-Update-v{version}.zip"
    update_asset = write_archive(
        output / update_name, {dest[len(APP):]: data for dest, data in entries.items()
                               if dest.startswith(APP)},
    )
    for item in (asset, update_asset):
        item["url"] = (f"https://github.com/{repository}/releases/download/v{version}/{item['name']}"
                       if repository else None)
    manifest = {
        "schema": 1, "repository": repository, "channel": "stable" if stable_manifest else "preview", "version": version,
        "target": {"os": "KNULLI", "arch": "aarch64", "runtime": "love_11.5",
                   "min_firmware": "Gladiator II"},
        "minimum_updater": 3, "asset": asset, "update_asset": update_asset, "native": native,
    }
    (output / "release-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", nargs="?", default=(ROOT / "VERSION").read_text().strip())
    parser.add_argument("--repository")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--testing", action="store_true",
                        help="Copy the SD-card ZIP and checksum to the sibling Testing folder")
    parser.add_argument("--app-credentials", action="store_true",
                        help="Include extractable SPgram app credentials from build environment variables")
    parser.add_argument("--chat-preview", action="store_true",
                        help="Enable development chat browsing in a local test build")
    parser.add_argument("--release-candidate", action="store_true",
                        help="Build the full zero-setup client and matching preview update artifacts")
    parser.add_argument("--video-runtime", type=Path,
                        help="Bundle a standalone AArch64 FFmpeg and its license and source files")
    parser.add_argument("--update-public-key", type=Path, help="Pin a DER Ed25519 public key in the full installer")
    parser.add_argument("--stable-manifest", action="store_true", help="Write stable metadata for offline signing")
    args = parser.parse_args()
    if args.chat_preview and not args.testing:
        parser.error("--chat-preview requires --testing")
    if args.release_candidate and args.chat_preview:
        parser.error("Choose either --release-candidate or --chat-preview")
    if args.testing:
        if args.output is not None:
            parser.error("--testing and --output cannot be used together")
        testing = ROOT.parent / "Testing"
        testing.mkdir(exist_ok=True)
        archive = f"SPgram-PortMaster-v{args.version}.zip"
        with TemporaryDirectory(prefix="spgram-build-") as temporary:
            output = Path(temporary)
            package(args.version, args.repository, output, args.app_credentials, args.chat_preview,
                    args.release_candidate, args.video_runtime, args.update_public_key, args.stable_manifest)
            for filename in (archive, archive + ".sha256"):
                shutil.copyfile(output / filename, testing / filename)
        print(testing / archive)
    else:
        package(args.version, args.repository, args.output or ROOT / "dist", args.app_credentials,
                release_candidate=args.release_candidate, video_runtime=args.video_runtime,
                update_public_key=args.update_public_key, stable_manifest=args.stable_manifest)
