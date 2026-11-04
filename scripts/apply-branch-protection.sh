#!/bin/bash
# Protect main. GitHub allows this on public repos, or on private repos with GitHub Pro.
# Usage: scripts/apply-branch-protection.sh
set -euo pipefail
repo="${1:-n4berius/halogen-bootc}"
gh api -X PUT "repos/$repo/branches/main/protection" --input - <<'J'
{
  "required_status_checks": {"strict": true, "contexts": ["build (npu)", "build (no-npu)"]},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
J
echo "main now needs passing builds, and cannot be force-pushed or deleted."
echo "Pull requests are not required for admins, so you keep a way to fix a broken main."
