# iFogSim2 (Fork: Fog vs Cloud Experiments)

This repository is a fork of [iFogSim2](https://github.com/Cloudslab/iFogSim) extended with CLI-driven experiment variants, unified CSV export, placement fixes, and an automated experiment runner. It compares **Cloud-only** (`ModulePlacementMapping`) vs **Fog** (`ModulePlacementEdgewards`) placement across four scenarios: DCNS and CrowdSensing (upstream), **EnvironmentalMonitoringFog** (our smart-building case), and **VRGameFog** (latency-critical VR/EEG, upstream extended).

## Requirements

- **Java 8 or 11** (`java` and `javac` on `PATH`)
- **Bash** (for `scripts/run_experiments.sh`)
- JAR dependencies are bundled under `jars/` (CloudSim, iFogSim libs)

## Build and run experiments

From the project root:

```bash
./scripts/run_experiments.sh
```

With no arguments, the script compiles modified classes and runs **all 224 variants** (10-minute timeout per variant):

| Phase | Application | Description | Variants | CSV |
|-------|-------------|-------------|----------|-----|
| `crowd` | `CrowdSensing_Microservices_RandomMobility_Clustering` | Mobile crowd sensing with microservice migration | 56 | `results_CrowdSensing.csv` |
| `dcns` | `DCNSFog` | Intelligent video surveillance in a smart city | 84 | `results_DCNS.csv` |
| `env` | `EnvironmentalMonitoringFog` | Smart-building temperature/humidity monitoring (selectivity 1.0) | 28 | `results_EnvironmentalMonitoring.csv` |
| `env-sparse` | `EnvironmentalMonitoringFog` | Same app with `--anomaly-selectivity=0.1` (10% of readings reach the heavy detector) | 28 | same file |
| `vrgame` | `VRGameFog` | VR game loop driven by EEG sensor input | 28 | `results_VRGame.csv` |

Logs go to `logs/variant_NNN_<label>.log`. CSV files are moved to `results/` when the script finishes.

### Running selected phases only

Pass one or more phase names (`crowd`, `dcns`, `env`, `env-sparse`, `vrgame`):

```bash
./scripts/run_experiments.sh env env-sparse
./scripts/run_experiments.sh dcns vrgame
./scripts/run_experiments.sh --list
./scripts/run_experiments.sh --help
```

### Running a single variant manually

The script always compiles first. To run one configuration by hand, build once then invoke the main class directly from the project root:

```bash
# Build first (compile runs at the start of the script)
./scripts/run_experiments.sh --help

CP="out/production/iFogSim_7:$(find jars -name '*.jar' | tr '\n' ':')"

java -cp "$CP" org.fog.test.perfeval.EnvironmentalMonitoringFog \
  --gateways=2 --sensors-per-gateway=2 --cloud=false

java -cp "$CP" org.fog.test.perfeval.VRGameFog \
  --departments=2 --mobiles-per-dept=5 --cloud=true
```

CSV rows append to `results_<Scenario>.csv` in the working directory; move them to `results/` when done.

## Analysis

```bash
python -m venv .venv && .venv/bin/pip install -r analysis/requirements.txt
.venv/bin/jupyter notebook analysis/experiment_analysis.ipynb
# or headless:
.venv/bin/jupyter nbconvert --execute --to notebook analysis/experiment_analysis.ipynb
```

Charts are written to `tex/img/`; summary tables to `analysis/summary_tables.json`. All analysis logic lives in `analysis/experiment_analysis.ipynb`.

## Project layout

| Path | Purpose |
|------|---------|
| `src/org/fog/test/perfeval/` | Simulation entry points (`DCNSFog`, `CrowdSensing_*`, `EnvironmentalMonitoringFog`, `VRGameFog`) |
| `src/org/fog/placement/` | Placement logic (fork modifications) |
| `scripts/run_experiments.sh` | Compile + run variants (all or selected phases) |
| `results/` | Experiment CSV output |
| `analysis/` | Python charts and summary tables |
| `jars/` | Third-party JAR dependencies |
| `dataset/` | Mobility traces for CrowdSensing |
| `tex/` | LaTeX report and figures |

## Fork modifications (summary)

- **CLI arguments** on all four perfeval apps (`--cloud`, scale params, `--anomaly-selectivity` on EnvironmentalMonitoringFog)
- **CSV export** via shutdown hooks into unified files per scenario
- **`scripts/run_experiments.sh`**: 224-variant sweep with phase selection, timeout, and logging
- **Placement fixes** in `ModulePlacementEdgewards`, `ClusteredMicroservicePlacementLogic`, `MicroservicesMobilityClusteringController`
- **`EnvironmentalMonitoringFog.java`**: own use case, smart-building env monitoring with configurable anomaly selectivity
- **`VRGameFog.java`**: extended with CLI and CSV export for Cloud vs Fog latency experiments

Upstream example applications retain original authorship; see file headers.

## References

 * Redowan Mahmud, Samodha Pallewatta, Mohammad Goudarzi, and Rajkumar Buyya, <A href="https://arxiv.org/abs/2109.05636">iFogSim2: An Extended iFogSim Simulator for Mobility, Clustering, and Microservice Management in Edge and Fog Computing Environments</A>, Journal of Systems and Software (JSS), Volume 190, Pages: 1-17, ISSN:0164-1212, Elsevier Press, Amsterdam, The Netherlands, August 2022.
 * Harshit Gupta, Amir Vahid Dastjerdi , Soumya K. Ghosh, and Rajkumar Buyya, <A href="http://www.buyya.com/papers/iFogSim.pdf">iFogSim: A Toolkit for Modeling and Simulation of Resource Management Techniques in Internet of Things, Edge and Fog Computing Environments</A>, Software: Practice and Experience (SPE), Volume 47, Issue 9, Pages: 1275-1296, ISSN: 0038-0644, Wiley Press, New York, USA, September 2017.
 * Redowan Mahmud and Rajkumar Buyya, <A href="http://www.buyya.com/papers/iFogSim-Tut.pdf">Modelling and Simulation of Fog and Edge Computing Environments using iFogSim Toolkit</A>, Fog and Edge Computing: Principles and Paradigms, R. Buyya and S. Srirama (eds), 433-466pp, ISBN: 978-111-95-2498-4, Wiley Press, New York, USA, January 2019.
