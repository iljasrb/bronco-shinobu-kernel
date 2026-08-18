# ThinkPhone Shinobu Kernel

This project builds a ReSukiSU kernel for the Motorola ThinkPhone (`bronco`) on LineageOS 23.2.

> [!IMPORTANT]
> ## Maintenance mode
> This project is in maintenance mode.
> The project receives only fixes for the build procedure.
> The project does not add new features.

> [!WARNING]
> Before you flash kernel, prepare a rollback image.
> You must know how to recover from a boot loop.

## Requirements

- A ThinkPhone with an unlocked bootloader.
- `adb`, `fastboot`, and Nix.

## Build

1. Download the pinned sources:

   ```sh
   nix develop --command ./sync-sources.sh --reset
   ```

2. Build the boot image:

   ```sh
   nix run .#bronco-build -- ./build.sh
   ```

The build saves the rollback image as `inputs/boot.img`.
The flash image is `out/boot-custom.img`.

## Battery tuner module

The battery tuner module has three profiles: `battery`, `balanced`, and `performance`.

Set a profile:

```sh
su -c 'sh /data/adb/modules/shinobu-battery/action.sh apply battery'
```

Use `status` to show the selected profile. Use `preview <profile>` before you set a profile.

## Flash

Run these commands in order. Replace `<slot>` with `a` or `b` from `fastboot getvar current-slot`.

```sh
adb reboot bootloader
fastboot getvar current-slot
fastboot flash boot_<slot> out/boot-custom.img
fastboot reboot
```

The image changes only the boot partition. AVB stays enabled.

### Roll back

If boot fails, hold Volume Down and Power to enter bootloader mode.

```sh
fastboot flash boot_<slot> inputs/boot.img
fastboot reboot
```
