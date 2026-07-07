# Buildroot Config Sets

Each subdirectory is a selectable Buildroot baseline profile. The build script
loads `defconfig`, appends `features.fragment` when present, runs
`make olddefconfig`, then builds the image pair.

Required files:

- `defconfig`: starting Buildroot config.
- `features.fragment`: additional package/rootfs selections.
- `required-commands.txt`: commands expected to exist in the built rootfs.
- `README.md`: human description of the profile.

Add new profiles by copying the closest existing config set and adjusting its
Buildroot package symbols.
