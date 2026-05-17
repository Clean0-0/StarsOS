//! This module gives the core kernel loading functionality

const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;

const output = @import("./output.zig");
const efi = @import("./efi.zig");
const puts = output.puts;
const printf = output.printf;
/// Read a UEFI file
pub fn read_file(
    file: *uefi.protocol.File,
    position: u64,
    buffer: []u8,
) !void {
    file.setPosition(position) catch |err| {
        puts("Error: setting file position failed\r\n");
        return err;
    };

    _ = try file.read(buffer);
}

/// Read a UEFI file and allocate free memory for it
pub fn read_and_allocate(
    file: *uefi.protocol.File,
    position: u64,
    size: usize,
    buffer: *[]u8,
) !void {
    const boot_services = uefi.system_table.boot_services.?;
    buffer.* = boot_services.allocatePool(.loader_data, size) catch |err| {
        puts("Error: Allocating space for file failed\r\n");
        return err;
    };

    try read_file(file, position, buffer.*);
}

/// Load an ELF program segment

pub fn load_segment (
    file: *uefi.protocol.File,
    segment_file_offset: u64,
    segment_file_size: usize,
    segment_memory_size: usize,
    segment_virtual_address: u64,
) !void {
   if (segment_virtual_address & 4095 != 0 ) {
        puts("Warning: segment_virtual_address is not aligned, returning\r\n");
        return;
   } 
   var segment_buffer: []u8 = &.{};
   const segment_page_count = efi.efi_size_to_pages(segment_memory_size);
   var zero_fill_start: u64 = 0;
   var zero_fill_count: usize = 0;
   const boot_services = uefi.system_table.boot_services.?;
    
   printf("Allocating {} pages at address 0x{x}\r\n", .{ segment_page_count, segment_virtual_address});

   const segbuf = (boot_services.allocatePages(
           .{ .address = @ptrFromInt(segment_virtual_address) },
           .loader_data,
           segment_page_count,
        ) catch |err| {
            puts("Error: Allocating pages for ELF segment failed\r\n");
            return err;
        });
    segment_buffer.ptr = @ptrCast(segbuf.ptr);
    segment_buffer.len = segbuf.len * 4096;

    if (segment_file_size > 0) {
        printf("Reading segment data with file size 0x{x}\r\n", .{segment_file_size});
        read_file(file, segment_file_offset, segment_buffer) catch |err| {
            puts("Error: Reading segment data failed\r\n");
            return err;
        };
    }
    zero_fill_start = segment_virtual_address + segment_file_size;
    zero_fill_count = segment_memory_size - segment_file_size;

    // ELF spec requires unused bytes between file size and memory size
    // to be zeroed — typically covers uninitialised data like .bss
    if (zero_fill_count > 0) {
        printf("Zero-filling {} bytes at address 0x{x}\r\n", .{ zero_fill_count, zero_fill_start});
        
        @memset(@as([*]u8, @ptrFromInt(zero_fill_start))[0..zero_fill_count], 0);
        puts("Zero-filling bytes succeeded\r\n");
    }
}

/// Load all ELF program segments
pub fn load_program_segments(
    file: *uefi.protocol.File,
    program_headers: []const elf.Elf64_Phdr,
    base_physical_address: u64,
    kernel_start_address: *u64,
) !void {
    var n_segments_loaded: u64 = 0;
    var set_start_address: bool = true;
    var base_address_difference: u64 = 0;
    if (program_headers.len == 0) {
        puts("Error: No program segments to load\r\n");
        return error.InvalidParameter;
    }
    printf("Loading {} segments\r\n", .{program_headers.len});
    for (program_headers, 0..) |prog_hdr, i| {
        if (prog_hdr.p_type == elf.PT_LOAD) {
            printf("Loading program segment {}\r\n", .{i});
            if (set_start_address) {
                set_start_address = false;
                kernel_start_address.* = prog_hdr.p_vaddr;
                base_address_difference = prog_hdr.p_vaddr - base_physical_address;
                    printf("Set kernel start address to 0x{x} and base address difference to 0x{x}\r\n", .{ kernel_start_address.*, base_address_difference });
            }
            load_segment(
                file,
                prog_hdr.p_offset,
                prog_hdr.p_filesz,
                prog_hdr.p_memsz,
                prog_hdr.p_vaddr - base_address_difference,
            ) catch |err| {
                printf("Error: Loading program segment {} failed\r\n", .{i});
                return err;
            };
            n_segments_loaded += 1;
        }
    }
    if (n_segments_loaded == 0) {
        puts("Error: No loadable program segments found in executable\r\n");
        return error.NotFound;
    }
}

