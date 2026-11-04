#!/bin/bash
# Exit 0 if the changed files, read from stdin, can affect an image.
# Docs and repository settings do not, so CI can skip the build for them.
set -uo pipefail
while IFS= read -r file; do
  case "$file" in
    ''|*.md|LICENSE|.github/ISSUE_TEMPLATE/*|.github/rulesets/*|.github/CODEOWNERS|.github/dependabot.yml) ;;
    *) exit 0 ;;
  esac
done
exit 1
