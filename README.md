# HelloWatch

Example Nerves app for the Mobvoi TicWatch Pro 3, built on
[`nerves_system_tickwatch_pro3`](https://github.com/mlainez/nerves_system_tickwatch_pro3).
It shows an analog clock face with network and sensor pages.

## Try it without building

Put the watch in fastboot mode (power off, then hold the top button while
plugging in USB) and run:

```sh
git clone https://github.com/mlainez/nerves_system_tickwatch_pro3.git
nerves_system_tickwatch_pro3/flash.sh --unlock
```

This flashes the latest prebuilt image from this repository's releases.
`--unlock` **wipes the watch**. The prebuilt image has no Wi-Fi or SSH
configured; build it yourself for those.

## Build and flash

```sh
cp config/target.secret.exs.example config/target.secret.exs  # your Wi-Fi
export MIX_TARGET=ticwatch_pro3
mix deps.get
mix firmware.image

deps/nerves_system_tickwatch_pro3/flash.sh --unlock hello_watch.img    # first install
deps/nerves_system_tickwatch_pro3/flash.sh --app-only hello_watch.img  # reinstall
mix upload                                                             # over the network
```

Your `~/.ssh/id_*.pub` keys are authorized for SSH and `mix upload`. USB
networking (`usb0`) works without Wi-Fi. `mix test` runs the host tests.

`HELLO_WATCH_PUBLIC_IMAGE=1` builds the image published on releases,
without your SSH keys or Wi-Fi credentials.

## Using it

- **Bottom button** toggles the screen; a touch also wakes it. The screen
  fades off after 2 minutes idle.
- **Swipe** left or right to switch between the clock, network and sensor
  pages.
- The **charge indicator** reads the sensor hub's fuel gauge.
- From IEx: `HelloWatch.Clock.toggle()`, `HelloWatch.Clock.status()`.

Set the time zone (IANA name, falls back to UTC) in `config/target.exs`:

```elixir
config :hello_watch, HelloWatch.Clock, time_zone: "Europe/Brussels"
```

## Notes

- **Display:** frames are drawn straight to `/dev/fb0`, which handles both
  SimpleDRM (24 bpp) and the MSM driver (32 bpp, padded rows). Turning the
  screen off blanks the framebuffer, which powers the panel down with
  system v0.2.0 or later. There are no UI dependencies; Scenic would need
  Cairo, which the system does not include.
- **Time:** `HelloWatch.PmicRtc` is a `NervesTime` RTC that keeps the clock
  across reboots by storing an offset to the PMIC counter, which Linux
  cannot set.
- **Wi-Fi MAC:** `HelloWatch.WiFi.stable_mac/0` derives a stable address
  from the eMMC CID.
- **GPS:** `HelloWatch.GPS.start_stream/0` and `subscribe/0` deliver
  `{:gps, map}` messages.
