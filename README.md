# ThinkPhone Shinobu Kernel

Custom Linux 5.10 kernel for the Motorola ThinkPhone (`bronco`) on LineageOS
24.0 (Android 17), with BakaSU, SUSFS v2.3.0 and NoMount.

## Compatibility

An exact LineageOS version/build match is recommended but not necessary. The
installer warns and continues on a mismatch. Use only on `bronco`.

## Download

Download the latest `.img`, `-anykernel3.zip` and `.sha` files from
[Releases](https://github.com/iljasrb/bronco-shinobu-kernel/releases). Check
`INFO.md` for the validated build and hashes. Verify before flashing:

```sh
sha256sum -c shinobu-kernel-*.img.sha
sha256sum -c shinobu-kernel-*-anykernel3.zip.sha
```

## Install with AnyKernel3

The ZIP can be installed from BakaSU's kernel flash screen or from recovery
(install/apply update, or `adb sideload shinobu-kernel-*-anykernel3.zip`).

It replaces only the kernel and preserves the ramdisk, cmdline and DTB. After
an OTA, select the inactive slot in BakaSU before rebooting. The kernel does not
survive an OTA by itself. Do not use BakaSU's LKM "Install to inactive slot
(After OTA)" flow; this kernel already contains BakaSU.

The actual KMI is **android12-5.10**, despite LineageOS's `-android13-0` vendor
label. The AnyKernel3 ZIP avoids LKM/KMI selection.

## Install with fastboot

Requires an unlocked bootloader.

```sh
adb reboot bootloader
fastboot flash boot shinobu-kernel-<version>.img
fastboot reboot
```

## Rollback

```sh
fastboot getvar current-slot
fastboot flash boot_<slot> <stock-boot.img>
fastboot reboot
```

Use a stock boot image known to work on the current LineageOS build.

## Root and NoMount

Install the [BakaSU manager](https://bakasu.org/guide/install). For NoMount,
install its [metamodule](https://github.com/maxsteeel/nomount/releases) and use
only one mounting metamodule. Check root with:

```sh
adb shell 'su -c id'
```

It must contain `uid=0(root)` and `u:r:ksu:s0`.
