"""Prepare local configuration and package the Windows personal client."""

import argparse
import base64
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / ".personal-remote.json"
OUTPUT = ROOT / "dist" / "personal-remote"
BUILD_ARGS = ["--portable", "--flutter", "--skip-portable-pack", "--hwcodec", "--vram"]
VERSION = "0.1.2"
PROFILE_NAME = "PersonalRemote.server.json"
TEMPLATE_DIR = OUTPUT / "template"
TEMPLATE_NAME = "PersonalRemote-template.exe"
RUNNER_NAME = "PersonalRemote.exe"


def validate_profile(data):
    if not isinstance(data, dict):
        raise ValueError("Server configuration must be a JSON object.")
    server = data.get("id_server")
    relay = data.get("relay_server", "")
    key = data.get("server_key")
    if not isinstance(server, str) or not server or re.search(r"[\s/\\]", server):
        raise ValueError("Supply the ID server as a hostname or IP, with an optional port.")
    if not isinstance(relay, str) or re.search(r"[\s/\\]", relay):
        raise ValueError("Supply a relay address or leave the relay blank for automatic selection.")
    if not isinstance(key, str) or len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("Supply the 32-byte server public key from id_ed25519.pub.")
    return server, relay, key


def import_profile(source):
    with source.open("rb") as stream:
        options = tomllib.load(stream).get("options", {})
    profile = {
        "id_server": options.get("custom-rendezvous-server", ""),
        "relay_server": "",
        "server_key": options.get("key", ""),
    }
    validate_profile(profile)
    if PROFILE.is_file():
        existing = json.loads(PROFILE.read_text(encoding="utf-8"))
        if existing != profile:
            raise ValueError(f"{PROFILE.name} already contains a different configuration.")
        print(f"{PROFILE.name} already matches the selected server.")
        return
    with PROFILE.open("x", encoding="utf-8") as stream:
        json.dump(profile, stream, indent=2)
        stream.write("\n")
    print(f"Saved {PROFILE.name}. Relay selection is automatic.")


def install_bridge(artifact):
    paths = (
        "src/bridge_generated.rs",
        "src/bridge_generated.io.rs",
        "flutter/lib/generated_bridge.dart",
        "flutter/lib/generated_bridge.freezed.dart",
    )
    with zipfile.ZipFile(artifact) as bridge:
        files = {path: bridge.read(path) for path in paths}
    for path, content in files.items():
        (ROOT / path).write_bytes(content)


def source_commit():
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()


def make_template(helper):
    """Build a launcher template without user-specific server settings."""

    release = ROOT / "flutter" / "build" / "windows" / "x64" / "runner" / "Release"
    packer = ROOT / "libs" / "portable"
    revision = source_commit()
    TEMPLATE_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="payload-", dir=OUTPUT) as temp:
        payload = Path(temp) / "runner"
        shutil.copytree(release, payload, ignore=shutil.ignore_patterns(PROFILE_NAME))
        executable = payload / RUNNER_NAME
        (payload / "rustdesk.exe").rename(executable)
        shutil.copy2(ROOT / "LICENCE", payload / "LICENCE.txt")
        (payload / "PersonalRemote-source.txt").write_text(
            f"https://github.com/hyx505/rustdesk/tree/{revision}\n", encoding="ascii"
        )
        if helper is not None:
            shutil.copy2(helper, payload / "WindowInjection.dll")
        subprocess.run(
            [sys.executable, "generate.py", "-f", str(payload), "-e", str(executable),
             "-l", "6", "--exclude-exe"],
            cwd=packer,
            check=True,
        )
        shutil.copy2(executable, TEMPLATE_DIR / RUNNER_NAME)
    shutil.copy2(ROOT / "target" / "release" / "rustdesk-portable-packer.exe",
                 TEMPLATE_DIR / TEMPLATE_NAME)
    (TEMPLATE_DIR / "source-commit.txt").write_text(revision + "\n", encoding="ascii")


