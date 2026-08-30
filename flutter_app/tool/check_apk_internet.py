# -*- coding: utf-8 -*-
"""Prove the FINISHED apk can reach the cloud.

Patching AndroidManifest.xml before the build is not proof that the permission
survived into the apk - a build step could drop it and nothing would say so
until a shop tried to sign in.

The permission name lives in the binary manifest's UTF-16 string pool, so it
can be read straight out of the packaged apk without any Android tooling.

    python3 tool/check_apk_internet.py out/CasriPOS-20.apk
"""

import sys
import zipfile

WANT = "android.permission.INTERNET"


def main(path):
    try:
        manifest = zipfile.ZipFile(path).read("AndroidManifest.xml")
    except Exception as e:
        sys.exit("::error::could not read %s: %s" % (path, e))

    if WANT.encode("utf-16-le") not in manifest:
        sys.exit("::error::%s has no INTERNET permission, so it cannot sign in "
                 "to a workspace or fetch its plan" % path)
    print("%s: INTERNET is in the shipped apk" % path)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: check_apk_internet.py <apk>")
    main(sys.argv[1])
