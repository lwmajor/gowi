#!/bin/bash
# Run the test suite with code coverage and print a per-file breakdown
# filtered to Sources/Gowi (excludes generated/vendor code and test files).
#
# Usage:
#   ./scripts/coverage.sh              # build + test + report
#   ./scripts/coverage.sh --report-only # skip rebuild, just re-print last report

set -euo pipefail

BUNDLE=/tmp/gowi-coverage.xcresult
TMPJSON=$(mktemp)
trap "rm -f $TMPJSON" EXIT

if [[ "${1:-}" != "--report-only" ]]; then
    rm -rf "$BUNDLE"
    echo "==> Building and running tests with coverage..."
    xcodebuild \
        -scheme gowi \
        -destination 'platform=macOS' \
        -enableCodeCoverage YES \
        -resultBundlePath "$BUNDLE" \
        test 2>&1 \
        | grep -E '(error:|Test Suite \.All tests|BUILD SUCCEEDED|BUILD FAILED)' \
        | tail -4
    echo ""
fi

xcrun xccov view --report --json "$BUNDLE" > "$TMPJSON" 2>/dev/null

echo "==> Coverage report (Sources/Gowi):"
python3 - "$TMPJSON" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as fh:
    report = json.load(fh)

# Use a dict keyed by name so duplicate entries (app target + test recompile) collapse.
seen = {}
for target in report.get("targets", []):
    for f in target.get("files", []):
        path = f.get("path", "")
        if "Sources/Gowi" not in path:
            continue
        name       = path.split("Sources/Gowi/")[-1]
        cov        = f.get("lineCoverage", 0.0)
        covered    = f.get("coveredLines", 0)
        executable = f.get("executableLines", 0)
        # Keep the entry with more executable lines (app target is more complete).
        if name not in seen or executable > seen[name][3]:
            seen[name] = (name, cov, covered, executable)

files = sorted(seen.values(), key=lambda x: x[0])

if not files:
    print("No coverage data for Sources/Gowi — did the build succeed?")
    sys.exit(1)

col            = max(len(f[0]) for f in files) + 2
total_covered  = sum(f[2] for f in files)
total_exec     = sum(f[3] for f in files)

print(f"{'File':<{col}} {'Cov':>5}  Lines")
print("-" * (col + 22))
for name, cov, covered, executable in files:
    bar  = "█" * int(cov * 20)
    bar += "░" * (20 - len(bar))
    pct  = f"{cov*100:.0f}%"
    print(f"{name:<{col}} {pct:>5}  {bar}  {covered}/{executable}")

overall = total_covered / total_exec if total_exec else 0
print()
print(f"Overall: {overall*100:.1f}%  ({total_covered}/{total_exec} executable lines)")
PYEOF
