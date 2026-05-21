#!/usr/bin/env bash
# run_experiments.sh - compiles the two simulation files and runs all variants.
# Per-variant logs are written to logs/.
# CSV output lands in the project root as two unified files:
# - results_CrowdSensing.csv
# - results_DCNS.csv
set -uo pipefail

# Directory structure
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/out/production/iFogSim_7"
JARS_DIR="$PROJECT_DIR/jars"
SRC_DIR="$PROJECT_DIR/src"
LOGS_DIR="$PROJECT_DIR/logs"
RESULTS_DIR="$PROJECT_DIR/results"
mkdir -p "$LOGS_DIR" "$RESULTS_DIR"

# Build the Java Classpath: compiled output & every jar under jars/
CP="$OUT_DIR"
while IFS= read -r jar; do
    CP="$CP:$jar"
done < <(find "$JARS_DIR" -name "*.jar")

# Compilation step
echo "[build] Compiling simulation files..."
javac -cp "$CP" -d "$OUT_DIR" \
    "$SRC_DIR/org/fog/placement/ModulePlacementEdgewards.java" \
    "$SRC_DIR/org/fog/placement/MicroservicesMobilityClusteringController.java" \
    "$SRC_DIR/org/fog/placement/ClusteredMicroservicePlacementLogic.java" \
    "$SRC_DIR/org/fog/test/perfeval/DCNSFog.java" \
    "$SRC_DIR/org/fog/test/perfeval/CrowdSensing_Microservices_RandomMobility_Clustering.java"
echo "[build] Done."
echo ""

# Tracking variables
FAILURES=0
VARIANT=0
TOTAL=140

# run LABEL CLASS [ARGS...]
# Captures all JVM output to logs/variant_NNN_LABEL.log and tracks failures.
run() {
    local label=$1; shift
    local class=$1; shift
    VARIANT=$((VARIANT + 1))
    local num; printf -v num "%03d" "$VARIANT"
    local logfile="$LOGS_DIR/variant_${num}_${label}.log"

    echo "--- [$num/$TOTAL] $label  ($(date '+%H:%M:%S')) ---"
    # Some of the simulations may take longer to complete but no more than 10 minutes.
    # Timeout to kill the process if it exceeds this limit.
    (cd "$PROJECT_DIR" && timeout 600 java -cp "$CP" "$class" "$@") > "$logfile" 2>&1
    local exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        echo "[PASS] $label"
    elif [ "$exit_code" -eq 124 ]; then
        echo "[TIMEOUT] $label — exceeded 10 min, killed  (log: $logfile)"
        FAILURES=$((FAILURES + 1))
    else
        echo "[FAIL] $label (exit $exit_code) — full log: $logfile"
        FAILURES=$((FAILURES + 1))
    fi
    echo ""
}

# Class names for the two simulations
CS=org.fog.test.perfeval.CrowdSensing_Microservices_RandomMobility_Clustering
DC=org.fog.test.perfeval.DCNSFog

# ===========================================================================
# Phase A — CrowdSensing (56 variants = 28 user counts × Cloud + Fog)
#
# Zone 1 — Minimum edge cases          : 1, 2, 3
# Zone 2 — Small scale baseline        : 5, 8, 10, 12
# Zone 3 — Pre-crossover fill          : 14, 16
# Zone 4 — Crossover zone dense sample : 18, 20, 22, 24, 25, 27
# Zone 5 — Existing anchors            : 15, 30, 50
# Zone 6 — Post-crossover fill         : 35, 40
# Zone 7 — RAM boundary zone           : 45, 48, 52, 55
# Zone 8 — Stress / large scale        : 60, 70, 75, 100
# ===========================================================================

CS_USERS=(
    1 2 3
    5 8 10 12
    14 16 15
    18 20 22 24 25 27
    30 35 40
    45 48 50 52 55
    60 70 75 100
)

for users in "${CS_USERS[@]}"; do
    run "CrowdSensing_Cloud_${users}u" "$CS" --users="$users" --cloud-only=true
    run "CrowdSensing_Fog_${users}u"   "$CS" --users="$users" --cloud-only=false
done

# ===========================================================================
# Phase B — DCNS (84 variants = 42 configurations × Cloud + Fog)
#
# Each entry is "areas:cameras".
# Group 1 — Trivial minimum                            : 1x1..2x3
# Group 2 — Small scale, sub-saturation                : 1x5..3x8
# Group 3 — Pre-saturation fill                        : 4x7..5x9
# Group 4 (existing anchors)                           : 3x5, 5x10, 10x15
# Group 5 — Saturation zone                            : 5x11..6x11
# Group 6 — Post-saturation fill, pre-exhaustion       : 7x10..10x10
# Group 7 — MIPS exhaustion zone                       : 10x12..10x14
# Group 8 — Beyond 150 cameras / stress                : 12x15..20x10
# Group 9 — Aspect-ratio series (same total cameras)   : 10x5..15x10
# ===========================================================================

DCNS_CONFIGS=(
    1:1  1:2  1:3  2:2  2:3
    1:5  2:5  3:4  3:5  3:6  3:8
    4:7  4:8  4:9  4:10  5:8  5:9  5:10
    5:11  6:9  6:10  6:11
    7:10  7:12  8:10  8:12  9:10  9:12  10:10
    10:12  10:13  10:14  10:15
    12:15  15:15  20:10
    10:5  25:2  2:25  3:10  10:3  15:10
)

for config in "${DCNS_CONFIGS[@]}"; do
    areas="${config%%:*}"
    cameras="${config##*:}"
    run "DCNS_Cloud_${areas}x${cameras}" "$DC" --areas="$areas" --cameras="$cameras" --cloud=true
    run "DCNS_Fog_${areas}x${cameras}"   "$DC" --areas="$areas" --cameras="$cameras" --cloud=false
done

echo "========================================"
if [ "$FAILURES" -eq 0 ]; then
    echo "All $TOTAL variants completed successfully."
    echo "CSV files written to: $RESULTS_DIR"
    echo "- results_CrowdSensing.csv"
    echo "- results_DCNS.csv"
    echo "Logs written to: $LOGS_DIR"
else
    echo "$FAILURES of $TOTAL variants FAILED. Check the logs above."
fi

mv -f "$PROJECT_DIR/results_CrowdSensing.csv" "$RESULTS_DIR/" 2>/dev/null
mv -f "$PROJECT_DIR/results_DCNS.csv"         "$RESULTS_DIR/" 2>/dev/null

[ "$FAILURES" -gt 0 ] && exit 1