#!/bin/bash
# Checks that need no GPU, registry or network.
set -euo pipefail
cd "$(dirname "$0")/.."
tests/static.sh
tests/first-boot.sh
tests/preflight.sh
echo "all checks passed"
