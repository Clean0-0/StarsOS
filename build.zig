const std = @import("std");

pub fn build(b: *std.Build) void {
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

    const qemu = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-bios", "OVMF.fd",
        "-hdd", "fat:rw:zig-out",
        "-nographic",
    });
    qemu.step.dependOn(b.getInstallStep());

    const copy = b.addInstallFile(
        bootloader.getEmittedBin(),
        "./EFI/BOOT/BOOTX64.EFI",
    );

    copy.step.dependOn(&bootloader.step);

    qemu.step.dependOn(&copy.step);

    const run_step = b.step("run", "Run in QEMU");

    run_step.dependOn(&qemu.step);
}
