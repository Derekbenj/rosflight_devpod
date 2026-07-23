# ROSplane fixed-wing simulation helpers for Zsh.
#
# Source this file only after the caller has sourced ROS 2 and the ROSflight
# workspace:
#   source "$HOME/.config/veloxity/airframes/fixedwing/setup.zsh"
#   source "$HOME/.config/veloxity/airframes/fixedwing/commands.zsh"
#
# These helpers support either the upstream ROSflight C endpoint or Veloxity
# without modifying any ROSflight/ROSplane files.

: "${ROSPLANE_AIRFRAME_CONFIG:=$HOME/.config/veloxity/airframes/fixedwing}"
: "${ROSPLANE_AIRCRAFT:=anaconda}"
: "${ROSPLANE_CONTROL_TYPE:=default}"
: "${ROSPLANE_FIRMWARE:=veloxity}"
: "${ROSPLANE_USE_SIM_TIME:=false}"
: "${ROSPLANE_ESTIMATOR_RHO:=-1.0}"
: "${ROSPLANE_LOG_ROOT:=$HOME/flight-logs/rosplane}"
: "${ROSPLANE_FIRMWARE_PARAMS:=}"
: "${ROSPLANE_VELOXITY_FIRMWARE_PARAMS:=$ROSPLANE_AIRFRAME_CONFIG/firmware/firmware-startup-veloxity.yaml}"
: "${ROSPLANE_C_FIRMWARE_PARAMS:=$ROSPLANE_AIRFRAME_CONFIG/firmware/firmware-startup-c.yaml}"
: "${ROSPLANE_FIRMWARE_SNAPSHOT_DIR:=$ROSPLANE_AIRFRAME_CONFIG/firmware/snapshots}"
: "${VELOXITY_PARAM_DEFINITIONS:=${VELOXITY_ROOT:-$HOME/Veloxity}/crates/veloxity_core/src/params.rs}"
: "${ROSFLIGHT_C_PARAM_DEFINITIONS:=${ROSFLIGHT_WS:-$HOME/rosflight_devpod}/src/rosflight_ros_pkgs/rosflight_firmware/src/param.cpp}"
: "${ROSPLANE_MISSION:=$ROSPLANE_AIRFRAME_CONFIG/missions/fixedwing_mission.yaml}"
: "${ROSPLANE_ROSFLIGHT_UART:=${ROSFLIGHT_UART:-/dev/ttyAMA0}}"
: "${ROSPLANE_ROSFLIGHT_USB:=${ROSFLIGHT_USB:-/dev/ttyACM0}}"
: "${ROSPLANE_ROSFLIGHT_BAUD:=${ROSFLIGHT_BAUD:-921600}}"

_p_package_share() {
  local package="$1"
  local prefix

  if ! prefix="$(ros2 pkg prefix "$package" 2>/dev/null)"; then
    printf 'ROS package is not available in the sourced environment: %s\n' \
      "$package" >&2
    return 1
  fi

  printf '%s/share/%s\n' "$prefix" "$package"
}

_p_autopilot_params() {
  local share
  local params

  share="$(_p_package_share rosplane)" || return 1
  params="$share/params/${ROSPLANE_AIRCRAFT}_autopilot_params.yaml"

  if [[ ! -r "$params" ]]; then
    printf 'Cannot read ROSplane aircraft parameters: %s\n' "$params" >&2
    return 1
  fi

  printf '%s\n' "$params"
}

_p_estimator_params() {
  local share
  local params

  share="$(_p_package_share rosplane)" || return 1
  params="$share/params/estimator.yaml"

  if [[ ! -r "$params" ]]; then
    printf 'Cannot read ROSplane estimator parameters: %s\n' "$params" >&2
    return 1
  fi

  printf '%s\n' "$params"
}

