# Casri POS

Point-of-sale web app **and** its offline Android APK, in one folder.

- **Web app** — `index.html`, `app.js`, `styles.css`, `icon.svg`, `manifest.json`, `sw.js`.
  A self-contained SPA (no CDN, no server). Open `index.html` in a browser, or
  serve the folder with `python -m http.server 8000`.
- **Android app** — a thin Kivy/WebView shell (`main.py`) that **bundles the web
  files inside the APK** and loads them from `file://`, so the till runs with
  **zero internet**. Updating the app means rebuilding + reinstalling the APK.

## Build the APK

Pushing to GitHub `main` runs `.github/workflows/build-apk.yml`, which produces:

- **`CasriPOS-debug.apk`** — install on a phone to test before publishing.
- **`*.aab`** — the Android App Bundle you upload to the **Google Play Console**.

Both are attached to a GitHub Release. You can also trigger the build manually
from the Actions tab (workflow_dispatch).

### Signing (Play Store upload key)

The build signs with a **Play upload key** kept ONLY in GitHub secrets — never in
the repo. Set the four secrets once (values are printed by the key-generation
step; the `.b64` file holds the keystore):

```
gh secret set KEYSTORE_BASE64   --repo <owner>/casripos-mobile < casri-upload.keystore.b64
gh secret set KEYSTORE_PASSWORD --repo <owner>/casripos-mobile --body '<password>'
gh secret set KEY_ALIAS         --repo <owner>/casripos-mobile --body 'casri'
gh secret set KEY_PASSWORD      --repo <owner>/casripos-mobile --body '<password>'
```

**Back up `casri-upload.keystore` and its password somewhere safe.** With Play
App Signing a lost upload key can be reset via Google support, but keeping it is
far easier. `package.name` (`com.casri.casripos`) is permanent once published.

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
