# meta-imx93frm

A Yocto layer providing A/B (dual-copy) OTA updates for the **NXP FRDM-IMX93**
board booting from SD card, built on SWUpdate with signed FIT kernel images and
U-Boot bootcount-based rollback.

## Table of Contents

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Building](#building)
* [Flashing](#flashing)
* [Partition Layout](#partition-layout)
* [Boot Flow and Rollback](#boot-flow-and-rollback)
* [Performing an Update](#performing-an-update)
* [Recipes](#recipes)
* [Signing Keys](#signing-keys)
* [U-Boot Environment](#u-boot-environment)
* [Verification](#verification)
* [Known Limitations](#known-limitations)
* [Troubleshooting](#troubleshooting)

## Overview

This layer implements a field-updatable embedded Linux system with the
following properties:

| Property | Implementation |
|---|---|
| Update mechanism | SWUpdate (`.swu` packages) |
| Redundancy | A/B double-copy: two boot slots, two rootfs slots |
| Boot media | SD card (`mmcblk1`), raw bootloader at 32 KiB |
| Kernel format | Signed FIT image (kernel + DTB), verified by U-Boot |
| Rollback | U-Boot `bootcount` / `altbootcmd` ladder, gated on `upgrade_available` |
| Rescue tier | None — see [Known Limitations](#known-limitations) |
| Bootloader updates | Not part of routine OTA — see [Known Limitations](#known-limitations) |

An update writes the **standby** slot only. The running slot is never touched,
so a failed or interrupted update always leaves a known-good system to fall
back to.

## Prerequisites

* Linux build host with a working Yocto/OE toolchain
* [`kas`](https://github.com/siemens/kas) for build orchestration
* NXP FRDM-IMX93 board (machine: `imx93-11x11-lpddr4x-frdm`)
* microSD card, 8 GB or larger
* Serial console access (`ttyLP0`, 115200 baud)

### Version compatibility

This layer targets the NXP i.MX BSP release **`rel_imx_6.18.20_2.0.0`**
(Yocto "wrynose" era, kernel 6.18) with `DISTRO=fsl-imx-xwayland`. It is **not**
compatible with older releases — it depends on the `kernel-fit-image` class,
which replaced the older `fitImage` kernel image type.

## Building

The build is driven by kas:

```bash
kas build kas.yml
```

Or, to build individual targets:

```bash
kas shell kas.yml
bitbake swupdate-image      # main system image + full SD card (.wic.zst)
bitbake update-image        # the signed .swu OTA package
```

`swupdate-image` transitively builds `linux-imx-fitimage` (the signed FIT) and
`u-boot-env-blob` (the pre-seeded U-Boot environment), both of which must be
deployed before `wic` assembles the card.

### Key machine configuration

The FIT image build requires the following in the machine or distro config:

```
KERNEL_CLASSES        += "kernel-fit-extra-artifacts"
FIT_ADDRESS_CELLS      = "2"
UBOOT_LOADADDRESS      = "0x80400000"
UBOOT_ENTRYPOINT       = "0x80400000"
UBOOT_DTB_LOADADDRESS  = "0x83000000"
UBOOT_SIGN_ENABLE      = "1"
UBOOT_SIGN_KEYDIR      = "${TOPDIR}/keys"
UBOOT_SIGN_KEYNAME     = "dev"
KERNEL_DEVICETREE      = "freescale/imx93-11x11-frdm.dtb"
```

`kernel-fit-extra-artifacts` is **mandatory** — it makes the kernel recipe
deploy `linux.bin` and `linux_comp`, which `kernel-fit-image` consumes. Without
it the FIT build fails with a missing-`linux.bin` error.

## Flashing

```bash
zstd -d tmp/deploy/images/imx93-11x11-lpddr4x-frdm/swupdate-image-*.wic.zst \
     -o card.wic
sudo dd if=card.wic of=/dev/sdX bs=4M conv=fsync status=progress
```

> Verify `/dev/sdX` with `lsblk` before running `dd`. The board also exposes an
> onboard eMMC as `mmcblk0`; this system lives entirely on the SD card
> (`mmcblk1`) and does not touch eMMC.

Set the boot switches for SD/USDHC2 boot. The freshly flashed card contains a
pre-seeded U-Boot environment, so `fw_printenv` works on first boot with no
manual `saveenv`.

## Partition Layout

```
SD card (/dev/mmcblk1)
  0x008000  ( 32 KiB)   flash.bin           raw bootloader (ROM reads here)
  0x800000  (  8 MiB)   u-boot-env          128 KiB, raw, pre-seeded
  0xA00000  ( 10 MiB)   p1  boot_a          vfat, 128 MiB   fitImage
                        p2  boot_b          vfat, 128 MiB   fitImage
                        p3  root_a          ext4,   1 GiB
                        p4  root_b          ext4,   1 GiB
                        p5  data            ext4, 512 MiB   persistent
```

The bootloader and U-Boot environment are raw regions (`--no-table`) and do not
consume GPT partition numbers, so `boot_a` is `p1`. The environment occupies
8.000–8.125 MiB and the first partition starts at 10 MiB, leaving the two
clear of each other.

Slot mapping used throughout:

| Slot | Boot partition | Rootfs partition |
|---|---|---|
| A | `/dev/mmcblk1p1` | `/dev/mmcblk1p3` |
| B | `/dev/mmcblk1p2` | `/dev/mmcblk1p4` |

## Boot Flow and Rollback

U-Boot resolves the active slot from the `boot_slot` environment variable,
loads that slot's `fitImage`, verifies its signature, and boots it.

```
bootcmd -> mmcboot
             run setslot                 boot_slot A|B -> bootpart / rootpart
             fatload mmc 1:${bootpart} ${fit_load_addr} fitImage
             bootm ${fit_load_addr}      signature verified here
```

Rollback is driven by U-Boot's bootcount mechanism
(`CONFIG_BOOTCOUNT_LIMIT` + `CONFIG_BOOTCOUNT_ENV`):

1. An update sets `boot_slot` to the newly written slot, `upgrade_available=1`,
   `bootcount=0`, and reboots.
2. U-Boot increments `bootcount` on every boot.
3. A healthy boot runs `swupdate-confirm.service`, which clears
   `upgrade_available`, `bootcount`, and `fallback_done` — ending the trial.
4. If the system never reaches the confirm step, `bootcount` exceeds
   `bootlimit` (3) and U-Boot runs `altbootcmd`.

`altbootcmd` escalates:

* If `upgrade_available != 1` — no trial is pending, boot normally (a confirmed
  system is never rolled back, regardless of bootcount).
* First trial failure — flip to the other slot, set `fallback_done=1`, reset
  `bootcount`, retry.
* Second trial failure — both slots failed; halt with a console message for
  manual recovery.

The system does not detect "brokenness" directly; it detects the **absence of a
confirmation**. Anything that prevents the confirm step from running — kernel
panic, hang, failed application start — eventually triggers rollback.

## Performing an Update

Updates must always target the **standby** slot. Selecting the running slot
overwrites the live system and destroys the fallback copy.

```bash
swupdate -i update-image-imx93-11x11-lpddr4x-frdm.rootfs.swu -e stable,slot_b
```

Running on A → select `slot_b`. Running on B → select `slot_a`.

Use a wrapper rather than invoking this by hand:

```sh
#!/bin/sh
# ab-update.sh <path-to.swu>
set -e
CUR=$(fw_printenv -n boot_slot 2>/dev/null) || {
    echo "ERROR: cannot read boot_slot — aborting"; exit 1; }
case "$CUR" in
    A) SEL=slot_b ;;
    B) SEL=slot_a ;;
    *) echo "ERROR: boot_slot='$CUR' invalid — aborting"; exit 1 ;;
esac
echo "running slot=$CUR -> installing standby via stable,$SEL"
swupdate -i "$1" -e "stable,$SEL"
```

The `*)` branch fails closed: if the environment cannot be read, the script
refuses rather than guessing which slot to overwrite.

After the update completes, reboot. The board should come up on the other slot;
confirm with `fw_printenv boot_slot`.

## Recipes

| Recipe | Purpose |
|---|---|
| `swupdate-image.bbappend` | Main system image. Adds SWUpdate tooling, sets `IMAGE_BOOT_FILES = "fitImage"`, produces `.ext4.gz` (slot rootfs) and `.wic.zst` (full card). |
| `update-image.bb` | Assembles and packages the `.swu`. Pulls in the rootfs and `fitImage` via `SWUPDATE_IMAGES`. |
| `linux-imx-fitimage.bb` | Builds the signed FIT (kernel + DTB) via the `kernel-fit-image` class. |
| `u-boot-env-blob.bb` | Runs `mkenvimage` over U-Boot's `u-boot-imx-initial-env` to produce the pre-seeded environment blob written into the card. |

### sw-description

The update descriptor defines both slots as named selections under a `stable`
group. Each selection hardcodes its target partitions and commits the slot
switch declaratively via a `bootenv` block:

```
stable: {
    slot_b: {
        files:  ( { filename = "fitImage"; device = "/dev/mmcblk1p2"; ... } );
        images: ( { filename = "...ext4.gz"; device = "/dev/mmcblk1p4"; ... } );
        bootenv: ( { name = "boot_slot"; value = "B"; }, ... );
    };
    slot_a: { ... targets p1 / p3, sets boot_slot = A ... };
};
```

Because the slot commit lives in `bootenv`, no scripting is required to flip
the boot target.

## Signing Keys

The FIT signing key pair lives in `${UBOOT_SIGN_KEYDIR}` (default
`${TOPDIR}/keys`) as `<UBOOT_SIGN_KEYNAME>.key` and `.crt`:

```bash
mkdir -p keys
openssl genrsa -F4 -out keys/dev.key 2048
openssl req -batch -new -x509 -key keys/dev.key -out keys/dev.crt \
        -subj "/CN=frdm-imx93 fit signing"
```

The **public** key is injected into U-Boot's control device tree at build time
and packaged into `flash.bin`. U-Boot uses it to verify every FIT it loads.

> **Key rotation requires a bootloader update.** Because the public key lives
> inside `flash.bin`, changing the signing key means rewriting the bootloader —
> which on SD is a single-copy, non-rollbackable operation. Provision any keys
> you may need before deploying.

## U-Boot Environment

Single-copy environment stored raw on the SD card. All four of the following
**must agree** or the environment becomes unreadable:

| Location | Setting |
|---|---|
| U-Boot defconfig | `CONFIG_ENV_OFFSET=0x800000`, `CONFIG_ENV_SIZE=0x20000` |
| `u-boot-env-blob.bb` | `mkenvimage -s 0x20000` |
| `.wks` env partition | `--offset 8192 --fixed-size 128K` |
| `/etc/fw_env.config` | `/dev/mmcblk1  0x800000  0x20000` |

A mismatch in any one of them produces
`*** Warning - bad CRC, using default environment` at boot, after which U-Boot
falls back to compiled-in defaults and **silently ignores** anything written by
SWUpdate — meaning slot switches will not take effect.

### A/B state variables

| Variable | Meaning |
|---|---|
| `boot_slot` | `A` or `B` — which slot U-Boot boots |
| `bootcount` | Incremented by U-Boot each boot; reset on confirmation |
| `bootlimit` | Failed-boot threshold (3) before `altbootcmd` runs |
| `upgrade_available` | `1` while a trial is pending; gates rollback |
| `fallback_done` | `1` after one slot flip, to escalate rather than loop |

> The `.env` source file must contain **no `#` comments**. U-Boot's `.env`
> format folds them into the preceding variable's value, which silently
> corrupts variables such as `bootlimit`. Only `/* ... */` block comments are
> safe.

## Verification

After flashing, confirm each layer:

```bash
# Environment is readable (not "bad CRC") — check the U-Boot console:
#   Loading Environment from MMC... OK

# FIT signature is verified — check the U-Boot console:
#   Verifying Hash Integrity ... sha256,rsa2048:dev+ OK

# Userspace can read and write the environment:
fw_printenv boot_slot
fw_setenv test hello && fw_printenv test && fw_setenv test

# Trial was cleared on a healthy boot:
systemctl status swupdate-confirm.service
fw_printenv bootcount upgrade_available   # both 0

# Partition layout matches expectations:
cat /proc/partitions
cat /sys/block/mmcblk1/mmcblk1p1/start    # 20480 sectors = 10 MiB
```

Two behavioural tests are worth running before trusting the system in the
field:

* **Rollback** — install to the standby slot, prevent it from confirming, and
  verify U-Boot falls back to the previous slot after `bootlimit` attempts.
* **Tamper** — corrupt a byte of a slot's `fitImage` and verify U-Boot refuses
  to boot it. Passing signature checks on a *valid* image does not prove that
  an *invalid* one is rejected.

## Known Limitations

**No rescue tier.** If both slots fail their trials, the board halts and
requires manual recovery (UUU serial download or reflashing the SD card). This
was a deliberate trade-off: on SD, a rescue system would live on the same
media it is meant to repair.

**The bootloader is not updated over OTA.** `flash.bin` sits at a single fixed
raw offset (32 KiB) that the boot ROM reads; there is no second copy to fall
back to. Overwriting it has a small but unrecoverable brick window. ROM-level
bootloader failover on SD would require burning the `Secondary_boot_offset`
eFuses, which is permanent.

**The rootfs is not verified at boot.** FIT signing covers the kernel and
device tree only. A modified rootfs will boot. Adding dm-verity would close
this if rootfs integrity is in scope.

**Confirmation is currently gated on `multi-user.target`.** A system that boots
but whose application is broken will still be treated as healthy. Gating
`swupdate-confirm.sh` behind a real application health check is recommended
before production use.

**hawkBit / suricatta is not yet wired up.** Updates are applied manually via
the SWUpdate CLI. Fleet deployment additionally needs per-device identity and
token provisioning.

## Troubleshooting

**`*** Warning - bad CRC, using default environment`**
The environment blob on the card does not match what U-Boot expects. Check that
the offset and size agree across the defconfig, `mkenvimage -s`, the `.wks`
region, and `fw_env.config`. Rebuild and reflash the **whole** card, not just
`flash.bin`.

**`Cannot read environment` from `fw_printenv`**
`/etc/fw_env.config` does not match U-Boot's `CONFIG_ENV_OFFSET` /
`CONFIG_ENV_SIZE`, or the card was flashed without the seeded environment blob.

**`gzip compressed: uncompress error -3` during boot**
The FIT load address collides with the kernel's decompression target. Keep
`fit_load_addr` (where the FIT is `fatload`ed) clear of `UBOOT_LOADADDRESS`
(where the kernel decompresses to).

**`Required image file fitImage missing...aborting`**
The `.swu` does not contain `fitImage`, or the artifacts are ordered
differently from the `sw-description`. SWUpdate streams the cpio archive in
order; artifacts must appear in the same order they are referenced. Add
`fitImage` to `SWUPDATE_IMAGES` rather than copying it into `WORKDIR`.

**A slot switch does not take effect after reboot**
U-Boot is not reading the environment SWUpdate wrote. Confirm the console shows
`Loading Environment from MMC... OK` rather than a CRC warning, and that
`fw_printenv boot_slot` in Linux and `printenv boot_slot` in U-Boot report the
same value.

**Kernel FIT build fails with a missing `linux.bin`**
`KERNEL_CLASSES += "kernel-fit-extra-artifacts"` is missing or was added after
the kernel was already built. Add it globally, then
`bitbake -c cleansstate virtual/kernel` and rebuild.
