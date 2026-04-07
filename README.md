# gpu-environment-stack

Implementation repository for the GPU environment program.

This repository contains the Spack configuration, Ansible playbooks, wrapper scripts,
and module templates needed to deploy and manage the site GPU software environment.

The specification and governance documents are in the companion repository:
`gpu-environment-blueprint`.

## System Coverage

| System | Platform class | GPU | Scheduler |
|---|---|---|---|
| lodger | cray-amd | MI250X (gfx90a) | PBS + cray-pals |

## First-Time Bootstrap

See [`scripts/bootstrap-runbook.md`](scripts/bootstrap-runbook.md) for the full
operator procedure. The short version:

```bash
export SITE_STACK_ROOT=<path>
export SPACK_VERSION=v0.22.0
module load PrgEnv-amd
ansible-playbook -i ansible/inventory/lodger ansible/bootstrap.yml
```

## Subsequent Deployments

```bash
ansible-playbook -i ansible/inventory/lodger ansible/site.yml
```

## Repository Layout

```
scripts/          bootstrap and detection scripts
spack/
  classes/base/   universal Spack policy
  classes/cray-amd/  platform-class externals and compiler config
  systems/lodger/ system-specific external versions (committed after detection)
  envs/           Spack environment specs
modules/          hand-authored front-door module files
wrappers/bin/     wrapper scripts deployed to SITE_STACK_ROOT
ansible/          playbooks, inventory, group_vars, roles
docs/             operational notes and release records
reframe/          validation test configs (future)
```

## Companion Repositories

- `gpu-environment-blueprint` — specification, schemas, ADRs, contracts
- `clusterinspector` — passive node profiling and evidence capture
