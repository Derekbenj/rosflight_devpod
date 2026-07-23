#!/usr/bin/env bash
#
# setup_workspace.sh — set up the ROSflight ROS 2 workspace.
#
# Creates the src/ folder structure, clones the required ROSflight repositories
# (idempotently — existing clones are left untouched), installs dependencies
# with rosdep, and builds the workspace with colcon.
#
# Usage:
#   bash scripts/setup_workspace.sh
#
# Environment variables:
#   ROS_DISTRO           ROS 2 distro to source (default: humble)
#   ROSFLIGHT_SKIP_BUILD if set to 1, clone + rosdep only (skip colcon build)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROS_DISTRO="${ROS_DISTRO:-humble}"
ROSFLIGHT_SKIP_BUILD="${ROSFLIGHT_SKIP_BUILD:-0}"

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

cd "${WS_ROOT}"

# --- 3. Source ROS 2 ----------------------------------------------------------
if [ ! -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
    warn "ROS distro '${ROS_DISTRO}' not found at /opt/ros/${ROS_DISTRO}. Aborting build steps."
    exit 1
fi
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"

# --- 4. rosdep dependencies ---------------------------------------------------
log "Installing dependencies with rosdep..."
# rosdep init errors harmlessly if already initialized.
sudo rosdep init >/dev/null 2>&1 || true
rosdep update
rosdep install --from-paths src --ignore-src -y

# --- 5. Build -----------------------------------------------------------------
if [ "${ROSFLIGHT_SKIP_BUILD}" = "1" ]; then
    log "ROSFLIGHT_SKIP_BUILD=1 set; skipping colcon build."
else
    log "Building the workspace with colcon (this can take several minutes)..."
    colcon build --symlink-install
fi

# --- Done ---------------------------------------------------------------------
cat <<EOF

$(log "Workspace ready.")
Next steps (from ${WS_ROOT}):
  source install/setup.bash

Run a simulation, e.g.:
  ros2 launch rosflight_sim multirotor_standalone.launch.py            # RViz standalone sim
  ros2 launch rosflight_sim fixedwing_standalone.launch.py use_vimfly:=true
  ros2 launch rosflight_sim multirotor_gazebo.launch.py                # Gazebo Classic (Humble only)
  ros2 launch rosplane_sim sim.launch.py                               # ROSplane sim
  ros2 launch roscopter_sim sim.launch.py                              # ROScopter sim
EOF
