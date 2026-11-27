#!/bin/sh
# Xcode Cloud runs this after cloning. Cloud builds use a paid account, so the app is signed with the paid
# entitlements (push, Sign in with Apple, WeatherKit, Time Sensitive Notifications) instead of the free-account set.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"
sed -i '' 's#ENTITLEMENTS_FILE = Albatross/Albatross.entitlements;#ENTITLEMENTS_FILE = Config/Albatross.paid.entitlements;#' Albatross.xcodeproj/project.pbxproj
grep -c "Config/Albatross.paid.entitlements" Albatross.xcodeproj/project.pbxproj
