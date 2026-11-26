"""Verify, stage and select SPgram updates."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory, mkdtemp
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from zipfile import ZIP_DEFLATED, ZIP_STORED, BadZipFile, ZipFile

LIMIT = 100 * 1024 * 1024
EXPANDED_LIMIT = 160 * 1024 * 1024
MANIFEST_LIMIT = 65536
UPDATE_KEY = "update-public-key.der"
UPDATE_REPOSITORY = "update-repository"
DEFAULT_REPOSITORY = "Noksjava/SPGram"
SIGNATURE_NAME = "release-manifest.sig"
ED25519_SPKI_PREFIX = bytes.fromhex("302a300506032b6570032100")
VERSION = re.compile(r"(?:0|[1-9][0-9]{0,7})(?:\.(?:0|[1-9][0-9]{0,7})){2}")
ROOT_FILES = {
    "main.lua", "conf.lua", "dkjson.lua", "qr.lua", "VERSION", "lib/libtdjson.so",
    "fonts/AdwaitaSans-Regular.ttf", "fonts/JetBrainsMono_SemiBold.ttf",
    "fonts/NotoEmoji-Regular.ttf", "res/telegram.png", "app-credentials.ini", "SIGN_IN_PREVIEW",
}
REQUIRED = ROOT_FILES - {"res/telegram.png", "app-credentials.ini", "SIGN_IN_PREVIEW"}
TARGET = {"os": "KNULLI", "arch": "aarch64", "runtime": "love_11.5",
          "min_firmware": "Gladiator II"}
INSTALL_EXIT, ROLLBACK_EXIT, GITHUB_ROLLBACK_EXIT = 41, 42, 43
CDN = {"release-assets.githubusercontent.com", "objects.githubusercontent.com"}
APP_PREFIX = "telegramsp/gamedata/"
RETROSCROLL_THEMES = "effects/retroscroll/themes"
RELEASE_TAG = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,79}")
INSTALLER = re.compile(r"SPgram-PortMaster-v(" + VERSION.pattern + r")\.zip")


def version(value):
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise ValueError("Unsupported version")
    return tuple(map(int, value.split(".")))


def sync_dir(path):
    if os.name == "posix":
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def allowed_path(name):
    parts = PurePosixPath(name).parts
    if len(name) > 240 or not parts or "/".join(parts) != name:
        return False
    theme = len(parts) == 4 and "/".join(parts[:3]) == RETROSCROLL_THEMES
    if any(not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_. -]*" if theme else r"[A-Za-z0-9_][A-Za-z0-9_.-]*", part)
           or part.endswith(".") or part.split(".")[0].rstrip().upper() in
           {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)),
            *(f"LPT{i}" for i in range(1, 10))}
           for part in parts):
        return False
    if name in ROOT_FILES:
        return True
    if name in {"icons/app/spgram.png", "icons/app/bouncyarrow.png", "fonts/SPgramHan-Regular.ttf", "keyboard/pinyin.tsv",
                "licenses/LICENSE.NotoSansSC.txt", "licenses/LICENSE.PinyinData.txt", "sounds/beepo/beepo.wav",
                "icons/emoji/twemoji.png", "icons/emoji/twemoji.txt", "licenses/LICENSE.Twemoji.txt", "intro/spgram-intro.ogv"}:
        return True
    if len(parts) == 3 and parts[1] == "retro":
        return (parts[0] == "fonts" and name.endswith(".ttf")) or (parts[0] == "licenses" and name.endswith(".txt"))
    if theme:
        return PurePosixPath(name).suffix.lower() == ".png"
    return (len(parts) >= 2 and parts[0] in {"src", "threads"} and name.endswith(".lua")
            and not any(part.lower() in {"conf", "data", "private", "tdlib_files"} for part in parts))


def manifest_asset(manifest):
    if (manifest["schema"] != 1 or manifest["channel"] != "stable"
            or manifest["target"] != TARGET or manifest["minimum_updater"] != 3):
        raise ValueError("Incompatible update")
    label = manifest["version"]
    version(label)
    asset = manifest["update_asset"]
    if (asset["name"] != f"SPgram-Update-v{label}.zip"
            or type(asset["size"]) is not int or not 0 < asset["size"] <= LIMIT
            or not re.fullmatch(r"[a-f0-9]{64}", asset["sha256"])):
        raise ValueError("Invalid update asset metadata")
    return label, asset


def read_bytes(path, limit):
    with path.open("rb") as handle:
        data = handle.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Update metadata too large")
    return data


def read_json(path, limit=MANIFEST_LIMIT):
    return json.loads(read_bytes(path, limit))


def read_update_key(path):
    key = read_bytes(path, 44)
    if len(key) != 44 or not key.startswith(ED25519_SPKI_PREFIX):
        raise ValueError("Expected an Ed25519 public key in DER format")
    return key


def verify_manifest(key_path, payload, signature):
    if not 0 < len(payload) <= MANIFEST_LIMIT or len(signature) != 64:
        raise ValueError("Invalid signed manifest length")
    if key_path.is_symlink() or not key_path.is_file():
        raise ValueError("This installation does not have a trusted update key")
    key = read_update_key(key_path)
    openssl = shutil.which("openssl")
    if not openssl:
        raise ValueError("OpenSSL is unavailable for signature verification")
    with TemporaryDirectory(prefix="spgram-verify-") as temporary:
        root = Path(temporary)
        message, proof, public_key = (root / name for name in ("manifest", "signature", "public-key.der"))
        message.write_bytes(payload)
        proof.write_bytes(signature)
        public_key.write_bytes(key)
        result = subprocess.run(
            [openssl, "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER", "-inkey",
             str(public_key), "-in", str(message), "-sigfile", str(proof)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8,
        )
    if result.returncode != 0:
        raise ValueError("Update manifest signature is invalid")
    return json.loads(payload)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def fetch(url, initial_host, limit, write, cancelled=lambda: False):
    opener = build_opener(NoRedirect)
    allowed = {initial_host}
    deadline = time.monotonic() + (30 if limit <= 2 * 1024 * 1024 else 300)
    for _ in range(4):
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc not in allowed or parsed.fragment:
            raise ValueError("Untrusted release address")
        try:
            request = Request(url, headers={"User-Agent": "SPgram-updater",
                                           "Accept": "application/vnd.github+json"
                                           if initial_host == "api.github.com" else "*/*"})
            response = opener.open(request, timeout=8)
        except HTTPError as error:
            with error:
                if error.code not in {301, 302, 303, 307, 308} or initial_host != "github.com":
                    raise
                url = error.headers["Location"]
                allowed = CDN
                continue
        with response:
            if response.status != 200 or int(response.headers.get("Content-Length", "0")) > limit:
                raise ValueError("Unexpected release response")
            size = 0
            while True:
                if cancelled():
                    raise ValueError("Download cancelled")
                if time.monotonic() > deadline:
                    raise ValueError("Release request timed out")
                chunk = response.read1(65536)
                if not chunk:
                    return size
                size += len(chunk)
                if size > limit:
                    raise ValueError("Release response exceeds its size limit")
                write(chunk, size)
    raise ValueError("Too many release redirects")


class Releases:
    def __init__(self, store, installed, rollback=False):
        self.store = store
        self.rollback = rollback
        self.key = store.port / UPDATE_KEY
        self.signed = self.key.exists() or self.key.is_symlink()
        if self.signed and not store.update_authentication_available():
            raise ValueError("Signed updates are unavailable on this installation")
        repository_path = store.port / UPDATE_REPOSITORY
        if repository_path.is_symlink():
            raise ValueError("Invalid release repository")
        repository = (read_bytes(repository_path, 256).decode("ascii").strip()
                      if repository_path.is_file() else DEFAULT_REPOSITORY)
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_-][A-Za-z0-9_.-]*", repository):
            raise ValueError("Invalid release repository")
        if platform.machine() != TARGET["arch"]:
            raise ValueError("Unsupported update target")
        self.repository = repository
        self.installed = installed
        self.directory = store.port / "conf" / "update-download"
        self.directory.mkdir(exist_ok=True)
        if self.directory.is_symlink() or not self.directory.is_dir():
            raise ValueError("Invalid update download directory")
        if rollback:
            self.directory = self.directory / "rollback"
            self.directory.mkdir(exist_ok=True)
            if self.directory.is_symlink() or not self.directory.is_dir():
                raise ValueError("Invalid rollback download directory")
        self.options = self.directory / "options.json"
        self.manifest = self.directory / "manifest.json"
        self.signature = self.directory / SIGNATURE_NAME
        self.github_asset = self.directory / "github-asset.json"
        self.archive = self.directory / "verified.zip"
        self.cancel = self.directory / "cancel"
        self.progress = self.directory / "progress"

    def address(self, label, name):
        return self.tag_address("v" + label, name)

    def tag_address(self, tag, name):
        return f"https://github.com/{self.repository}/releases/download/{tag}/{name}"

    def metadata(self, endpoint):
        data = bytearray()
        fetch(f"https://api.github.com/repos/{self.repository}/releases{endpoint}",
              "api.github.com", 2 * 1024 * 1024, lambda chunk, _: data.extend(chunk))
        return json.loads(data)

    def accepts(self, label):
        target, installed = version(label), version(self.installed)
        return target < installed if self.rollback else target > installed

    def check(self):
        try:
            release = self.metadata("/latest")
        except HTTPError as error:
            if error.code != 404:
                raise
            return {"available": False, "no_release": True}
        return self.prepare(release)

    def list_rollback(self):
        found = {}
        for page in range(1, 6):
            releases = self.metadata(f"?per_page=30&page={page}")
            if not isinstance(releases, list):
                raise ValueError("Invalid GitHub release list")
            for release in releases:
                if release["draft"] is not False or release["prerelease"] is not False:
                    continue
                tag = release["tag_name"]
                if not isinstance(tag, str) or not RELEASE_TAG.fullmatch(tag):
                    continue
                assets = release["assets"]
                names = {asset["name"] for asset in assets}
                if self.signed:
                    label = tag[1:]
                    required = {"release-manifest.json", SIGNATURE_NAME, f"SPgram-Update-v{label}.zip"}
                    if not tag.startswith("v") or not required <= names:
                        continue
                else:
                    matches = [asset for asset in assets if INSTALLER.fullmatch(asset["name"])]
                    if len(matches) != 1:
                        continue
                    name = matches[0]["name"]
                    if not matches[0].get("digest") and name + ".sha256" not in names:
                        continue
                    label = INSTALLER.fullmatch(name)[1]
                if VERSION.fullmatch(label) and self.accepts(label):
                    found.setdefault(label, tag)
            if len(found) >= 3 or len(releases) < 30:
                break
        choices = dict(sorted(found.items(), key=lambda item: version(item[0]), reverse=True)[:3])
        self.options.write_text(json.dumps(choices), encoding="ascii")
        return {"versions": list(choices)}

    def download_rollback(self, label):
        tag = read_json(self.options).get(label)
        if not self.accepts(label) or not isinstance(tag, str) or not RELEASE_TAG.fullmatch(tag):
            raise ValueError("Version is outside the available rollback choices")
        release = self.metadata("/tags/" + tag)
        if release["tag_name"] != tag:
            raise ValueError("Rollback release tag changed")
        status = self.prepare(release)
        if status.get("latest") != label or not status.get("available"):
            raise ValueError("Selected rollback release changed")
        return self.download()

    def prepare(self, release):
        if release["draft"] is not False or release["prerelease"] is not False:
            raise ValueError("Unexpected release")
        if not self.signed:
            return self.check_installer(release)
        tag = release["tag_name"]
        if not tag.startswith("v") or not VERSION.fullmatch(tag[1:]):
            return {"available": False, "no_release": True}
        label = tag[1:]
        assets = release["assets"]

        def find_asset(name):
            matches = [asset for asset in assets if asset["name"] == name]
            if len(matches) != 1 or matches[0]["browser_download_url"] != self.address(label, name):
                raise ValueError("Expected release asset missing")
            return matches[0]

        if not self.accepts(label):
            return {"latest": label, "available": False, "installed_ahead": version(label) < version(self.installed)}
        if not any(asset["name"] in {"release-manifest.json", SIGNATURE_NAME} for asset in assets):
            find_asset(f"SPgram-PortMaster-v{label}.zip")
            return {"latest": label, "available": False, "signed_required": True}
        find_asset("release-manifest.json")
        find_asset(SIGNATURE_NAME)
        payload = bytearray()
        fetch(self.address(label, "release-manifest.json"), "github.com", MANIFEST_LIMIT,
              lambda data, _: payload.extend(data))
        signature = bytearray()
        fetch(self.address(label, SIGNATURE_NAME), "github.com", 64, lambda data, _: signature.extend(data))
        manifest = verify_manifest(self.key, payload, signature)
        name, declared = self.validate(manifest)
        actual = find_asset(declared["name"])
        if name != label or actual["size"] != declared["size"]:
            raise ValueError("Release and manifest disagree")
        self.archive.unlink(missing_ok=True)
        self.manifest.write_bytes(payload)
        self.signature.write_bytes(signature)
        notes = release.get("body") or ""
        return {"latest": label, "available": True,
                "notes": notes[:350] if isinstance(notes, str) else ""}

    def check_installer(self, release):
        tag = release["tag_name"]
        if not isinstance(tag, str) or not RELEASE_TAG.fullmatch(tag):
            raise ValueError("Invalid release tag")
        assets = release["assets"]
        matches = [item for item in assets if INSTALLER.fullmatch(item["name"])]
        if not matches:
            return {"available": False, "no_release": True}
        if len(matches) != 1:
            raise ValueError("Ambiguous PortMaster installer")
        chosen = matches[0]
        name = chosen["name"]
        label = INSTALLER.fullmatch(name)[1]
        latest, installed = version(label), version(self.installed)
        if not self.accepts(label):
            return {"latest": label, "available": False, "installed_ahead": latest < installed}

        url = self.tag_address(tag, name)
        if chosen["browser_download_url"] != url or chosen["state"] != "uploaded":
            raise ValueError("Untrusted installer address")
        digest = chosen.get("digest")
        if digest is not None and not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
            raise ValueError("Invalid GitHub asset digest")
        checksum_name = name + ".sha256"
        checksums = [item for item in assets if item["name"] == checksum_name]
        if checksums:
            checksum_url = self.tag_address(tag, checksum_name)
            if (len(checksums) != 1 or checksums[0]["browser_download_url"] != checksum_url
                    or checksums[0]["state"] != "uploaded"):
                raise ValueError("Untrusted installer checksum address")
            raw = bytearray()
            fetch(checksum_url, "github.com", 1024, lambda data, _: raw.extend(data))
            checksum = re.fullmatch(rb"([a-fA-F0-9]{64}) [ *]" + re.escape(name.encode("ascii")) + rb"\r?\n?", raw)
            if not checksum or (digest and checksum[1].decode("ascii").lower() != digest[7:]):
                raise ValueError("Installer checksums disagree or are invalid")
            digest = "sha256:" + checksum[1].decode("ascii").lower()
        if not digest:
            raise ValueError("No SHA-256 for this installer")
        asset = {"version": label, "tag": tag, "name": name, "url": url, "size": chosen["size"], "sha256": digest[7:]}
        self.validate_github_asset(asset)
        self.archive.unlink(missing_ok=True)
        self.github_asset.write_text(json.dumps(asset), encoding="ascii")
        notes = release.get("body")
        return {"latest": label, "available": True, "notes": notes[:350] if isinstance(notes, str) else ""}

    def validate_github_asset(self, asset):
        label, tag, name = asset["version"], asset["tag"], asset["name"]
        if (not self.accepts(label) or not RELEASE_TAG.fullmatch(tag)
                or name != f"SPgram-PortMaster-v{label}.zip" or asset["url"] != self.tag_address(tag, name)
                or type(asset["size"]) is not int or not 0 < asset["size"] <= LIMIT
                or not re.fullmatch(r"[a-f0-9]{64}", asset["sha256"])):
            raise ValueError("Invalid GitHub installer metadata")
        return asset

    def validate(self, manifest):
        label, item = manifest_asset(manifest)
        if (manifest["repository"].lower() != self.repository.lower()
                or item["url"] != self.address(label, item["name"])
                or not self.accepts(label)):
            raise ValueError("Update is outside the selected release")
        return label, item

    def load_verified_manifest(self):
        manifest = verify_manifest(self.key, read_bytes(self.manifest, MANIFEST_LIMIT), read_bytes(self.signature, 64))
        self.validate(manifest)
        return manifest

    def verified_asset(self):
        if self.signed:
            label, item = manifest_asset(self.load_verified_manifest())
            return label, item, ""
        item = self.validate_github_asset(read_json(self.github_asset))
        return item["version"], item, APP_PREFIX

    def install_verified(self):
        label, item, prefix = self.verified_asset()
        self.store.install_asset(self.archive, label, item, prefix, rollback=self.rollback)
        try:
            self.archive.unlink(missing_ok=True)
        except OSError:
            pass

    def download(self):
        label, item, prefix = self.verified_asset()
        if shutil.disk_usage(self.directory).free < item["size"] + EXPANDED_LIMIT:
            raise ValueError("Insufficient free space for update")
        part = self.directory / "download.part"
        self.archive.unlink(missing_ok=True)
        digest = hashlib.sha256()
        last_percent = -1
        try:
            with part.open("wb") as output:
                def receive(data, count):
                    nonlocal last_percent
                    output.write(data)
                    digest.update(data)
                    percent = int(100 * count / item["size"])
                    if last_percent != percent:
                        self.progress.write_text(str(percent), encoding="ascii")
                        last_percent = percent
                count = fetch(item["url"], "github.com", item["size"], receive, self.cancel.exists)
                output.flush()
                os.fsync(output.fileno())
            if count != item["size"] or digest.hexdigest() != item["sha256"]:
                raise ValueError("Update download failed verification")
            with ZipFile(part) as package:
                self.store.package_entries(package, label, prefix)
            if self.cancel.exists():
                raise ValueError("Download cancelled")
            os.replace(part, self.archive)
            sync_dir(self.directory)
            return {"verified": True}
        finally:
            part.unlink(missing_ok=True)


class Store:
    def __init__(self, port):
        self.port = port.resolve(strict=True)
        self.base = self.port / "gamedata"
        self.slots = self.port / ".update-slots-v3"
        self.slots.mkdir(exist_ok=True)
        if self.slots.is_symlink() or self.base.is_symlink() or not self.base.is_dir():
            raise ValueError("Unsupported application directory")
        sync_dir(self.port)
        self.state = self.slots / "selection.json"
        self.health = self.slots / "startup-ok"

    def update_authentication_available(self):
        path = self.port / UPDATE_KEY
        if not path.is_file() or path.is_symlink() or shutil.which("openssl") is None:
            return False
        try:
            read_update_key(path)
        except (OSError, ValueError):
            return False
        return True

    @contextmanager
    def lock(self):
        with (self.slots / "lock").open("a+b") as handle:
            if os.name == "posix":
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            else:
                import msvcrt
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            self.lock_fd = handle.fileno()
            try:
                yield
            finally:
                self.lock_fd = None

    def path(self, slot):
        if slot == "base":
            return self.base
        version(slot)
        path = self.slots / ("v" + slot)
        if path.is_symlink() or not path.is_dir():
            raise ValueError("Selected application slot is missing")
        return path

    def installed(self, slot):
        path = self.path(slot)
        with (path / "VERSION").open(encoding="ascii") as handle:
            label = handle.read(80).strip()
        version(label)
        if slot != "base" and label != slot:
            raise ValueError("Application slot version mismatch")
        return label

    def read(self):
        if not self.state.exists():
            return {"active": "base", "previous": None, "trial": False, "started": False}
        with self.state.open(encoding="utf-8") as handle:
            selection = json.loads(handle.read(4096))
        self.path(selection["active"])
        if selection["previous"] is not None:
            self.path(selection["previous"])
        return selection

    def save(self, selection):
        draft = self.slots / "selection.tmp"
        with draft.open("w", encoding="utf-8") as handle:
            json.dump(selection, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(draft, self.state)
        sync_dir(self.slots)

    def install(self, archive, manifest):
        label, asset = manifest_asset(manifest)
        self.install_asset(archive, label, asset, "")

    def install_asset(self, archive, label, asset, prefix, rollback=False):
        current = self.read()
        if current["trial"]:
            raise ValueError("Resolve the pending startup trial first")
        active = version(self.installed(current["active"]))
        base = self.installed("base")
        if rollback and version(label) >= active:
            raise ValueError("Rollback must be older than the installed version")
        if not rollback and (version(label) <= active or
                             (base != current.get("base_version") and version(label) <= version(base))):
            raise ValueError("Update must be newer than the installed version")
        slot = self.slots / ("v" + label)
        existing = slot.exists()
        if slot.is_symlink() or (existing and not slot.is_dir()):
            raise ValueError("Invalid update slot")
        with archive.open("rb") as handle:
            if os.fstat(handle.fileno()).st_size != asset["size"]:
                raise ValueError("Update size mismatch")
            digest = hashlib.sha256()
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
            if digest.hexdigest() != asset["sha256"]:
                raise ValueError("Update checksum mismatch")
            if existing:
                with (slot / ".verified").open(encoding="ascii") as receipt:
                    if receipt.read(65) != asset["sha256"]:
                        raise ValueError("Version already staged with different bytes")
            else:
                handle.seek(0)
                with ZipFile(handle) as package:
                    stage = self.extract(package, label, asset["sha256"], prefix)
        if not existing:
            os.rename(stage, slot)
            sync_dir(self.slots)
        self.save({"active": label, "previous": current["active"], "trial": True, "started": False,
                   "base_version": base})

    def package_entries(self, package, label, prefix):
        entries = package.infolist()
        if len(entries) > 500:
            raise ValueError("Too many archive entries")
        total = 0
        names = set()
        payload = {}
        for entry in entries:
            if prefix and (not entry.filename.startswith(prefix) or entry.is_dir()):
                continue
            name = entry.orig_filename[len(prefix):]
            mode = stat.S_IFMT(entry.external_attr >> 16)
            if (entry.orig_filename != entry.filename or not allowed_path(name) or name.lower() in names
                    or entry.is_dir() or mode not in {0, stat.S_IFREG}
                    or entry.compress_type not in {ZIP_DEFLATED, ZIP_STORED}
                    or entry.flag_bits & 1 or entry.file_size > LIMIT):
                raise ValueError("Unsafe archive entry")
            names.add(name.lower())
            payload[name] = entry
            total += entry.file_size
        if not REQUIRED <= payload.keys() or total > EXPANDED_LIMIT:
            raise ValueError("Incomplete or oversized application")
        if (payload["VERSION"].file_size > 80
                or package.read(payload["VERSION"]).decode("ascii").strip() != label):
            raise ValueError("Archive version mismatch")
        if prefix:
            preview = payload.get("SIGN_IN_PREVIEW")
            if not preview or preview.file_size > 8 or package.read(preview).strip() != b"0":
                raise ValueError("Expected a full PortMaster release")
        with package.open(payload["lib/libtdjson.so"]) as handle:
            elf = handle.read(20)
        if elf[:6] != b"\x7fELF\x02\x01" or elf[18:20] != b"\xb7\x00":
            raise ValueError("Invalid TDLib architecture")
        return payload, total

    def extract(self, package, label, digest, prefix):
        payload, total = self.package_entries(package, label, prefix)
        if shutil.disk_usage(self.slots).free < total + 8 * 1024 * 1024:
            raise ValueError("Insufficient free space")
        stage = Path(mkdtemp(prefix=".stage-", dir=self.slots))
        try:
            for name, entry in payload.items():
                output = stage / name
                output.parent.mkdir(parents=True, exist_ok=True)
                with package.open(entry) as source, output.open("xb") as destination:
                    shutil.copyfileobj(source, destination, 1024 * 1024)
                    destination.flush()
                    os.fsync(destination.fileno())
            with (stage / ".verified").open("x", encoding="ascii") as receipt:
                receipt.write(digest)
                receipt.flush()
                os.fsync(receipt.fileno())
            for directory, _, _ in os.walk(stage, topdown=False):
                sync_dir(Path(directory))
            return stage
        except BaseException:
            shutil.rmtree(stage)
            raise

    def rollback(self, selection):
        if selection["previous"] is None:
            raise ValueError("No previous version available")
        self.save({"active": selection["previous"], "previous": selection["active"],
                   "trial": False, "started": False, "base_version": selection.get("base_version")})

    def run(self, command):
        restarted = False
        update_result = None
        while True:
            result, selected = self.launch(command, update_result)
            update_result = None
            if restarted and self.read()["active"] != selected:
                restarted = False
                update_result = "rolled-back"
                continue
            if result in {INSTALL_EXIT, GITHUB_ROLLBACK_EXIT}:
                try:
                    Releases(self, self.installed(selected), rollback=result == GITHUB_ROLLBACK_EXIT).install_verified()
                except (OSError, ValueError, KeyError, TypeError, RuntimeError, BadZipFile):
                    update_result = "install-failed"
                else:
                    restarted = True
                continue
            if result == ROLLBACK_EXIT:
                self.rollback(self.read())
                return 0
            return result

    def launch(self, command, update_result):
        selection = self.read()
        if selection["trial"] and selection["started"]:
            self.finish_trial(selection)
            selection = self.read()
        selected = selection["active"]
        base = self.installed("base")
        if (selected != "base" and base != selection.get("base_version")
                and version(base) >= version(self.installed(selected))):
            selected = "base"
            selection = {"active": "base", "previous": None, "trial": False, "started": False}
            self.save(selection)
        environment = os.environ.copy()
        environment.pop("TELEGRAM_SP_STARTUP_OK", None)
        environment["TELEGRAM_SP_UPDATE_PORT"] = str(self.port)
        environment["TELEGRAM_SP_UPDATE_PYTHON"] = sys.executable
        environment["TELEGRAM_SP_CAN_ROLLBACK"] = "1" if selection["previous"] else "0"
        if update_result:
            environment["TELEGRAM_SP_UPDATE_RESULT"] = update_result
        else:
            environment.pop("TELEGRAM_SP_UPDATE_RESULT", None)
        trial = selected != "base" and selection["trial"]
        if trial:
            self.health.unlink(missing_ok=True)
            selection["started"] = True
            self.save(selection)
            environment["TELEGRAM_SP_STARTUP_OK"] = str(self.health)
        lock_fd = getattr(self, "lock_fd", None)
        inherited = {"pass_fds": (lock_fd,)} if os.name == "posix" and lock_fd is not None else {}
        result = subprocess.run([*command, str(self.path(selected))], env=environment, **inherited,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
        if trial:
            self.finish_trial(selection)
        return result, selected

    def finish_trial(self, selection):
        if self.health.is_file():
            selection.update(trial=False, started=False)
            self.save(selection)
        else:
            self.save({"active": selection["previous"], "previous": None,
                       "trial": False, "started": False, "base_version": selection.get("base_version")})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, type=Path)
    commands = parser.add_subparsers(dest="operation", required=True)
    install = commands.add_parser("install")
    install.add_argument("archive", type=Path)
    install.add_argument("manifest", type=Path)
    install.add_argument("signature", type=Path)
    commands.add_parser("rollback")
    for name in ("check", "download", "rollback-list", "rollback-download"):
        operation = commands.add_parser(name)
        operation.add_argument("installed")
        if name == "rollback-download":
            operation.add_argument("version")
    run = commands.add_parser("run")
    run.add_argument("launch", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        store = Store(args.port)
        if args.operation in {"check", "download", "rollback-list", "rollback-download"}:
            version(args.installed)
            releases = Releases(store, args.installed, rollback=args.operation.startswith("rollback-"))
            if args.operation == "rollback-download":
                result = releases.download_rollback(args.version)
            else:
                handler = {"check": releases.check, "download": releases.download,
                           "rollback-list": releases.list_rollback}[args.operation]
                result = handler()
            print(json.dumps(result))
            return 0
        with store.lock():
            if args.operation == "install":
                manifest = verify_manifest(store.port / UPDATE_KEY, read_bytes(args.manifest, MANIFEST_LIMIT),
                                           read_bytes(args.signature, 64))
                store.install(args.archive, manifest)
            elif args.operation == "rollback":
                store.rollback(store.read())
            else:
                command = args.launch[1:] if args.launch[:1] == ["--"] else args.launch
                if not command:
                    raise ValueError("Missing application command")
                return store.run(command)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, BadZipFile, AttributeError, subprocess.TimeoutExpired):
        print("SPgram update operation failed. Check the archive, installation and free space.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
