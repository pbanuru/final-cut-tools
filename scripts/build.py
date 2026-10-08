#!/usr/bin/env python3
"""Build a local Final Cut Pro workflow extension without project-generator dependencies."""
import argparse
import os
import pathlib
import plistlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(value))


def find_framework(explicit=None):
    candidates = [pathlib.Path(explicit)] if explicit else []
    candidates += [pathlib.Path("/Library/Frameworks/ProExtension.framework")]
    # Local development fallback: use the runtime already shipped with an installed Final Cut Pro.
    # Nothing from Apple's binaries is committed or downloaded by this script.
    candidates += [path for path in pathlib.Path("/Applications").glob("Final Cut*.app/Contents/PlugIns/*.appex/Contents/Frameworks/ProExtension.framework")
                   if path.parts[2] != "Final Cut Recorder.app"]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise SystemExit("Install Apple's Workflow Extension SDK, or pass --framework /path/to/ProExtension.framework")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--framework", help="Path to the official ProExtension.framework")
    parser.add_argument("--install", action="store_true", help="Install the built app into /Applications")
    args = parser.parse_args()
    framework = find_framework(args.framework or os.environ.get("PRO_EXTENSION_FRAMEWORK"))
    build = ROOT / "build"
    app = build / "Final Cut Recorder.app"
    if app.exists():
        shutil.rmtree(app)
    contents = app / "Contents"
    extension = contents / "PlugIns/Recorder.appex/Contents"
    for folder in [contents / "MacOS", extension / "MacOS", extension / "Frameworks"]:
        folder.mkdir(parents=True, exist_ok=True)
    common = {
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "3",
        "LSMinimumSystemVersion": "15.6",
        "NSCameraUsageDescription": "Preview and record your selected camera inside Final Cut Pro.",
        "NSMicrophoneUsageDescription": "Record your selected microphone with your camera.",
        "NSPrincipalClass": "NSApplication",
    }
    write_plist(contents / "Info.plist", {
        **common, "CFBundleIdentifier": "tools.finalcut.recorder",
        "CFBundleName": "Final Cut Recorder", "CFBundleDisplayName": "Final Cut Recorder",
        "CFBundleExecutable": "FinalCutRecorder", "CFBundlePackageType": "APPL",
    })
    write_plist(extension / "Info.plist", {
        **common, "CFBundleIdentifier": "tools.finalcut.recorder.extension",
        "CFBundleName": "Final Cut Recorder", "CFBundleDisplayName": "Final Cut Recorder",
        "CFBundleExecutable": "Recorder", "CFBundlePackageType": "XPC!",
        "NSExtension": {
            "NSExtensionPointIdentifier": "com.apple.FinalCut.WorkflowExtension",
            "ProExtensionPrincipalViewControllerClass": "RecorderViewController",
            "ProExtensionAttributes": {"ContentViewMinimumWidth": 600, "ContentViewMinimumHeight": 640},
        },
    })
    entitlements = build / "recorder.entitlements"
    write_plist(entitlements, {
        "com.apple.security.app-sandbox": True,
        "com.apple.security.device.camera": True,
        "com.apple.security.device.audio-input": True,
        "com.apple.security.files.user-selected.read-write": True,
        "com.apple.security.files.bookmarks.app-scope": True,
    })
    copied_framework = extension / "Frameworks/ProExtension.framework"
    shutil.copytree(framework, copied_framework, symlinks=True)
    source = ROOT / "tools/recorder"
    run("xcrun", "swiftc", "-swift-version", "5", "-O", "-module-name", "FinalCutRecorder",
        "-target", "arm64-apple-macosx15.6", source / "Container.swift", "-o", contents / "MacOS/FinalCutRecorder")
    run("xcrun", "swiftc", "-swift-version", "5", "-O", "-parse-as-library", "-module-name", "RecorderExtension",
        "-target", "arm64-apple-macosx15.6", source / "Recorder.swift",
        "-F", framework.parent, "-framework", "ProExtension",
        "-Xlinker", "-e", "-Xlinker", "_ProExtensionMain",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        "-o", extension / "MacOS/Recorder")
    run("codesign", "--force", "--sign", "-", copied_framework)
    run("codesign", "--force", "--sign", "-", "--entitlements", entitlements, extension.parent)
    run("codesign", "--force", "--sign", "-", "--entitlements", entitlements, app)
    run("codesign", "--verify", "--deep", "--strict", app)
    if args.install:
        destination = pathlib.Path("/Applications/Final Cut Recorder.app")
        if destination.exists():
            installed = plistlib.loads((destination / "Contents/Info.plist").read_bytes())
            if installed.get("CFBundleIdentifier") != "tools.finalcut.recorder":
                raise SystemExit("An unrelated app already uses this name; refusing to replace it.")
            shutil.rmtree(destination)
        shutil.copytree(app, destination, symlinks=True)
        print(f"Installed: {destination}")
    print(f"Built: {app}")


if __name__ == "__main__":
    main()
