# ThinkPhone Shinobu Kernel

A ReSukiSU kernel for the Motorola ThinkPhone (`bronco`) on LineageOS 23.2.

[![build](https://github.com/iljasrb/bronco-shinobu-kernel/actions/workflows/build.yml/badge.svg)](https://github.com/iljasrb/bronco-shinobu-kernel/actions/workflows/build.yml)

> [!WARNING]
> Experimental. Know how to recover from a bootloop before flashing.

- Based on the LineageOS kernel tree, with ReSukiSU and SUSFS integrated into the build.
- Flashable boot image: [flac.moe/shinobu](https://flac.moe/shinobu)
- Builds a kernel + boot image only, not LineageOS itself.

> The kernel will be developed until a stable state is reached, afterwards the project will enter maintenance mode.

## Features

- ReSukiSU with SUSFS
- BBR default TCP (`CONFIG_TCP_CONG_BBR`, `CONFIG_DEFAULT_BBR`)
- ThinLTO + CFI (shadow) build with the pinned Android clang
- Frequency-QoS input boost, tuned per battery-module profile

## Requirements

- ThinkPhone with unlocked bootloader
- `adb`, `fastboot`, Nix
- Fetch the pinned boot image with `./scripts/fetch-boot-image.sh` (the same image is your rollback image)

## Build

```sh
nix develop --command ./sync-sources.sh --reset   # download pinned sources
nix run .#bronco-build -- ./build.sh              # build + package
```

`build.sh` downloads and verifies the pinned boot image itself; the same image in `inputs/boot.img` doubles as your rollback image.

Result: `out/boot-custom.img` (+ `out/shinobu-kernel-<version>.img`), plus the flashable `out/shinobu-battery.zip` module.

## Battery tuner module

`module/` is a KernelSU module built alongside the kernel (`scripts/build-module.sh`, run by `build.sh`). It applies battery/performance profiles at boot. Caps are computed from the device's own frequency tables:

| Profile | little | big | prime | GPU | walt governor |
| --- | --- | --- | --- | --- | --- |
| battery | stock | 80% | 70% | 60% | up 20 ms / down 10 ms, hispeed_load 95 |
| balanced | stock | 90% | 85% | 80% | 10 ms / 10 ms, 90 |
| performance | stock | stock | stock | stock | 5 ms / 5 ms, 80 |

Also tuned: input boost and UFS clock scaling. Applied at boot.

- Profiles persist in `/data/adb/shinobu-battery/profile` (survives module updates).
- Switch: `su -c 'sh /data/adb/modules/shinobu-battery/action.sh apply battery'` (or `status`, `preview <profile>`).
- WebUI: module page in the KernelSU/ReSukiSU manager — pick a profile to preview its values next to the current ones, then apply.

## Kernel patches

Put patches in `patches/` as `0001-name.patch` (applied in order after ReSukiSU integration):

```sh
git -C kernel diff --binary -- path/to/file.c > patches/0001-my-change.patch
```

## Flash

```sh
adb reboot bootloader
fastboot getvar current-slot
fastboot flash boot_<slot> out/boot-custom.img   # boot_a or boot_b
fastboot reboot
```

This default build is kernel-only: it never touches `dtbo`, `vendor_boot`, `vbmeta`, or `vendor_dlkm`, and AVB stays on. Vendor-partition experiments (e.g. a `vendor_dlkm` rebuild for features that can't ship in vmlinux) are off-default and bootloop/hang-risky: stage rollback images first.

### Roll back

Volume Down + Power → bootloader, then:

```sh
fastboot flash boot_<slot> inputs/boot.img
fastboot reboot
```

## Update sources

`sources.env` pins all source revisions. To update everything:

```sh
nix develop --command ./sync-sources.sh --pull-latest all --reset
```

(`lineage`, `resukisu`, `mkbootimg`, `clang` work individually.) `lineage` and `all` update the kernel, device-tree, boot URL, and boot sha256 as one compatible set only when the newest build for `LINEAGE_BRANCH` ships the current kernel branch tip. Otherwise the LineageOS pins stay unchanged with a warning; re-run after the next build. `build.sh` fetches the pinned boot image itself, so no manual download is needed. To pin manually instead, use the `boot.img` URL and sha256 published by the [LineageOS builds API](https://download.lineageos.org/api/v2/devices/bronco/builds).

`.github/workflows/update.yml` checks each Monday, builds a compatible candidate, and opens or refreshes `automation/lineage-update` only after the build and tuner self-check pass. Merge only after reviewing the upstream delta and flash-testing the workflow artifact; releases remain manual tags. The repository must allow GitHub Actions to create pull requests.

## Files

| Path | Purpose |
| --- | --- |
| `sources.env` | Pinned source revisions, project version, pinned boot image |
| `.github/workflows/build.yml` | CI: builds pull requests, release tags, and manual dispatches |
| `.github/workflows/update.yml` | Weekly build-gated LineageOS pin update PR |
| `sync-sources.sh` | Downloads and resets pinned sources |
| `scripts/fetch-boot-image.sh` | Downloads and verifies the pinned boot image |
| `build.sh` | Build + package entry point |
| `patches/` | Kernel patches, applied in order |
| `module/` | Battery tuner module source (KernelSU module + WebUI + tests) |
| `scripts/build-module.sh` | Packages the flashable module zip |
| `out/boot-custom.img` | Flashable image |
| `out/shinobu-battery.zip` | Flashable battery tuner module |
