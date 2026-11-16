# snort-attacker

Buildroot 2025.02.15 baseline for the hidden attacker guest in the browser lab.
It retains the networking and diagnostic programs visible in the existing image,
including Nmap, nping, ConnMan, Snort, tcpdump, and Python 3.

The attacker behavior remains separate payload content for script 03. It is not
compiled into this baseline.

The `linux.config` path assumes buildroot-builder2's default directory layout.
If `WORK_DIR` is moved outside the builder directory, change
`BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` to an absolute path or copy this file to
the Buildroot source tree and update that setting.
