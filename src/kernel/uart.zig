//! This module implements UART (Universal Asynchronous Receiver-Transmitter) functionality.
//! UART is for all intents and purposes a hacky debug measure.
//! For this reason, we do not advise using UART outside of necessity.

const port_io = @import("./port_io.zig");

// COM1 port - all UART registers are offset from here
pub const uart_com1 = 0x3f8;

/// This function initialises UART devices
pub fn uart_initialise() void {
    
    // Write 0x00 to COM1 + 1 to disable interrupts
    port_io.outb(uart_com1 + 1, 0x00);

    // Set the DLAB (Divisor Latch Access Bit) in the Line Control Register
    // This is to set the BAUD rate as it switches to meaning of registers 1 and 0 from data/interrupt registers
    // to BAUD rate divisor registers. 
    port_io.outb(uart_com1 + 3, 0x80);

    // Set the BAUD rate divisor. With DLAB writing to registers 0 an 1 sets the divisor
    // that determines communication speed. 
    port_io.outb(uart_com1 + 0, 0x03);
    port_io.outb(uart_com1 + 1, 0x00);
    
    // Clear DLAB and set format. 8 bits with no parity and one stop bit.
    port_io.outb(uart_com1 + 3, 0x03);

    // Enables FIFO buffers, clear the recieve and transmit buffers.
    port_io.outb(uart_com1 + 2, 0xc7);

    // Configure Modem Control Register. Sets data terminal as ready,
    // and enables the IRQ pin. 
    port_io.outb(uart_com1 + 4, 0x0b);

}

pub inline fn is_uart_transmit_buffer_empty() bool {

    return (port_io.inb(uart_com1 + 5) & 0x20) != 0;

}

pub inline fn uart_putchar(char: u8) void {
    
    // Wait until the transmit buffer is empty
    while (!is_uart_transmit_buffer_empty()) {}

    // If it is empty, send the character to our COM1 port
    port_io.outb(uart_com1, char);

}

pub fn uart_puts(str: []const u8) void {

    for (str) |char| {
        // Unfortunately only accepts one character at a time
        // because UART is a hacky POS.
        uart_putchar(char);

    }

}


