# Cray-AMD Platform Notes

Platform class `cray-amd` covers Cray systems with AMD GPUs. This document records
MI250X-specific requirements, known constraints, and operational details for lodger.

## GPU Architecture

| Property | Value |
|---|---|
| GPU | AMD MI250X |
| Spack target | `gfx90a` |
| GCDs per node | 8 (4 physical dies × 2 GCDs each) |
| HBM2e per GCD | ~64 GB |
| Interconnect | Slingshot (CXI, HPE proprietary) |
| MPI | cray-mpich + GTL (GPU Transport Layer) |
| Launcher | cray-pals (`mpirun`) |

## Required Environment Variables

These are set by the front-door module (`2026.06.lua`). Do not unset them.

| Variable | Value | Reason |
|---|---|---|
| `MPICH_GPU_SUPPORT_ENABLED` | `1` | Activates GTL device-buffer transfers in cray-mpich |
| `FI_CXI_ATS=0` | `0` | Mandatory for RCCL on Slingshot; RCCL hangs without this |
| `HSA_ENABLE_SDMA` | `0` | Prevents SDMA engine conflicts in multi-process workloads on MI250X |
| `HSA_FORCE_FINE_GRAIN_PCIE` | `1` | Enables PCIe fine-grain memory for GPU-NIC direct transfers |
| `RCCL_NET_PLUGIN` | `librccl-net-ofi-plugin.so` | Routes RCCL through aws-ofi-rccl → CXI |

## PyTorch ROCm Installation

PyTorch is **not** built by Spack. Use the AMD ROCm pip wheel index:

```bash
# 1. Create a site-managed venv
python3 -m venv $SITE_STACK_ROOT/python-envs/pytorch-rocm

# 2. Install PyTorch for the ROCm version on lodger
#    Check the loaded ROCm version: module list | grep rocm
source $SITE_STACK_ROOT/python-envs/pytorch-rocm/bin/activate
pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/rocm<ROCM_MAJOR_MINOR>

# 3. Verify
python3 -c "import torch; print(torch.version.hip); print(torch.cuda.is_available())"
```

After installation, users access PyTorch via `gpu-venv`:

```bash
gpu-venv ~/my-project/venv
source ~/my-project/venv/bin/activate
python3 -c "import torch; print(torch.version.hip)"
```

## RCCL and aws-ofi-rccl

RCCL (ROCm Collective Communications Library) is the AMD equivalent of NCCL.
On Slingshot systems, RCCL must use the `aws-ofi-rccl` plugin to route
collectives through libfabric/CXI instead of TCP.

The plugin (`aws-ofi-rccl`) is built by Spack as a Category C package with `+cxi`.
`RCCL_NET_PLUGIN=librccl-net-ofi-plugin.so` in the environment points RCCL to it.

If RCCL collective hangs or shows degraded performance:
1. Check `FI_CXI_ATS=0` is set: `echo $FI_CXI_ATS`
2. Check the plugin is found: `ldd $(which python3) | grep rccl` or check `gpu-doctor`
3. Check Slingshot firmware and CXI provider versions with the system admin

## ROCm/CPE Version Alignment

ROCm version must be aligned with the CPE release. Mixing ROCm versions with a
different CPE release can cause cray-mpich GTL failures. The ROCm version is
pinned in `systems/lodger/packages.yaml`.

To check the current alignment:

```bash
module list   # should show consistent rocm/X.Y.Z and cray-mpich/A.B.C
gpu-doctor    # checks amdgpu_target matches expected gfx90a
```

## PBS Job Submission Notes

This system uses PBS with cray-pals. Key differences from SLURM:

| SLURM | PBS equivalent |
|---|---|
| `#SBATCH --nodes=2` | `#PBS -l select=2:ncpus=<n>:ngpus=<n>` |
| `#SBATCH --partition=gpu` | `#PBS -q gpu` |
| `sbatch --wait script.sh` | `qsub -W block=true script.sh` |
| `srun -n 16 ./app` | `mpirun -n 16 ./app` (via `gpu-run`) |
| `SLURM_NODELIST` | `PBS_NODEFILE` |

The master node for `torchrun` rendezvous is obtained from `PBS_NODEFILE`:
```bash
MASTER_ADDR=$(head -1 "$PBS_NODEFILE")
```
