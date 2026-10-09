# HelloWatch

A Nerves firmware application for the Mobvoi TicWatch Pro 3. It builds on
[`nerves_system_tickwatch_pro3`](https://github.com/mlainez/nerves_system_tickwatch_pro3),
fetched as a git dependency; `mix deps.get` pulls a prebuilt system artifact
from that repository's GitHub releases, so no local Buildroot checkout or
compile is needed to build firmware.

## Try it without building

A prebuilt image of this app is attached to each GitHub release. The
system repository's `flash.sh` downloads and flashes the latest one:

```sh
git clone https://github.com/mlainez/nerves_system_tickwatch_pro3.git
nerves_system_tickwatch_pro3/flash.sh --unlock
```

See the [system's Quickstart](https://github.com/mlainez/nerves_system_tickwatch_pro3#quickstart)
for entering fastboot mode. The prebuilt image is built with
`HELLO_WATCH_PUBLIC_IMAGE=1`, so it carries no Wi-Fi network and no SSH key;
build it yourself (below) to get networking, SSH and `mix upload`.

## Targets

Nerves applications produce images for hardware targets based on the
`MIX_TARGET` environment variable. If `MIX_TARGET` is unset, `mix` builds an
image that runs on the host (e.g., your laptop). This is useful for executing
logic tests, running utilities, and debugging. Other targets are represented by
a short name like `rpi3` that maps to a Nerves system image for that platform.
All of this logic is in the generated `mix.exs` and may be customized. For more
information about targets see:

https://hexdocs.pm/nerves/supported-targets.html

## Getting Started

Copy `config/target.secret.exs.example` to `config/target.secret.exs` and fill
in your own Wi-Fi network — it's gitignored, so it's not shared by cloning
this repo. Without it, wlan0 has no configured network.

The public keys in `~/.ssh` (`id_rsa.pub`, `id_ecdsa.pub`, `id_ed25519.pub`)
are authorized for SSH, which also carries `mix upload`. USB networking
(`usb0`) works without Wi-Fi.

To build a fastboot-compatible image:

```sh
export MIX_TARGET=ticwatch_pro3
mix deps.get
mix firmware
mix firmware.image
```

The raw image is written to `hello_watch.img` in the project root. To flash
it, put the watch in fastboot mode (power off, then hold the top button while
plugging in USB) and run the system's flashing script:

```sh
# First install: unlocks the bootloader (wipes the watch), then flashes
# dtbo, lk2nd and the firmware.
deps/nerves_system_tickwatch_pro3/flash.sh --unlock hello_watch.img

# Later reinstalls over USB, keeping lk2nd:
deps/nerves_system_tickwatch_pro3/flash.sh --app-only hello_watch.img
```

Once it is running, `mix upload` updates the firmware over the network. See
the system repository's README for details on the boot chain.

## Learn more

  * Official docs: https://hexdocs.pm/nerves/getting-started.html
  * Official website: https://nerves-project.org/
  * Forum: https://elixirforum.com/c/nerves-forum
  * Elixir Slack #nerves channel: https://elixir-slack.community/
  * Elixir Discord #nerves channel: https://discord.gg/elixir
  * Source: https://github.com/nerves-project/nerves

## Clock and bottom button

The firmware starts an antialiased analog clock on the 454×454 AMOLED display.
The bottom button toggles the face off/on; touching the screen while it is off
also wakes it. Holding the button does not repeatedly toggle; presses within
250 ms are ignored as contact bounce. Both directions fade over one second
rather than cutting instantly. Rendering pauses while the screen is off.

With no touch, swipe or button activity for 2 minutes, the screen fades off on
its own. Any activity resets that countdown.

Time uses the system clock, which NervesTime synchronizes over the network as UTC.
The face shows local time for the zone named in `config/target.exs`:

```elixir
config :hello_watch, HelloWatch.Clock, time_zone: "Europe/Brussels"
```

This is an IANA zone name, so daylight saving is handled; the zone database is
compiled into the release by `tz` rather than downloaded at runtime. An unknown
zone name falls back to UTC rather than crashing the face.

A charge indicator sits below the centre of the dial. There is no battery
power-supply device on this board, so the reading comes from the sensor hub's
fuel gauge, which reports charge and terminal voltage. The hub hands each event
to a single reader, so the clock keeps one stream open for charge and widens it
to the motion sensors while the sensor page is up.

From SSH/IEx, `HelloWatch.Clock.toggle()` toggles the screen and
`HelloWatch.Clock.status()` reports its state, including the current charge.

### Display support

The renderer draws packed BGR888 frames into `/dev/fb0`. At boot that is
SimpleDRM's framebuffer (24 bpp, 1362-byte stride); once `nerves_uevent`
loads the system's MSM DRM and DSI panel drivers, it is the MSM fbdev
emulation (usually 32 bpp XRGB8888 with padded rows). The renderer reads the
geometry from sysfs, converts accordingly, and releases the framebuffer
console before drawing. The gpio-keys input device is discovered by name; the
bottom button is Linux `KEY_VOLUMEDOWN` (114). The evdev reader uses the
target's 64-bit Linux event layout.

Screen off fades to black and then blanks `/dev/fb0`. With the native panel
driver, blanking powers the panel and display pipeline down; under SimpleDRM
it is a no-op and all-black AMOLED pixels are the lowest-power state. Either
way the watch keeps running and can be woken with the button, a touch, or
reached via SSH. This requires `nerves_system_tickwatch_pro3` v0.2.0 or later.

The renderer has no additional dependencies. Scenic's current framebuffer driver
requires Cairo in the Nerves system; this system does not include it. See the
[Scenic driver requirements](https://github.com/ScenicFramework/scenic_driver_local#targets-nerves)
if expanding this into a larger UI.

```sh
mix test
MIX_TARGET=ticwatch_pro3 mix firmware
MIX_TARGET=ticwatch_pro3 mix upload nerves.local
```
