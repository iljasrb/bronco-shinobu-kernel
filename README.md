# ThinkPhone Shinobu Kernel

Kernel for Motorola ThinkPhone (`bronco`) running LineageOS 23.2.
Includes BakaSU, SUSFS v2.3.0 and [NoMount](https://github.com/maxsteeel/nomount).

## Download

Open [Releases](https://github.com/iljasrb/bronco-shinobu-kernel/releases),
download latest build.

Match the LineageOS build date in `INFO.md` to the build on your phone.

## Flash

Requires an unlocked bootloader, `adb` and `fastboot`.
Run:

```sh
(sha256sum -c shinobu-kernel-*.img.sha)
adb reboot bootloader
```

```sh
fastboot flash boot shinobu-kernel-*.img
fastboot reboot
```

## Rollback

Hold Volume Down + Power to enter the bootloader, then restore the same slot:

```sh
fastboot flash boot_<slot> inputs/boot.img
fastboot reboot
```

## Root and NoMount

Install a compatible [BakaSU manager](https://github.com/Baka-SU/BakaSU/releases).
Any SUSFS userspace tools must support v2.3.0.

For NoMount, install its [metamodule](https://github.com/maxsteeel/nomount/releases)
in BakaSU and reboot. Use only one mounting metamodule.

To check root, authorize ADB in the manager and run:

```sh
adb shell 'su -c id'
```

The output must contain `uid=0(root)` and `u:r:ksu:s0`.
