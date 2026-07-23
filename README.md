# ROSflight Sim DevPod

A [DevPod](https://devpod.sh) container for developing and running
[ROSflight](https://rosflight.org) simulations, with the **Claude Code** and
**Codex** AI coding agents preinstalled. It is modeled on the
[`jusevitch/claude_code_devpod`](https://github.com/jusevitch/claude_code_devpod)
template and built on ROSflight's official Docker base image
(`osrf/ros:${ROS_DISTRO}-desktop`, default **Humble**).

`devpod up` gives you a container that:

- Builds on the ROSflight base image with `ros-dev-tools`, `plotjuggler`, `colcon`, `rosdep`
- Installs Claude Code + Codex (like the reference template)
- Clones the ROSflight repos, resolves dependencies with `rosdep`, and builds the workspace
- Forwards X11 so RViz / Gazebo / PlotJuggler display on your host

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [DevPod](https://devpod.sh/docs/getting-started/install) (CLI or desktop app)
- An X11 server on the host (standard on Linux) for GUI sim tools

## Quick start

```bash
# One-time: register Docker as a DevPod provider
devpod provider add docker
devpod provider use docker

# From this repo's root:
devpod up . --ide vscode
```

On first launch the container image is built and `postCreateCommand` runs
`.devcontainer/setup.sh`, which installs the agents and then runs
`scripts/setup_workspace.sh` (clone → `rosdep` → `colcon build`). **The first
build takes several minutes.** Build failures are reported but do not abort
container creation.

If you prefer plain Docker/VS Code, this is a standard devcontainer — "Reopen in
Container" from VS Code works too.

## Running the agents

Inside the container:

```bash
claude          # Claude Code (permissions are pre-bypassed in this container)
codex           # Codex CLI  (use `codex --yolo` for no approval prompts)
```

You authenticate the agents interactively on first use — no API keys are stored
in this repo.

## Running a simulation

From the workspace root (open a fresh shell so ROS is sourced, or
`source install/setup.bash`):

```bash
ros2 launch rosflight_sim multirotor_standalone.launch.py             # RViz standalone
ros2 launch rosflight_sim fixedwing_standalone.launch.py use_vimfly:=true

# Gazebo Classic — Humble only:
source /usr/share/gazebo/setup.sh
ros2 launch rosflight_sim multirotor_gazebo.launch.py

ros2 launch rosplane_sim sim.launch.py     # ROSplane (fixed-wing)
ros2 launch roscopter_sim sim.launch.py    # ROScopter (multirotor)
```

If GUI windows don't appear, run on the **host**: `xhost +local:docker`.

## Manually (re)building the workspace

The setup script is idempotent — existing clones are left in place:

```bash
bash scripts/setup_workspace.sh                 # clone + rosdep + colcon build
ROSFLIGHT_SKIP_BUILD=1 bash scripts/setup_workspace.sh   # clone + rosdep only
```

## Changing the ROS distribution

Edit the single build arg in [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json):

```jsonc
"build": { "dockerfile": "Dockerfile", "args": { "ROS_DISTRO": "humble" } }
```

Set it to `jazzy` for ROS 2 Jazzy (Ubuntu 24.04), then rebuild the container.
**Note:** Gazebo Classic is EOL and does **not** work on Jazzy — only the
standalone (RViz) and HoloOcean sims are available there.

## Connecting real hardware (optional)

This template is simulation-focused, so it does **not** run privileged or bind
`/dev`. To use a physical flight controller, add to
`.devcontainer/devcontainer.json`:

```jsonc
"runArgs": ["--network=host", "--ipc=host", "--privileged"],
"mounts": [
    "source=/tmp/.X11-unix,target=/tmp/.X11-unix,type=bind",
    "source=/dev,target=/dev,type=bind"
]
```

`--privileged` grants broad host access — enable it only when you need it.

## Security notes

- `.claude/settings.json` sets `defaultMode: bypassPermissions`, so Claude Code
  acts without approval prompts. This is intended for a disposable container; if
  you'd rather be prompted, remove that setting.
- `--network=host` / `--ipc=host` assume a **local Docker** provider. Remote
  DevPod providers may not support host networking or GUI forwarding.

## Layout

```
.
├── .devcontainer/   # Dockerfile, devcontainer.json, setup.sh, .bash_aliases
├── .claude/         # Claude Code settings (bypassPermissions)
├── scripts/         # setup_workspace.sh
├── src/             # ROSflight repos (cloned by the setup script; gitignored)
├── AGENTS.md        # guidance for AI coding agents
└── CLAUDE.md        # imports AGENTS.md
```
