v_start_uart() {
  ros2 run rosflight_io rosflight_io --ros-args \
    -p port:="$ROSFLIGHT_UART" \
    -p baud_rate:="$ROSFLIGHT_BAUD"
}

v_start_usb() {
  ros2 run rosflight_io rosflight_io --ros-args \
    -p port:="$ROSFLIGHT_USB" \
    -p baud_rate:="$ROSFLIGHT_BAUD"
}

v_write_firmware_params() {
  local tool="$AIRFRAME_CONFIG/assured_param_io.py"

  if [[ ! -r "$tool" ]]; then
    printf 'Cannot read assured parameter tool: %s\n' "$tool" >&2
    return 1
  fi

  python3 "$tool" write "$@"
}

v_load_firmware_params() {
  local loader="$AIRFRAME_CONFIG/verified_param_loader.py"
  local params

  if [[ -n "$FIRMWARE_PARAMS" ]]; then
    params="$FIRMWARE_PARAMS"
  else
    case "$VELOXITY_FIRMWARE" in
      veloxity) params="$VELOXITY_FIRMWARE_PARAMS" ;;
      c) params="$C_FIRMWARE_PARAMS" ;;
      *)
        printf 'Unsupported VELOXITY_FIRMWARE: %s (expected veloxity or c)\n' \
          "$VELOXITY_FIRMWARE" >&2
        return 2
        ;;
    esac
  fi

  if [[ ! -r "$params" ]]; then
    printf 'Cannot read firmware parameter file: %s\n' \
      "$params" >&2
    return 1
  fi

  if [[ ! -r "$loader" ]]; then
    printf 'Cannot read verified parameter loader: %s\n' \
      "$loader" >&2
    return 1
  fi

  python3 "$loader" "$params" --check-only || return 1
  python3 "$loader" "$params" "$@"
}

v_calibrate_imu() {
  ros2 service call /calibrate_imu std_srvs/srv/Trigger '{}'
}

v_calibrate_baro() {
  ros2 service call /calibrate_baro std_srvs/srv/Trigger '{}'
}

_v_set_channel_output_mask() {
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

v_disable_motors() {
  _v_set_channel_output_mask 0
}

v_enable_motors() {
  local confirmation

  printf 'WARNING: this enables every physical output channel. Type yes to continue: '
  IFS= read -r confirmation
  if [[ "$confirmation" != 'yes' ]]; then
    printf 'Output channels remain disabled.\n' >&2
    return 1
  fi

  _v_set_channel_output_mask -1
}

v_mode_rate() {
  ros2 service call \
    /param_set \
    rosflight_msgs/srv/ParamSet \
    "{name: 'RC_ATT_MODE', value: 0.0}"
}

v_mode_angle() {
  ros2 service call \
    /param_set \
    rosflight_msgs/srv/ParamSet \
    "{name: 'RC_ATT_MODE', value: 1.0}"
}

v_save_firmware_snapshot() {
  local tool="$AIRFRAME_CONFIG/assured_param_io.py"
  local snapshot_dir
  local destination
  local definitions

  if [[ ! -r "$tool" ]]; then
    printf 'Cannot read assured parameter tool: %s\n' "$tool" >&2
    return 1
  fi

  snapshot_dir="$(v_firmware_snapshot_dir)"
  mkdir -p "$snapshot_dir"

  destination="$snapshot_dir/firmware-$(date +%Y%m%d-%H%M%S).yaml"

  case "$VELOXITY_FIRMWARE" in
    veloxity) definitions="$VELOXITY_PARAM_DEFINITIONS" ;;
    c) definitions="$ROSFLIGHT_C_PARAM_DEFINITIONS" ;;
    *)
      printf 'Unsupported VELOXITY_FIRMWARE: %s (expected veloxity or c)\n' \
        "$VELOXITY_FIRMWARE" >&2
      return 2
      ;;
  esac
  if [[ ! -r "$definitions" ]]; then
    printf 'Cannot read %s firmware parameter definitions: %s\n' \
      "$VELOXITY_FIRMWARE" "$definitions" >&2
    return 1
  fi

  python3 "$tool" save "$destination" \
    --backend "$VELOXITY_FIRMWARE" --definitions "$definitions" "$@"
}

v_toggle_sim_arm() {
  ros2 service call /toggle_arm std_srvs/srv/Trigger '{}'
}

v_toggle_sim_override() {
  ros2 service call /toggle_override std_srvs/srv/Trigger '{}'
}

v_firmware_snapshot_dir() {
  printf '%s\n' "$AIRFRAME_CONFIG/firmware/snapshots"
}

