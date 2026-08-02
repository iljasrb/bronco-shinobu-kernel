# ThinkPhone Shinobu Kernel

A ReSukiSU kernel for the Motorola ThinkPhone (`bronco`) on LineageOS 23.2.

> [!WARNING]
> This project is in experimental state, before using this kernel make sure you know how to restore the device in case of bootloop and that you have enough time to deal with possible issues.


- Based on LineageOS kernel tree.
- Integrates ReSukiSU
- SUSFS **not** integrated.

Flashable boot.img is published on [flac.moe/shinobu](https://flac.moe/shinobu)

This project builds a kernel and puts it into an Android boot image. It does not build LineageOS itself.

## Before you start

Requirements:

- A Motorola ThinkPhone with an unlocked bootloader.
- The exact LineageOS boot image that is currently installed on the phone.
- `adb`, `fastboot`, and Nix on the build computer.
- Enough free disk space for the Android compiler, kernel source, and build output.

Copy the matching boot image to:

```text
inputs/boot.img
```

Do not use a boot image from a different LineageOS build. Keep a copy: it is the rollback image.

## Build

First download the pinned kernel sources, device trees, ReSukiSU, boot-image tools, and Android compiler:

```sh
nix develop --command ./sync-sources.sh --reset
```

`--reset` deletes local changes inside the downloaded source directories. Do not edit those directories directly unless you have backed up your work.

Build the kernel:

```sh
nix run .#bronco-build -- ./build-kernel.sh
```

Create a flashable boot image:

```sh
nix develop --command ./make-boot-image.sh
```

The result is:

```text
out/boot-custom.img
```

The packager reads the kernel version from `inputs/boot.img` and refuses to package a kernel for a different release. It preserves the original boot header and ramdisk, replacing only the kernel.

## Flash

Boot the phone into the bootloader and find the active slot:

```sh
adb reboot bootloader
fastboot getvar current-slot
```

Flash the matching slot. If the active slot is `a`:

```sh
fastboot flash boot_a out/boot-custom.img
fastboot reboot
```

If the active slot is `b`, use `boot_b` instead.

Do not flash `dtbo`, `vendor_boot`, or `vbmeta` for this kernel-only test. Do not disable AVB verification.

### Roll back

If the phone does not boot, return to the bootloader with **Volume Down + Power** and flash the saved original image to the same slot. Example for slot `a`:

```sh
fastboot flash boot_a inputs/boot.img
fastboot reboot
```

## ReSukiSU

ReSukiSU is built into this kernel. It uses the GKI tracepoint syscall hook; manual syscall hooks and SuSFS are disabled.

Install a compatible ReSukiSU, KernelSU, MKSU, RKSU, or SukiSU-Ultra manager after booting. The manager's **Version** field shows the project version and ReSukiSU source revision:

```text
ThinkPhone-Shinobu-v0.1.0-v4.1.0-59c99fdf@ReSukiSU
```

Change `PROJECT_VERSION` in `sources.env` before a new project release. This label does not change `uname -r` or vendor-module compatibility.

## Update sources

`sources.env` records the exact source revisions used by this project. Normal builds use those pins.

To update a source pin to the newest commit on its configured branch:

```sh
nix develop --command ./sync-sources.sh --pull-latest lineage --reset
nix develop --command ./sync-sources.sh --pull-latest resukisu --reset
nix develop --command ./sync-sources.sh --pull-latest mkbootimg --reset
nix develop --command ./sync-sources.sh --pull-latest all --reset
```

The command saves the old manifest as `sources.env.bak` before changing it. `all` updates the LineageOS kernel and device trees, ReSukiSU, and `mkbootimg`. It does not update Android Clang automatically.

Before updating LineageOS sources, replace `inputs/boot.img` with the boot image from the new target build. If you change LineageOS release lines, update `LINEAGE_BRANCH` first. Then build, package, and test the new image before daily use.

## Important files

| Path | Purpose |
| --- | --- |
| `sources.env` | Pinned source revisions and project version. |
| `sync-sources.sh` | Downloads and resets the pinned sources. |
| `build-kernel.sh` | Builds the kernel and Bronco device trees. |
| `make-boot-image.sh` | Replaces the kernel inside `inputs/boot.img`. |
| `out/boot-custom.img` | Flashable image produced by the build. |
