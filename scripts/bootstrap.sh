#!/usr/bin/env bash
# bootstrap.sh — First-time setup for the cray-amd gpu-stack.
#
# Installs Spack, detects CPE externals, builds the Spack environment,
# generates Lmod modules, and deploys wrapper scripts and the front-door module.
#
# Usage:
#   bash scripts/bootstrap.sh [OPTIONS]
#
# Options:
#   --dry-run              Print every action without executing anything
#   --skip-spack-install   Skip Spack clone (Spack already installed)
#   --skip-build           Skip Spack build steps; redeploy wrappers/module only
#
# Requires:
#   config/system.env   — filled in by operator (copy from config/system.env.template)
#   PrgEnv-amd and rocm modules loaded before running

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------

DRY_RUN=0
SKIP_SPACK_INSTALL=0
SKIP_BUILD=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)            DRY_RUN=1 ;;
        --skip-spack-install) SKIP_SPACK_INSTALL=1 ;;
        --skip-build)         SKIP_BUILD=1 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# run CMD [ARGS...] — execute normally, or print with [DRY-RUN] prefix.
run() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# run_write DEST CMD [ARGS...] — like run, but for commands that write to a file via >.
run_write() {
    local dest="$1"; shift
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "[DRY-RUN] $* > ${dest}"
    else
        "$@" > "${dest}"
    fi
}

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------

CONFIG="${REPO_ROOT}/config/system.env"
if [[ ! -f "${CONFIG}" ]]; then
    echo "ERROR: config/system.env not found."
    echo "       Run: cp config/system.env.template config/system.env"
    echo "       Then edit config/system.env to set SITE_STACK_ROOT, SYSTEM_NAME, and SPACK_VERSION."
    exit 1
fi
# shellcheck source=../config/system.env
source "${CONFIG}"

# ---------------------------------------------------------------------------
# Validate config values
# ---------------------------------------------------------------------------

_check_placeholder() {
    local var_name="$1"
    local var_value="$2"
    if [[ -z "${var_value}" || "${var_value}" == *"<"* ]]; then
        echo "ERROR: ${var_name} is not set or still contains a placeholder."
        echo "       Edit config/system.env and fill in all <PLACEHOLDER> values."
        exit 1
    fi
}

_check_placeholder "SITE_STACK_ROOT" "${SITE_STACK_ROOT}"
_check_placeholder "SYSTEM_NAME"     "${SYSTEM_NAME}"
_check_placeholder "SPACK_VERSION"   "${SPACK_VERSION}"

if [[ ! "${SPACK_VERSION}" =~ ^v ]]; then
    echo "ERROR: SPACK_VERSION must start with 'v', e.g. v0.23.1 (got: ${SPACK_VERSION})"
    exit 1
fi

echo "=== bootstrap.sh: ${RELEASE} / ${SYSTEM_NAME}${DRY_RUN:+ [DRY-RUN — no changes will be made]} ==="
echo "  SITE_STACK_ROOT: ${SITE_STACK_ROOT}"
echo "  SPACK_ROOT:      ${SPACK_ROOT}"
echo "  SPACK_ENV:       ${SPACK_ENV_NAME}"
echo ""

if [[ "${DRY_RUN}" -eq 0 && ! -w "${SITE_STACK_ROOT}" ]]; then
    echo "ERROR: SITE_STACK_ROOT is not writable: ${SITE_STACK_ROOT}"
    echo "       Create it first: mkdir -p ${SITE_STACK_ROOT}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Install Spack (idempotent)
# ---------------------------------------------------------------------------

if [[ "${SKIP_SPACK_INSTALL}" -eq 0 ]]; then
    echo "--- Step 1: Install Spack ${SPACK_VERSION} ---"
    run bash "${SCRIPT_DIR}/install-spack.sh"
else
    echo "--- Step 1: Skipping Spack install (--skip-spack-install) ---"
fi

# Source Spack (skipped in dry-run — Spack may not exist yet)
if [[ "${DRY_RUN}" -eq 0 ]]; then
    if [[ ! -f "${SPACK_ROOT}/share/spack/setup-env.sh" ]]; then
        echo "ERROR: Spack setup-env.sh not found at ${SPACK_ROOT}/share/spack/setup-env.sh"
        echo "       Run bootstrap.sh without --skip-spack-install."
        exit 1
    fi
    # shellcheck source=/dev/null
    source "${SPACK_ROOT}/share/spack/setup-env.sh"
else
    echo "[DRY-RUN] source ${SPACK_ROOT}/share/spack/setup-env.sh"
fi

if [[ "${SKIP_BUILD}" -eq 1 ]]; then
    echo ""
    echo "--- Skipping build steps (--skip-build); proceeding to wrapper/module deploy ---"
