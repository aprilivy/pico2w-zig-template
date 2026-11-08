//! the cyw43 wireless chip, which also owns the onboard led

const std = @import("std");
const microzig = @import("microzig");
const net = @import("net");
const config = @import("config");

const hal = microzig.hal;
const time = microzig.drivers.time;
const Chip = hal.drivers.WiFi.Chip;
// microzig doesn't export this type by name
const JoinPoller = @typeInfo(@typeInfo(@TypeOf(Chip.join)).@"fn".return_type.?).error_union.payload;
const log = std.log.scoped(.wifi);

// regulatory domain, decides which channels the radio may use
const country = "GB";
const retry_delay: time.Duration = .from_ms(10_000);

pub const Radio = struct {
    driver: hal.drivers.WiFi,
    led: Chip.Pin,
    /// null when the firmware was built without -Dwifi-ssid
    network: ?Network,

    const Network = struct {
        ssid: []const u8,
        /// lwip interface, gets its address over dhcp
        nic: net.Interface,
        state: union(enum) {
            joining: JoinPoller,
            joined,
            /// join again at this time, unless the chip rejoins by itself first
            down: time.Absolute,
        },
        online: bool,

        fn step(network: *Network, chip: *Chip, now: time.Absolute) !void {
            switch (network.state) {
                .joining => |*joiner| {
                    if (try joiner.poll()) return;
                    log.info("joined {s}", .{network.ssid});
                    network.state = .joined;
                },
                .joined => if (!chip.is_joined()) {
                    log.warn("lost {s}", .{network.ssid});
                    network.state = .{ .down = now.add_duration(retry_delay) };
                },
                .down => |retry_at| if (chip.is_joined()) {
                    log.info("joined {s}", .{network.ssid});
                    network.state = .joined;
                } else if (retry_at.is_reached_by(now)) {
                    log.info("joining {s}", .{network.ssid});
                    // the driver keeps the last attempt's events, which would fail this one straight away
                    chip.wifi.event_log = .{};
                    network.state = .{ .joining = try chip.join(network.ssid, config.wifi_password orelse "", .{
                        .security = if (config.wifi_password == null) .open else .wpa2_psk,
                    }) };
                },
            }
        }
    };

    /// brings the chip up, joining starts on the first poll.
    /// fills `self` in place because the driver and lwip keep pointers into it
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
        self.network = .{
            .ssid = ssid,
            .nic = .{ .link = chip.link() },
            .state = .{ .down = hal.time.get_time_since_boot() },
            .online = false,
        };
        try self.network.?.nic.init(chip.mac, .{});
    }

    pub fn poll(self: *Radio) void {
        const network = if (self.network) |*n| n else return;
        const chip = &self.driver.chip;
        const now = hal.time.get_time_since_boot();

        network.step(chip, now) catch |err| {
            log.err("couldn't join {s}: {t}", .{ network.ssid, err });
            // the driver would return it from every receive until the next join
            chip.wifi.err = null;
            network.state = .{ .down = now.add_duration(retry_delay) };
        };

        // a join that fails makes the next receive return its error, and
        // net's poll leaks a packet buffer whenever a receive errors
        if (network.state == .joining) return;
        network.nic.poll() catch |err| log.warn("network poll failed: {t}", .{err});

        const online = network.nic.ready();
        if (online == network.online) return;
        network.online = online;
        if (online) {
            log.info("online at {s}", .{std.mem.span(net.lwip.ipaddr_ntoa(&network.nic.netif.ip_addr))});
        } else {
            log.warn("offline", .{});
        }
    }

    /// true while a network is configured but there's no address on it
    pub fn connecting(self: *const Radio) bool {
        const network = self.network orelse return false;
        return !network.online;
    }
};

// lwip calls these, see vendor/net/src/include/arch/cc.h
export fn lwip_sys_now() u32 {
    return @truncate(hal.time.get_time_since_boot().to_us() / std.time.us_per_ms);
}

export fn lwip_rand() u32 {
    return hal.rand.trng.random_blocking();
}
