#!/bin/bash
# ML smoke: LLaMA-1B DDP training smoke test using PyTorch + ROCm.
# Submitted by validate.sh via qsub. PBS directives are prepended at submission time
# from config/pbs_resources.template (multi-node block).
#PBS -N validate-ml-smoke
#PBS -o ${EVIDENCE_DIR}/ml_smoke_job.log
#PBS -e ${EVIDENCE_DIR}/ml_smoke_job.err
#PBS -j oe

source /etc/profile.d/modules.sh 2>/dev/null || true
module load gpu-stack/cray-amd/${RELEASE}

MASTER_ADDR=$(head -1 "$PBS_NODEFILE")
MASTER_PORT=29500
NNODES=${VALIDATE_NODE_COUNT}
NPROC_PER_NODE=${GPUS_PER_NODE}

gpu-run \
    -n $(( NNODES * NPROC_PER_NODE )) \
    --ppn "${NPROC_PER_NODE}" \
    torchrun \
        --nproc_per_node="${NPROC_PER_NODE}" \
        --nnodes="${NNODES}" \
        --rdzv_backend=c10d \
        --rdzv_endpoint="${MASTER_ADDR}:${MASTER_PORT}" \
        "${SITE_STACK_ROOT}/wrappers/libexec/benchmark_ddp.py" \
            --model llama-1b \
            --steps 50 \
    | tee "${EVIDENCE_DIR}/ml_smoke.txt"

# Extract final tokens/sec for the evidence bundle
grep "^RESULT tokens/sec=" "${EVIDENCE_DIR}/ml_smoke.txt" \
    | tail -1 \
    | sed 's/RESULT tokens\/sec=//' \
    > "${EVIDENCE_DIR}/ml_tokens_per_sec.txt"
