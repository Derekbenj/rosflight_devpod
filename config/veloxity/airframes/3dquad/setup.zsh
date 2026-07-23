# Workspace locations are exported by the DevPod shell setup. Keep portable
# defaults so these files can also be reused outside the container.
: "${VELOXITY_ROOT:=$HOME/Veloxity}"
: "${ROSFLIGHT_WS:=$HOME/rosflight_devpod}"
export VELOXITY_ROOT
export ROSFLIGHT_WS
export VELOXITY_FIRMWARE="${VELOXITY_FIRMWARE:-veloxity}"
export VELOXITY_PARAM_DEFINITIONS="$VELOXITY_ROOT/crates/veloxity_core/src/params.rs"
export ROSFLIGHT_C_PARAM_DEFINITIONS="$ROSFLIGHT_WS/src/rosflight_ros_pkgs/rosflight_firmware/src/param.cpp"

# Discover installed ROScopter files
export ROSCOPTER_SHARE="$(ros2 pkg prefix roscopter)/share/roscopter"
export MULTIROTOR="$ROSCOPTER_SHARE/params/multirotor.yaml"
export ESTIMATOR="$ROSCOPTER_SHARE/params/estimator.yaml"

# Airframe-specific configuration
export AIRFRAME_CONFIG="$HOME/.config/veloxity/airframes/3dquad"
export VELOXITY_FIRMWARE_PARAMS="$AIRFRAME_CONFIG/firmware/firmware-startup-veloxity.yaml"
export C_FIRMWARE_PARAMS="$AIRFRAME_CONFIG/firmware/firmware-startup-c.yaml"
if [[ "${FIRMWARE_PARAMS:-}" == "$AIRFRAME_CONFIG/firmware/firmware-startup.yaml" ]]; then
  unset FIRMWARE_PARAMS
fi
: "${FIRMWARE_PARAMS:=}"
export FIRMWARE_PARAMS
export EXPERIMENT="$AIRFRAME_CONFIG/ros/hardware-exp2.yaml"
export ESTIMATOR_HW="$AIRFRAME_CONFIG/ros/estimator-hardware.yaml"
export MISSION="$AIRFRAME_CONFIG/missions/hover-check.yaml"

# Logging.
export FLIGHT_LOG_ROOT="$HOME/flight-logs"

#ROSflight serial interfaces
export ROSFLIGHT_UART="/dev/ttyAMA0"
export ROSFLIGHT_USB="/dev/ttyACM0"
export ROSFLIGHT_BAUD=921600

export ROS_DOMAIN_ID=23
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

for required_file in \
    "$MULTIROTOR" \
    "$ESTIMATOR" \
    "$VELOXITY_FIRMWARE_PARAMS" \
    "$C_FIRMWARE_PARAMS" \
    "$VELOXITY_PARAM_DEFINITIONS" \
    "$ROSFLIGHT_C_PARAM_DEFINITIONS" \
    "$EXPERIMENT" \
    "$ESTIMATOR_HW" \
    "$MISSION"
do
  if [[ ! -r "$required_file" ]]; then
    printf 'Missing configuration file: %s\n' "$required_file" >&2
  fi
done

if [[ -n "$FIRMWARE_PARAMS" && ! -r "$FIRMWARE_PARAMS" ]]; then
  printf 'Missing firmware parameter override: %s\n' "$FIRMWARE_PARAMS" >&2
fi
