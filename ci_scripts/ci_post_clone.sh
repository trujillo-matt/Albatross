#!/bin/sh
# Xcode Cloud runs this after cloning. The project signs with the paid entitlements by default (push, Sign in with Apple,
# WeatherKit, Time Sensitive Notifications), which is what cloud builds need. Nothing to change; this only checks it.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"
grep -q "ENTITLEMENTS_FILE = Config/Albatross.paid.entitlements;" Albatross.xcodeproj/project.pbxproj || { echo "Albatross is not set to the paid entitlements"; exit 1; }