p_start_sim() {
  local firmware="$ROSPLANE_FIRMWARE"
  local -a launch_args=()

  while (( $# > 0 )); do
    case "$1" in
      --firmware)
        if (( $# < 2 )); then
          printf 'Usage: p_start_sim [--firmware veloxity|c] [LAUNCH_ARG:=VALUE ...]\n' >&2
          return 2
        fi
        firmware="$2"
        shift 2
        ;;
      --help|-h)
        printf 'Usage: p_start_sim [--firmware veloxity|c] [LAUNCH_ARG:=VALUE ...]\n'
        printf '  Default firmware: %s\n' "$ROSPLANE_FIRMWARE"
        printf '  RViz is separate; start it with p_start_sim_rviz.\n'
        return 0
        ;;
      --)
        shift
        launch_args+=("$@")
        break
        ;;
      *)
        launch_args+=("$1")
        shift
        ;;
    esac
  done

  case "$firmware" in
    veloxity|c) ;;
    *)
      printf 'Unsupported firmware backend: %s (expected veloxity or c)\n' \
        "$firmware" >&2
      return 2
      ;;
  esac

  if ! ros2 pkg prefix veloxity_sil_board_shim >/dev/null 2>&1; then
    printf 'veloxity_sil_board_shim is not available in the sourced ROS environment.\n' >&2
    return 1
  fi

  ros2 launch veloxity_sil_board_shim fixedwing_standalone_sil.launch.py \
    firmware:="$firmware" \
    use_sim_time:="$ROSPLANE_USE_SIM_TIME" \
    use_rviz:=false \
    "${launch_args[@]}"
}

p_start_uart() {
  ros2 run rosflight_io rosflight_io --ros-args \
    -p port:="$ROSPLANE_ROSFLIGHT_UART" \
    -p baud_rate:="$ROSPLANE_ROSFLIGHT_BAUD"
}

p_start_usb() {
  ros2 run rosflight_io rosflight_io --ros-args \
    -p port:="$ROSPLANE_ROSFLIGHT_USB" \
    -p baud_rate:="$ROSPLANE_ROSFLIGHT_BAUD"
}

p_start_sim_rviz() {
  ros2 launch rosflight_sim standalone_sim.launch.py \
    sim_aircraft_file:=common_resource/skyhunter.dae \
    "$@"
}

p_load_firmware_params() {
  local params

  if [[ -n "$ROSPLANE_FIRMWARE_PARAMS" ]]; then
    params="$ROSPLANE_FIRMWARE_PARAMS"
  else
    case "$ROSPLANE_FIRMWARE" in
      veloxity) params="$ROSPLANE_VELOXITY_FIRMWARE_PARAMS" ;;
      c) params="$ROSPLANE_C_FIRMWARE_PARAMS" ;;
      *)
        printf 'Unsupported ROSPLANE_FIRMWARE: %s (expected veloxity or c)\n' \
          "$ROSPLANE_FIRMWARE" >&2
        return 2
        ;;
    esac
  fi

  if [[ ! -r "$params" ]]; then
    printf 'Cannot read fixed-wing firmware parameters: %s\n' "$params" >&2
    return 1
  fi

  printf 'Loading and verifying fixed-wing firmware parameters...\n'
  _p_load_firmware_yaml "$params" "$@"
}

_p_preflight_firmware_yaml() {
  local params="$1"
  local loader="$ROSPLANE_AIRFRAME_CONFIG/verified_param_loader.py"

  if [[ ! -r "$loader" ]]; then
    printf 'Cannot read verified parameter loader: %s\n' "$loader" >&2
    return 1
  fi

  python3 "$loader" "$params" --check-only
}

_p_load_firmware_yaml() {
  local params="$1"
  local loader="$ROSPLANE_AIRFRAME_CONFIG/verified_param_loader.py"
  shift

  _p_preflight_firmware_yaml "$params" || return 1

  python3 "$loader" "$params" "$@" || return 1

  # The ROSflight fixed-wing force model can make its one startup parameter
  # request before rosflight_io has discovered the firmware parameter table.
  # Reload it only after every fixed-wing parameter has verified successfully.
  ros2 topic pub \
    --once \
    /status/params_changed \
    std_msgs/msg/Bool \
    '{data: true}'
}

p_firmware_snapshot_dir() {
  printf '%s\n' "$ROSPLANE_FIRMWARE_SNAPSHOT_DIR"
}

p_list_firmware_snapshots() {
  local snapshot_dir

  snapshot_dir="$(p_firmware_snapshot_dir)"
  if [[ ! -d "$snapshot_dir" ]]; then
    printf 'Snapshot directory does not exist: %s\n' "$snapshot_dir" >&2
    return 1
  fi

  find "$snapshot_dir" \
    -maxdepth 1 \
    -type f \
    -name '*.yaml' \
    -printf '%f\n' |
    sort
}

