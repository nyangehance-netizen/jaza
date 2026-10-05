"""Adds what Letea needs to the iOS files that `flutter create` generates.

Safe to run more than once. Usage: python3 tool/ci_patch_ios.py
"""
import pathlib
import plistlib
import re

MIN_IOS = "15.0"
BUNDLE_ID = "com.letea.letea"

# ---------------------------------------------------------------- Info.plist
info_path = pathlib.Path("ios/Runner/Info.plist")
info = plistlib.loads(info_path.read_bytes())

info["CFBundleDisplayName"] = "Letea"
# The messages iPhone shows when Letea asks for permission. Apple rejects apps
# whose messages don't say clearly why the access is needed.
info["NSLocationWhenInUseUsageDescription"] = (
    "Letea uses your location to pin your delivery address and, for riders, "
    "to show customers where their order is on the map."
)
info["NSCameraUsageDescription"] = (
    "Take photos of products and services you sell, or of your prescription."
)
info["NSPhotoLibraryUsageDescription"] = (
    "Choose photos of products and services you sell, or of your prescription."
)
# Letea only uses standard HTTPS, so App Store Connect can skip the export-compliance question.
info["ITSAppUsesNonExemptEncryption"] = False

google = pathlib.Path("ios/Runner/GoogleService-Info.plist")
connected = google.exists()
if connected:
    # Phone login needs the app's reversed client ID as a URL scheme.
    reversed_id = plistlib.loads(google.read_bytes()).get("REVERSED_CLIENT_ID")
    if reversed_id:
        types = info.setdefault("CFBundleURLTypes", [])
        if not any(reversed_id in t.get("CFBundleURLSchemes", []) for t in types):
            types.append({"CFBundleTypeRole": "Editor", "CFBundleURLSchemes": [reversed_id]})
    # Push notifications for new orders and jobs.
    modes = info.setdefault("UIBackgroundModes", [])
    if "remote-notification" not in modes:
        modes.append("remote-notification")

info_path.write_bytes(plistlib.dumps(info))

# ---------------------------------------------------------------- Podfile
podfile = pathlib.Path("ios/Podfile")
if podfile.exists():
    s = podfile.read_text()
    s = re.sub(r"^#?\s*platform :ios, '[\d.]+'", f"platform :ios, '{MIN_IOS}'", s, count=1, flags=re.M)
    if f"platform :ios, '{MIN_IOS}'" not in s:
        s = f"platform :ios, '{MIN_IOS}'\n" + s
    # Make every library build for the same minimum iOS version (avoids warnings and old-SDK errors).
    if "IPHONEOS_DEPLOYMENT_TARGET'] = " not in s:
        s = s.replace(
            "flutter_additional_ios_build_settings(target)",
            "flutter_additional_ios_build_settings(target)\n"
            "    target.build_configurations.each do |config|\n"
            f"      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '{MIN_IOS}'\n"
            "    end",
            1,
        )
    podfile.write_text(s)

# ---------------------------------------------------------------- Xcode project
proj = pathlib.Path("ios/Runner.xcodeproj/project.pbxproj")
p = proj.read_text()
p = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {MIN_IOS};", p)
if connected:
    ent = pathlib.Path("ios/Runner/Runner.entitlements")
    ent.write_bytes(plistlib.dumps({"aps-environment": "production"}))
    if "CODE_SIGN_ENTITLEMENTS" not in p:
        p = p.replace(
            f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};",
            f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;",
        )
proj.write_text(p)

print(f"iOS files patched (minimum iOS {MIN_IOS}, Firebase {'connected' if connected else 'not connected: preview mode'}).")
