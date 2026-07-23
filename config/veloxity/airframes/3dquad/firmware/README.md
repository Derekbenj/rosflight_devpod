# 3dquad firmware startup parameters

The two startup files are selected by `VELOXITY_FIRMWARE`:

- `firmware-startup-veloxity.yaml` is loaded for `VELOXITY_FIRMWARE=veloxity`.
- `firmware-startup-c.yaml` is loaded for `VELOXITY_FIRMWARE=c`.

They intentionally share the same 110 quadrotor configuration parameters and
the same values. The Veloxity file has exactly one additional entry:

```yaml
- {name: CHN_OUTPUT_MASK, type: 6, value: 0}
```

`CHN_OUTPUT_MASK=0` disables every physical output channel until the operator
explicitly runs `v_enable_motors`. It is omitted from the C file because the
upstream C firmware does not expose this Veloxity-specific parameter; the
verified loader would correctly reject it as unknown.

`FIRMWARE_PARAMS` remains available as an explicit reviewed-file override. If
it is empty, `v_load_firmware_params` selects the backend-specific file above.
Complete verified snapshots are stored in `snapshots/`.
