# gpu-environment-stack

Implementation repository for the GPU environment program.

This repository contains the Spack configuration, wrapper scripts, module templates,
and deployment scripts needed to set up and validate the site GPU software environment
on a Cray-AMD system (MI250X / gfx90a, PBS scheduler, cray-pals launcher).

The specification and governance documents are in the companion repository:
`gpu-environment-blueprint`.

## Supported Platform

| Platform class | GPU | Scheduler |
|---|---|---|
| cray-amd | AMD MI250X (gfx90a) | PBS + cray-pals |

The system name (`SYSTEM_NAME`) is supplied by the operator at bootstrap time —
there is no hardcoded system name in this repository.

## First-Time Bootstrap

See [`scripts/bootstrap-runbook.md`](scripts/bootstrap-runbook.md) for the full
operator procedure. The short version:

```bash
cp config/system.env.template config/system.env
vi config/system.env          # set SITE_STACK_ROOT, SYSTEM_NAME, SPACK_VERSION
module load PrgEnv-amd rocm
bash scripts/bootstrap.sh
```

## Subsequent Deployments

```bash
git pull
bash scripts/bootstrap.sh --skip-spack-install
```

## Run Validation Only

```bash
bash scripts/validate.sh
```

## Repository Layout

```
config/
  system.env.template   operator copies → system.env; fill in before bootstrap
  pbs_resources.template  PBS GPU resource directives for this system
scripts/
  bootstrap.sh          first-time setup (Spack install, build, wrappers, module)
  validate.sh           L1 validation (T0 + T1 OSU + ML smoke + evidence bundle)
  install-spack.sh      idempotent Spack clone helper
  detect-externals.sh   queries CPE modules → spack/systems/${SYSTEM_NAME}/packages.yaml
  jobs/                 PBS job scripts submitted by validate.sh
spack/
  classes/base/         universal Spack policy (config, compilers, OS externals, modules)
  classes/cray-amd/     platform-class externals and compiler config
  systems/              runtime-generated per system; created by detect-externals.sh
  envs/cray-amd-dev/    Spack environment spec (spack.yaml.template → spack.yaml)
modules/                hand-authored front-door module files
wrappers/
  bin/                  wrapper scripts deployed to SITE_STACK_ROOT
  libexec/              support scripts (benchmark_ddp.py)
docs/                   operational notes, release records, platform specifics
reframe/                validation test configs (future L2/L3)
```

## Companion Repositories

- `gpu-environment-blueprint` — specification, schemas, ADRs, contracts
- `clusterinspector` — passive node profiling and evidence capture
