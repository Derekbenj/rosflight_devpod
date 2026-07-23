#!/usr/bin/env bash
#
# postCreateCommand for the ROSflight Sim devcontainer.
#
# 1. Installs the AI coding agents (Claude Code + Codex), matching the
#    jusevitch/claude_code_devpod template.
# 2. Wires up ROS 2 + workspace sourcing for both bash and zsh.
# 3. Hands off to scripts/setup_workspace.sh to clone the ROSflight repos and
#    build the workspace.
#
# Runs as the "rosflight" user. Idempotent: safe to re-run.

set -euo pipefail

# Resolve paths. postCreateCommand runs from the workspace folder, but derive it
# from this script's location to be robust.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROS_DISTRO="${ROS_DISTRO:-humble}"

log() { printf '\n\033[1;34m[setup.sh]\033[0m %s\n' "$*"; }

# --- Node / npm global prefix -------------------------------------------------
# The node devcontainer feature installs Node via nvm under /usr/local/share/nvm.
# postCreateCommand runs before interactive shell init, so source nvm here and
# redirect the npm global prefix into $HOME to avoid permission issues.
export NVM_DIR="${NVM_DIR:-/usr/local/share/nvm}"
if [ -s "${NVM_DIR}/nvm.sh" ]; then
    # shellcheck disable=SC1091
    . "${NVM_DIR}/nvm.sh"
fi

export NPM_CONFIG_PREFIX="${HOME}/.npm-global"
mkdir -p "${NPM_CONFIG_PREFIX}/bin"
# Strip prefix/globalconfig lines that conflict with nvm, if present.
if [ -f "${HOME}/.npmrc" ]; then
    sed -i '/^prefix=/d;/^globalconfig=/d' "${HOME}/.npmrc" || true
fi
if command -v nvm >/dev/null 2>&1; then
    nvm use --delete-prefix --silent default >/dev/null 2>&1 || true
fi
export PATH="${NPM_CONFIG_PREFIX}/bin:${HOME}/.local/bin:${PATH}"

# --- Persist PATH additions for future shells --------------------------------
add_line() {
    # add_line <file> <line>: append <line> to <file> if not already present.
    local file="$1" line="$2"
    touch "${file}"
    grep -qsF -- "${line}" "${file}" || printf '%s\n' "${line}" >> "${file}"
}

for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    add_line "${rc}" 'export NPM_CONFIG_PREFIX="$HOME/.npm-global"'
    add_line "${rc}" 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"'
done

# --- Claude Code (native installer, same as the reference template) ----------
if ! command -v claude >/dev/null 2>&1; then
    log "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash || log "WARNING: Claude Code install failed (continuing)."
else
    log "Claude Code already installed; skipping."
fi

# --- Codex CLI (npm) ----------------------------------------------------------
if ! command -v codex >/dev/null 2>&1; then
    log "Installing Codex CLI..."
    npm install -g @openai/codex --loglevel=error --no-fund --no-audit \
        || log "WARNING: Codex install failed (continuing)."
else
    log "Codex CLI already installed; skipping."
fi

# --- uv (Python package/environment manager) ---------------------------------
if ! command -v uv >/dev/null 2>&1; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh || log "WARNING: uv install failed (continuing)."
    # uv installs to ~/.local/bin, which is already on PATH and persisted above.
else
    log "uv already installed; skipping."
fi
# Provide a uv-managed CPython (independent of the system/ROS Python).
if command -v uv >/dev/null 2>&1; then
    uv python install 3.12 || log "WARNING: 'uv python install 3.12' failed (continuing)."
fi

# --- Shell config: aliases + vim ---------------------------------------------
if [ -f "${SCRIPT_DIR}/.bash_aliases" ]; then
    cp "${SCRIPT_DIR}/.bash_aliases" "${HOME}/.bash_aliases"
    add_line "${HOME}/.bashrc" '[ -f "$HOME/.bash_aliases" ] && . "$HOME/.bash_aliases"'
fi

if [ ! -f "${HOME}/.vimrc" ]; then
    cat > "${HOME}/.vimrc" <<'VIMRC'
syntax on
set number
set background=dark
set tabstop=4 shiftwidth=4 expandtab
set autoindent
set splitright splitbelow
" Treat ROS launch/world files as XML
autocmd BufRead,BufNewFile *.launch,*.world set filetype=xml
VIMRC
fi

# --- ROS 2 + workspace sourcing ----------------------------------------------
# bash uses setup.bash, zsh uses setup.zsh. Guard the workspace source so shells
# don't error before the first colcon build.
setup_ros_sourcing() {
    local rc="$1" ext="$2"
    add_line "${rc}" "source /opt/ros/${ROS_DISTRO}/setup.${ext}"
    add_line "${rc}" "[ -f \"${WS_ROOT}/install/setup.${ext}\" ] && source \"${WS_ROOT}/install/setup.${ext}\""
    # Temporary fix for running ROS in Docker (matches ROSflight image).
    add_line "${rc}" "ulimit -n 1024"
}
setup_ros_sourcing "${HOME}/.bashrc" "bash"
setup_ros_sourcing "${HOME}/.zshrc" "zsh"
# ROS 2 CLI autocompletion for zsh.
add_line "${HOME}/.zshrc" 'eval "$(register-python-argcomplete3 ros2)"'
add_line "${HOME}/.zshrc" 'eval "$(register-python-argcomplete3 colcon)"'

# --- Workspace: clone repos + rosdep + colcon build --------------------------
# Non-fatal: a build failure should not abort container creation.
log "Setting up the ROSflight workspace (clone + rosdep + colcon build)..."
if bash "${WS_ROOT}/scripts/setup_workspace.sh"; then
    log "Workspace setup complete."
else
    log "WARNING: workspace setup reported an error. The container is still usable;"
    log "         re-run 'bash scripts/setup_workspace.sh' after resolving the issue."
fi

log "postCreate finished. Open a new shell (or 'source ~/.bashrc') to load ROS."