else
    # -------------------------------------------------------------------------
    # Step 2: Detect CPE externals → spack/systems/${SYSTEM_NAME}/packages.yaml
    # -------------------------------------------------------------------------

    echo ""
    echo "--- Step 2: Detect CPE externals ---"
    run bash "${SCRIPT_DIR}/detect-externals.sh"

    # -------------------------------------------------------------------------
    # Step 3: spack external find (OS libraries → classes/base/packages.yaml)
    # -------------------------------------------------------------------------

    echo ""
    echo "--- Step 3: spack external find (OS libraries) ---"
    run spack external find --scope "${REPO_ROOT}/spack/classes/base" \
        openssl cmake perl python3

    # -------------------------------------------------------------------------
    # Step 4: spack compiler find → classes/base/compilers.yaml
    # -------------------------------------------------------------------------

    echo ""
    echo "--- Step 4: spack compiler find ---"
    run spack compiler find --scope "${REPO_ROOT}/spack/classes/base"

    # -------------------------------------------------------------------------
    # Step 5: Generate spack.yaml from template
    # -------------------------------------------------------------------------

    echo ""
    echo "--- Step 5: Generate spack.yaml for system '${SYSTEM_NAME}' ---"
    SPACK_YAML="${REPO_ROOT}/spack/envs/${SPACK_ENV_NAME}/spack.yaml"
    run_write "${SPACK_YAML}" \
        sed "s|systems/SYSTEM_NAME|systems/${SYSTEM_NAME}|g" "${SPACK_YAML}.template"
    echo "  Written: ${SPACK_YAML}"

    # -------------------------------------------------------------------------
    # Step 6: Create and concretize the Spack environment
    # -------------------------------------------------------------------------

    echo ""
    echo "--- Step 6: Create Spack environment '${SPACK_ENV_NAME}' ---"
    if [[ "${DRY_RUN}" -eq 0 ]] && spack env list 2>/dev/null | grep -qx "${SPACK_ENV_NAME}"; then
        echo "  Environment already exists — skipping create."
    else
        run spack env create "${SPACK_ENV_NAME}" "${SPACK_YAML}"
    fi

    echo ""
    echo "--- Step 7: Concretize ---"
    run spack -e "${SPACK_ENV_NAME}" concretize -f

    # -------------------------------------------------------------------------
    # Step 7: Install
    # -------------------------------------------------------------------------

    echo ""
    echo "--- Step 8: Install (this may take 2–6 hours on first run) ---"
    run spack -e "${SPACK_ENV_NAME}" install --fail-fast

    # -------------------------------------------------------------------------
    # Step 8: Regenerate Lmod module tree
    # -------------------------------------------------------------------------

    echo ""
    echo "--- Step 9: Generate Lmod modules ---"
    run spack module lmod refresh --delete-tree -y
fi

# ---------------------------------------------------------------------------
# Step 9: Deploy wrapper scripts
# ---------------------------------------------------------------------------

echo ""
echo "--- Step 10: Deploy wrappers ---"
run mkdir -p "${SITE_STACK_ROOT}/wrappers/bin" "${SITE_STACK_ROOT}/wrappers/libexec"
run rsync -a --chmod=755 "${REPO_ROOT}/wrappers/bin/" "${SITE_STACK_ROOT}/wrappers/bin/"
run rsync -a "${REPO_ROOT}/wrappers/libexec/" "${SITE_STACK_ROOT}/wrappers/libexec/"
echo "  Wrappers deployed to ${SITE_STACK_ROOT}/wrappers/"

# ---------------------------------------------------------------------------
# Step 10: Deploy front-door module
# ---------------------------------------------------------------------------

echo ""
echo "--- Step 11: Deploy front-door module ---"
MODULE_SRC="${REPO_ROOT}/modules/gpu-stack/cray-amd/${RELEASE}.lua"
MODULE_DEST_DIR="${SITE_STACK_ROOT}/modulefiles/gpu-stack/cray-amd"
MODULE_DEST="${MODULE_DEST_DIR}/${RELEASE}.lua"

run mkdir -p "${MODULE_DEST_DIR}"
run_write "${MODULE_DEST}" \
    sed \
        -e "s|<SITE_STACK_ROOT>|${SITE_STACK_ROOT}|g" \
        -e "s|<SPACK_VERSION>|${SPACK_VERSION}|g" \
        "${MODULE_SRC}"
echo "  Module deployed to ${MODULE_DEST}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "=== Dry-run complete — no changes were made ==="
    echo "Re-run without --dry-run to execute."
else
    echo "=== Bootstrap complete ==="
fi
echo ""
echo "Next steps:"
echo "  1. Load the stack module:  module use ${SITE_STACK_ROOT}/modulefiles"
echo "                             module load gpu-stack/cray-amd/${RELEASE}"
echo "  2. Verify the environment: gpu-doctor"
echo "  3. Run L1 validation:      bash ${REPO_ROOT}/scripts/validate.sh"
echo ""
