import argparse
import ctypes
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import sys
import tempfile


APP_NAME = "Codex Radar.app"
BUNDLE_ID = "local.codexradar.desktop"
EXTENSION = Path("Contents/PlugIns/CodexRadarWidget.appex")
RENAME_SWAP = 0x00000002
RENAME_EXCL = 0x00000004


def signing_identity(requested):
    output = subprocess.check_output(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"], text=True
    )
    identities = set(re.findall(
        r'^\s*\d+\)\s+([0-9A-F]{40})\s+"Apple Development:',
        output, re.MULTILINE | re.IGNORECASE,
    ))
    if requested:
        if requested.upper() not in identities:
            raise ValueError("--identity must match an Apple Development identity in your Keychain.")
        return requested.upper()
    if not identities:
        raise ValueError("Set up an Apple Development signing identity as described in the README.")
    if len(identities) != 1:
        raise ValueError("Multiple Apple Development identities found. Choose one with --identity.")
    return identities.pop()


def install_destination():
    shared = Path("/Applications") / APP_NAME
    personal = Path.home() / "Applications" / APP_NAME
    existing = [path for path in (shared, personal) if path.exists() or path.is_symlink()]
    if len(existing) > 1:
        raise ValueError("Codex Radar.app is present in both Applications folders. Keep one installation.")
    if not existing:
        return shared if os.access(shared.parent, os.W_OK) else personal

    app = existing[0]
    if app.is_symlink():
        raise ValueError(f"Choose a regular app bundle instead of the link at {app}.")
    try:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException):
        info = {}
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError(f"A different item already exists at {app}.")
    return app


def move_bundle(source, destination, replacing):
    # Swap on upgrade so the rollback copy stays on the same volume.
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    flag = RENAME_SWAP if replacing else RENAME_EXCL
    if rename(os.fsencode(source), os.fsencode(destination), flag) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


def install(app, identity):
    app.parent.mkdir(parents=True, exist_ok=True)
    replacing = app.exists()
    with tempfile.TemporaryDirectory(prefix=".codex-radar-", dir=app.parent) as stage:
        candidate = Path(stage) / APP_NAME
        build = Path(__file__).resolve().with_name("build.sh")
        subprocess.run(["/bin/bash", build, candidate, identity], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", candidate], check=True)
        move_bundle(candidate, app, replacing)
        try:
            subprocess.run(["/usr/bin/pluginkit", "-a", app / EXTENSION], check=True)
        except (OSError, subprocess.CalledProcessError):
            move_bundle(app, candidate, replacing)
            raise
    print(f"Installed {app}")
    subprocess.run(["/usr/bin/open", app], check=True)


def main():
    parser = argparse.ArgumentParser(description="Build and install the Codex Radar macOS widget.")
    parser.add_argument("--identity", metavar="SHA1", help="Select an Apple Development identity by fingerprint.")
    args = parser.parse_args()
    try:
        if sys.platform != "darwin" or int(platform.mac_ver()[0].split(".")[0]) < 14:
            raise ValueError("Codex Radar requires macOS 14 or later.")
        install(install_destination(), signing_identity(args.identity))
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    except subprocess.CalledProcessError as error:
        parser.exit(1, f"{Path(error.cmd[0]).name} failed with exit code {error.returncode}.\n")


if __name__ == "__main__":
    main()
