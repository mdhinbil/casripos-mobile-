# -*- coding: utf-8 -*-
"""Give the generated Android project a release signing config.

android/ is not in the repo - CI runs `flutter create` on every build, so there
is no Gradle file to edit by hand. What `flutter create` writes signs the
release build with the DEBUG key, and an APK signed with the debug key is one
Play refuses and one that cannot be installed over a build signed properly.

This adds a signingConfig that reads android/key.properties, which CI writes
from the GitHub secrets and never commits.

    python3 tool/wire_release_signing.py            # from flutter_app/
    python3 tool/wire_release_signing.py <path>     # for a test copy
"""

import io
import os
import sys

# Imports go at the very top. The `val` declarations CANNOT: Gradle's Kotlin
# DSL requires the plugins {} block to be the first statement in the script, so
# anything declared before it fails the build with "The plugins {} block must
# not be used here."
IMPORTS = """import java.util.Properties
import java.io.FileInputStream

"""

VALS = """// Written by CI from the GitHub secrets - never committed. If it is missing
// (a local build, say) the config below is left empty and Gradle falls back to
// the debug key, which is what a developer wants and what CI must never ship.
val keyProps = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.exists()) { keyProps.load(FileInputStream(keyFile)) }

android {"""

SIGNING = """    signingConfigs {
        create("release") {
            if (keyFile.exists()) {
                keyAlias = keyProps["keyAlias"] as String
                keyPassword = keyProps["keyPassword"] as String
                storeFile = file(keyProps["storeFile"] as String)
                storePassword = keyProps["storePassword"] as String
            }
        }
    }

    buildTypes {"""


def main(path):
    if not os.path.exists(path):
        sys.exit("%s is not there - has `flutter create` run?" % path)

    s = io.open(path, encoding="utf-8").read()

    if "signingConfigs" in s and "getByName(\"release\")" in s:
        print("already wired")
        return

    if "buildTypes {" not in s:
        sys.exit("no buildTypes block - flutter create has changed shape, and "
                 "this script has to change with it rather than sign nothing")

    marker = chr(10) + "android {"
    if marker not in s:
        sys.exit("no android {} block - nothing to attach signing to")

    s = IMPORTS + s
    s = s.replace(marker, chr(10) + VALS, 1)
    s = s.replace("    buildTypes {", SIGNING, 1)

    swapped = s.replace('signingConfig = signingConfigs.getByName("debug")',
                        'signingConfig = signingConfigs.getByName("release")', 1)
    if swapped == s:
        sys.exit("the release buildType does not name the debug signingConfig, "
                 "so nothing was switched over - refusing to pretend it worked")
    s = swapped

    io.open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("release signing wired into", path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "android/app/build.gradle.kts")
