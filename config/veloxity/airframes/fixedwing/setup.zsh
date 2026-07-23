# Fixed-wing airframe configuration. The caller must already have sourced ROS 2
# and the ROSflight workspace.
: "${VELOXITY_ROOT:=$HOME/Veloxity}"
: "${ROSFLIGHT_WS:=$HOME/rosflight_devpod}"
export VELOXITY_ROOT
export ROSFLIGHT_WS
export ROSPLANE_AIRFRAME_CONFIG="$HOME/.config/veloxity/airframes/fixedwing"

# An explicitly supplied ROSPLANE_FIRMWARE_PARAMS always wins. When empty,
# p_load_firmware_params selects one of these according to ROSPLANE_FIRMWARE.
export ROSPLANE_VELOXITY_FIRMWARE_PARAMS="$ROSPLANE_AIRFRAME_CONFIG/firmware/firmware-startup-veloxity.yaml"
export ROSPLANE_C_FIRMWARE_PARAMS="$ROSPLANE_AIRFRAME_CONFIG/firmware/firmware-startup-c.yaml"
export ROSPLANE_FIRMWARE_SNAPSHOT_DIR="$ROSPLANE_AIRFRAME_CONFIG/firmware/snapshots"
export VELOXITY_PARAM_DEFINITIONS="$VELOXITY_ROOT/crates/veloxity_core/src/params.rs"
export ROSFLIGHT_C_PARAM_DEFINITIONS="$ROSFLIGHT_WS/src/rosflight_ros_pkgs/rosflight_firmware/src/param.cpp"
export ROSPLANE_MISSION="$ROSPLANE_AIRFRAME_CONFIG/missions/fixedwing_mission.yaml"

: "${ROSPLANE_FIRMWARE:=veloxity}"
: "${ROSPLANE_FIRMWARE_PARAMS:=}"
: "${ROSPLANE_LOG_ROOT:=$HOME/flight-logs/rosplane}"

export ROSPLANE_FIRMWARE
export ROSPLANE_FIRMWARE_PARAMS
export ROSPLANE_LOG_ROOT

for required_file in \
    "$ROSPLANE_VELOXITY_FIRMWARE_PARAMS" \
    "$ROSPLANE_C_FIRMWARE_PARAMS" \
    "$VELOXITY_PARAM_DEFINITIONS" \
    "$ROSFLIGHT_C_PARAM_DEFINITIONS" \
    "$ROSPLANE_MISSION" \
    "$ROSPLANE_AIRFRAME_CONFIG/assured_param_io.py" \
    "$ROSPLANE_AIRFRAME_CONFIG/verified_param_loader.py"
do
  if [[ ! -r "$required_file" ]]; then
    printf 'Missing fixed-wing configuration file: %s\n' "$required_file" >&2
  fi
done
