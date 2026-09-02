[app]

# ─────────────────────────────────────────────────────────────────────────
#  Casri POS — offline WebView shell.
#  The web app (index.html / app.js / styles.css / icon.svg / manifest.json)
#  lives in this same folder and is BUNDLED into the APK, then loaded from
#  file:// at runtime. No server, works with zero internet.
# ─────────────────────────────────────────────────────────────────────────

title           = Casri POS
package.name    = casripos
package.domain  = com.casri

source.dir      = .
# Package the web app alongside the Python shell. html/js/css/svg/json are the
# bundled offline content; png/jpg cover the launcher icon + presplash.
source.include_exts = py,png,jpg,kv,atlas,html,js,css,svg,json
# Keep build/output + the sibling Isguul-style zips out of the packaged app.
source.exclude_dirs = bin,.buildozer,.git,__pycache__
source.exclude_patterns = */*.zip,*.md

version         = 1.0.0
# Android decides whether an APK is an UPDATE by versionCode, not by this
# string. It sat at the default for every build, so each new APK looked like
# the version already installed and the phone quietly kept the old one — new
# fixes appeared to do nothing. CI overwrites this with the run number.
android.numeric_version = 1

requirements = python3,kivy==2.3.0,android

# Pin python-for-android to the known-good release. WITHOUT this, p4a uses its
# latest master, which fails to compile Kivy 2.3.0 against NDK 25b
# ("too few arguments to function call" in kivy/graphics/*.c). This is the exact
# pin the working Isguul APK uses.
p4a.fork = kivy
p4a.branch = v2024.01.21

orientation     = landscape
# Immersive fullscreen — hides the system/taskbar so the till is edge-to-edge
# like Vektori (Vektori runs fullscreen; that's why it has no taskbar).
fullscreen      = 1
# Follow the device. Locked to landscape, a phone could only ever show the
# till sideways - where the sign-in card (490px) does not fit in the ~360px of
# height a landscape phone has, and the Checkout button sat below the bottom of
# the cart sheet. A tablet on a counter still gets landscape; it is simply held
# that way.
#
# p4a's own `orientation` above only accepts portrait/landscape, so `sensor`
# has to be set here: the webview manifest writes android:screenOrientation
# from this key, last, and it wins.
android.manifest.orientation = sensor

# ── App icon & presplash (flat navy → suppresses Kivy "Loading..." splash) ──
icon.filename           = %(source.dir)s/assets/icon.png
presplash.filename      = %(source.dir)s/assets/presplash.png
android.presplash_color = #0a1628

# INTERNET is kept only so external hand-offs (wa.me receipts, tel:) work; the
# app itself needs no network. ACCESS_NETWORK_STATE lets the WebView behave.
#
# CAMERA is deliberately NOT declared yet. Google Play treats a declared CAMERA
# permission as implying <uses-feature android:hardware.camera required="true">
# unless the manifest says otherwise — and this buildozer.spec has no way to add
# a uses-feature entry. Declaring it now would hide the app from camera-less
# devices (some counter tablets) for a feature that isn't built yet. It gets
# added in the same release as the scanner, together with a required="false"
# uses-feature. main.py already has the runtime request wired and dormant.
android.permissions = INTERNET, ACCESS_NETWORK_STATE

android.api        = 35
android.minapi     = 21
android.ndk        = 25b
android.sdk        = 35
android.build_tools_version = 35.0.0

android.release_artifact = aab

android.archs = arm64-v8a, armeabi-v7a

android.accept_sdk_license = True
android.gradle_dependencies = androidx.webkit:webkit:1.12.1

# Everything loads over file:// — no cleartext http needed.
android.manifest.activity_attributes = android:hardwareAccelerated="true"
android.manifest.application_attributes = android:usesCleartextTraffic="false"

android.entrypoint = org.kivy.android.PythonActivity
android.add_src = src


[buildozer]

log_level = 2
warn_on_root = 1
