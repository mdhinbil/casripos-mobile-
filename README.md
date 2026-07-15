# Casri POS

Point-of-sale web app **and** its offline Android APK, in one folder.

- **Web app** — `index.html`, `app.js`, `styles.css`, `icon.svg`, `manifest.json`, `sw.js`.
  A self-contained SPA (no CDN, no server). Open `index.html` in a browser, or
  serve the folder with `python -m http.server 8000`.
- **Android app** — a thin Kivy/WebView shell (`main.py`) that **bundles the web
  files inside the APK** and loads them from `file://`, so the till runs with
  **zero internet**. Updating the app means rebuilding + reinstalling the APK.

## Build the APK

Pushing to GitHub `main` runs `.github/workflows/build-apk.yml`, which builds a
signed, installable debug APK and attaches **`CasriPOS-debug.apk`** to a GitHub
Release. Download it on the phone and install (enable "Install unknown apps"
for your browser/file manager first).

You can also trigger it manually from the Actions tab (workflow_dispatch).

### Signing

With no secrets set, CI generates a throwaway keystore so the build works out of
the box. For stable reinstalls/updates (and eventual Play Store upload), add repo
secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS` and CI will use them.

## Local build (optional)

```
pip install buildozer cython pillow
python generate_assets.py      # regenerate assets/icon.png + presplash.png
buildozer android debug        # requires Linux/WSL + Android SDK/NDK
```

## Layout

```
CasriPOS/
├─ index.html app.js styles.css icon.svg manifest.json sw.js   # web app (bundled)
├─ main.py                     # Kivy WebView shell → loads bundled index.html
├─ buildozer.spec              # APK build config
├─ generate_assets.py          # rasterises icon.svg → assets/*.png
├─ assets/icon.png presplash.png
├─ src/org/casri/pos/CasriWebViewClient.java   # routes tel:/wa.me/maps to phone apps
└─ .github/workflows/build-apk.yml             # CI → signed APK on GitHub Releases
```
