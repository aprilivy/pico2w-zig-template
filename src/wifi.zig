//! the cyw43 wireless chip, which also owns the onboard led

const std = @import("std");
const microzig = @import("microzig");
const config = @import("config");

const hal = microzig.hal;
const Chip = hal.drivers.WiFi.Chip;
// microzig doesn't export this type by name
const JoinPoller = @typeInfo(@typeInfo(@TypeOf(Chip.join)).@"fn".return_type.?).error_union.payload;
const log = std.log.scoped(.wifi);

// regulatory domain, decides which channels the radio may use
const country = "GB";

pub const Radio = struct {
    driver: hal.drivers.WiFi,
    led: Chip.Pin,
    /// null when the firmware was built without -Dwifi-ssid
    network: ?Network,

    const Network = struct {
        ssid: []const u8,
        joining: ?JoinPoller,
        joined: bool,
        frame: [1540]u8 align(4),
    };

    /// brings the chip up and starts joining the network given at build time.
    /// fills `self` in place because the driver keeps pointers into it
    pub fn init(self: *Radio) !void {
        self.driver = .{};
        const chip = try self.driver.init(.{ .country = .{ .code = country.* } });
        log.info("mac {x}", .{chip.mac});
        self.led = chip.gpio(0);

        const ssid = config.wifi_ssid orelse {
            log.info("built without -Dwifi-ssid, staying offline", .{});
            self.network = null;
            return;
        };
        log.info("joining {s}", .{ssid});
        self.network = .{
            .ssid = ssid,
            .joining = try chip.join(ssid, config.wifi_password orelse "", .{
                .security = if (config.wifi_password == null) .open else .wpa2_psk,
            }),
            .joined = false,
            .frame = undefined,
        };
    }

    pub fn poll(self: *Radio) void {
        const network = if (self.network) |*n| n else return;
        const chip = &self.driver.chip;

        if (network.joining) |*joiner| {
            const still_joining = joiner.poll() catch |err| blk: {
                log.err("couldn't join {s}: {t}", .{ network.ssid, err });
                break :blk false;
            };
            if (!still_joining) network.joining = null;
        } else {
            // nothing runs above the link layer yet, so frames are only read
            // to keep link events coming, then dropped
            _ = Chip.recv_zc(chip, &network.frame) catch |err| log.warn("receive failed: {t}", .{err});
        }

        const joined = chip.is_joined();
        if (joined == network.joined) return;
        network.joined = joined;
        if (joined) {
            log.info("joined {s}", .{network.ssid});
        } else {
            log.warn("lost {s}", .{network.ssid});
        }
    }

    /// true while a network is configured but not joined
    pub fn connecting(self: *const Radio) bool {
        const network = self.network orelse return false;
        return !network.joined;
    }
};
