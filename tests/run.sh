#!/bin/bash
# Checks that need no GPU, registry or network.
set -euo pipefail
cd "$(dirname "$0")/.."
tests/static.sh
tests/config.sh
tests/release-info.sh
tests/needs-build.sh
tests/first-boot.sh
tests/preflight.sh
tests/halogen-update.sh
echo "all checks passed"
