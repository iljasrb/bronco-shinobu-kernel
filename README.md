# ThinkPhone Shinobu Kernel

A ReSukiSU kernel for the Motorola ThinkPhone (`bronco`) on LineageOS 23.2.

> [!WARNING]
> Experimental. Know how to recover from a bootloop before flashing.

- Based on the LineageOS kernel tree, with ReSukiSU and SUSFS integrated into the build.
- Flashable boot image: [flac.moe/shinobu](https://flac.moe/shinobu)
- Builds a kernel + boot image only, not LineageOS itself.

## Features

- ReSukiSU kernel root with SUSFS (`CONFIG_KSU`, `CONFIG_KSU_SUSFS`)
- BBR default TCP congestion control (`CONFIG_TCP_CONG_BBR`, `CONFIG_DEFAULT_BBR`)
- ThinLTO + CFI (shadow) build with the pinned Android clang
- CPU input boost driver (`CONFIG_CPU_INPUT_BOOST`), tuned for the SM8475 cluster masks
- LLVM Polly loop optimizations (`CONFIG_LLVM_POLLY`)
- LineageOS 23.2 (`5.10.257-android13`) kernel tree, kernel-only boot image

## Requirements

- ThinkPhone with unlocked bootloader
- `adb`, `fastboot`, Nix
- Fetch the pinned boot image with `./scripts/fetch-boot-image.sh` (the same image is your rollback image)

## Build

```sh
nix develop --command ./sync-sources.sh --reset   # download pinned sources
nix run .#bronco-build -- ./build.sh --yes        # build + package (unattended)
```

`build.sh` downloads and verifies the pinned boot image itself; the same image in `inputs/boot.img` doubles as your rollback image.

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

(`lineage`, `resukisu`, `mkbootimg`, `clang` work individually.) `lineage` and `all` also resolve the newest nightly's boot image and bump `BOOT_IMAGE_URL`/`BOOT_IMAGE_SHA256` when its kernel matches the pinned revision; if the newest nightly still ships an older kernel, the pin is left unchanged with a warning — re-run after the next nightly. `build.sh` fetches the pinned boot image itself, so no manual download is needed. To pin manually instead, `BOOT_IMAGE_URL` is published as `https://mirrorbits.lineageos.org/full/bronco/<date>/boot.img` next to the ROM zip; verify the sha256 after download.

## Files

| Path | Purpose |
| --- | --- |
| `sources.env` | Pinned source revisions, project version, pinned boot image |
| `.github/workflows/build.yml` | CI: builds the kernel and boot image on every push |
| `sync-sources.sh` | Downloads and resets pinned sources |
| `scripts/fetch-boot-image.sh` | Downloads and verifies the pinned boot image |
| `build.sh` | Build + package entry point |
| `patches/` | Kernel patches, applied in order |
| `out/boot-custom.img` | Flashable image |
