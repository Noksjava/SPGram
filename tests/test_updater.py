import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from zipfile import ZipFile, ZipInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "portmaster"))
import updater


class UpdateTest(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        base = self.root / "gamedata"
        base.mkdir()
        (base / "VERSION").write_text("0.1.0", encoding="ascii")
        self.session = self.root / "conf" / "session"
        self.session.parent.mkdir()
        self.session.write_bytes(b"synthetic state")
        self.store = updater.Store(self.root)

    def package(self, label="0.2.0", extra=None):
        archive = self.root / f"SPgram-Update-v{label}.zip"
        with ZipFile(archive, "w") as package:
            for name in updater.REQUIRED:
                content = b"fixture"
                if name == "VERSION":
                    content = label.encode()
                elif name == "lib/libtdjson.so":
                    content = b"\x7fELF\x02\x01" + bytes(12) + b"\xb7\x00"
                package.writestr(name, content)
            if extra is not None:
                info = extra if isinstance(extra, ZipInfo) else ZipInfo(extra)
                info.filename = info.orig_filename
                package.writestr(info, b"fixture")
        data = archive.read_bytes()
        return archive, {
            "schema": 1, "channel": "stable", "version": label, "target": updater.TARGET,
            "minimum_updater": 3, "update_asset": {
                "name": archive.name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            },
        }

    def test_install_acknowledge_and_rollback(self):
        self.store.install(*self.package(extra="SIGN_IN_PREVIEW"))
        self.assertTrue(self.store.read()["trial"])
        script = ("import os,sys; from pathlib import Path; "
                  "assert Path(sys.argv[1], 'VERSION').read_text() == '0.2.0'; "
                  "Path(os.environ['TELEGRAM_SP_STARTUP_OK']).touch()")
        self.assertEqual(self.store.run([sys.executable, "-c", script]), 0)
        state = self.store.read()
        self.assertFalse(state["trial"])
        self.store.rollback(state)
        self.assertEqual(self.store.read()["active"], "base")
        self.assertEqual(self.session.read_bytes(), b"synthetic state")

    def test_startup_intro_asset(self):
        archive, manifest = self.package(extra="intro/spgram-intro.ogv")
        self.store.install(archive, manifest)
        self.assertEqual((self.store.path("0.2.0") / "intro/spgram-intro.ogv").read_bytes(), b"fixture")

    def test_failure_and_interrupted_trial(self):
        args = self.package()
        self.store.install(*args)
        self.assertEqual(self.store.run([sys.executable, "-c", "raise SystemExit(9)"]), 9)
        self.assertEqual(self.store.read()["active"], "base")
        self.store.install(*args)
        interrupted = self.store.read()
        interrupted["started"] = True
        self.store.save(interrupted)
        self.assertEqual(self.store.run([sys.executable, "-c", "pass"]), 0)
        self.assertEqual(self.store.read()["active"], "base")

    def test_interrupted_selection_write_can_retry(self):
        args = self.package()
        with patch.object(self.store, "save", side_effect=OSError("fixture")):
            with self.assertRaises(OSError):
                self.store.install(*args)
        self.assertEqual(self.store.read()["active"], "base")
        self.store.install(*args)
        self.assertEqual(self.store.read()["active"], "0.2.0")

    def test_rejects_bad_metadata_and_bytes(self):
        archive, manifest = self.package()
        for field, value in (("channel", "beta"), ("target", {}), ("minimum_updater", 9)):
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.store.install(archive, dict(manifest, **{field: value}))
        with archive.open("ab") as file:
            file.write(b"x")
        with self.assertRaisesRegex(ValueError, "size"):
            self.store.install(archive, manifest)
        manifest["update_asset"]["size"] += 1
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.store.install(archive, manifest)
        self.assertEqual(self.store.read()["active"], "base")

    def test_archive_policy(self):
        link = ZipInfo("src/link.lua")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        for entry in ("../outside.lua", "/tmp/outside.lua", "src\\escape.lua",
                      "src/private/session.lua", "conf/session", "MAIN.lua", link):
            with self.subTest(entry=entry), self.assertRaisesRegex(ValueError, "Unsafe archive"):
                self.store.install(*self.package(extra=entry))
        self.assertEqual(self.session.read_bytes(), b"synthetic state")

    def test_space_and_version(self):
        archive, manifest = self.package()
        with patch.object(updater.shutil, "disk_usage") as space:
            space.return_value.free = 0
            with self.assertRaisesRegex(ValueError, "space"):
                self.store.install(archive, manifest)
        with self.assertRaisesRegex(ValueError, "newer"):
            self.store.install(*self.package("0.1.0"))
        self.assertGreater(updater.version("0.10.0"), updater.version("0.9.9"))

    def releases(self):
        self.openssl = shutil.which("openssl")
        if not self.openssl:
            self.skipTest("OpenSSL is required for signed update fixtures")
        self.private_key = self.root / "fixture-private.pem"
        self.openssl_run("genpkey", "-algorithm", "ED25519", "-out", self.private_key)
        self.openssl_run("pkey", "-in", self.private_key, "-pubout", "-outform", "DER",
                         "-out", self.root / updater.UPDATE_KEY)
        with patch.object(updater.platform, "machine", return_value="aarch64"):
            return updater.Releases(self.store, "0.1.0")

    def openssl_run(self, *args):
        subprocess.run([self.openssl, *map(str, args)], check=True, capture_output=True, timeout=8)

    def sign(self, payload):
        message = self.root / "fixture-manifest.json"
        proof = self.root / "fixture-signature"
        message.write_bytes(payload)
        self.openssl_run("pkeyutl", "-sign", "-rawin", "-inkey", self.private_key, "-in", message, "-out", proof)
        return proof.read_bytes()

    def test_release_validation_and_cancel_retry(self):
        releases = self.releases()
        archive, manifest = self.package()
        name = manifest["update_asset"]["name"]
        asset_url = releases.address("0.2.0", name)
        manifest.update(repository=releases.repository)
        manifest["update_asset"]["url"] = asset_url
        manifest_url = releases.address("0.2.0", "release-manifest.json")
        sig_url = releases.address("0.2.0", updater.SIGNATURE_NAME)
        api_url = "https://api.github.com/repos/Noksjava/SPGram/releases/latest"
        payload = json.dumps(manifest).encode()
        proof = self.sign(payload)
        release = {"tag_name": "v0.2.0", "draft": False, "prerelease": False,
                   "assets": [
                       {"name": "release-manifest.json", "browser_download_url": manifest_url},
                       {"name": updater.SIGNATURE_NAME, "browser_download_url": sig_url},
                       {"name": name, "browser_download_url": asset_url,
                        "size": manifest["update_asset"]["size"]},
                   ]}
        def mock_fetch(url, host, limit, write, cancelled=lambda: False):
            if url == api_url:
                data = json.dumps(release).encode()
            elif url == manifest_url:
                data = payload
            elif url == sig_url:
                data = proof
            else:
                self.assertEqual(url, asset_url)
                data = archive.read_bytes()
            if cancelled():
                raise ValueError("cancelled")
            write(data, len(data))
            return len(data)

        with patch.object(updater, "fetch", side_effect=mock_fetch):
            release["tag_name"] = "2.57-I"
            self.assertEqual(releases.check(), {"available": False, "no_release": True})
            release["tag_name"] = "v0.2.0"
            signed_assets = release["assets"]
            full_name = "SPgram-PortMaster-v0.2.0.zip"
            release["assets"] = [{"name": full_name, "browser_download_url": releases.address("0.2.0", full_name)}]
            self.assertEqual(releases.check(), {"latest": "0.2.0", "manual_update": True})
            release["assets"] = signed_assets
            good_proof = proof
            proof = bytes([proof[0] ^ 1]) + proof[1:]
            with self.assertRaisesRegex(ValueError, "signature"):
                releases.check()
            self.assertFalse(releases.manifest.exists())
            proof = good_proof
            self.assertTrue(releases.check()["available"])
            releases.cancel.touch()
            with self.assertRaisesRegex(ValueError, "cancelled"):
                releases.download()
            self.assertFalse(releases.archive.exists())
            releases.cancel.unlink()
            self.assertTrue(releases.download()["verified"])
            with patch.object(updater.platform, "machine", return_value="aarch64"):
                self.assertEqual(self.store.run([sys.executable, "-c", "raise SystemExit(41)"]), 0)
            self.assertEqual(self.store.read()["active"], "0.2.0")
            release["prerelease"] = True
            with self.assertRaisesRegex(ValueError, "Unexpected release"):
                releases.check()
            release["prerelease"] = False
            release["assets"][2]["browser_download_url"] = "https://example.org/other.zip"
            with self.assertRaisesRegex(ValueError, "missing"):
                releases.check()

    def test_fixed_repository_and_empty_release(self):
        current = self.releases()
        (self.session.parent / "updates.json").write_text(
            '{"repository":"other/project","firmware":"Gladiator II"}', encoding="ascii",
        )
        with patch.object(updater.platform, "machine", return_value="aarch64"):
            self.assertEqual(updater.Releases(self.store, "0.1.0").repository, current.repository)
            (self.root / updater.UPDATE_REPOSITORY).write_text("maintainer/fork\n", encoding="ascii")
            self.assertEqual(updater.Releases(self.store, "0.1.0").repository, "maintainer/fork")
        with patch.object(updater, "fetch", side_effect=HTTPError("", 404, "", None, None)):
            self.assertEqual(current.check(), {"available": False, "no_release": True})

    def test_network_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "Untrusted"):
            updater.fetch("http://github.com/file", "github.com", 64, lambda *_: None)
        releases = self.releases()
        with patch.object(updater, "fetch", side_effect=OSError("offline fixture")):
            with self.assertRaises(OSError):
                releases.check()
        self.assertFalse(releases.archive.exists())

    def test_manifest_authentication_has_no_unsigned_fallback(self):
        self.assertFalse(self.store.update_authentication_available())
        with self.assertRaisesRegex(ValueError, "unavailable"):
            updater.Releases(self.store, "0.1.0")
        releases = self.releases()
        _, manifest = self.package()
        manifest["repository"] = releases.repository
        manifest["update_asset"]["url"] = releases.address("0.2.0", manifest["update_asset"]["name"])
        payload = json.dumps(manifest).encode()
        proof = self.sign(payload)
        releases.manifest.write_bytes(payload)
        with self.assertRaises(FileNotFoundError):
            releases.download()
        releases.signature.write_bytes(proof[:-1])
        with self.assertRaisesRegex(ValueError, "length"):
            releases.load_verified_manifest()
        releases.signature.write_bytes(proof)
        self.assertEqual(releases.load_verified_manifest(), manifest)
        releases.manifest.write_bytes(payload + b"\n")
        with self.assertRaisesRegex(ValueError, "signature"):
            releases.download()
        releases.manifest.write_bytes(payload)
        self.openssl_run("genpkey", "-algorithm", "ED25519", "-out", self.private_key)
        self.openssl_run("pkey", "-in", self.private_key, "-pubout", "-outform", "DER", "-out", releases.key)
        with self.assertRaisesRegex(ValueError, "signature"):
            releases.load_verified_manifest()

    def test_upgrade_starts_from_full_installer_instead_of_legacy_slots(self):
        legacy = self.root / ".update-slots"
        slot = legacy / "v9.0.0"
        slot.mkdir(parents=True)
        (slot / "VERSION").write_text("9.0.0", encoding="ascii")
        (legacy / "selection.json").write_text(
            json.dumps({"active": "9.0.0", "previous": "base", "trial": False, "started": False}),
            encoding="ascii",
        )
        probe = ("import sys; from pathlib import Path; "
                 "assert Path(sys.argv[1], 'VERSION').read_text() == '0.1.0'")
        self.assertEqual(self.store.run([sys.executable, "-c", probe]), 0)
        self.assertFalse(self.store.read()["previous"])


if __name__ == "__main__":
    unittest.main()
