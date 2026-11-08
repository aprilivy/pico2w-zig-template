//! usb cdc serial port that std.log writes to

const std = @import("std");
const microzig = @import("microzig");
const config = @import("config");

const hal = microzig.hal;
const usb = microzig.core.usb;

const Device = hal.usb.Polled(.{});

var device: ?Device = null;
var controller: usb.DeviceController(.{
    .bcd_usb = Device.max_supported_bcd_usb,
    .device_triple = .unspecified,
    .vendor = Device.default_vendor_id,
    .product = .{ .id = Device.default_product_id.id, .str = config.name },
    .bcd_device = .v1_00,
    // no serial number, so the host tells boards apart by which port they're in
    .serial = "",
    .max_supported_packet_size = Device.max_supported_packet_size,
    .configurations = &.{.{
        .attributes = .{ .self_powered = false },
        .max_current_ma = 100,
        .Drivers = struct { serial: usb.drivers.CDC },
    }},
}, .{.{
    .serial = .{ .itf_notifi = config.name, .itf_data = config.name },
}}) = .init;

// the host only reads once a terminal opens the port, so output waits here till then
var pending: [4096]u8 = undefined;
var pending_len: usize = 0;
var dropped: usize = 0;

/// attaches to the bus, safe to call again once attached
pub fn init() void {
    if (device == null) device = .init();
}

/// call often, nothing else services the usb peripheral
pub fn poll() void {
    const dev = if (device) |*d| d else return;
    dev.poll(&controller);

    const serial = &(controller.drivers() orelse return).serial;
    const sent = serial.write(pending[0..pending_len]);
    std.mem.copyForwards(u8, &pending, pending[sent..pending_len]);
    pending_len -= sent;
    _ = serial.flush();
}

/// std.log backend, not safe to call from interrupt handlers or core 1
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime "[{d}.{d:0>6}] " ++ level.asText() ++ switch (scope) {
        .default => ": ",
        else => " (" ++ @tagName(scope) ++ "): ",
    };
    const us = hal.time.get_time_since_boot().to_us();

    if (dropped > 0) {
        if (!append("({d} log messages dropped)\r\n", .{dropped})) {
            dropped += 1;
            return;
        }
        dropped = 0;
    }
    if (!append(prefix ++ format ++ "\r\n", .{ us / std.time.us_per_s, us % std.time.us_per_s } ++ args))
        dropped += 1;
}

fn append(comptime format: []const u8, args: anytype) bool {
    var writer: std.Io.Writer = .fixed(pending[pending_len..]);
    writer.print(format, args) catch return false;
    pending_len += writer.end;
    return true;
}
