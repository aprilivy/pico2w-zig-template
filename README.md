# pico2w-zig-template

starting point for raspberry pi pico 2 w firmware in zig, on [microzig](https://github.com/ZigEmbeddedGroup/microzig).
blinks the onboard led, logs over usb serial, and joins a wi-fi network and gets an address over dhcp if you give it one.

needs zig 0.17.1, which is what microzig 0.17.35 asks for.

## build

```sh
zig build
```

writes `zig-out/firmware/pico2w_template.uf2` and a matching `.elf` with debug info.
the default is a debug build with safety checks on. `zig build --release=small` makes a smaller one.

to join a network on boot:

```sh
zig build -Dwifi-ssid=MyNetwork -Dwifi-password=secret
```

without `-Dwifi-password` it joins as an open network, otherwise as wpa2-psk.
if a join fails, or the network drops and the chip doesn't rejoin by itself, it tries again every 10 seconds.
once dhcp hands out an address the log shows `online at <address>`.
wpa3-only networks need `.wpa3_sae` in `src/wifi.zig`.
the regulatory country is set there too (`GB`).

the credentials are compiled into the firmware, so they're in `zig-out/` and `.zig-cache/`.
both are gitignored.

## flash

hold bootsel while plugging the board in. it mounts as a drive called `RP2350`.
copy the `.uf2` onto it and the board reboots into the new firmware.

## logs

the board shows up as a usb serial port (a `COM` port on windows). open it with any terminal, the baud rate doesn't matter.
`std.log` output from boot onwards waits in a 4 KiB buffer until a terminal opens the port.
anything past that is dropped, and the log says how many messages went.

panics are logged the same way, and the port stays up afterwards so you can read them.
to turn the trace addresses into source lines:

```sh
arm-none-eabi-addr2line -e zig-out/firmware/pico2w_template.elf 0x1000abcd
```

## led

the led is wired to the wi-fi chip, not the rp2350, so it only works once the chip is up.

- fast blink: no address yet. joining, waiting on dhcp, or the network was lost
- slow blink: online, or built without wi-fi
- not blinking: the firmware stopped. check the serial log

## layout

- `src/main.zig`: startup, the main loop, and the panic handler
- `src/usb_serial.zig`: the usb serial port and the `std.log` backend
- `src/wifi.zig`: the cyw43 chip, which owns the led, the wi-fi join and the lwip interface
- `vendor/`: microzig's `net` and `lwip` packages with a packaging fix, see `vendor/README.md`

usb and the radio are both polled from the main loop, so add your code there and keep each pass short.
anything that blocks stalls both.

the lwip interface is `nic` in `src/wifi.zig`. microzig's `net` package has `Udp` and `tcp` on top of it.

to build for the risc-v cores instead, change `pico2_arm` to `pico2_riscv` in `build.zig`.

## new project from this

1. copy the folder
2. change `.name` in `build.zig.zon`. it's also the firmware file name and the usb product string
3. delete the `.fingerprint` line and run `zig build`. zig prints a new value to paste back in
