//! UEFI bootloader entry for StarsOS.
//! Currently prints a greeting and halts.

const std = @import("std");
const uefi = std.os.uefi;

const output = @import("./output.zig");
const config = @import("./config.zig");
const puts = output.puts;
const printf = output.printf;

pub fn main() void {
    
    // Initialises con_out
    output.init();

    // Print out debug info
    puts("starsOS bootloader v0.0.1\r\n");
    puts("Hello, World!\r\n");

    const countdown = config.countdown;

    // If enabled in the config, it will countdown for n seconds
    // and close.
    if (countdown == true) {
        var wait_time = config.wait_time;
        puts("This screen will close in: ");
        while (wait_time > 0) : (wait_time -= 1) {
            printf("{}...", .{wait_time});
            _ = uefi.system_table.boot_services.?.stall(1_000_000) catch {};
        }
    }
}

