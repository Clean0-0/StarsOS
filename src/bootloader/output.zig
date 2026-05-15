//! This module provides text output via UEFI ConOut for the bootloader sequence.
//! All functions must be called before ExitBootServices.

const std = @import("std");
const uefi = std.os.uefi;

// UEFI protocol to output text to console.
var con_out: *uefi.protocol.SimpleTextOutput = undefined;


// Initialises con_out
pub fn init() void {
    con_out = uefi.system_table.con_out.?;
    con_out.reset(false) catch {};
}

/// Function to simply put text to the UEFI console without formatting
pub fn puts(msg: []const u8) void {
    
    // Create a buffer for the characters to be loaded into
    var buffer: [256:0]u16 = undefined;
    
    // Insert the characters one by one into the buffer
    for (msg, 0..) |c, i| {
        buffer[i] = c;
    }
    // Add a zero to the end of the string to ensure it can be null terminated
    buffer[msg.len] = 0;
    // Actually output the string within the buffer
    _ = con_out.outputString(&buffer) catch {};

}

/// Formatted printing function that prints to the UEFI console
pub fn printf(comptime fmt: []const u8, args:anytype) void {
    var buffer: [256:0]u8 = undefined;
    var msg: []u8 = undefined;

    // Calls a function to write and format string arguments
    // into the buffer.
    msg = std.fmt.bufPrint(&buffer, fmt, args) catch unreachable;
    puts(msg);
}
