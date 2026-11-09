#!/bin/bash
# Prints the next release's version and build number:  <version> <build>
#
# The version follows MARKETING_VERSION in the Xcode project. Its major.minor picks the series, such as 1.0, and each
# release in that series takes the next patch number after the highest one already tagged on GitHub: 1.0.0, then
# 1.0.1, 1.0.2. Setting MARKETING_VERSION to 1.1.0 starts the next series at 1.1.0.
#
# The build number is the commit count. It only ever grows, and it's what installed copies compare to decide whether
# a release is newer.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_VERSION="$(grep -m1 'MARKETING_VERSION = ' Sesame.xcodeproj/project.pbxproj | sed -E 's/.*= ([0-9.]+);/\1/')"
[[ "$PROJECT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "MARKETING_VERSION must look like 1.0.0, not $PROJECT_VERSION" >&2; exit 1; }
SERIES="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
FIRST_PATCH="${BASH_REMATCH[3]}"

LAST_PATCH="$(git ls-remote --tags --refs origin "v$SERIES.*" | sed -nE "s#.*refs/tags/v${SERIES//./\\.}\.([0-9]+)\$#\1#p" | sort -n | tail -1)"
if [ -n "$LAST_PATCH" ] && [ "$LAST_PATCH" -ge "$FIRST_PATCH" ]; then
    PATCH=$((LAST_PATCH + 1))
else
    PATCH="$FIRST_PATCH"
fi

echo "$SERIES.$PATCH $(git rev-list --count HEAD)"
