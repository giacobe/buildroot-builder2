# basic-processes

Reusable PolyLinux/v86 baseline for labs that teach Linux processes, signals,
process groups, scheduling priority, and interactive shell job control.

This profile extends `basic` with procps-ng and its original `top`
implementation. It is designed to support:

```text
ps -o pid,ppid,pgid,stat,ni,comm,args
ps -o stat= -p PID
ps -o ni= -p PID
top
nice
renice
```

`jobs`, `fg`, `bg`, and `wait` are Bash built-ins supplied by the enabled Bash
package. The qemu x86 kernel profile supplies `/proc`, signals, process groups,
and scheduling facilities needed by the lab.

After building, verify both command presence and the three `ps` invocations
above before publishing the empty `bzImage` and `rootfs.cpio.gz`.

Build this profile with the Buildroot version against which its symbols were
validated:

```sh
BUILDROOT_VERSION=2025.02.15 scripts/01-setup-buildroot.sh
scripts/02-build-baseline.sh --config basic-processes
```
