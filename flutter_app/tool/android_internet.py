"""Give the release APK permission to reach the cloud.

`flutter create` puts INTERNET only in the debug and profile manifests, so an
app that syncs works perfectly on a development phone and then cannot reach
anything at all once it is a release build. The failure looks like a broken
server, not a missing line, which is why this is a build step rather than
something to remember.

The Kivy WebView build has always asked for this through buildozer.spec.
The native build never did, so the workspace sign-in - and with it the MPQ
plan and its caps - could not reach Firebase at all.

Nothing else here needs the network: no location, no contacts. One
permission, and a shop can see why it was asked for.
"""

import io
import os
import sys

MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")
LINE = '    <uses-permission android:name="android.permission.INTERNET"/>\n'


def main():
    if not os.path.exists(MANIFEST):
        sys.exit(f"{MANIFEST} is not there - run this after `flutter create`.")

    text = io.open(MANIFEST, encoding="utf-8").read()
    if "android.permission.INTERNET" in text:
        print("INTERNET already asked for")
        return

    mark = "<manifest"
    end = text.index(">", text.index(mark)) + 1
    text = text[:end] + "\n" + LINE + text[end:]
    io.open(MANIFEST, "w", encoding="utf-8", newline="\n").write(text)
    print("INTERNET added to the release manifest")


if __name__ == "__main__":
    main()
