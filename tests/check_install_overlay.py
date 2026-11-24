"""Check that a candidate ZIP overlay replaces app files and preserves saves."""

import argparse
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile


def check_overlay(archive):
    fixtures = {
        "telegram.conf": b"synthetic configuration",
        "love/Telegram/private/production-account_1.key": bytes(range(32)),
        "love/Telegram/tdlib/db.sqlite": b"synthetic database",
        "love/Telegram/tdlib_files/photo": b"synthetic cached bytes",
        "love/Telegram/accounts.json": b"{}",
        "love/Telegram/private/production-account_1-reading.77.json": b'{"42":"5242880"}',
    }
    with ZipFile(archive) as package, TemporaryDirectory() as directory:

        prefix = "telegramsp/conf/"
        assert not any(name.startswith(prefix) for name in package.namelist())
        root = Path(directory)
        package.extractall(root)
        for name, contents in fixtures.items():
            path = root / prefix / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
        entrypoint = "telegramsp/gamedata/main.lua"
        (root / entrypoint).write_bytes(b"previous application revision")
        package.extractall(root)
        assert (root / entrypoint).read_bytes() == package.read(entrypoint)
        for name, contents in fixtures.items():
            assert (root / prefix / name).read_bytes() == contents, name
    print("Offline ZIP overlay replaced the app and preserved six synthetic persistent files")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    check_overlay(parser.parse_args().archive)
