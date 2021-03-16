# Hacking Evercade over USB

The Evercade's USB hardware supports treating the Evercade as a peripheral.
This means you can make the Evercade behave as an Android device (using adbd), and connect to the Evercade from a computer using USB.
This document describes how to make your Evercade device run adbd.

1. Install rkdeveloptool
2. Boot Evercade in flash mode
3. Back up firmware
4. Patch firmware
5. Install firmware
6. Connect with adb

## 1. Install rkdeveloptool

To follow this guide, you must install [rkdeveloptool][] on a Linux computer.
Other flashing tools might work but have not been tested.

## 2. Boot Evercade in flash mode

1. Connect your Evercade to your computer using a USB cable.
2. Turn off your Evercade.
   Your Evercade's power LED should be orange.
3. Hold your Evercade's menu button, then turn on your Evercade.
   Your Evercade's screen should be blank, and its power LED should still be orange.

## 3. Back up firmware

Use rkdeveloptool to back up your Evercade's firmware.

1. Run `sudo rkdeveloptool ppt`.
   It should output something similar to the following:

    ```
    **********Partition Info(GPT)**********
    NO  LBA       Name
    00  00002000  uboot
    01  00002800  trust
    02  00003800  boot
    03  00007800  rootfs
    04  00025800  userdata
    ```

2. Run `sudo rkdeveloptool rl 0x00003800 $((0x00007800 - 0x00003800)) original-boot.img`, replacing `00003800` with the LBA of the `boot` partition, and replacing `00007800` with the LBA of the partition after the `boot` partition (`rootfs` in the example above).
   This command will create a file on your computer called `original-boot.img`
3. Fix the file permissions of the firmware image file by running `sudo chown $(id -u).$(id -g) original-boot.img`.

## 4. Patch firmware

1. Copy `original-boot.img` (created in [step 2][]) to `hacked-boot.img`.
2. Open `hacked-boot.img` in a hex editor.
3. Search for the bytes `68 6F 73 74 00` (ASCII `host` followed by a null byte).
   Narrow the search down to the occurrence in the second-stage bootloader (i.e. not in the Linux kernel blob).
   TODO: Document how the disk and partitions are configured.
   On Evercade firmware version 1.0, these bytes are at partition byte offset `0x3ba6d0`:

    ```
    3ba6b0: 000001da 00000003 00000004 00000321  ...Ú...........!
    3ba6c0: 6f746700 00000003 00000005 000006d5  otg............Õ
    3ba6d0: 686f7374 00000000 00000003 00000004  host............
    3ba6e0: 000006dd 00000010 00000003 00000004  ...Ý............
    3ba6f0: 000006ef 00000118 00000003 00000018  ...ï............
    ```

4. Replace the bytes with `6f 74 67 00 00` (ASCII `otg` followed by two null bytes).
5. Save the `hacked-boot.img` file.

## 5. Install firmware

1. Run `sudo rkdeveloptool wlx boot hacked-boot.img`.

## 6. Connect with adb

Connecting with adb has only been tested on firmware version 1.0.

1. Turn off your Evercade.
2. Turn on your Evercade as normal.
   (Do not hold down the menu button.)
3. On your computer, run `adb devices`, which should show your Evercade device:

    ```
    List of devices attached
    0123456789ABCDEF        device
    ```

4. Run `adb shell`, `adb pull`, or whatever commands you want.

[rkdeveloptool]: https://github.com/rockchip-linux/rkdeveloptool
[step 2]:
