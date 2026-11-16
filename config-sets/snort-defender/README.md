# snort-defender

Buildroot 2025.02.15 baseline for the visible Snort IDS guest in the browser lab.
It produces the `bzImage` and gzipped full cpio initramfs expected by v86.

The profile provides Snort 2.9.20, DAQ 2.0.7, libpcap/tcpdump, Python 3,
iproute2/ifupdown, iptables, editors, and the serial plus VGA consoles used by
the current page. Guest-specific files remain separate for script 03 packaging.

The `linux.config` path assumes buildroot-builder2's default directory layout.
If `WORK_DIR` is moved outside the builder directory, change
`BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` to an absolute path or copy this file to
the Buildroot source tree and update that setting.
