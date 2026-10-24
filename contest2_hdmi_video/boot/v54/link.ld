OUTPUT_ARCH(riscv)
ENTRY(_boot_start)
MEMORY { flash (rx) : ORIGIN = 0x20e00000, LENGTH = 64K }
SECTIONS {
 .text : { KEEP(*(.text.boot)) *(.text*) *(.rodata*) } > flash
 /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
ASSERT(SIZEOF(.text) < 65536, "Bootloader overlaps payload header")
