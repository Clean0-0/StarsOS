//! Raw x86-64 port I/O primitives
//! These are the lowest forms of hardware communication functions found in the kernel

/// Reads a single byte from an x86 I/O port
pub fn inb(port: u16) u8 {
    // 'in' is the x86 instruction for I/O reads
    // The port number must be in dx, and the result is to placed into al
    return asm volatile ("in %[port], %[ret]"
        // ret to al, and return it as u8
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

/// Writes a single byte to an x86 I/O port
pub fn outb(port: u16, val: u8) void {
    // 'out' is the x86 instruction for I/O writes
    // The byte to be written (val) is to be stored in al
    // The port to be written to is stored in dx
    asm volatile ("out %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}
