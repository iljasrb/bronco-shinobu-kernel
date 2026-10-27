# ThinkPhone Shinobu Kernel

Custom Linux 5.10 kernel for the Motorola ThinkPhone (`bronco`) running
LineageOS 24.0 (Android 17). Includes BakaSU, SUSFS v2.3.0 and
[NoMount](https://github.com/maxsteeel/nomount).

## Compatibility

This kernel tracks LineageOS 24.0 (`lineage-24.0`). Each release is built and
validated against one `bronco` LineageOS build, listed in `INFO.md`.

**An exact LineageOS version/build match is recommended but not necessary.**
The installer warns when `ro.lineage.version` differs and then continues. Other
LineageOS 24.0 builds may work, but test before relying on them, and keep a
known-good stock boot image for the current build as a rollback. Do not use
this kernel on other devices or Android versions.

## Download

Open [Releases](https://github.com/iljasrb/bronco-shinobu-kernel/releases) and
download the latest build.

Each release provides:

- `shinobu-kernel-<version>.img` for fastboot
- `shinobu-kernel-<version>-anykernel3.zip` for BakaSU's kernel flash screen
- `INFO.md` with the validated LineageOS build, kernel release and hashes

Verify the downloads before flashing:

```sh
sha256sum -c shinobu-kernel-*.img.sha
sha256sum -c shinobu-kernel-*-anykernel3.zip.sha
```

## Install with BakaSU (AnyKernel3)

Use this path when BakaSU is already installed and rooted. It works for a normal
install and for installing into the inactive slot before rebooting after an OTA.

1. Download the AnyKernel3 ZIP and its `.sha` file, then verify it with the
   command above.
2. In BakaSU, open the kernel flash screen and select the ZIP.
3. Select the inactive slot after an OTA, or the current slot for a normal
   install.
4. Reboot.

The ZIP replaces only the kernel in the target boot image. It preserves the
ramdisk contents, cmdline and DTB; vendor modules remain in
`vendor_boot`/`vendor_dlkm`. The installed kernel does not survive an OTA by
itself, so repeat this after each OTA or use fastboot.

After an OTA, the running build can differ from the build embedded in the
package. The installer warns about this and continues; an exact build match is
recommended but not necessary.

Do not use BakaSU's "Install to inactive slot (After OTA)" LKM flow to install
this kernel. That flow injects an LKM into the stock boot image; this kernel
already includes BakaSU.

## Install with fastboot

Requires an unlocked bootloader, `adb` and `fastboot`.

```sh
sha256sum -c shinobu-kernel-*.img.sha
adb reboot bootloader
fastboot flash boot shinobu-kernel-<version>.img
fastboot reboot
```

## KMI note

LineageOS labels the kernel `-android13-0`, but the kernel is built from the
ACK `android12-5.10` branch with KMI generation 9. The actual KMI is
**android12-5.10**. BakaSU may auto-detect `android13-5.10`; if your BakaSU
build lets you choose the KMI manually, select `android12-5.10`. The AnyKernel3
package avoids the LKM/KMI selection entirely.

## Rollback

Restore a stock boot image known to work on your current LineageOS build. The
matching build is the safest choice. From the bootloader:

```sh
fastboot getvar current-slot
fastboot flash boot_<slot> <stock-boot.img>
fastboot reboot
```

## Root, SUSFS and NoMount

Install the BakaSU manager: <https://bakasu.org/guide/install>. Any SUSFS
userspace tools must support v2.3.0.

For NoMount, install its
[metamodule](https://github.com/maxsteeel/nomount/releases) in BakaSU and
reboot. Use only one mounting metamodule.

To check root, authorize ADB in the manager and run:

```sh
adb shell 'su -c id'
```

The output must contain `uid=0(root)` and `u:r:ksu:s0`.

## Build from source

The build pins the kernel, device trees, BakaSU, SUSFS, NoMount, AnyKernel3,
mkbootimg and Clang in `sources.env`.

```sh
./sync-sources.sh --reset
./build.sh
```

Artifacts are written to `out/`.
