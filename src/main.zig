const std = @import("std");
const microzig = @import("microzig");
const usb_serial = @import("usb_serial.zig");
const wifi = @import("wifi.zig");

const hal = microzig.hal;

pub const std_options = microzig.std_options(.{
    .logFn = usb_serial.log,
    // the usb stack's debug logs would feed back into the port they're sent over
    .log_scope_levels = &.{
        .{ .scope = .usb_dev, .level = .warn },
        .{ .scope = .usb_ctrl, .level = .warn },
        .{ .scope = .usb_cdc, .level = .warn },
    },
});

pub const panic = std.debug.FullPanic(on_panic);

comptime {
    _ = microzig.export_startup();
}

pub fn main() !void {
    // the radio takes a while to come up and usb isn't serviced meanwhile,
    // so attach afterwards rather than stall the host mid-enumeration
    var radio: wifi.Radio = undefined;
    try radio.init();
    usb_serial.init();

    var next_blink = hal.time.get_time_since_boot();
    while (true) {
        usb_serial.poll();
        radio.poll();

        const now = hal.time.get_time_since_boot();
        if (next_blink.is_reached_by(now)) {
            radio.led.toggle();
            next_blink = now.add_duration(.from_ms(if (radio.connecting()) 100 else 500));
        }
    }
}

var panicking = false;

fn on_panic(message: []const u8, _: ?usize) noreturn {
    if (panicking) microzig.hang();
    panicking = true;

    std.log.err("panic: {s}", .{message});
    if (@errorReturnTrace()) |trace| _ = microzig.utilities.dump_error_trace(trace);

    // keep usb running so the log can still be read
    usb_serial.init();
    while (true) usb_serial.poll();
}