pub fn load_kernel_image(
    root_file_system: *const uefi.protocol.File,
    kernel_image_filename: [*:0]const u16,
    base_physical_address: u64,
    kernel_entry_point: *u64,
    kernel_start_address: *u64,
) !void {
    const boot_services = uefi.system_table.boot_services.?;
    var kernel_img_file: *uefi.protocol.File = undefined;
    var header_buffer: []u8 = undefined;
    puts("Opening kernel image\r\n");
    kernel_img_file = root_file_system.open(
        kernel_image_filename,
        .read,
        .{ .read_only = true },
    ) catch |err| {
        puts("Error: Opening kernel file failed\r\n");
        return err;
    };
    defer kernel_img_file.close() catch {};
    {
        puts("Checking ELF identity\r\n");
        read_and_allocate(kernel_img_file, 0, elf.EI_NIDENT, &header_buffer) catch |err| {
            puts("Error: Reading ELF identity failed\r\n");
            return err;
        };
        defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};
        if ((header_buffer[0] != 0x7f) or
            (header_buffer[1] != 0x45) or
            (header_buffer[2] != 0x4c) or
            (header_buffer[3] != 0x46))
        {
            puts("Error: Invalid ELF magic\r\n");
            return error.InvalidParameter;
        }
        if (header_buffer[elf.EI_CLASS] != elf.ELFCLASS64) {
            puts("Error: Can only load 64-bit binaries\r\n");
            return error.Unsupported;
        }
        if (header_buffer[elf.EI_DATA] != elf.ELFDATA2LSB) {
            puts("Error: Can only load little-endian binaries\r\n");
            return error.IncompatibleVersion;
        }
        puts("ELF identity is good; continuing loading\r\n");
    }
        puts("Loading ELF header\r\n");
    read_and_allocate(kernel_img_file, 0, @sizeOf(elf.Elf64_Ehdr), &header_buffer) catch |err| {
        puts("Error: Reading ELF header failed\r\n");
        return err;
    };
    defer boot_services.freePool(@alignCast(header_buffer.ptr)) catch {};
    var hdr_reader: std.Io.Reader = .fixed(header_buffer[0..64]);
    const header = elf.Header.read(&hdr_reader) catch |err| {
        switch (err) {
            error.InvalidElfMagic => {
                puts("Error: Invalid ELF magic\r\n");
            },
            error.InvalidElfVersion => {
                puts("Error: Invalid ELF version\r\n");
            },
            error.InvalidElfEndian => {
                puts("Error: Invalid ELF endianness\r\n");
            },
            error.InvalidElfClass => {
                puts("Error: Invalid ELF class\r\n");
            },
            else => {},
        }
        return err;
    };
    printf("Loading ELF header succeeded; entry point is 0x{x}\r\n", .{header.entry});
    kernel_entry_point.* = header.entry;
    puts("Loading program headers\r\n");
    var program_headers_buffer: []u8 = undefined;
    read_and_allocate(kernel_img_file, header.phoff, header.phentsize * header.phnum, &program_headers_buffer) catch |err| {
        puts("Error: Reading ELF program headers failed\r\n");
        return err;
    };
    defer boot_services.freePool(@alignCast(program_headers_buffer.ptr)) catch {};
    const program_headers = @as([*]const elf.Elf64_Phdr, @ptrCast(@alignCast(program_headers_buffer)))[0..header.phnum];
    try load_program_segments(kernel_img_file, program_headers, base_physical_address, kernel_start_address);
}
