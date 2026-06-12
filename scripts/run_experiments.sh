#!/usr/bin/env bash
# Compile and run Fog vs Cloud experiment variants.
#
#     ./scripts/run_experiments.sh                 # all phases (224 variants)
#     ./scripts/run_experiments.sh env env-sparse  # selected phases only
#     ./scripts/run_experiments.sh --help
#
# Logs: logs/variant_NNN_<label>.log
# CSV:  results/results_*.csv (apps append during simulation)
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/out/production/iFogSim_7"
SRC_DIR="$PROJECT_DIR/src"
LOGS_DIR="$PROJECT_DIR/logs"
RESULTS_DIR="$PROJECT_DIR/results"
mkdir -p "$LOGS_DIR" "$RESULTS_DIR"

# Classpath: compiled output + every jar under jars/ (including nested dirs)
CP="$OUT_DIR"
while IFS= read -r jar; do
    CP="$CP:$jar"
done < <(find "$PROJECT_DIR/jars" -name '*.jar' | sort)

# Main classes (org.fog.test.perfeval.*)
CS=org.fog.test.perfeval.CrowdSensing_Microservices_RandomMobility_Clustering
DC=org.fog.test.perfeval.DCNSFog
ENV=org.fog.test.perfeval.EnvironmentalMonitoringFog
VR=org.fog.test.perfeval.VRGameFog

# Parameter sweeps (areas:cameras, gateways:sensors-per-gateway, departments:mobiles-per-dept, ...)
CS_USERS=(
    1 2 3
    5 8 10 12
    14 16 15
    18 20 22 24 25 27
    30 35 40
    45 48 50 52 55
    60 70 75 100
)

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

ENV_CONFIGS=(
    1:1  1:2  2:2
    2:4  3:3  4:4  5:3
    5:5  6:4  8:3
    8:5  10:4  10:5  12:4
)

VR_CONFIGS=(
    1:1  1:2  2:2
    2:4  3:3  4:4  5:3
    5:5  6:4  8:3
    8:5  10:4  10:5  12:4
)

# Which phases to run (set from CLI below)
RUN_CROWD=0
RUN_DCNS=0
RUN_ENV=0
RUN_ENV_SPARSE=0
RUN_VRGAME=0

print_phases() {
    printf "  %-11s %3d variants   %s\n" "crowd"      56 "CrowdSensing"
    printf "  %-11s %3d variants   %s\n" "dcns"       84 "DCNSFog"
    printf "  %-11s %3d variants   %s\n" "env"        28 "EnvironmentalMonitoringFog, selectivity 1.0"
    printf "  %-11s %3d variants   %s\n" "env-sparse" 28 "EnvironmentalMonitoringFog, selectivity 0.1"
    printf "  %-11s %3d variants   %s\n" "vrgame"     28 "VRGameFog"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<EOF
Usage: $0 [phase ...]

Phases:
EOF
    print_phases
    cat <<EOF

No arguments = run all (224 variants).
EOF
    exit 0
fi

if [ "${1:-}" = "--list" ]; then
    print_phases
    exit 0
fi

if [ $# -eq 0 ]; then
    RUN_CROWD=1
    RUN_DCNS=1
    RUN_ENV=1
    RUN_ENV_SPARSE=1
    RUN_VRGAME=1
else
    for arg in "$@"; do
        case "$(echo "$arg" | tr '[:upper:]' '[:lower:]')" in
            crowd)      RUN_CROWD=1 ;;
            dcns)       RUN_DCNS=1 ;;
            env)        RUN_ENV=1 ;;
            env-sparse) RUN_ENV_SPARSE=1 ;;
            vrgame)     RUN_VRGAME=1 ;;
            *)
                echo "Unknown phase: $arg (try --help)" >&2
                exit 1
                ;;
        esac
    done
fi

TOTAL=0
[ "$RUN_CROWD" -eq 1 ]      && TOTAL=$((TOTAL + 56))
[ "$RUN_DCNS" -eq 1 ]       && TOTAL=$((TOTAL + 84))
[ "$RUN_ENV" -eq 1 ]        && TOTAL=$((TOTAL + 28))
[ "$RUN_ENV_SPARSE" -eq 1 ] && TOTAL=$((TOTAL + 28))
[ "$RUN_VRGAME" -eq 1 ]     && TOTAL=$((TOTAL + 28))

# Build
echo "Compiling..."
javac -cp "$CP" -d "$OUT_DIR" \
    "$SRC_DIR/org/fog/placement/ModulePlacementEdgewards.java" \
    "$SRC_DIR/org/fog/placement/MicroservicesMobilityClusteringController.java" \
    "$SRC_DIR/org/fog/placement/ClusteredMicroservicePlacementLogic.java" \
    "$SRC_DIR/org/fog/test/perfeval/DCNSFog.java" \
    "$SRC_DIR/org/fog/test/perfeval/CrowdSensing_Microservices_RandomMobility_Clustering.java" \
    "$SRC_DIR/org/fog/test/perfeval/EnvironmentalMonitoringFog.java" \
    "$SRC_DIR/org/fog/test/perfeval/VRGameFog.java"

