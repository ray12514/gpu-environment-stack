# Release Notes — 2026.06

Release identifier: `2026.06`
Platform class: `cray-amd`
System: `lodger`
Status: initial

## What Is In This Release

| Package | Version | Notes |
|---|---|---|
| Kokkos | 4.3.01 | +rocm amdgpu_target=gfx90a |
| RAJA | 2024.07.0 | +rocm amdgpu_target=gfx90a |
| PETSc | 3.21.4 | +mpi +hdf5 +hypre +suite-sparse |
| Trilinos | 16.0.0 | +mpi +hdf5 +suite-sparse +boost |
| AMReX | 24.11 | +mpi +rocm amdgpu_target=gfx90a |
| heFFTe | 2.4.0 | +fftw +rocm amdgpu_target=gfx90a |
| aws-ofi-rccl | — | +cxi (Slingshot transport) |
| OSU Micro-Benchmarks | 6.1 | +rocm (for T1 validation) |
| py-mpi4py | 3.1.6 | — |
| py-numpy | 1.26.4 | — |
| py-scipy | 1.13.0 | — |
| PyTorch | — | Installed from AMD ROCm pip wheel; see docs/cray-amd-specifics.md |

## Externals (CPE-provided)

| Package | Version | Source |
|---|---|---|
| ROCm | `<VERSION>` | Cray module: rocm/X.Y.Z |
| cray-mpich | `<VERSION>` | CPE |
| cray-pals | `<VERSION>` | CPE |
| cray-libsci | `<VERSION>` | CPE |
| HDF5 | `<VERSION>` | cray-hdf5-parallel |
| FFTW | `<VERSION>` | cray-fftw |
| NetCDF-C | `<VERSION>` | cray-netcdf-hdf5parallel |
| Python | `<VERSION>` | cray-python |

_Fill in actual versions from `spack/systems/lodger/packages.yaml` after detection._

## Validation Status

| Check | Status | Evidence |
|---|---|---|
| T0: GPU visible | pending | — |
| T1: GPU-buffer MPI | pending | — |
| ML smoke: LLaMA-1B | pending | — |

_Update after running `ansible-playbook ... --tags stack_validate`._

## Known Limitations

- PyTorch is not Spack-built; users must activate a `gpu-venv` to access it.
- T2 and T3 capability tiers are not claimed in this release.
