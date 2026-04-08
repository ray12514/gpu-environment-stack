#!/usr/bin/env bash
# validate.sh — L1 validation for the cray-amd gpu-stack.
#
# Runs T0 (GPU visible), T1 (GPU-buffer MPI), and ML smoke (DDP training)
# by submitting PBS jobs from a login node, then writes an evidence bundle.
#
# Usage:
#   bash scripts/validate.sh
#
# Requires:
#   config/system.env        — filled in by operator
#   config/pbs_resources.template — PBS directives filled in for this system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------

CONFIG="${REPO_ROOT}/config/system.env"
if [[ ! -f "${CONFIG}" ]]; then
    echo "ERROR: config/system.env not found."
    echo "       Copy config/system.env.template to config/system.env and fill in values."
    exit 1
fi
# shellcheck source=../config/system.env
source "${CONFIG}"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

echo "=== validate.sh: ${RELEASE} / ${SYSTEM_NAME} ==="
echo ""

if [[ "${SYSTEM_NAME}" == *"<"* ]] || [[ "${SITE_STACK_ROOT}" == *"<"* ]]; then
    echo "ERROR: Unfilled placeholder in config/system.env — edit the file before running."
    exit 1
fi

if [[ ! -f "${REPO_ROOT}/config/pbs_resources.template" ]]; then
    echo "ERROR: config/pbs_resources.template not found."
    exit 1
fi

# shellcheck source=../config/pbs_resources.template
source "${REPO_ROOT}/config/pbs_resources.template"

if [[ "${T0_PBS_RESOURCES}" == *"<"* ]] || [[ "${TN_PBS_RESOURCES}" == *"<"* ]]; then
    echo "ERROR: Unfilled placeholder in config/pbs_resources.template — edit that file."
    exit 1
fi

# Expand VALIDATE_NODE_COUNT into the multi-node PBS directives
TN_PBS_RESOURCES="${TN_PBS_RESOURCES//<VALIDATE_NODE_COUNT>/${VALIDATE_NODE_COUNT}}"

mkdir -p "${EVIDENCE_DIR}"

echo "Evidence will be written to: ${EVIDENCE_DIR}"
echo ""

# Load the front-door module for pre-flight env checks
source /etc/profile.d/modules.sh 2>/dev/null || true
module load "gpu-stack/cray-amd/${RELEASE}" || {
    echo "ERROR: Could not load gpu-stack/cray-amd/${RELEASE}."
    echo "       Run bootstrap.sh first to deploy the stack and front-door module."
    exit 1
}

echo "--- Pre-flight: gpu-stack-info ---"
gpu-stack-info

echo ""
echo "--- Pre-flight: gpu-doctor (GPU hardware checks skipped on login node) ---"
gpu-doctor
echo ""

# ---------------------------------------------------------------------------
# Helper: build and submit a PBS job, block until complete
# ---------------------------------------------------------------------------

_submit_job() {
    local name="$1"          # job name for logging
    local template="$2"      # path to job script template
    local pbs_directives="$3" # PBS resource string to prepend
    local job_script="${EVIDENCE_DIR}/${name}_job_submitted.sh"

    # Build the actual job script: inject PBS directives after the shebang,
    # then envsubst to expand $EVIDENCE_DIR, $RELEASE, etc. in the body.
    {
        head -1 "${template}"                  # #!/bin/bash
        echo "${pbs_directives}"
        tail -n +2 "${template}"               # rest of the template
    } | envsubst > "${job_script}"
    chmod +x "${job_script}"

    echo "Submitting ${name} job..."
    qsub -W block=true "${job_script}"
    echo "${name} job completed."
}

# ---------------------------------------------------------------------------
# T0: GPU visible
# ---------------------------------------------------------------------------

echo "=== T0: GPU visibility ==="
_submit_job "t0" "${REPO_ROOT}/scripts/jobs/t0_gpu_job.sh" "${T0_PBS_RESOURCES}"
T0_RESULT="fail"
if [[ -f "${EVIDENCE_DIR}/t0_rocm_smi.txt" ]] && grep -qi "product\|gpu\|MI2\|gfx" "${EVIDENCE_DIR}/t0_rocm_smi.txt" 2>/dev/null; then
    T0_RESULT="pass"
fi
echo "T0 result: ${T0_RESULT}"
echo ""

# ---------------------------------------------------------------------------
# T1: GPU-buffer MPI (OSU)
# ---------------------------------------------------------------------------

