#!/usr/bin/env bash
# Fork builds must ship no Sparkle appcast.
#
# The fork shares upstream's bundle ID *and* upstream's Sparkle public key, so a non-empty feed
# would let an upstream release validate, auto-install over a fork install, and silently remove
# the fork-only features. package_app.sh carries a comment saying not to restore these values
# when syncing upstream; this is what makes the comment enforceable.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE_SCRIPT="$ROOT/Scripts/package_app.sh"

python3 - "$PACKAGE_SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text()
failures = []

# Every assignment, on every code path (release, debug, adhoc), must disable updates. Checking
# assignments rather than one rendered plist means a newly added branch cannot slip through.
feed_assignments = re.findall(r'^\s*FEED_URL=(.*)$', script, re.MULTILINE)
if not feed_assignments:
    failures.append("no FEED_URL assignment found -- did package_app.sh rename it?")
for value in feed_assignments:
    if value.strip() not in ('""', "''"):
        failures.append(f"FEED_URL must be empty in fork builds, found: FEED_URL={value.strip()}")

checks_assignments = re.findall(r'^\s*AUTO_CHECKS=(.*)$', script, re.MULTILINE)
if not checks_assignments:
    failures.append("no AUTO_CHECKS assignment found -- did package_app.sh rename it?")
for value in checks_assignments:
    if value.strip() != "false":
        failures.append(f"AUTO_CHECKS must be false in fork builds, found: AUTO_CHECKS={value.strip()}")

# The values above only matter while the plist keys are still driven by them. An upstream sync
# that hardcodes a feed straight into the heredoc would otherwise pass the checks above.
if "<key>SUFeedURL</key><string>${FEED_URL}</string>" not in script:
    failures.append("SUFeedURL is no longer driven by ${FEED_URL} in the Info.plist heredoc")
if "<key>SUEnableAutomaticChecks</key><${AUTO_CHECKS}/>" not in script:
    failures.append("SUEnableAutomaticChecks is no longer driven by ${AUTO_CHECKS}")

if failures:
    print("Sparkle feed must stay disabled in fork builds:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)

print(
    f"Sparkle feed disabled: {len(feed_assignments)} FEED_URL and "
    f"{len(checks_assignments)} AUTO_CHECKS assignments, all safe.")
PY

echo "Package Sparkle feed tests passed."
