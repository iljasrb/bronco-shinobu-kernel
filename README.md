# ThinkPhone Shinobu Kernel

A ReSukiSU kernel for the Motorola ThinkPhone (`bronco`) on LineageOS 23.2.

> [!WARNING]
> Experimental. Know how to recover from a bootloop before flashing.

- Based on the LineageOS kernel tree, with ReSukiSU and SUSFS integrated into the build.
- Flashable boot image: [flac.moe/shinobu](https://flac.moe/shinobu)
- Builds a kernel + boot image only, not LineageOS itself.

## Requirements

- ThinkPhone with unlocked bootloader
- The exact LineageOS boot image currently installed
- `adb`, `fastboot`, Nix
- Copy the boot image to `inputs/boot.img` (keep a copy — it's your rollback image)

## Build

```sh
nix develop --command ./sync-sources.sh --reset   # download pinned sources
nix run .#bronco-build -- ./build.sh --yes        # build + package (unattended)
```

Result: `out/boot-custom.img`. Drop `--yes` for the interactive build; add `--skip-resukisu` or `--skip-patches` to skip a step.

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

(`lineage`, `resukisu`, `mkbootimg`, `clang` work individually.) Before updating LineageOS, replace `inputs/boot.img` with the new build's boot image.

## Files

| Path | Purpose |
| --- | --- |
| `sources.env` | Pinned source revisions, project version |
| `sync-sources.sh` | Downloads and resets pinned sources |
| `build.sh` | Build + package entry point |
| `patches/` | Kernel patches, applied in order |
| `out/boot-custom.img` | Flashable image |
