#!/usr/bin/env bash
set -euo pipefail

# ─── Run tests with code coverage ───
echo "==> Running tests with code coverage…"
swift test --enable-code-coverage --quiet 2>&1

# ─── Locate build artifacts ───
BIN_PATH=$(swift build --show-bin-path)
PROFDATA="$BIN_PATH/codecov/default.profdata"
# The test binary name matches the test target name
TEST_BIN="$BIN_PATH/PRStatusWatcherPackageTests"

# On macOS, SPM test binaries may be inside an .xctest bundle
if [ -d "$TEST_BIN.xctest" ]; then
    TEST_BIN="$TEST_BIN.xctest/Contents/MacOS/PRStatusWatcherPackageTests"
fi

if [ ! -f "$PROFDATA" ]; then
    echo "Error: Coverage data not found at $PROFDATA"
    echo "Make sure 'swift test --enable-code-coverage' succeeded."
    exit 1
fi

# ─── Print per-file summary ───
echo ""
echo "==> Coverage Summary (Sources/ only)"
echo ""
xcrun llvm-cov report "$TEST_BIN" \
    --instr-profile="$PROFDATA" \
    --sources Sources/

# ─── Optional: HTML report ───
if [[ "${1:-}" == "--html" ]]; then
    OUTPUT_DIR=".build/coverage-html"
    echo ""
    echo "==> Generating HTML report at $OUTPUT_DIR"
    xcrun llvm-cov show "$TEST_BIN" \
        --instr-profile="$PROFDATA" \
        --sources Sources/ \
        --format=html \
        --output-dir="$OUTPUT_DIR"
    echo "    Open with: open $OUTPUT_DIR/index.html"
fi

# ─── Optional: Export lcov for CI ───
if [[ "${1:-}" == "--lcov" ]]; then
    LCOV_FILE=".build/coverage.lcov"
    echo ""
    echo "==> Exporting lcov to $LCOV_FILE"
    xcrun llvm-cov export "$TEST_BIN" \
        --instr-profile="$PROFDATA" \
        --sources Sources/ \
        --format=lcov > "$LCOV_FILE"
    echo "    File: $LCOV_FILE"
fi
