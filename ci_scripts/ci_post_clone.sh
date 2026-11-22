#!/bin/sh
set -eu

# Core tests are a separate Swift package, not part of the Xcode scheme.
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"
echo "Running MarginCore tests before the Xcode Cloud action."
xcrun swift test
