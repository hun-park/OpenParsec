"""Check the custom package before handing it to Sideloadly; does not test its UI."""
import hashlib
import plistlib
import sys
import zipfile
from pathlib import Path


def verify(path):
    with zipfile.ZipFile(path) as archive:
        bad_member = archive.testzip()
        if bad_member:
            raise ValueError(f"Corrupt ZIP member: {bad_member}")
        manifests = [name for name in archive.namelist()
                     if name.startswith("Payload/") and name.count("/") == 2
                     and name.endswith(".app/Info.plist")]
        if len(manifests) != 1:
            raise ValueError("Expected exactly one Payload/*.app/Info.plist")
        manifest = manifests[0]
        info = plistlib.loads(archive.read(manifest))
        expected = ["UIInterfaceOrientationLandscapeRight", "UIInterfaceOrientationLandscapeLeft"]
        if info.get("UISupportedInterfaceOrientations") != expected:
            raise ValueError("iPhone launch orientations differ from the custom profile")
        if "UIInterfaceOrientationPortrait" not in info.get("UISupportedInterfaceOrientations~ipad", []):
            raise ValueError("iPad portrait support is missing")
        executable = manifest.removesuffix("Info.plist") + info["CFBundleExecutable"]
        if not archive.read(executable):
            raise ValueError("The application executable is empty")
        frameworks = [name for name in archive.namelist() if "/Frameworks/ParsecSDK.framework/" in name]
        if not frameworks:
            raise ValueError("ParsecSDK framework is missing")
        print(f"Bundle: {info['CFBundleIdentifier']}")
        print(f"Version: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
        print("IPA structure, ZIP integrity and launch settings verified.")
    print(f"SHA256: {hashlib.sha256(path.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
