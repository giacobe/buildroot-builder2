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

## Booting a baseline locally

The config sets do not build a host QEMU: it takes a large part of every
build and is not part of the image. To boot a baseline locally, use your
system's QEMU (for example the `qemu-system-x86` package):

```sh
qemu-system-i386 -m 512M -nographic -kernel bzImage -initrd rootfs.cpio.gz \
  -append "console=ttyS0"
```

Or, to have Buildroot build one as before, add these two lines to the config
set's `features.fragment` for your local build:

```
BR2_PACKAGE_HOST_QEMU=y
BR2_PACKAGE_HOST_QEMU_SYSTEM_MODE=y
```
