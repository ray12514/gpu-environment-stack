#!/bin/bash
# T0: GPU visibility check — confirms rocm-smi sees GPUs on a compute node.
# Submitted by validate.sh via qsub. PBS directives are prepended at submission time
# from config/pbs_resources.template (single-node block).
#PBS -N validate-t0-gpu
#PBS -o ${EVIDENCE_DIR}/t0_gpu_job.log
#PBS -e ${EVIDENCE_DIR}/t0_gpu_job.err
#PBS -j oe

source /etc/profile.d/modules.sh 2>/dev/null || true
module load gpu-stack/cray-amd/${RELEASE}

rocm-smi --showproductname \
    | tee "${EVIDENCE_DIR}/t0_rocm_smi.txt"

rocm-smi --showmeminfo vram \
    | tee -a "${EVIDENCE_DIR}/t0_rocm_smi.txt"
