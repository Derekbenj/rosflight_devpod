#!/usr/bin/env bash
#
# setup_workspace.sh — set up the ROSflight ROS 2 workspace.
#
# Creates the src/ folder structure, clones the required ROSflight repositories
# and Veloxity (idempotently — existing clones are left untouched), installs
# dependencies with rosdep, and builds ROSflight plus the Veloxity simulator
# and ROS 2 shim.
#
# Usage:
#   bash scripts/setup_workspace.sh
#
# Environment variables:
#   ROS_DISTRO           ROS 2 distro to source (default: humble)
#   ROSFLIGHT_SKIP_BUILD if set to 1, clone + rosdep only (skip all builds)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROS_DISTRO="${ROS_DISTRO:-humble}"
ROSFLIGHT_SKIP_BUILD="${ROSFLIGHT_SKIP_BUILD:-0}"
VELOXITY_ROOT="${VELOXITY_ROOT:-${HOME}/Veloxity}"
VELOXITY_URL="${VELOXITY_URL:-https://github.com/magicc-safety/Veloxity.git}"

log() { printf '\n\033[1;32m[setup_workspace]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[setup_workspace]\033[0m %s\n' "$*"; }

# Repositories to clone into src/. Format: "<dir> <url> <extra-git-args>".
# Add or remove lines here to change which ROSflight packages are set up.
REPOS=(
    "rosflight_ros_pkgs https://github.com/rosflight/rosflight_ros_pkgs --recursive"
    "rosplane          https://github.com/rosflight/rosplane"
    "roscopter         https://github.com/rosflight/roscopter"
)

# --- 1. Folder structure ------------------------------------------------------
log "Ensuring workspace structure at ${WS_ROOT}"
mkdir -p "${WS_ROOT}/src"
cd "${WS_ROOT}/src"

# --- 2. Clone repos (idempotent) ---------------------------------------------
for entry in "${REPOS[@]}"; do
    # shellcheck disable=SC2086
    set -- ${entry}
    dir="$1"; url="$2"; shift 2 || true
    extra_args=("$@")
    if [ -d "${dir}/.git" ]; then
        log "Repo '${dir}' already present; skipping clone."
        # Make sure submodules (e.g. rosflight_firmware) are initialized.
        git -C "${dir}" submodule update --init --recursive || \
            warn "Could not update submodules for '${dir}'."
    else
        log "Cloning ${url} -> src/${dir}"
        git clone "${extra_args[@]}" "${url}" "${dir}"
    fi
done

# Veloxity lives in the container user's home rather than src/ so the main
# colcon invocation does not discover its nested shim before libsim is built.
if [ -d "${VELOXITY_ROOT}/.git" ]; then
    log "Repo '${VELOXITY_ROOT}' already present; skipping clone."
elif [ -e "${VELOXITY_ROOT}" ]; then
    warn "Cannot clone Veloxity: '${VELOXITY_ROOT}' exists but is not a git repository."
    exit 1
else
    log "Cloning ${VELOXITY_URL} -> ${VELOXITY_ROOT}"
    git clone "${VELOXITY_URL}" "${VELOXITY_ROOT}"
fi

cd "${WS_ROOT}"

# --- 3. Source ROS 2 ----------------------------------------------------------
if [ ! -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
    warn "ROS distro '${ROS_DISTRO}' not found at /opt/ros/${ROS_DISTRO}. Aborting build steps."
    exit 1
fi
# NOTE: the ament/colcon setup scripts read undefined variables (e.g.
# AMENT_TRACE_SETUP_FILES), so they abort under `set -u`. Disable nounset
# across the source, then restore it.
set +u
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

# --- 4. rosdep dependencies ---------------------------------------------------
log "Installing dependencies with rosdep..."
# The base image clears /var/lib/apt/lists, so apt cannot resolve any package
# name until the lists are refreshed. rosdep shells out to `apt-get install`,
# so without this it fails with "Unable to locate package ...".
sudo apt-get update
# rosdep init errors harmlessly if already initialized.
sudo rosdep init >/dev/null 2>&1 || true
rosdep update
rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" -y

# --- 5. Build -----------------------------------------------------------------
if [ "${ROSFLIGHT_SKIP_BUILD}" = "1" ]; then
    log "ROSFLIGHT_SKIP_BUILD=1 set; skipping ROSflight and Veloxity builds."
else
    log "Building the workspace with colcon (this can take several minutes)..."
    colcon build --symlink-install

    # The Veloxity ROS package is an overlay over the completed ROSflight
    # workspace. Source ROSflight before configuring that package.
    set +u
    # shellcheck disable=SC1091
    source "${WS_ROOT}/install/setup.bash"
    set -u

    if ! command -v cargo >/dev/null 2>&1; then
        warn "cargo is required to build Veloxity."
        exit 1
    fi

    log "Building the Veloxity core and simulator library..."
    (
        cd "${VELOXITY_ROOT}"
        # The current shim imports target/debug/libsim.a. Its CMake build also
        # produces the release library, so build the required debug artifact
        # first and let colcon perform the release build.
        cargo build -p veloxity_core -p sim --lib
    )

    VELOXITY_WORKSPACE="${VELOXITY_WORKSPACE:-${VELOXITY_ROOT}/workspace}"
    VELOXITY_SHIM="${VELOXITY_ROOT}/sim/ros2/veloxity_sil_board_shim"
    if [ ! -d "${VELOXITY_SHIM}" ]; then
        warn "Veloxity ROS 2 shim package not found at '${VELOXITY_SHIM}'."
        exit 1
    fi

    log "Building the Veloxity ROS 2 C-FFI shim overlay..."
    mkdir -p "${VELOXITY_WORKSPACE}"
    colcon --log-base "${VELOXITY_WORKSPACE}/log" build \
        --base-paths "${VELOXITY_SHIM}" \
        --build-base "${VELOXITY_WORKSPACE}/build" \
        --install-base "${VELOXITY_WORKSPACE}/install" \
        --packages-select veloxity_sil_board_shim

    for ext in bash zsh; do
        if [ ! -f "${VELOXITY_WORKSPACE}/install/setup.${ext}" ]; then
            warn "Veloxity overlay did not create setup.${ext}."
            exit 1
        fi
    done
fi

# --- Done ---------------------------------------------------------------------
cat <<EOF

$(log "Workspace ready.")
Next steps (from ${WS_ROOT}):
  source install/setup.bash
  source ${VELOXITY_ROOT}/workspace/install/setup.bash

Run a simulation, e.g.:
  ros2 launch veloxity_sil_board_shim multirotor_standalone_sil.launch.py use_rviz:=true
  ros2 launch rosflight_sim multirotor_standalone.launch.py            # RViz standalone sim
  ros2 launch rosflight_sim fixedwing_standalone.launch.py use_vimfly:=true
  ros2 launch rosflight_sim multirotor_gazebo.launch.py                # Gazebo Classic (Humble only)
  ros2 launch rosplane_sim sim.launch.py                               # ROSplane sim
  ros2 launch roscopter_sim sim.launch.py                              # ROScopter sim
EOF
