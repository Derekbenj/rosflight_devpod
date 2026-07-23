# Fixed-wing firmware startup parameters

The two startup files are selected by `ROSPLANE_FIRMWARE`:

- `firmware-startup-veloxity.yaml` is loaded for `ROSPLANE_FIRMWARE=veloxity`.
- `firmware-startup-c.yaml` is loaded for `ROSPLANE_FIRMWARE=c`.

They intentionally share the same 16 fixed-wing configuration parameters and
the same values. The Veloxity file has exactly one additional entry:

```yaml
- {name: CHN_OUTPUT_MASK, type: 6, value: 0}
```

`CHN_OUTPUT_MASK=0` disables every physical output channel until the operator
explicitly runs `p_enable_motors`. It is omitted from the C file because the
upstream C firmware does not expose this Veloxity-specific parameter; the
verified loader would correctly reject it as unknown.

These are reviewed startup subsets, not complete firmware snapshots. Verified
snapshots created by `p_save_firmware_snapshot` are stored in `snapshots/`.
