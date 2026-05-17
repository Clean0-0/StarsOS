//! The StarsOS kernel

// Commented out as it will be used later on in development
// const builtin = @import("std").builtin;
const uart = @import("./uart.zig");


export fn kmain() noreturn {
    
    uart.uart_initialise();

    // Clear the screen
    uart.uart_puts("\x1b[2J");

    uart.uart_puts("Greetings from kernel space!\n");

    while (true) {
        asm volatile ("hlt");
    }
}
