#!/usr/bin/env bash
# install-spack.sh — Clone a pinned Spack release into SITE_STACK_ROOT/spack/SPACK_VERSION
#
# Usage: SITE_STACK_ROOT=/path SPACK_VERSION=v0.22.0 ./scripts/install-spack.sh
#
# Idempotent: exits 0 without doing anything if Spack is already installed.
# Called by the spack_install Ansible role and by operators running bootstrap manually.

set -euo pipefail

: "${SITE_STACK_ROOT:?SITE_STACK_ROOT must be set (e.g. export SITE_STACK_ROOT=/shared/gpu-stack)}"
: "${SPACK_VERSION:?SPACK_VERSION must be set (e.g. export SPACK_VERSION=v0.22.0)}"

SPACK_DEST="${SITE_STACK_ROOT}/spack/${SPACK_VERSION}"

# Enforce a release tag — never install from develop or an arbitrary branch
if [[ "${SPACK_VERSION}" != v* ]]; then
  echo "ERROR: SPACK_VERSION must be a release tag starting with 'v' (e.g. v0.22.0)." >&2
  echo "       Got: '${SPACK_VERSION}'" >&2
  echo "       Using 'develop' or an arbitrary branch is not supported for site installs." >&2
  exit 1
fi

# Idempotency check
if [[ -d "${SPACK_DEST}/.git" ]]; then
  echo "Spack ${SPACK_VERSION} already installed at ${SPACK_DEST} — nothing to do."
  echo "Activate with: source ${SPACK_DEST}/share/spack/setup-env.sh"
  exit 0
fi

echo "Installing Spack ${SPACK_VERSION} → ${SPACK_DEST}"
mkdir -p "$(dirname "${SPACK_DEST}")"

git clone \
  --depth=1 \
  --branch "${SPACK_VERSION}" \
  https://github.com/spack/spack.git \
  "${SPACK_DEST}"

# Make readable and executable by all users (shared install)
chmod -R 755 "${SPACK_DEST}"

echo ""
echo "Spack ${SPACK_VERSION} installed at ${SPACK_DEST}"
echo "Activate with: source ${SPACK_DEST}/share/spack/setup-env.sh"
