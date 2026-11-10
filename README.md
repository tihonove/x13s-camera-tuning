# x13s-camera-tuning

Better front camera picture on the **ThinkPad X13s** under Linux: a colour
calibration for the `ov5675` sensor plus a few patches to libcamera's software
ISP. Everything runs on the GPU inside libcamera, so apps (Chrome, Firefox,
anything on pipewire) just see the normal built-in camera. No daemon, no virtual
camera. 0% CPU when the camera is off, about 6% of one core during a call.

Out of the box the X13s camera is dull. Qualcomm's hardware ISP isn't available
on Linux, so libcamera processes frames in its software ISP using
`uncalibrated.yaml`, where the colour correction matrix is turned off. This repo
adds:

- **Colour matrix**: solved from a ColorChecker chart, applied at half strength
  and a bit warmer (`tuning/ov5675.yaml`, full solution in `tuning/ccm-linear.json`)
- **Auto exposure**: AGC fixes from libcamera 0.7.2, plus a configurable target
  and highlight limit, so it doesn't blow out next to a window
- **White balance** that ignores clipped pixels (no more green faces outdoors)
- **Contrast** read from the tuning file

> Tested on one machine: X13s, BIOS 1.67, Ubuntu 26.04, libcamera0.7
> `0.7.0-1ubuntu2`. It's a personal setup shared as is, not an official package.

## Requirements

- Ubuntu 26.04 arm64 with `libcamera0.7` **exactly** `0.7.0-1ubuntu2`
  (`dpkg-query -W libcamera0.7`). pipewire is built against this library, so the
  patched one has to match it. The scripts refuse to run on another version.
- Camera through pipewire + wireplumber (user services). Sound doesn't matter:
  restarting pipewire is fine on PulseAudio, on pipewire-pulse audio will blip once.

## Install

```sh
sudo apt install --no-install-recommends git curl ca-certificates build-essential \
    meson ninja-build pkgconf python3-yaml python3-jinja2 libegl-dev libgles-dev libyaml-dev

git clone https://github.com/tihonove/x13s-camera-tuning
cd x13s-camera-tuning
./build.sh            # no root; clones libcamera into .work/, result in out/
./camera-mode gpu     # copies to ~/.local/share/x13s-camera-tuning, restarts pipewire
```

Then restart your browser (it keeps the old camera node).

`./camera-mode status` shows the current mode and which tuning file the running
pipewire uses.

## Undo

```sh
./camera-mode stock
```

This removes the two drop-ins and `~/.local/share/x13s-camera-tuning`, and
restarts pipewire and wireplumber. By hand:

```sh
rm ~/.config/systemd/user/{pipewire,wireplumber}.service.d/x13s-camera-tuning.conf
systemctl --user daemon-reload
systemctl --user restart pipewire wireplumber
```

No system files are touched: the patched `libcamera.so` and IPA module are only
loaded by pipewire and wireplumber, via `LD_LIBRARY_PATH` and
`LIBCAMERA_IPA_MODULE_PATH` in their drop-ins.

## After a libcamera update

If apt upgrades `libcamera0.7`, `./camera-mode gpu` will refuse to start with the
old build. Go back to `./camera-mode stock`. Supporting a new version means
taking the Ubuntu patches from the new `debian.tar.xz` into `patches/ubuntu/`,
updating `PKG` in `build.sh` and rebuilding.

## Tweaking

Everything you'd want to tune is in `tuning/ov5675.yaml`. Edit the copy in
`~/.local/share/x13s-camera-tuning/ov5675.yaml` and restart pipewire to try a
change, or edit the repo copy and run `./camera-mode gpu` again.

- matrix too strong or too weak: blend toward identity, `I + s (M - I)` with the
  full matrix from `ccm-linear.json`
- picture too bright or too dark: `Agc` / `target`
- a bit more punch: `contrast: 1.098` with `gamma: 2.38`

## Known limits

- Exposure can't go longer than 33.6 ms (30 fps), so dark rooms stay noisy. There's
  no denoising here.
- No black point correction yet, so the picture is a little flat.
- One matrix for all light; it was measured under ~D65 (a phone screen). Warm
  indoor light isn't calibrated separately.
- On some X13s units the camera can get stuck until reboot after its power domain
  turns off. That's a separate issue and not fixed here.

## What's inside

| path | what |
|---|---|
| `build.sh` | builds libcamera 0.7.0 as the Ubuntu package + `patches/` |
| `camera-mode` | `gpu` / `stock` / `status` switcher |
| `patches/0001-0002` | AGC fixes from libcamera 0.7.2 (upstream authors) |
| `patches/0003-0006` | contrast from tuning file, AWB without clipped pixels, build fix, AGC target from tuning file |
| `patches/ubuntu/` | patches of the Ubuntu `0.7.0-1ubuntu2` package |
| `tuning/` | tuning file and the solved colour matrix |

## Licenses

Patches to libcamera are under libcamera's license (LGPL-2.1-or-later).
`tuning/ov5675.yaml` is CC0. The scripts are MIT.

## Thanks

libcamera folks for the GPU soft ISP, Johan Hovold and Linaro for getting the
X13s into mainline, and the Ubuntu X13s maintainers.
