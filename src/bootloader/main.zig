//! UEFI bootloader entry for StarsOS.
//! Currently prints a greeting and halts.

const std = @import("std");
const uefi = std.os.uefi;

const output = @import("./output.zig");
const config = @import("./config.zig");
const loader = @import("./loader.zig");
const puts = output.puts;
const printf = output.printf;

fn countdown(countdown_enabled: bool) void {
    // If enabled in the config, it will countdown for n seconds
    // and close.
    if (countdown_enabled) {
        var wait_time = config.wait_time;
        puts("This screen will close in: ");
        while (wait_time > 0) : (wait_time -= 1) {
            printf("{}...", .{wait_time});
            _ = uefi.system_table.boot_services.?.stall(1_000_000) catch {};
        }
        puts("\r\n");
    }
}


fn bootloader() !void{
    // Initialises con_out
    output.init();

    // Print out debug info
    puts("starsOS v0.0.2\r\n");
    
    const boot_services = uefi.system_table.boot_services.?;
    const runtime_services = uefi.system_table.runtime_services;
    const kernel_executable_path: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("\\kernel.elf");
    
    var root_file_system: *const uefi.protocol.File = undefined;

    var memory_map: uefi.tables.MemoryMapSlice = undefined;
    var memory_map_size: usize = @sizeOf(uefi.tables.MemoryMapSlice);
    var memory_map_key: uefi.tables.MemoryMapKey = undefined;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;

    var kernel_entry_point: u64 = undefined;
    var kernel_start_address: u64 = undefined;

    var kmain: *const fn () callconv(.c) void = undefined;

   puts("Starting Filesystem\r\n"); 
   
   const file_system = blk: {
        const res = boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null) catch |err| {
            puts ("Error: Could not local the filesystem protocol\r\n");
            return err;
        };
        if (res) |fs| {
            break :blk fs;
        } else {
            puts("Error: Filesystem protocol not found\r\n");
            return error.NotFound;
        }
    };

   puts("Opening root volume\r\n");

   root_file_system = file_system.openVolume() catch |err| {
        puts("Error: Opening root volume failed\r\n");
        return err;
   };

    puts("Getting memory map to find free addresses\r\n");

    var memmap_info = boot_services.getMemoryMapInfo() catch |err| {
        puts("Error: Getting memory map info failed\r\n");
        return err;
    };

    descriptor_size = memmap_info.descriptor_size;
    descriptor_version = memmap_info.descriptor_version;
    memory_map_key = memmap_info.key;

    memory_map_size = memmap_info.len * descriptor_size;

    var memory_map_buffer = boot_services.allocatePool(.boot_services_data, memory_map_size) catch |err| {
        puts("Error: Allocating memory map failed\r\n");
        return err;
    };

    memory_map = boot_services.getMemoryMap(memory_map_buffer) catch |err| {
        puts("Error: Getting memory map failed\r\n");
        return err;
    };

    puts("Finding free kernel base address\r\n");

    var mem_index: usize = 0;
    var mem_count: usize = memmap_info.len;
    var mem_point: *uefi.tables.MemoryDescriptor = undefined;
    var base_address: u64 = 0x100000;
    var num_pages: usize = 0;

    printf("mem_count is {}\r\n", .{mem_count});
    
    while (mem_index < mem_count) : (mem_index += 1) {
        printf("mem_index is {}\r\n", .{mem_index});
    
        mem_point = @ptrFromInt(@intFromPtr(memory_map.ptr) + (mem_index * descriptor_size));

        if (mem_point.type == .conventional_memory and mem_point.physical_start >= base_address) {
            base_address = mem_point.physical_start;
            num_pages = mem_point.number_of_pages;
            printf("Found {} free pages at 0x{x}\r\n", .{num_pages, base_address});
            break;
        }
    }

    puts("Loading kernel image\r\n");
    
    loader.load_kernel_image(
        root_file_system,
        kernel_executable_path,
        base_address,
        &kernel_entry_point,
        &kernel_start_address,
    ) catch |err| {
        printf("Set kernel entry point to: 0x{x}\r\n", .{kernel_entry_point});
        return err;
    };

    puts("Disabling watchdog timer\r\n");
    

    boot_services.setWatchdogTimer(0, 0, null) catch |err|{
        puts("Error: Disabling watchdog timer failed\r\n");
        return err;
    };
    
    // getMemoryMap invalidates the key — any allocation between calls
    // makes the key stale. Retry until exitBootServices succeeds.
    while (blk: {
        boot_services.exitBootServices(uefi.handle, memory_map_key) catch break :blk true;
        break :blk false;
    }) {
        puts("Getting memory map and trying to exit boot services \r\n");

        if (config.countdown) {
            countdown(config.countdown);
        }

        memmap_info = boot_services.getMemoryMapInfo() catch |err| {
            puts("Error: Getting memory map info failed\r\n"); 
            return err;
        };
    
            descriptor_size = memmap_info.descriptor_size;
            descriptor_version = memmap_info.descriptor_version;
            memory_map_key = memmap_info.key;

            memory_map_size = memmap_info.len * descriptor_size;
            memory_map_buffer = boot_services.allocatePool(.boot_services_data, memory_map_size) catch |err| {
                puts("Error: Allocating memory map failed\r\n");
                return err;
            };

            memory_map = boot_services.getMemoryMap(memory_map_buffer) catch |err| {
                puts("Error: Geting memory map failed\r\n");
                return err;
            };

            memory_map_key = memory_map.info.key;
    }
   
    // The kernel was compiled assuming it lives at 0x100000 virtually.
    // It may be physically elsewhere. Mark its pages with the virtual
    // address so setVirtualAddressMap can establish the mapping.
    mem_index = 0;
    mem_count = memory_map_size / descriptor_size;
    while (mem_index < mem_count) : (mem_index += 1) {
        mem_point = @ptrFromInt(@intFromPtr(memory_map.ptr) + (mem_index * descriptor_size));

        if (mem_point.type == .loader_data) {
            mem_point.virtual_start = kernel_start_address;
        } else {
            mem_point.virtual_start = mem_point.physical_start;
        }
    }

    try runtime_services.setVirtualAddressMap(memory_map);

    kmain = @ptrFromInt(kernel_entry_point);
    kmain();
    return error.LoadError;
}

pub fn main() void {
    bootloader() catch {};
}

