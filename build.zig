const std = @import("std");

pub fn build(b: *std.Build) void {
    // Bootloader
    const bootloader = b.addExecutable(.{
        .name = "BOOTX64",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bootloader/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .uefi,
            }),
            .optimize = .ReleaseSmall,
        }),
    });
    b.installArtifact(bootloader);

    // Kernel
    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .freestanding,
                .abi = .none,
            }),
            .optimize = .ReleaseSafe,
        }),
    });
    kernel.entry = .disabled;

    kernel.setLinkerScript(b.path("src/kernel/linker.ld"));
    b.installArtifact(kernel);

    // Copy bootloader to EFI/BOOT/BOOTX64.EFI
    const copy = b.addInstallFile(
        bootloader.getEmittedBin(),
        "EFI/BOOT/BOOTX64.EFI",
    );
    copy.step.dependOn(&bootloader.step);


    // QEMU
    const qemu = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-bios", "OVMF.fd",
        "-hdd", "fat:rw:zig-out",
        "-nographic",
        "-serial", "mon:stdio",
    });
    qemu.step.dependOn(&copy.step);
    qemu.step.dependOn(&kernel.step);

    const install_kernel = b.addInstallFile(
         kernel.getEmittedBin(),
        "kernel.elf",
    );
    install_kernel.step.dependOn(&kernel.step);
    qemu.step.dependOn(&install_kernel.step);

    const run_step = b.step("run", "Run in QEMU");
    run_step.dependOn(&qemu.step);
}
