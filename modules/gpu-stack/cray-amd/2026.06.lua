-- modules/gpu-stack/cray-amd/2026.06.lua
-- Hand-authored front-door module for gpu-stack release 2026.06
--
-- Platform class : cray-amd
-- GPU            : AMD MI250X (gfx90a)
-- MPI            : cray-mpich (GPU-aware via GTL) + cray-pals launcher
-- Scheduler      : PBS
-- Compiler       : PrgEnv-amd (validated context for this release)
--
-- This file is deployed by the stack_wrappers Ansible role to:
--   <SITE_STACK_ROOT>/modulefiles/gpu-stack/cray-amd/2026.06.lua
--
-- OPERATOR: replace all <SITE_STACK_ROOT> and <SPACK_VERSION> tokens
-- before deploying. The stack_wrappers role templates these automatically.

whatis("Name: gpu-stack")
whatis("Version: 2026.06")
whatis("Platform class: cray-amd")
whatis("GPU: AMD MI250X (gfx90a)")
whatis("MPI: cray-mpich + GTL (GPU-aware)")
whatis("Launcher: cray-pals (mpirun)")
whatis("Description: GPU HPC software environment — release 2026.06")

-- Only one gpu-stack release may be active at a time
conflict("gpu-stack")

-- ---- Validated vendor substrate ----
-- PrgEnv-amd is the validated compiler context for this release.
-- cray-pals provides mpirun on PBS systems.
load("PrgEnv-amd")
load("cray-mpich")
load("cray-pals")
load("rocm")

-- ---- Spack environment activation ----
local spack_root = "<SITE_STACK_ROOT>/spack/<SPACK_VERSION>"
local env_path   = "<SITE_STACK_ROOT>/repos/gpu-environment-stack/spack/envs/cray-amd-dev"

execute{
  cmd   = "source " .. spack_root .. "/share/spack/setup-env.sh"
          .. " && spack env activate " .. env_path,
  modeA = {"load"}
}

-- ---- Package module tree ----
-- Exposes Spack-generated modules (kokkos, raja, petsc, etc.) under gpu-stack/
prepend_path("MODULEPATH", "<SITE_STACK_ROOT>/modules/lmod/Core")

-- ---- Wrappers ----
prepend_path("PATH", "<SITE_STACK_ROOT>/wrappers/bin")

-- ---- Release metadata ----
setenv("GPU_STACK_RELEASE",        "2026.06")
setenv("GPU_STACK_PLATFORM_CLASS", "cray-amd")
setenv("GPU_STACK_GPU_ARCH",       "gfx90a")
setenv("GPU_STACK_SPACK_ROOT",     spack_root)

-- ---- Python isolation ----
-- Prevents user ~/.local packages from leaking into the stack Python
setenv("PYTHONNOUSERSITE", "1")

-- ---- GPU-aware MPI ----
-- Enables the cray-mpich GPU Transport Layer (GTL) for device-buffer transfers
setenv("MPICH_GPU_SUPPORT_ENABLED", "1")

-- ---- AMD MI250X runtime requirements ----
-- FI_CXI_ATS=0: mandatory for RCCL on HPE Slingshot / CXI fabric
-- Without this, RCCL collectives hang or produce incorrect results.
setenv("FI_CXI_ATS", "0")

-- HSA_ENABLE_SDMA=0: prevents SDMA engine conflicts in multi-process MI250X workloads
setenv("HSA_ENABLE_SDMA", "0")

-- HSA_FORCE_FINE_GRAIN_PCIE=1: enables PCIe fine-grain memory access
-- Required for GPU-NIC direct transfers (GPUDirect RDMA equivalent on ROCm)
setenv("HSA_FORCE_FINE_GRAIN_PCIE", "1")

-- ---- RCCL transport plugin ----
-- Routes RCCL collectives through aws-ofi-rccl → libfabric → CXI → Slingshot
setenv("RCCL_NET_PLUGIN", "librccl-net-ofi-plugin.so")
