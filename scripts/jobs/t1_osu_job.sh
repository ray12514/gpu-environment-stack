#!/bin/bash
# T1: GPU-buffer MPI bandwidth and latency using OSU Micro-Benchmarks.
# Submitted by validate.sh via qsub. PBS directives are prepended at submission time
# from config/pbs_resources.template (multi-node block).
#PBS -N validate-t1-osu
#PBS -o ${EVIDENCE_DIR}/t1_osu_job.log
#PBS -e ${EVIDENCE_DIR}/t1_osu_job.err
#PBS -j oe

source /etc/profile.d/modules.sh 2>/dev/null || true
module load gpu-stack/cray-amd/${RELEASE}

OSU_BW_BIN=$(spack location -i osu-micro-benchmarks)/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_bw
OSU_LAT_BIN=$(spack location -i osu-micro-benchmarks)/libexec/osu-micro-benchmarks/mpi/pt2pt/osu_latency

# GPU-buffer bandwidth: both endpoints use device (D) buffers
gpu-run \
    -n 2 \
    --ppn 1 \
    "${OSU_BW_BIN}" \
    -d rocm D D \
    -m 1:67108864 \
    | tee "${EVIDENCE_DIR}/t1_osu_bw.txt"

# GPU-buffer latency
gpu-run \
    -n 2 \
    --ppn 1 \
    "${OSU_LAT_BIN}" \
    -d rocm D D \
    -m 1:4096 \
    | tee "${EVIDENCE_DIR}/t1_osu_latency.txt"