v_list_firmware_snapshots() {
  local snapshot_dir
  
  snapshot_dir="$(v_firmware_snapshot_dir)"

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

v_load_firmware_snapshot() {
  local loader="$AIRFRAME_CONFIG/verified_param_loader.py"
  local requested="${1:-}"
  local snapshot_dir
  local snapshot

  snapshot_dir="$(v_firmware_snapshot_dir)"

  if [[ -z "$requested" ]]; then
    printf 'Usage: v_load_firmware_snapshot SNAPSHOT.yaml\n' >&2
    printf 'Available snapshots:\n' >&2
    v_list_firmware_snapshots >&2
    return 2
  fi

  # Accept either an absolute path or a filename from the snapshot directory.
  if [[ "$requested" = /* ]]; then
    snapshot="$requested"
  else
    snapshot="$snapshot_dir/$requested"
  fi

  if [[ ! -r "$snapshot" ]]; then
    printf 'Cannot read firmware snapshot: %s\n' "$snapshot" >&2
    return 1
  fi

  if [[ ! -r "$loader" ]]; then
    printf 'Cannot read verified parameter loader: %s\n' \
      "$loader" >&2
    return 1
  fi

  shift

  printf 'Loading firmware snapshot into running firmware:\n %s\n' "$snapshot"

  python3 "$loader" "$snapshot" --check-only || return 1
  python3 "$loader" "$snapshot" "$@"
}

v_load_mission() {
  if [[ ! -r "$MISSION" ]]; then
    printf 'Cannot read mission: %s\n' "$MISSION" >&2
    return 1
  fi

  ros2 service call \
    /path_planner/load_mission_from_file \
    rosflight_msgs/srv/ParamFile \
    "{filename: '$MISSION'}"
}

v_show_status() {
  ros2 topic echo /status --once
}

v_start_bag() {
  mkdir -p "$FLIGHT_LOG_ROOT"

  ros2 bag record -a \
    -o "$FLIGHT_LOG_ROOT/hardware_exp2_$(date +%Y%m%d-%H%M%S)"
}

# ------------------------------------------------------------------------------------------------------------------

v_start_estimator() {
  ros2 run roscopter estimator --ros-args \
    -r __node:=estimator \
    --params-file "$ESTIMATOR" \
    --params-file "$ESTIMATOR_HW"
}

v_start_path_manager() {
  ros2 run roscopter path_manager --ros-args \
    -r __node:=path_manager \
    --params-file "$MULTIROTOR" \
    --params-file "$EXPERIMENT" \
    -r estimated_state:=estimated_state
}

v_start_path_planner() {
  ros2 run roscopter path_planner --ros-args \
    -r __node:=path_planner \
    --params-file "$MULTIROTOR" \
    -r estimated_state:=estimated_state
}

v_start_velocity_adapter() {
  python3 \
    "$VELOXITY_ROOT/examples/quadx_upstream_angle_waypoints/trajectory_velocity_adapter.py" \
    --ros-args \
    --params-file "$EXPERIMENT"
}

v_start_trajectory_follower() {
  ros2 run roscopter trajectory_follower --ros-args \
    -r __node:=trajectory_follower \
    --params-file "$MULTIROTOR" \
    --params-file "$EXPERIMENT" \
    -r estimated_state:=estimated_state \
    -r trajectory_command:=trajectory_command_compensated \
    -r high_level_command:=high_level_command_thrust
}

v_start_throttle_adapter() {
  python3 \
    "$VELOXITY_ROOT/examples/quadx_upstream_angle_waypoints/thrust_to_throttle_adapter.py" \
    --ros-args \
    --params-file "$MULTIROTOR" \
    --params-file "$EXPERIMENT"
}

v_start_controller() {
  ros2 run roscopter controller --ros-args \
    -r __node:=controller \
    --params-file "$MULTIROTOR" \
    --params-file "$EXPERIMENT" \
    -r estimated_state:=estimated_state
}

v_start_waypoint_viz() {
  ros2 run roscopter_gcs rviz_waypoint_publisher "$@"
}

v_start_gcs() {
  v_start_waypoint_viz "$@"
}

v_start_screen() {
  local session="${1:-veloxity-autonomy}"
  local interactive_shell

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    interactive_shell="zsh"
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    interactive_shell="bash"
  else
    interactive_shell="${SHELL:-/bin/bash}"
  fi

  if ! command -v screen >/dev/null 2>&1; then
    printf 'GNU screen is not installed. Install it before using %s.\n' \
      "v_start_screen" >&2
    return 1
  fi

  if screen -list 2>/dev/null | grep -q "[.]${session}[[:space:]]"; then
    printf 'A screen session named %s already exists.\n' "$session" >&2
    printf 'Attach with: screen -r %s\n' "$session" >&2
    return 1
  fi

  screen -dmS "$session" -t firmware \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i
  # The detached screen server needs a moment to create its control socket.
  # Do not use `screen -Q` as a readiness probe here: during startup it can
  # leave the caller's terminal in raw mode if the query blocks.
  sleep 0.5

  screen -S "$session" -X screen -t estimator \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t path_manager \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t path_planner \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t velocity_adapter \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t trajectory_follower \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t throttle_adapter \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t controller \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t gcs \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1
  screen -S "$session" -X screen -t commands \
    env DISABLE_AUTO_TITLE=true "$interactive_shell" -i || return 1

  screen -S "$session" -X caption always \
    '%{= kG} Veloxity %{= kw}| %n:%t %{= kG}| Ctrl-a " windows | Ctrl-a d detach'
  screen -S "$session" -X select 0

  printf 'Started detached screen session %s.\n' "$session"
  printf 'Attach with: screen -r %s\n' "$session"
  printf 'Inside screen: Ctrl-a then " lists windows; Ctrl-a d detaches.\n'
}

v_print_mission() {
  ros2 service call \
    /path_planner/print_waypoints \
    std_srvs/srv/Trigger \
    '{}'

  ros2 service call \
    /path_manager/print_waypoints \
    std_srvs/srv/Trigger \
    '{}'
}

v_help() {
  printf '%s\n' \
    'Veloxity quadrotor commands:' \
    '  v_start_screen [SESSION]       create named interactive Screen windows' \
    '  v_start_sim [--firmware veloxity|c] [--sim-rc]' \
    '                                  start multirotor physics, firmware, I/O, and RC' \
    '  v_start_sim_rviz               start the multirotor RViz visualization separately' \
    '  v_start_uart                   connect rosflight_io to Pixracer Pro over UART' \
    '  v_start_usb                    connect rosflight_io to Pixracer Pro over USB VCP' \
    '  v_load_firmware_params [ARGS]  syntax-check, load, and verify airframe parameters' \
    '  v_write_firmware_params [ARGS] backend write request; not durable on Veloxity Pixracer' \
    '  v_calibrate_imu                call the firmware IMU calibration service' \
    '  v_calibrate_baro               call the firmware barometer calibration service' \
    '  v_disable_motors               immediately disable every physical output channel' \
    '  v_enable_motors                enable every output channel after typing exact "yes"' \
    '  v_mode_rate                    select firmware RC rate mode' \
    '  v_mode_angle                   select firmware RC angle mode' \
    '  v_save_firmware_snapshot       independently read/write/verify every source-defined parameter' \
    '  v_list_firmware_snapshots      list saved firmware parameter snapshots' \
    '  v_load_firmware_snapshot FILE  syntax-check, load, and verify a saved snapshot' \
    '  v_start_estimator              start the ROScopter estimator' \
    '  v_start_path_manager           start the ROScopter path manager' \
    '  v_start_path_planner           start the ROScopter path planner' \
    '  v_start_velocity_adapter       add trajectory velocity feed-forward' \
    '  v_start_trajectory_follower    start the remapped trajectory follower' \
    '  v_start_throttle_adapter       convert requested thrust to firmware throttle' \
    '  v_start_controller             start the ROScopter controller' \
    '  v_start_waypoint_viz           publish ROScopter waypoint markers for RViz' \
    '  v_start_gcs                    alias for v_start_waypoint_viz' \
    '  v_load_mission                 load the configured MISSION file' \
    '  v_print_mission                print planner and manager waypoint lists' \
    '  v_show_status                  print one ROSflight status message' \
    '  v_start_bag                    record all ROS topics under FLIGHT_LOG_ROOT' \
    '' \
    'Configuration variables:' \
    '  VELOXITY_FIRMWARE              veloxity or c (default: veloxity)' \
    '  VELOXITY_PARAM_DEFINITIONS     authoritative Veloxity params.rs for snapshot schema' \
    '  ROSFLIGHT_C_PARAM_DEFINITIONS  authoritative C param.cpp for snapshot schema' \
    '  FIRMWARE_PARAMS                optional YAML override; empty selects the backend-local file' \
    '  VELOXITY_FIRMWARE_PARAMS       firmware-startup-veloxity.yaml' \
    '  C_FIRMWARE_PARAMS              firmware-startup-c.yaml' \
    '  EXPERIMENT                     adapter/controller experiment YAML' \
    '  ESTIMATOR_HW                   hardware estimator overrides' \
    '  MISSION                        mission YAML loaded by v_load_mission' \
    '  ROSFLIGHT_UART                 UART device (default: /dev/ttyAMA0)' \
    '  ROSFLIGHT_USB                  USB VCP device (default: /dev/ttyACM0)' \
    '  ROSFLIGHT_BAUD                 transport baud rate (default: 921600)' \
    '  FLIGHT_LOG_ROOT                bag and experiment log directory' \
    '  Snapshot directory             AIRFRAME_CONFIG/firmware/snapshots' \
    '  Snapshot assumption            selected definition source matches the running firmware build' \
    '' \
    '3dquad startup YAML difference:' \
    '  Both files contain the same 110 shared quadrotor settings.' \
    '  Veloxity adds CHN_OUTPUT_MASK=0 so every output starts disabled.' \
    '  C omits it because upstream C firmware does not expose that parameter.' \
    '' \
    'Quad simulation opening order:' \
    '  1. v_start_screen; attach with: screen -r veloxity-autonomy' \
    '  2. firmware: v_start_sim [--sim-rc]' \
    '  3. Separate shell: v_start_sim_rviz' \
    '  4. commands: v_load_firmware_params OR v_load_firmware_snapshot FILE' \
    '  5. commands: v_calibrate_imu; v_calibrate_baro; v_show_status' \
    '  6. Optional: v_save_firmware_snapshot writes and verifies YAML without rosflight_io file I/O.' \
    '  7. Start the like-named estimator, manager, planner, adapters, follower, and controller windows.' \
    '  8. gcs: v_start_waypoint_viz' \
    '  9. commands: v_load_mission; v_print_mission; separate shell: v_start_bag' \
    ' 10. Arm under RC override, verify status/commands, then release override.' \
    '     setup.zsh exports the Veloxity default; set VELOXITY_FIRMWARE=c before setup only for C.' \
    '' \
    'Pixracer Pro hardware opening order:' \
    '  1. Keep the vehicle disarmed with physical RC override active; firmware must already be flashed.' \
    '  2. v_start_screen; attach with: screen -r veloxity-autonomy' \
    '  3. firmware: v_start_uart OR v_start_usb -- never both.' \
    '  4. commands: v_load_firmware_params OR v_load_firmware_snapshot FILE; calibrate as required.' \
    '  5. Optional: v_save_firmware_snapshot writes and verifies YAML without rosflight_io file I/O.' \
    '  6. Start estimator, manager, planner, velocity adapter, follower, throttle adapter, and controller.' \
    '  7. gcs: v_start_waypoint_viz; open the desired RViz separately.' \
    '  8. commands: v_load_mission; v_print_mission; v_show_status; separate shell: v_start_bag' \
    '  9. Arm with physical override held, wait for estimator/barometer initialization, validate /command, then release override.'
}

v_start_sim() {
  local firmware="$VELOXITY_FIRMWARE"
  local force_sim_rc="false"

  while (( $# > 0 )); do
    case "$1" in
      --firmware)
        if (( $# < 2 )); then
          printf 'Usage: v_start_sim [--firmware veloxity|c] [--sim-rc]\n' >&2
          return 2
        fi
        firmware="$2"
        shift 2
        ;;
      --sim-rc)
        force_sim_rc="true"
        shift
        ;;
      --help|-h)
        printf 'Usage: v_start_sim [--firmware veloxity|c] [--sim-rc]\n'
        printf '  Default RC behavior: use a supported USB joystick if detected; otherwise use simulated RC.\n'
        printf '  --sim-rc: force the service-controlled simulated RC even when a USB joystick is present.\n'
        return 0
        ;;
      *)
        printf 'Unknown v_start_sim argument: %s\n' "$1" >&2
        printf 'Usage: v_start_sim [--firmware veloxity|c] [--sim-rc]\n' >&2
        return 2
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

  if [[ "$force_sim_rc" == "true" ]]; then
    # rc.py treats a pygame display/joystick initialization failure as the
    # signal to use its service-controlled simulated RC implementation.
    SDL_VIDEODRIVER=veloxity_force_simulated_rc \
      ros2 launch veloxity_sil_board_shim multirotor_standalone_sil.launch.py \
        firmware:="$firmware" \
        use_builtin_rc:=true \
        use_rviz:=false
  else
    ros2 launch veloxity_sil_board_shim multirotor_standalone_sil.launch.py \
      firmware:="$firmware" \
      use_builtin_rc:=true \
      use_rviz:=false
  fi
}

v_start_sim_rviz() {
  ros2 launch rosflight_sim standalone_sim.launch.py \
    sim_aircraft_file:=common_resource/multirotor.dae
}
