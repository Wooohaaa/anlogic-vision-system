/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

OUTPUT_FORMAT("elf64-littleaarch64", "elf64-littleaarch64", "elf64-littleaarch64")
OUTPUT_ARCH(aarch64)
ENTRY(_start)

/*
 *  [
 *       start section:                                            -> xip
 *  ]
 *
 *  [
 *       _text_start(vma)/_text_lma(lma)                         -> start of text and rodata: start address of text copy from lma to vma
 *       _text_end
 *
 *       _rodata_start
 *       _rodata_end
 *          .....(fini, preinit_array, init_array, fini_array, ctors, dtors)
 *       _etext                                                   -> end address of valid code & rodata; end address of text copy from lma to vma
 *  ]
 *
 *  [
 *       _data_start(vma) / _data_lma(lma)                       -> start of data; start address of data copy from lma to vma
 *       _edata                                                   -> end of data need to load/copy: start address of data copy from lma to vma;
 *       _data (noload) (noncacheable, async_print_ring_buf)
 *       _data_end                                                -> end of data
 *  ]
 *
 *  [    __bss_start__/_bss_start
 *       __bss_end__/_bss_end
 *  ]
 */

__ROM_BASE = 0x70400000;
__ROM_SIZE = 0x100000;

MEMORY
{
    flash  : ORIGIN = __ROM_BASE, LENGTH = __ROM_SIZE
    ocm    : ORIGIN = 0x61000000, LENGTH = 0x3F000
    npuram : ORIGIN = 0x63e00000, LENGTH = 256K
}

_data_rt_lma   = 0;
_data_rt_start = 0;
_data_rt_end   = 0;
_text_rt_lma   = 0;
_text_rt_start = 0;
_text_rt_end   = 0;

REGION_ALIAS("START_VMA", flash)
REGION_ALIAS("START_LMA", flash)
REGION_ALIAS("CODE_VMA", ocm)
REGION_ALIAS("CODE_LMA", flash)
REGION_ALIAS("RODATA_LMA", flash)
REGION_ALIAS("DATA_VMA", ocm)
REGION_ALIAS("DATA_LMA", flash)

SECTION_ALIGN = 32;