echo "=== T1: GPU-buffer MPI bandwidth/latency ==="
_submit_job "t1" "${REPO_ROOT}/scripts/jobs/t1_osu_job.sh" "${TN_PBS_RESOURCES}"
T1_RESULT="fail"
T1_PEAK_BW="0"
if [[ -f "${EVIDENCE_DIR}/t1_osu_bw.txt" ]]; then
    # Peak BW is the highest value in column 2 of the osu_bw output
    T1_PEAK_BW=$(grep -E '^[0-9]' "${EVIDENCE_DIR}/t1_osu_bw.txt" 2>/dev/null \
        | awk '{print $2}' | sort -n | tail -1 || echo "0")
    [[ "${T1_PEAK_BW}" != "0" ]] && T1_RESULT="pass"
fi
echo "T1 result: ${T1_RESULT} (peak BW: ${T1_PEAK_BW} MB/s)"
echo ""

# ---------------------------------------------------------------------------
# ML smoke: DDP training
# ---------------------------------------------------------------------------

echo "=== ML smoke: LLaMA-1B DDP ==="
_submit_job "ml_smoke" "${REPO_ROOT}/scripts/jobs/ml_smoke_job.sh" "${TN_PBS_RESOURCES}"
ML_RESULT="fail"
ML_TOKENS_PER_SEC="0"
if [[ -f "${EVIDENCE_DIR}/ml_tokens_per_sec.txt" ]]; then
    ML_TOKENS_PER_SEC=$(tr -d '[:space:]' < "${EVIDENCE_DIR}/ml_tokens_per_sec.txt" || echo "0")
    [[ "${ML_TOKENS_PER_SEC}" != "0" ]] && ML_RESULT="pass"
fi
echo "ML smoke result: ${ML_RESULT} (tokens/sec: ${ML_TOKENS_PER_SEC})"
echo ""

# ---------------------------------------------------------------------------
# Write evidence bundle
# ---------------------------------------------------------------------------

EVIDENCE_FILE="${EVIDENCE_DIR}/evidence.yaml"
cat > "${EVIDENCE_FILE}" <<EOF
schema_version: "1.0"
release: "${RELEASE}"
system: "${SYSTEM_NAME}"
platform_class: "${PLATFORM_CLASS}"
validation_layer: L1
executed_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
owner: "$(id -un)"

results:

  preflight:
    capability: environment
    result: pass
    command: "gpu-stack-info"

  t0_gpu_visible:
    capability: T0
    result: "${T0_RESULT}"
    command: "rocm-smi --showproductname"
    artifacts:
      - "${EVIDENCE_DIR}/t0_rocm_smi.txt"

  t1_gpu_mpi:
    capability: T1
    result: "${T1_RESULT}"
    benchmark_family: osu-micro-benchmarks
    workload_class: point-to-point GPU-buffer
    node_count: ${VALIDATE_NODE_COUNT}
    gpu_count: $(( VALIDATE_NODE_COUNT * GPUS_PER_NODE ))
    metrics:
      osu_bw_peak_mbs: ${T1_PEAK_BW}
    artifacts:
      - "${EVIDENCE_DIR}/t1_osu_bw.txt"
      - "${EVIDENCE_DIR}/t1_osu_latency.txt"

  ml_smoke:
    capability: T1
    result: "${ML_RESULT}"
    benchmark_family: pytorch-ddp
    workload_class: distributed training smoke
    node_count: ${VALIDATE_NODE_COUNT}
    gpu_count: $(( VALIDATE_NODE_COUNT * GPUS_PER_NODE ))
    metrics:
      tokens_per_sec: ${ML_TOKENS_PER_SEC}
    artifacts:
      - "${EVIDENCE_DIR}/ml_smoke.txt"
EOF

echo "=== Evidence bundle written to: ${EVIDENCE_FILE} ==="
echo ""
echo "Summary:"
echo "  T0 GPU visible:  ${T0_RESULT}"
echo "  T1 GPU MPI:      ${T1_RESULT} (${T1_PEAK_BW} MB/s peak)"
echo "  ML smoke:        ${ML_RESULT} (${ML_TOKENS_PER_SEC} tokens/sec)"
echo ""

if [[ "${T0_RESULT}" == "pass" && "${T1_RESULT}" == "pass" && "${ML_RESULT}" == "pass" ]]; then
    echo "All L1 checks passed."
    exit 0
else
    echo "One or more L1 checks FAILED. Review artifacts in ${EVIDENCE_DIR}/"
    exit 1
fi
