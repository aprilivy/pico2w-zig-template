const std = @import("std");
const microzig = @import("microzig");
const manifest = @import("build.zig.zon");

const MicroBuild = microzig.MicroBuild(.{ .rp2xxx = true });

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const wifi_ssid = b.option([]const u8, "wifi-ssid", "Wi-Fi network to join on boot (Wi-Fi stays off without it)");
    const wifi_password = b.option([]const u8, "wifi-password", "Wi-Fi password (leave out for an open network)");

    if (wifi_password != null and wifi_ssid == null) {
        b.getInstallStep().dependOn(&b.addFail("-Dwifi-password needs -Dwifi-ssid as well").step);
        return;
    }

    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;
    // swap for pico2_riscv to run on the hazard3 cores instead
    const target = mb.ports.rp2xxx.boards.raspberrypi.pico2_arm;

    const net_dep = b.dependency("net", .{
        .target = b.resolveTargetQuery(target.zig_target),
        .optimize = optimize,
        // the cyw43 wants 22 bytes in front of each ethernet frame and 4 after: 22 + 14 + 1500 + 4
        .mtu = 1500,
        .pbuf_header_length = 22,
        .pbuf_length = 1540,
    });

    const config = b.addOptions();
    config.addOption([]const u8, "name", @tagName(manifest.name));
    config.addOption(?[]const u8, "wifi_ssid", wifi_ssid);
    config.addOption(?[]const u8, "wifi_password", wifi_password);

    const fw = mb.add_firmware(.{
        .name = @tagName(manifest.name),
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "net", .module = net_dep.module("net") },
            .{ .name = "config", .module = config.createModule() },
        },
    });

    mb.install_firmware(fw, .{});
    mb.install_firmware(fw, .{ .format = .elf });
}
