"""Adds what Letea needs to the Android files that `flutter create` generates.

Safe to run more than once. Usage: python3 tool/ci_patch_android.py [MAPS_API_KEY]
"""
import pathlib
import re
import sys

# Without any key entry Google Maps crashes the app, so always add one.
maps_key = (sys.argv[1] if len(sys.argv) > 1 else "") or "NO_MAPS_KEY_SET"

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
m = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
]
missing = [p for p in perms if p not in m]
if missing:
    block = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in missing)
    m = m.replace("<application", block + "    <application", 1)
if maps_key and "com.google.android.geo.API_KEY" not in m:
    m = re.sub(
        r"(<application[^>]*>)",
        r'\1\n        <meta-data android:name="com.google.android.geo.API_KEY" android:value="' + maps_key + '"/>',
        m,
        count=1,
    )
manifest.write_text(m)

for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = pathlib.Path(name)
    if not g.exists():
        continue
    s = g.read_text()
    s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", s)
    s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", s)
    g.write_text(s)

print("Android files patched.")
