ASM=x86_64-elf-as
SRC_DIR=src
BUILD_DIR=build

$(BUILD_DIR)/starKernel.bin: $(BUILD_DIR)/starKernel.o $(BUILD_DIR)/boot.o
	@echo "Setting kernel base virtual address to 2Mb (0x200000)... "
	x86_64-elf-gcc -ffreestanding -T $(SRC_DIR)/linker.ld $(BUILD_DIR)/boot.o $(BUILD_DIR)/starKernel.o -o $(BUILD_DIR)/starKernel.bin -nostdlib -lgcc -Xlinker --defsym -Xlinker KERNEL_VMA=0x200000
	@echo "Done!"
$(BUILD_DIR)/starKernel.o: $(SRC_DIR)/starKernel.c $(BUILD_DIR)/boot.o
	@echo "Compiling the kernel... "
	x86_64-elf-gcc -ffreestanding -mcmodel=large -mno-red-zone -mno-mmx -mno-sse -mno-sse2 -c $(SRC_DIR)/starKernel.c -o $(BUILD_DIR)/starKernel.o
	@echo "Done!"
$(BUILD_DIR)/boot.o: $(SRC_DIR)/boot.s
	@echo "Assembling bootloader... "
	$(ASM) $(SRC_DIR)/boot.s -o $(BUILD_DIR)/boot.o
	@echo "Done!"

clean:
	rm $(BUILD_DIR)/*