def attach_package(template, blob):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    begin = kernel.BeginUpdateResourceW
    begin.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    begin.restype = wintypes.HANDLE
    update = kernel.UpdateResourceW
    update.argtypes = [
        wintypes.HANDLE, ctypes.c_void_p, wintypes.LPCWSTR, wintypes.WORD,
        ctypes.c_void_p, wintypes.DWORD,
    ]
    update.restype = wintypes.BOOL
    end = kernel.EndUpdateResourceW
    end.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    end.restype = wintypes.BOOL
    # RT_RCDATA type and RDPKG name are the existing upstream packer format.
    handle = begin(str(template), False)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    buffer = ctypes.create_string_buffer(blob)
    if not update(handle, 10, "RDPKG", 0, buffer, len(blob)):
        error = ctypes.get_last_error()
        end(handle, True)
        raise ctypes.WinError(error)
    if not end(handle, False):
        raise ctypes.WinError(ctypes.get_last_error())


def package(artifact=None):
    with PROFILE.open(encoding="utf-8") as stream:
        server, relay, key = validate_profile(json.load(stream))
    if sys.platform != "win32":
        raise ValueError("The install package requires a Windows build host.")
    names = ("source-commit.txt", TEMPLATE_NAME, RUNNER_NAME)
    if artifact is not None:
        with zipfile.ZipFile(artifact) as archive:
            files = {name: archive.read(name) for name in names}
    else:
        files = {name: (TEMPLATE_DIR / name).read_bytes() for name in names}
    if files["source-commit.txt"].decode("ascii").strip() != source_commit():
        raise ValueError("Download the Windows template for the currently checked-out commit.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    package = OUTPUT / f"PersonalRemote-{VERSION}-windows-x64.exe"
    with tempfile.TemporaryDirectory(prefix="package-", dir=OUTPUT) as temp:
        temp = Path(temp)
        payload = temp / "profile"
        payload.mkdir()
        executable = payload / RUNNER_NAME
        executable.write_bytes(files[RUNNER_NAME])
        (payload / PROFILE_NAME).write_text(
            json.dumps({"id_server": server, "relay_server": relay, "server_key": key}),
            encoding="utf-8",
        )
        package_blob = temp / "package.bin"
        subprocess.run(
            [sys.executable, "generate.py", "-f", str(payload), "-e", str(executable),
             "-l", "6", "--package", str(package_blob)],
            cwd=ROOT / "libs" / "portable",
            check=True,
        )
        staged = temp / package.name
        staged.write_bytes(files[TEMPLATE_NAME])
        attach_package(staged, package_blob.read_bytes())
        staged.replace(package)
    with package.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    package.with_suffix(".exe.sha256").write_text(f"{digest}  {package.name}\n", encoding="ascii")
    print(package)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    config = commands.add_parser("import-config")
    config.add_argument("source", type=Path, nargs="?", default=Path(
        os.environ.get("APPDATA", ".")) / "RustDesk" / "config" / "RustDesk2.toml")
    bridge = commands.add_parser("import-bridge")
    bridge.add_argument("artifact", type=Path)
    template = commands.add_parser("make-template")
    template.add_argument("--privacy-helper", type=Path)
    pack = commands.add_parser("package")
    pack.add_argument("artifact", type=Path, nargs="?")
    commands.add_parser("build")
    args = parser.parse_args()
    try:
        if args.command == "import-config":
            import_profile(args.source)
        elif args.command == "import-bridge":
            install_bridge(args.artifact)
        elif args.command == "make-template":
            make_template(args.privacy_helper)
        elif args.command == "package":
            package(args.artifact)
        else:
            with PROFILE.open(encoding="utf-8") as stream:
                validate_profile(json.load(stream))
            if not (ROOT / "src/bridge_generated.rs").is_file():
                raise ValueError("Import bridge-artifact before running the local build.")
            subprocess.run([sys.executable, "build.py", *BUILD_ARGS], cwd=ROOT, check=True)
            make_template(None)
            package()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
