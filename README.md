# PG49-KVM

Switch the video input **and** the USB hub (KVM) of an ASUS ROG Swift OLED PG49WCD
together from software, via DDC/CI. Keyboard and mouse plugged into the monitor follow
the picture.

## Install

Copy this folder to the machine and double-click `install.cmd`, or run:

```powershell
.\install.cmd -Role pc -PcInput dp          # desktop PC on DisplayPort + USB-B
.\install.cmd -Role pc -PcInput hdmi        # desktop PC on HDMI + USB-B
.\install.cmd -Role notebook -PcInput dp    # notebook (USB-C); PcInput = where the PC sits
```

Without arguments the installer asks. No admin rights needed. Installs to
`%LOCALAPPDATA%\PG49-KVM`, starts a tray icon at logon (task "PG49 KVM") and adds Start
Menu shortcuts in the folder "PG49 KVM".

**Tray icon:** green `N` = notebook, blue `P` = PC, amber = switching, gray `?` =
unknown. Left click switches to the other side; right click opens a menu with both
targets (current one checked) and Exit. Start it again via Start Menu > PG49 KVM >
PG49 KVM Tray.

| Hotkey | Effect |
|---|---|
| Ctrl+Alt+N | picture + USB to notebook (input USB-C) |
| Ctrl+Alt+P | picture + USB to PC (input DP or HDMI) |

Hotkeys may need a re-login before they work.

On both machines the tray also follows a KVM switch made in the monitor OSD: the
keyboard appears = picture to this machine, keyboard gone = picture to the other one.
So the notebook takes the picture even while the PC is off. The installer picks the
first keyboard behind the monitor's USB hub, so run it while the KVM is on that
machine; pass `-Keyboard <USB instance id>` to choose another device.

The tray checks GitHub (`main`) for new versions 1 minute after start, then daily, and
via right click > Check for updates. Changed scripts are replaced and the tray
restarts. A copy running from a git checkout is never updated.

Uninstall: `uninstall.cmd`.

## How it works

Found by reverse engineering firmware MCM107 (Realtek RTD2738, MIPS16):

- VCP `0x60` = input: `0x0F` DP, `0x11` HDMI, `0x1A` USB-C.
- VCP `0xF3` = KVM mode: `1` auto, `2` USB-B, `3` USB-C.
- Writing `0xF3` alone only stores the value; the hub switches on the **next input
  change**. So `kvm-switch.ps1` writes `0xF3` first, then `0x60`.
- After a switch `kvm-switch.ps1` pre-sets `0xF3` to the other side. The hub does not
  move, but the next input change takes it along. So if one machine is off (the OSD
  then hides the USB menu), selecting the other input in the OSD also moves keyboard
  and mouse (tested). The tray re-arms `0xF3` after such an OSD change, so the way back
  works the same. The OSD KVM entry therefore shows the other side; that is expected.
- Auto mode (`0xF3=1`) switches to USB-C on input change but does not come back while
  the notebook stays connected, so it is not used.

Requirements: DDC/CI enabled in the OSD, Windows PowerShell 5.1. Tested on both
sides: the PC (DP + USB-B) and the notebook (DDC over the USB-C cable). The HDMI path
uses the same mechanism but is not tested yet.
