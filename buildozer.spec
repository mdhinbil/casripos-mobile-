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

requirements = python3,kivy==2.3.0,android

# Pin python-for-android to the known-good release. WITHOUT this, p4a uses its
# latest master, which fails to compile Kivy 2.3.0 against NDK 25b
# ("too few arguments to function call" in kivy/graphics/*.c). This is the exact
# pin the working Isguul APK uses.
p4a.fork = kivy
p4a.branch = v2024.01.21

orientation     = portrait
fullscreen      = 0

# ── App icon & presplash (flat navy → suppresses Kivy "Loading..." splash) ──
icon.filename           = %(source.dir)s/assets/icon.png
presplash.filename      = %(source.dir)s/assets/presplash.png
android.presplash_color = #0a1628

# INTERNET is kept only so external hand-offs (wa.me receipts, tel:) work; the
# app itself needs no network. ACCESS_NETWORK_STATE lets the WebView behave.
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
