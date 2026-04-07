# Bootstrap Operator Runbook

This document describes the first-time setup procedure for deploying the GPU environment
stack on a new system. These steps are run **once** by the stack maintainer on the target
cluster. Subsequent deployments use `ansible/site.yml`.

## Prerequisites

Before starting:

- [ ] You have a service account or personal account with write access to `SITE_STACK_ROOT`
- [ ] The shared filesystem path is mounted on login, build, and compute nodes
- [ ] The Cray Programming Environment (CPE) is installed: `module avail PrgEnv-amd`
- [ ] ROCm is available: `module avail rocm`
- [ ] Ansible is installed on the login node: `ansible --version`
- [ ] Git is available: `git --version`
- [ ] The cluster runs PBS and cray-pals is available: `module avail cray-pals`

## Step 1 — Clone this repository

Clone this repo to a stable location on the shared filesystem. It should live adjacent to
(but outside of) `SITE_STACK_ROOT`:

```bash
cd <parent-directory>
git clone <remote-url> gpu-environment-stack
# or, for initial local setup before a remote exists:
# copy the repo directory to the cluster via scp/rsync
```

## Step 2 — Set required environment variables

```bash
export SITE_STACK_ROOT=<path>       # e.g. /shared/gpu-stack
export SPACK_VERSION=v0.22.0        # pin to a Spack release tag
export REPO_ROOT=$(pwd)/gpu-environment-stack
```

Update `ansible/group_vars/all.yml` to record these values permanently before running
the playbook.

## Step 3 — Load the validated compiler environment

External detection requires PrgEnv-amd to be active:

```bash
module load PrgEnv-amd
module load rocm          # needed for rocminfo GPU target detection
```

## Step 4 — Run the bootstrap playbook

```bash
cd gpu-environment-stack
ansible-playbook -i ansible/inventory/lodger ansible/bootstrap.yml
```

The playbook runs these roles in order:

1. `spack_install` — clones Spack to `$SITE_STACK_ROOT/spack/$SPACK_VERSION` if absent
2. `stack_env_install` — runs detect-externals.sh, configures Spack, concretizes, builds, generates modules
3. `stack_wrappers` — deploys wrapper scripts and the front-door module
4. `stack_validate` — runs L1 validation (T0 + T1 OSU + ML smoke) and writes evidence bundle

Expected runtime: 2–6 hours depending on package cache availability (Kokkos, PETSc, and
Trilinos are the longest builds).

## Step 5 — Review detection output

After `stack_env_install` runs `detect-externals.sh`, inspect:

```bash
cat spack/systems/lodger/packages.yaml
```

If any `<UNKNOWN>` placeholders remain, resolve them manually, then re-run:

```bash
ansible-playbook -i ansible/inventory/lodger ansible/bootstrap.yml \
  --start-at-task "Run detect-externals"
```

## Step 6 — Verify the deployment

```bash
module load gpu-stack/cray-amd/2026.06
gpu-stack-info       # all GPU_STACK_* vars should be set
gpu-doctor           # all checks should pass
module avail gpu-stack/
module load gpu-stack/kokkos/4.3.01-gfx90a
```

Check the L1 evidence bundle:

```bash
cat $SITE_STACK_ROOT/evidence/2026.06/lodger/evidence.yaml
```

## Step 7 — Commit system-specific files and push to remote

After a successful bootstrap, commit the auto-generated files and initialize the remote:

```bash
git add spack/systems/lodger/packages.yaml
git add spack/classes/base/compilers.yaml   # written by spack compiler find
git commit -m "add lodger externals and compiler config for 2026.06"

git remote add origin <remote-url>
git push -u origin main
```

## Subsequent deployments

For patch releases or re-deployments after the initial bootstrap:

```bash
git pull
ansible-playbook -i ansible/inventory/lodger ansible/site.yml
```

To run only validation:

```bash
ansible-playbook -i ansible/inventory/lodger ansible/site.yml --tags stack_validate
```

## Troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `spack concretize` fails on `hip` | ROCm not detected in packages.yaml | Check `<UNKNOWN>` in lodger/packages.yaml; re-run detect-externals.sh |
| `gpu-doctor` fails `FI_CXI_ATS` check | Front-door module not loaded | `module load gpu-stack/cray-amd/2026.06` first |
| T1 OSU job fails to launch | PBS queue name wrong | Check `pbs_queue` in `ansible/group_vars/lodger.yml` |
| `mpirun` not found in job | cray-pals not in module path | Ensure `cray-pals` is loaded by front-door or job script |
| `rocminfo` shows wrong target | Module mismatch | Verify `rocm` module version matches CPE release |
