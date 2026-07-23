# ROSflight DevPod

A [DevPod](https://devpod.sh) container for developing and running
[ROSflight](https://rosflight.org) simulations with the C firmware or the
[Veloxity](https://github.com/magicc-safety/Veloxity) Rust firmware.

## Prerequisites

Install the following:

- [Docker](https://docs.docker.com/get-docker/)
- [DevPod](https://devpod.sh/docs/getting-started/install) (CLI or desktop app)
- An X11 server on the host (standard on Linux) for GUI sim tools

Add Docker as a provider the first time you install DevPod:

```bash
devpod provider add docker
devpod provider use docker
```

## Quick start

Run the following from the project's root directory:

```bash
devpod up . --ide vscode
```

This launches VS Code over SSH into a Docker container with ROS 2, ROSflight,
and Veloxity installed. On first launch the setup clones and builds the
ROSflight workspace, then builds the Veloxity core, simulator library, and ROS
2 C-FFI shim. The first build will take several minutes. Setup fails visibly if
a required clone or build fails rather than reporting a partial installation
as ready.

If you prefer plain Docker/VS Code, this is a standard devcontainer — "Reopen in
Container" from VS Code works too.



## Running a simulation

From the workspace root (open a fresh shell so ROS is sourced, or
`source install/setup.bash`):

```bash
ros2 launch veloxity_sil_board_shim multirotor_standalone_sil.launch.py use_rviz:=true

ros2 launch rosflight_sim multirotor_standalone.launch.py             # RViz standalone
ros2 launch rosflight_sim fixedwing_standalone.launch.py use_vimfly:=true

# Gazebo Classic — Humble only:
source /usr/share/gazebo/setup.sh
ros2 launch rosflight_sim multirotor_gazebo.launch.py

ros2 launch rosplane_sim sim.launch.py     # ROSplane (fixed-wing)
ros2 launch roscopter_sim sim.launch.py    # ROScopter (multirotor)
```

If GUI windows don't appear, run the following on the **host computer** (not in the DevPod container): `xhost +local:docker`.

## Veloxity environment

Veloxity is cloned from `magicc-safety/Veloxity` into `~/Veloxity`. Its ROS 2
shim is built as an overlay under `~/Veloxity/workspace`. New bash and zsh
shells automatically source ROS 2, the ROSflight workspace, the Veloxity
overlay, and the 3D-quad and fixed-wing command helpers.

Durable airframe configuration is installed from this repository's
`config/veloxity` template into `~/.config/veloxity`. Rerunning setup preserves
an existing Veloxity checkout and all existing configuration files; it only
fills in missing files. This protects local code changes and tuned parameters.

To rebuild everything after making changes:

```bash
bash scripts/setup_workspace.sh
```

To clone and install dependencies without rebuilding either workspace:

```bash
ROSFLIGHT_SKIP_BUILD=1 bash scripts/setup_workspace.sh
```


## Troubleshooting

Frankly, just ask any capable AI agent for help. As of July 2026 this will probably be more effective than outdated instructions in this README.md. 

You can point your AI agent to the instructions on the [project website](https://docs.rosflight.org/latest/user-guide/overview/) for context.

## Changing the ROS distribution

Edit the single build arg in [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json):

```jsonc
"build": { "dockerfile": "Dockerfile", "args": { "ROS_DISTRO": "humble" } }
```

Set it to `jazzy` for ROS 2 Jazzy (Ubuntu 24.04), then rebuild the container.
**Note:** Gazebo Classic is EOL and does **not** work on Jazzy — only the
standalone (RViz) and HoloOcean sims are available there.


## Additional included features

- **Claude Code** and the **Codex CLI**
  - Run `claude` or `codex` to launch these.
- **uv**, plus a uv-managed **Python 3.12**
- **Rust** (rustup, stable toolchain)
- **GNU Screen**, **tmux**, and **Zellij**



## Layout

```
.
├── .devcontainer/   # Dockerfile, devcontainer.json, setup.sh, .bash_aliases
├── .claude/         # Claude Code settings (bypassPermissions)
├── config/veloxity/ # durable airframe configuration installed into ~/.config
├── scripts/         # setup_workspace.sh
├── src/             # ROSflight repos (cloned by the setup script; gitignored)
├── AGENTS.md        # guidance for AI coding agents
└── CLAUDE.md        # imports AGENTS.md
```
