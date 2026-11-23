# PG49-KVM

Switch the video input **and** the USB hub (KVM) of an ASUS ROG Swift OLED PG49WCD
together from software, via DDC/CI. Keyboard and mouse plugged into the monitor follow
the picture.

## Install

Copy this folder to the machine and double-click `install.cmd`, or run:

```powershell
.\install.cmd pc         # desktop PC (DP + USB-B)
.\install.cmd notebook   # notebook (USB-C)
```

No admin rights needed. Installs to `%LOCALAPPDATA%\PG49-KVM` and adds Start Menu
shortcuts in the folder "PG49 KVM".

| Hotkey | Effect |
|---|---|
| Ctrl+Alt+N | picture + USB to notebook (input USB-C) |
| Ctrl+Alt+P | picture + USB to PC (input DP) |

Hotkeys may need a re-login before they work.

Typical use: on the PC press Ctrl+Alt+N; keyboard is now on the notebook; there press
Ctrl+Alt+P to come back.

Role `pc` also installs the task "PG49 KVM Follow" (`kvm-follow.ps1`): if the KVM is
switched in the monitor OSD instead, the picture follows (keyboard gone = USB-C,
keyboard back = DP). It watches one specific keyboard; change `-Keyboard` in
`kvm-follow.ps1` for another device. Log: `%TEMP%\kvm-follow.log`.

Uninstall: `uninstall.cmd`.

## How it works

Found by reverse engineering firmware MCM107 (Realtek RTD2738, MIPS16):

- VCP `0x60` = input: `0x0F` DP, `0x11` HDMI, `0x1A` USB-C.
- VCP `0xF3` = KVM mode: `1` auto, `2` USB-B, `3` USB-C.
- Writing `0xF3` alone only stores the value; the hub switches on the **next input
  change**. So `kvm-switch.ps1` writes `0xF3` first, then `0x60`.
- Auto mode (`0xF3=1`) switches to USB-C on input change but does not come back while
  the notebook stays connected, so it is not used.

Requirements: DDC/CI enabled in the OSD, Windows PowerShell 5.1. Tested on the PC;
the notebook side uses the same DDC path over USB-C and is not yet tested.