FAILURES=0
VARIANT=0

run() {
    local label=$1
    local class=$2
    shift 2

    VARIANT=$((VARIANT + 1))
    printf -v num "%03d" "$VARIANT"
    local logfile="$LOGS_DIR/variant_${num}_${label}.log"

    echo "[$num/$TOTAL] $label ($(date '+%H:%M:%S'))"
    (cd "$PROJECT_DIR" && timeout 600 java -cp "$CP" "$class" "$@") > "$logfile" 2>&1
    local exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        echo "  PASS"
    elif [ "$exit_code" -eq 124 ]; then
        echo "  TIMEOUT (>10 min), log: $logfile"
        FAILURES=$((FAILURES + 1))
    else
        echo "  FAIL (exit $exit_code), log: $logfile"
        FAILURES=$((FAILURES + 1))
    fi
}

# crowd - CrowdSensing
if [ "$RUN_CROWD" -eq 1 ]; then
    for users in "${CS_USERS[@]}"; do
        run "CrowdSensing_Cloud_${users}u" "$CS" --users="$users" --cloud-only=true
        run "CrowdSensing_Fog_${users}u" "$CS" --users="$users" --cloud-only=false
    done
fi

# dcns - DCNSFog
if [ "$RUN_DCNS" -eq 1 ]; then
    for config in "${DCNS_CONFIGS[@]}"; do
        areas="${config%%:*}"
        cameras="${config##*:}"
        run "DCNS_Cloud_${areas}x${cameras}" "$DC" --areas="$areas" --cameras="$cameras" --cloud=true
        run "DCNS_Fog_${areas}x${cameras}" "$DC" --areas="$areas" --cameras="$cameras" --cloud=false
    done
fi

# env - EnvironmentalMonitoringFog, selectivity 1.0 
if [ "$RUN_ENV" -eq 1 ]; then
    for config in "${ENV_CONFIGS[@]}"; do
        gw="${config%%:*}"
        spg="${config##*:}"
        run "EnvMonitoring_Cloud_${gw}x${spg}" "$ENV" \
            --gateways="$gw" --sensors-per-gateway="$spg" --cloud=true
        run "EnvMonitoring_Fog_${gw}x${spg}" "$ENV" \
            --gateways="$gw" --sensors-per-gateway="$spg" --cloud=false
    done
fi

# env-sparse - EnvironmentalMonitoringFog, selectivity 0.1
if [ "$RUN_ENV_SPARSE" -eq 1 ]; then
    for config in "${ENV_CONFIGS[@]}"; do
        gw="${config%%:*}"
        spg="${config##*:}"
        run "EnvMonitoringSparse_Cloud_${gw}x${spg}" "$ENV" \
            --gateways="$gw" --sensors-per-gateway="$spg" --cloud=true --anomaly-selectivity=0.1
        run "EnvMonitoringSparse_Fog_${gw}x${spg}" "$ENV" \
            --gateways="$gw" --sensors-per-gateway="$spg" --cloud=false --anomaly-selectivity=0.1
    done
fi

# vrgame - VRGameFog
if [ "$RUN_VRGAME" -eq 1 ]; then
    for config in "${VR_CONFIGS[@]}"; do
        depts="${config%%:*}"
        mobiles="${config##*:}"
        run "VRGame_Cloud_${depts}x${mobiles}" "$VR" \
            --departments="$depts" --mobiles-per-dept="$mobiles" --cloud=true
        run "VRGame_Fog_${depts}x${mobiles}" "$VR" \
            --departments="$depts" --mobiles-per-dept="$mobiles" --cloud=false
    done
fi

# Finish: move CSV from project root to results/
mv -f "$PROJECT_DIR/results_CrowdSensing.csv" "$RESULTS_DIR/" 2>/dev/null
mv -f "$PROJECT_DIR/results_DCNS.csv" "$RESULTS_DIR/" 2>/dev/null
mv -f "$PROJECT_DIR/results_EnvironmentalMonitoring.csv" "$RESULTS_DIR/" 2>/dev/null
mv -f "$PROJECT_DIR/results_VRGame.csv" "$RESULTS_DIR/" 2>/dev/null

if [ "$FAILURES" -eq 0 ]; then
    echo "Done: $TOTAL variants completed successfully. CSV in $RESULTS_DIR/"
else
    echo "Done with errors: $FAILURES / $TOTAL failed. See $LOGS_DIR/"
    exit 1
fi
