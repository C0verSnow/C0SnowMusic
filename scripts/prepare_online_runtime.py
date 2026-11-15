"""Fetch pinned, precompiled iOS Python and pure Python wheels. Does not build."""

import hashlib
from pathlib import Path
import subprocess
import sys
import tarfile
from urllib.request import urlopen


def main():
    root = Path(__file__).resolve().parents[1]
    vendor = root / "Vendor"
    vendor.mkdir(exist_ok=True)
    archive = vendor / "Python-3.13-iOS-support.b18.tar.gz"
    expected = "d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d"
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        url = "https://github.com/beeware/Python-Apple-support/releases/download/3.13-b18/" + archive.name
        with urlopen(url, timeout=120) as source, archive.open("wb") as output:
            while chunk := source.read(1024 * 1024):
                output.write(chunk)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise SystemExit("Python runtime checksum mismatch")
    if not (vendor / "Python.xcframework/Info.plist").exists():
        with tarfile.open(archive) as source:
            # The release archive contains the official relative libpython symlinks.
            source.extractall(vendor, filter="data")
    subprocess.run([
        sys.executable, "-m", "pip", "install", "--disable-pip-version-check",
        "--require-hashes", "--only-binary=:all:", "--no-deps", "--no-compile",
        "--python-version", "3.13", "--upgrade", "--target", str(vendor / "python-packages"),
        "-r", str(root / "scripts/online-requirements.txt"),
    ], check=True)


if __name__ == "__main__":
    main()
