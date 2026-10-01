# ThinkPhone Shinobu Kernel

Kernel for Motorola ThinkPhone (`bronco`) running LineageOS 23.2.
Includes ReSukiSU, SUSFS v2.3.0 and [NoMount](https://github.com/maxsteeel/nomount).

## Download

Open [Actions](https://github.com/iljasrb/bronco-shinobu-kernel/actions/workflows/build.yml),
select the latest successful `dev` build and download `shinobu-build`.
Extract the ZIP. The custom image is in `out/`; the original image is
`inputs/boot.img`.

Match the LineageOS build date in `out/INFO.md` to the build on your phone.
Do not flash an image for a different build. CI success does not confirm that
the kernel boots on a ThinkPhone.

## Flash

Requires an unlocked bootloader, `adb` and `fastboot`. Keep `inputs/boot.img`
for rollback. Run from the extracted directory:

```sh
(cd out && sha256sum -c shinobu-kernel-*.img.sha)
adb reboot bootloader
fastboot getvar current-slot
```

Replace `<slot>` with the reported slot (`a` or `b`):

```sh
fastboot flash boot_<slot> out/shinobu-kernel-*.img
fastboot reboot
```

Do not modify `vbmeta`.

## Rollback

Hold Volume Down + Power to enter the bootloader, then restore the same slot:

```sh
fastboot flash boot_<slot> inputs/boot.img
fastboot reboot
```

## Root and NoMount

Install a compatible [ReSukiSU manager](https://github.com/ReSukiSU/ReSukiSU/releases).
Any SUSFS userspace tools must support v2.3.0.

For NoMount, install its [metamodule](https://github.com/maxsteeel/nomount/releases)
in ReSukiSU and reboot. Use only one mounting metamodule.

To check root, authorize ADB in the manager and run:

```sh
adb shell 'su -c id'
```

The output must contain `uid=0(root)` and `u:r:ksu:s0`.
