# Bootstrap Operator Runbook

This document describes the first-time setup procedure for deploying the GPU environment
stack on a new system. These steps are run **once** by the stack maintainer on the target
cluster.

## Prerequisites

Before starting:

- [ ] You have a service account or personal account with write access to `SITE_STACK_ROOT`
- [ ] The shared filesystem path is mounted on login, build, and compute nodes
- [ ] The Cray Programming Environment (CPE) is installed: `module avail PrgEnv-amd`
- [ ] ROCm is available: `module avail rocm`
- [ ] Git is available: `git --version`
- [ ] The cluster runs PBS and cray-pals is available: `module avail cray-pals`
- [ ] (Recommended) `clusterinspector` is installed and on PATH — bootstrap will capture a
  system profile automatically if it is available. Without it, no system profile is recorded.

## Step 1 — Clone this repository

Clone this repo to a stable location on the shared filesystem, adjacent to (but outside
of) `SITE_STACK_ROOT`:

```bash
git clone <remote-url> gpu-environment-stack
cd gpu-environment-stack
```

## Step 2 — Create and fill in `config/system.env`

```bash
cp config/system.env.template config/system.env
vi config/system.env
```

Set these three required values:

| Variable | Description |
|---|---|
| `SITE_STACK_ROOT` | Absolute path to the shared install root, e.g. `/shared/gpu-stack` |
| `SYSTEM_NAME` | Short name for this system with no spaces, e.g. `crusher` |
| `SPACK_VERSION` | Spack release tag, e.g. `v0.23.1` — see https://github.com/spack/spack/releases |

`config/system.env` is in `.gitignore` and is never committed.

## Step 3 — Fill in `config/pbs_resources.template`

Edit `config/pbs_resources.template` to set the correct PBS resource syntax for your
system. Replace `<CPUS>`, `<GPUS>`, and `<MEM>` with the per-node values for your cluster.
This file is committed to the repo; it controls how validation jobs request GPUs.

## Step 4 — Load the compiler environment

External detection requires `PrgEnv-amd` and `rocm` to be active on the login node:

```bash
module load PrgEnv-amd
module load rocm
```

## Step 5 — Run bootstrap

Preview what bootstrap will do without making any changes:

```bash
bash scripts/bootstrap.sh --dry-run
```

When ready, run for real:

```bash
bash scripts/bootstrap.sh
```

The script runs these steps in order:

0. If `clusterinspector` is on PATH, captures a system profile to
   `$EVIDENCE_DIR/system-profile.yaml` before any changes are made
1. Installs Spack to `$SITE_STACK_ROOT/spack/$SPACK_VERSION` (skips if already present)
2. Runs `detect-externals.sh` → writes `spack/systems/${SYSTEM_NAME}/packages.yaml`
3. Runs `spack external find` for OS libraries
4. Runs `spack compiler find`
5. Generates `spack/envs/cray-amd-dev/spack.yaml` from `spack.yaml.template`
6. Creates and concretizes the Spack environment
7. Installs all packages (`--fail-fast`)
8. Regenerates the Lmod module tree
9. Deploys wrapper scripts to `$SITE_STACK_ROOT/wrappers/`
10. Deploys the front-door module to `$SITE_STACK_ROOT/modulefiles/`

Expected runtime: 2–6 hours on first run (Kokkos, PETSc, and Trilinos are the longest
builds; subsequent runs with a warm Spack cache are much faster).

To redeploy only wrappers and the module without rebuilding:

```bash
bash scripts/bootstrap.sh --skip-build
```

## Step 6 — Review detection output

Inspect the generated externals file:

```bash
cat spack/systems/${SYSTEM_NAME}/packages.yaml
```

If any `<UNKNOWN>` placeholders remain, fill them in manually, then re-run with
`--skip-spack-install` to resume from detection:

```bash
bash scripts/bootstrap.sh --skip-spack-install
```

## Step 7 — Verify the deployment

```bash
module use ${SITE_STACK_ROOT}/modulefiles
module load gpu-stack/cray-amd/2026.06
gpu-stack-info     # all GPU_STACK_* vars should be set
gpu-doctor         # env-var checks pass on login node; GPU checks require a compute node
module avail gpu-stack/
```

## Step 8 — Run L1 validation

From a login node (jobs are submitted via PBS):

```bash
bash scripts/validate.sh
cat ${SITE_STACK_ROOT}/evidence/2026.06/${SYSTEM_NAME}/evidence.yaml
```

## Subsequent deployments

For patch releases or re-deployments:

```bash
git pull
bash scripts/bootstrap.sh --skip-spack-install
```

To run validation only:

```bash
bash scripts/validate.sh
```

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `spack concretize` fails on `hip` | ROCm not detected | Check `<UNKNOWN>` in `spack/systems/${SYSTEM_NAME}/packages.yaml`; re-run |
| `gpu-doctor` fails `FI_CXI_ATS` | Front-door module not loaded | `module load gpu-stack/cray-amd/2026.06` first |
| T1 OSU job fails to launch | PBS resource syntax wrong | Edit `config/pbs_resources.template` |
| `mpirun` not found in job | cray-pals not in module path | Ensure front-door module loads `cray-pals` |
| `rocminfo` shows wrong target | Module mismatch | Verify `rocm` version matches CPE release |
| `gpu-doctor` GPU checks show `[SKIP]` | Running on login node — expected | Run `gpu-doctor` inside a PBS job on a compute node |