p_load_firmware_snapshot() {
  local requested="${1:-}"
  local snapshot_dir
  local snapshot

  snapshot_dir="$(p_firmware_snapshot_dir)"
  if [[ -z "$requested" ]]; then
    printf 'Usage: p_load_firmware_snapshot SNAPSHOT.yaml [LOADER_ARGS...]\n' >&2
    printf 'Available snapshots:\n' >&2
    p_list_firmware_snapshots >&2
    return 2
  fi

  if [[ "$requested" = /* ]]; then
    snapshot="$requested"
  else
    snapshot="$snapshot_dir/$requested"
  fi

  if [[ ! -r "$snapshot" ]]; then
    printf 'Cannot read firmware snapshot: %s\n' "$snapshot" >&2
    return 1
  fi

  shift
  printf 'Loading fixed-wing firmware snapshot:\n %s\n' "$snapshot"
  _p_load_firmware_yaml "$snapshot" "$@"
}

p_write_firmware_params() {
  local tool="$ROSPLANE_AIRFRAME_CONFIG/assured_param_io.py"

  if [[ ! -r "$tool" ]]; then
    printf 'Cannot read assured parameter tool: %s\n' "$tool" >&2
    return 1
  fi

  python3 "$tool" write "$@"
}

p_save_firmware_snapshot() {
  local tool="$ROSPLANE_AIRFRAME_CONFIG/assured_param_io.py"
  local snapshot_dir
  local destination
  local definitions

  if [[ ! -r "$tool" ]]; then
    printf 'Cannot read assured parameter tool: %s\n' "$tool" >&2
    return 1
  fi

  snapshot_dir="$(p_firmware_snapshot_dir)"
  mkdir -p "$snapshot_dir"
  destination="$snapshot_dir/firmware-$(date +%Y%m%d-%H%M%S).yaml"

  case "$ROSPLANE_FIRMWARE" in
    veloxity) definitions="$VELOXITY_PARAM_DEFINITIONS" ;;
    c) definitions="$ROSFLIGHT_C_PARAM_DEFINITIONS" ;;
    *)
      printf 'Unsupported ROSPLANE_FIRMWARE: %s (expected veloxity or c)\n' \
        "$ROSPLANE_FIRMWARE" >&2
      return 2
      ;;
  esac
  if [[ ! -r "$definitions" ]]; then
    printf 'Cannot read %s firmware parameter definitions: %s\n' \
      "$ROSPLANE_FIRMWARE" "$definitions" >&2
    return 1
  fi

  python3 "$tool" save "$destination" \
    --backend "$ROSPLANE_FIRMWARE" --definitions "$definitions" "$@"
}

p_calibrate_imu() {
  ros2 service call /calibrate_imu std_srvs/srv/Trigger '{}'
}

p_calibrate_baro() {
  ros2 service call /calibrate_baro std_srvs/srv/Trigger '{}'
}

_p_set_channel_output_mask() {
  local value="$1"
  local response
  local normalized

  response="$(ros2 service call \
    /param_set \
    rosflight_msgs/srv/ParamSet \
    "{name: 'CHN_OUTPUT_MASK', value: ${value}.0}")" || return 1
  printf '%s\n' "$response"

  normalized="${(L)response}"
  if [[ "$normalized" != *'exists=true'* && "$normalized" != *'exists: true'* ]]; then
    printf 'Firmware does not expose CHN_OUTPUT_MASK; output state was not changed.\n' >&2
    return 1
  fi
}

p_disable_motors() {
  _p_set_channel_output_mask 0
}

p_enable_motors() {
  local confirmation

  printf 'WARNING: this enables every physical output channel. Type yes to continue: '
  IFS= read -r confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    printf 'Output channels remain disabled.\n' >&2
    return 1
  fi

  _p_set_channel_output_mask -1
}

p_toggle_sim_arm() {
  ros2 service call /toggle_arm std_srvs/srv/Trigger '{}'
}

p_toggle_sim_override() {
  ros2 service call /toggle_override std_srvs/srv/Trigger '{}'
}

p_start_estimator() {
  local params

  params="$(_p_estimator_params)" || return 1

  ros2 run rosplane estimator --ros-args \
    -r __node:=estimator \
    --params-file "$params" \
    -p rho:="$ROSPLANE_ESTIMATOR_RHO" \
    -p use_sim_time:="$ROSPLANE_USE_SIM_TIME"
}

p_start_truth() {
  ros2 run rosplane_sim sim_state_transcriber --ros-args \
    -r __node:=rosplane_truth \
    -p use_sim_time:="$ROSPLANE_USE_SIM_TIME"
}

p_start_path_planner() {
  ros2 run rosplane path_planner --ros-args \
    -r __node:=path_planner \
    -p use_sim_time:="$ROSPLANE_USE_SIM_TIME"
}

p_start_path_manager() {
  local params

  params="$(_p_autopilot_params)" || return 1

  ros2 run rosplane path_manager --ros-args \
    -r __node:=path_manager \
    --params-file "$params" \
    -p use_sim_time:="$ROSPLANE_USE_SIM_TIME"
}

p_start_path_follower() {
  local params

  params="$(_p_autopilot_params)" || return 1

  ros2 run rosplane path_follower --ros-args \
    -r __node:=path_follower \
    --params-file "$params" \
    -p use_sim_time:="$ROSPLANE_USE_SIM_TIME"
}

p_start_controller() {
  local params

  params="$(_p_autopilot_params)" || return 1

  ros2 run rosplane controller "$ROSPLANE_CONTROL_TYPE" --ros-args \
    -r __node:=controller \
    --params-file "$params" \
    -p use_sim_time:="$ROSPLANE_USE_SIM_TIME"
}

p_start_gcs() {
  p_start_waypoint_viz
}

p_start_hardware_gcs() {
  ros2 launch rosplane_gcs rosplane_gcs.launch.py
}

p_start_waypoint_viz() {
  # p_start_sim_rviz starts RViz and the standalone visualization transcriber.
  # This command adds ROSplane waypoint markers. The waypoint publisher also
  # emits its own aircraft mesh and TF, so isolate those outputs to avoid
  # competing with standalone_viz_transcriber.
  ros2 run rosplane_gcs rviz_waypoint_publisher --ros-args \
    -r __node:=rosplane_waypoint_publisher \
    -r /rviz/mesh:=/rosplane_waypoint_viz/mesh \
    -r /rviz/mesh_path:=/rosplane_waypoint_viz/mesh_path \
    -r /tf:=/rosplane_waypoint_viz/tf
}

p_load_mission() {
  local mission="${1:-${ROSPLANE_MISSION:-}}"

  if [[ -z "$mission" ]]; then
    printf 'Usage: p_load_mission MISSION.yaml\n' >&2
    printf 'Alternatively set ROSPLANE_MISSION to a readable mission file.\n' >&2
    return 2
  fi

  if [[ ! -r "$mission" ]]; then
    printf 'Cannot read ROSplane mission: %s\n' "$mission" >&2
    return 1
  fi

  ros2 service call \
    /load_mission_from_file \
    rosflight_msgs/srv/ParamFile \
    "{filename: '$mission'}"
}

p_publish_next_waypoint() {
  ros2 service call \
    /publish_next_waypoint \
    std_srvs/srv/Trigger \
    '{}'
}

p_clear_waypoints() {
  ros2 service call \
    /clear_waypoints \
    std_srvs/srv/Trigger \
    '{}'
}

p_print_waypoints() {
  ros2 service call \
    /print_waypoints \
    std_srvs/srv/Trigger \
    '{}'
}

p_show_status() {
  ros2 topic echo /status --once
}

p_start_bag() {
  mkdir -p "$ROSPLANE_LOG_ROOT"

  ros2 bag record -a \
    -o "$ROSPLANE_LOG_ROOT/rosplane_$(date +%Y%m%d-%H%M%S)"
}

p_start_screen() {
  local session="${1:-veloxity-plane}"
  local window
  local interactive_shell
  local -a windows=(
    estimator
    truth
    path_planner
    path_manager
    path_follower
    controller
    gcs
    commands
  )

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    interactive_shell="zsh"
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    interactive_shell="bash"
  else
    interactive_shell="${SHELL:-/bin/bash}"
  fi

  if ! command -v screen >/dev/null 2>&1; then
    printf 'GNU Screen is not installed. Install it before using p_start_screen.\n' >&2
    return 1
  fi

  if screen -list 2>/dev/null | grep -q "[.]${session}[[:space:]]"; then
    printf 'A screen session named %s already exists.\n' "$session" >&2
    printf 'Attach with: screen -r %s\n' "$session" >&2
    return 1
  fi

  screen -dmS "$session" -t firmware \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1

  # Give the detached server time to create its socket before adding windows.
  sleep 0.5

  for window in "${windows[@]}"; do
    screen -S "$session" -X screen -t "$window" \
      env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  done

  screen -S "$session" -X caption always \
    '%{= kG} ROSplane %{= kw}| %n:%t %{= kG}| Ctrl-a " windows | Ctrl-a d detach'
  screen -S "$session" -X select 0

  printf 'Started detached Screen session %s.\n' "$session"
  printf 'Attach with: screen -r %s\n' "$session"
  printf 'Recommended order: firmware, commands (load/calibrate), estimator, truth (simulation only), path_planner, path_manager, path_follower, controller.\n'
  printf 'Inside Screen: Ctrl-a then " lists windows; Ctrl-a d detaches.\n'
}

p_help() {
  printf '%s\n' \
    'ROSplane fixed-wing simulation commands:' \
    '  p_start_screen [SESSION]       create named interactive Screen windows' \
    '  p_start_sim [--firmware veloxity|c] [LAUNCH_ARGS...]' \
    '                                  start fixed-wing physics, firmware, I/O, and RC' \
    '  p_start_sim_rviz [LAUNCH_ARGS...]' \
    '                                  start the fixed-wing RViz visualization separately' \
    '  p_start_uart                   connect rosflight_io to Pixracer Pro over UART' \
    '  p_start_usb                    connect rosflight_io to Pixracer Pro over USB VCP' \
    '  p_load_firmware_params [LOADER_ARGS...]' \
    '                                  syntax-check, load, and verify fixed-wing parameters' \
    '  p_write_firmware_params        backend write request; not durable on Veloxity Pixracer' \
    '  p_save_firmware_snapshot       independently read/write/verify every source-defined parameter' \
    '  p_list_firmware_snapshots      list saved fixed-wing firmware snapshots' \
    '  p_load_firmware_snapshot FILE  syntax-check, load, and verify a firmware snapshot' \
    '  p_start_estimator              start the ROSplane estimator' \
    '  p_start_truth                  transcribe simulator truth for ROSplane' \
    '  p_start_path_planner           start the waypoint planner' \
    '  p_start_path_manager           start the fixed-wing path manager' \
    '  p_start_path_follower          start the fixed-wing path follower' \
    '  p_start_controller             start the fixed-wing controller' \
    '  p_start_waypoint_viz           publish waypoints in the simulator RViz' \
    '  p_start_gcs                    alias for p_start_waypoint_viz' \
    '  p_start_hardware_gcs           start the complete ROSplane hardware GCS/RViz launch' \
    '  p_load_mission FILE            load a ROSplane mission YAML' \
    '  p_publish_next_waypoint        publish the next loaded waypoint' \
    '  p_clear_waypoints              clear the planner waypoint list' \
    '  p_print_waypoints              print the planner waypoint list' \
    '  p_calibrate_imu                call the firmware IMU calibration service' \
    '  p_calibrate_baro               call the firmware barometer calibration service' \
    '  p_disable_motors               immediately disable every physical output channel' \
    '  p_enable_motors                enable every output channel after typing exact "yes"' \
    '  p_toggle_sim_override          toggle simulated-RC pilot override' \
    '  p_toggle_sim_arm               toggle the simulated-RC arm switch' \
    '  p_show_status                  print one ROSflight status message' \
    '  p_start_bag                    record all ROS topics under ROSPLANE_LOG_ROOT' \
    '' \
    'Configuration variables:' \
    '  ROSPLANE_AIRFRAME_CONFIG       fixed-wing configuration directory' \
    '  ROSPLANE_AIRCRAFT              aircraft params basename (default: anaconda)' \
    '  ROSPLANE_CONTROL_TYPE          controller implementation (default: default)' \
    '  ROSPLANE_FIRMWARE              veloxity or c (default: veloxity)' \
    '  ROSPLANE_USE_SIM_TIME          true or false (default: false)' \
    '  ROSPLANE_ESTIMATOR_RHO         density override; negative uses local calculation' \
    '  ROSPLANE_MISSION               optional default mission YAML path' \
    '  ROSPLANE_LOG_ROOT              bag output directory' \
    '  ROSPLANE_FIRMWARE_PARAMS       optional YAML override; empty selects the backend-local file' \
    '  ROSPLANE_VELOXITY_FIRMWARE_PARAMS firmware-startup-veloxity.yaml' \
    '  ROSPLANE_C_FIRMWARE_PARAMS     firmware-startup-c.yaml' \
    '  ROSPLANE_FIRMWARE_SNAPSHOT_DIR fixed-wing firmware snapshot directory' \
    '  VELOXITY_PARAM_DEFINITIONS     authoritative Veloxity params.rs for snapshot schema' \
    '  ROSFLIGHT_C_PARAM_DEFINITIONS  authoritative C param.cpp for snapshot schema' \
    '  ROSPLANE_ROSFLIGHT_UART        Pixracer UART device (default: /dev/ttyAMA0)' \
    '  ROSPLANE_ROSFLIGHT_USB         Pixracer USB VCP device (default: /dev/ttyACM0)' \
    '  ROSPLANE_ROSFLIGHT_BAUD        transport baud rate (default: 921600)' \
    '  Snapshot assumption            selected definition source matches the running firmware build' \
    '' \
    'Fixed-wing startup YAML difference:' \
    '  Both files contain the same 16 shared fixed-wing settings.' \
    '  Veloxity adds CHN_OUTPUT_MASK=0 so every output starts disabled.' \
    '  C omits it because upstream C firmware does not expose that parameter.' \
    '' \
    'Fresh simulated-RC autonomous handoff:' \
    '  p_toggle_sim_arm               arm while override is initially enabled' \
    '  p_toggle_sim_override          then release override to ROSplane' \
    '' \
    'ROSplane simulation opening order:' \
    '  1. p_start_screen; attach with: screen -r veloxity-plane' \
    '  2. firmware: p_start_sim' \
    '  3. Separate shell: p_start_sim_rviz' \
    '  4. commands: p_load_firmware_params OR p_load_firmware_snapshot FILE' \
    '  5. commands: p_calibrate_imu; p_calibrate_baro; p_show_status' \
    '  6. Optional: p_save_firmware_snapshot writes and verifies YAML without rosflight_io file I/O.' \
    '  7. Start estimator, truth, planner, manager, follower, and controller in their like-named windows.' \
    '  8. gcs: p_start_waypoint_viz' \
    '  9. commands: p_load_mission FILE; p_print_waypoints; separate shell: p_start_bag' \
    ' 10. Arm under RC override, verify status/commands, then release override.' \
    '     With simulated RC use p_toggle_sim_arm then p_toggle_sim_override;' \
    '     with a detected USB transmitter use its mapped arm and override switches.' \
    '     setup.zsh exports the Veloxity default; set ROSPLANE_FIRMWARE=c before setup only for C.' \
    '' \
    'Pixracer Pro / ROSplane fixed-wing hardware opening order:' \
    '  1. Flash reviewed fixed-wing firmware; keep the aircraft disarmed with physical RC override active.' \
    '  2. Set ROSPLANE_FIRMWARE_PARAMS to the reviewed hardware YAML, then run p_start_screen.' \
    '  3. firmware: p_start_uart OR p_start_usb -- never both.' \
    '  4. commands: p_load_firmware_params OR p_load_firmware_snapshot FILE; calibrate as required.' \
    '  5. Optional: p_save_firmware_snapshot writes and verifies YAML without rosflight_io file I/O.' \
    '  6. Start estimator, planner, manager, follower, and controller; do not start p_start_truth.' \
    '  7. gcs: p_start_hardware_gcs' \
    '  8. Load/print the approved mission, verify status and command bounds, and start a bag separately.' \
    '  9. Arm with physical override held, wait for estimator/barometer initialization, then release override.'
}