SECTIONS
{
    __stack_size = DEFINED(__stack_size) ? __stack_size : 8K;

    .start : ALIGN(4096)
    {
        *al_aarch64_start.S.o(.text)
        *al_aarch64_mmu.S.o(.text)
        *al_mpu.S.o(.text)
        *al_dr1m90.S.o(.text)
        *al_top.S.o(.text)
        *al_chip.S.o(.text)
        *al_aarch64_pagetable.S.o(.text)
    }  > START_VMA AT>START_LMA

    .text : ALIGN(4096)
    {
        PROVIDE( _text_lma = LOADADDR(.text) );
        PROVIDE( _text_start = ADDR(.text) );
        *(.text*)
        PROVIDE(_text_end  = .);
    }  > CODE_VMA AT> CODE_LMA

    .rodata :        ALIGN(SECTION_ALIGN)
    {
        PROVIDE(_rodata_start = .);
        *(.rodata .rodata.*)
        /* section information for initial. */
        . = ALIGN(4);
        __rt_init_start = .;
        KEEP(*(SORT(.rti_fn*)))
        __rt_init_end = .;
        /* section information for finsh shell */
        . = ALIGN(4);
        __fsymtab_start = .;
        KEEP(*(FSymTab))
        __fsymtab_end = .;
        . = ALIGN(4);
        __vsymtab_start = .;
        KEEP(*(VSymTab))
        __vsymtab_end = .;
        . = ALIGN(4);
        __rt_utest_tc_tab_start = .;
        KEEP(*(UtestTcTab))
        __rt_utest_tc_tab_end = .;
        /* section information for usbh class */
        . = ALIGN(4);
        __usbh_class_info_start__ = .;
        KEEP(*(.usbh_class_info))
        __usbh_class_info_end__ = .;
        . = ALIGN(16);
        PROVIDE(_rodata_end   = .);
    }  > CODE_VMA AT>RODATA_LMA

    .fini           : ALIGN(8)
    {
        KEEP (*(SORT_NONE(.fini)))
    }  >CODE_VMA AT>RODATA_LMA

    .preinit_array  : ALIGN(8)
    {
        PROVIDE_HIDDEN (__preinit_array_start = .);
        KEEP (*(.preinit_array))
        PROVIDE_HIDDEN (__preinit_array_end = .);
    }  >CODE_VMA AT>RODATA_LMA

    .init_array     : ALIGN(8)
    {
        PROVIDE_HIDDEN (__init_array_start = .);
        KEEP (*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
        KEEP (*(.init_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .ctors))
        PROVIDE_HIDDEN (__init_array_end = .);
    }  >CODE_VMA AT>RODATA_LMA

    .fini_array     : ALIGN(8)
    {
        PROVIDE_HIDDEN (__fini_array_start = .);
        KEEP (*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
        KEEP (*(.fini_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .dtors))
        PROVIDE_HIDDEN (__fini_array_end = .);
    }  >CODE_VMA AT>RODATA_LMA

    .ctors          :  ALIGN(8)
    {
        /* gcc uses crtbegin.o to find the start of
        the constructors, so we make sure it is
        first.  Because this is a wildcard, it
        doesn't matter if the user does not
        actually link against crtbegin.o; the
        linker won't look for a file to match a
        wildcard.  The wildcard also means that it
        doesn't matter which directory crtbegin.o
        is in.  */
        KEEP (*crtbegin.o(.ctors))
        KEEP (*crtbegin?.o(.ctors))
        /* We don't want to include the .ctor section from
        the crtend.o file until after the sorted ctors.
        The .ctor section from the crtend file contains the
        end of ctors marker and it must be last */
        KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .ctors))
        KEEP (*(SORT(.ctors.*)))
        KEEP (*(.ctors))

        PROVIDE(__ctors_start__ = .);
        /* new GCC version uses .init_array */
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE(__ctors_end__ = .);
    } >CODE_VMA AT>RODATA_LMA

    .dtors :            ALIGN(8)
    {
        KEEP (*crtbegin.o(.dtors))
        KEEP (*crtbegin?.o(.dtors))
        KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .dtors))
        KEEP (*(SORT(.dtors.*)))
        KEEP (*(.dtors))
    } >CODE_VMA AT>RODATA_LMA

    .eh_frame : ALIGN(8)
    {
       *(.eh_frame)
    } >CODE_VMA AT>RODATA_LMA

    .ARM.extab :        ALIGN(8)
    {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } >CODE_VMA AT>RODATA_LMA

    .ARM.exidx :        ALIGN(8)
    {
        __exidx_start = .;
        *(.ARM.exidx* .gnu.linkonce.armexidx.*)
        __exidx_end = .;
    } >CODE_VMA AT>RODATA_LMA

    .eh_framehdr : ALIGN(8)
    {
       __eh_framehdr_start = .;
       *(.eh_framehdr)
       __eh_framehdr_end = .;
    } >CODE_VMA AT>RODATA_LMA

    .gcc_except_table : ALIGN(8)
    {
       *(.gcc_except_table)
    } >CODE_VMA AT>RODATA_LMA

    PROVIDE(_etext = .);

    /*
     * put pagetable ALIGN(4096) here, so VMA & LMA align to 4096;
    */
    .pagetable :            ALIGN(4096)
    {
        PROVIDE(_data_start = ADDR(.pagetable));
        PROVIDE(_data_lma   = LOADADDR(.pagetable));

        PROVIDE(_pagetable_start = .);
        *(.page_table)
        PROVIDE(_pagetable_end   = .);
    }  > DATA_VMA AT>DATA_LMA

    .data             : ALIGN(SECTION_ALIGN)
    {
        *(.data* .gnu.linkonce.r.* .jcr .got .got.plt)
        *(.sdata .sdata.* .sdata*)
        *(.gnu.linkonce.s.*)
    }  > DATA_VMA AT>DATA_LMA

    .tdata           : ALIGN(8)
    {
        *(.tdata .tdata.* .gnu.linkonce.td.*)
    }  > DATA_VMA AT>DATA_LMA

    .cli_section    : ALIGN(16)
    {
        _cli_section_start = .;
        KEEP(*(cli_section))
        _cli_section_end   = .;
    }  > DATA_VMA AT>DATA_LMA

    .gbe_phy_section : ALIGN(16)
    {
        _gbe_phy_section_start = .;
        KEEP(*(gbe_phy_section))
        _gbe_phy_section_end   = .;
    }  > DATA_VMA AT>DATA_LMA

    /* section information for openamp rsc table */
    .resource_table :       ALIGN(4)
    {
        PROVIDE(_resource_table_start = .);
        *(.resource_table)
        PROVIDE(_resource_table_end = .);
    }  > DATA_VMA AT>DATA_LMA

    PROVIDE( _edata = . );
    PROVIDE( _data_end = .);

    .noncacheable (NOLOAD):   ALIGN(2M)
    {
        PROVIDE( _no_cache_section_start = .);
        *(.noncacheable*)
        ASSERT(SIZEOF(.noncacheable) < LENGTH(npuram), "noncacheable size out of range");
        PROVIDE( _no_cache_section_end = _no_cache_section_start + ((SIZEOF(.noncacheable) > 0) ?  2M : 0));
    }  > npuram
    /*
     * all bss segment
     */
    .tbss (NOLOAD)   : ALIGN(64)
    {
        PROVIDE(__bss_start__ = ADDR(.tbss));
        PROVIDE(_bss_start = __bss_start__);

        *(.tbss .tbss.* .gnu.linkonce.tb.*)
        *(.tcommon)

    } > DATA_VMA

    .tbss_space (NOLOAD) : ALIGN(64)
    {
        . = . + SIZEOF(.tbss);
    } > DATA_VMA

    .bss (NOLOAD) : ALIGN(64)
    {
        *(.bss .bss.*)
        *(COMMON*)

        . = ALIGN(16);
        PROVIDE(_bss_end = .);
        PROVIDE(__bss_end__ = .);
    }  > DATA_VMA

    PROVIDE( _heap_start = .);
    PROVIDE( _heap_end = ORIGIN(DATA_VMA) + LENGTH(DATA_VMA) - __stack_size);

    .stack (ORIGIN(DATA_VMA) + LENGTH(DATA_VMA) - __stack_size) (NOLOAD) : ALIGN(64)
    {
        PROVIDE(stack_start = .);
        . += __stack_size;
        PROVIDE(stack_top = .);
        PROVIDE(_sp = .);
        . = ALIGN(16);
    } > DATA_VMA
}
