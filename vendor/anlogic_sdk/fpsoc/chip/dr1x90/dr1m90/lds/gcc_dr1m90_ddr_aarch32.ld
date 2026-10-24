/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

OUTPUT_FORMAT("elf32-littlearm", "elf32-littlearm", "elf32-littlearm")
OUTPUT_ARCH(arm)
ENTRY(aarch64_start)

/*
 *  [
 *       _text_start(vma)/_text_lma(lma)                         -> start of text and rodata
 *       _text_end
 *
 *       _rodata_start
 *       _rodata_end
 *          .....(fini, preinit_array, init_array, fini_array, ctors, dtors)
 *       _etext                                                   -> end address of valid code & rodata
 *  ]
 *
 *  [
 *       _data_start(vma) / _data_lma(lma)                       -> start of data
 *       _edata                                                   -> end of data need to load/copy
 *       _data (noload) (noncacheable, async_print_ring_buf)
 *       _data_end                                                -> end of data
 *  ]
 *
 *  [    __bss_start__/_bss_start
 *       __bss_end__/_bss_end
 *  ]
 */

MEMORY
{
    ram    : ORIGIN = 0x8000000, LENGTH = 0x1000000
    ocram  : ORIGIN = 0x61000000, LENGTH = 0x3F000
}

SECTION_ALIGN = 4096;

SECTIONS
{
    __stack_size = DEFINED(__stack_size) ? __stack_size : 6M;
    __async_print_ring_buf_size = DEFINED(async_print_ring_buf_size) ? async_print_ring_buf_size : 1M;

    .text               : ALIGN(SECTION_ALIGN)
    {
    	PROVIDE(_text_lma  = LOADADDR(.text));
    	PROVIDE(_text_start  = ADDR(.text));

        KEEP (*(.aarch64_start*))
        . = _text_start + 0x400;
        KEEP (*(.vectors*))
        KEEP (*al_aarch32_start.S.o(.text*))
        *(.text)
        PROVIDE(_text_end  = .);
    }  > ram

    .rodata             : ALIGN(SECTION_ALIGN)
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
    }  > ram

    .fini           : ALIGN(8)
    {
        KEEP (*(SORT_NONE(.fini)))
    } >ram

    .preinit_array  : ALIGN(8)
    {
        PROVIDE_HIDDEN (__preinit_array_start = .);
        KEEP (*(.preinit_array))
        PROVIDE_HIDDEN (__preinit_array_end = .);
    } >ram

    .init_array     : ALIGN(8)
    {
        PROVIDE_HIDDEN (__init_array_start = .);
        KEEP (*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
        KEEP (*(.init_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .ctors))
        PROVIDE_HIDDEN (__init_array_end = .);
    } >ram

    .fini_array     : ALIGN(8)
    {
        PROVIDE_HIDDEN (__fini_array_start = .);
        KEEP (*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
        KEEP (*(.fini_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .dtors))
        PROVIDE_HIDDEN (__fini_array_end = .);
    } >ram

    .ctors          : ALIGN(8)
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
    } >ram

    .dtors          : ALIGN(8)
    {
        KEEP (*crtbegin.o(.dtors))
        KEEP (*crtbegin?.o(.dtors))
        KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .dtors))
        KEEP (*(SORT(.dtors.*)))
        KEEP (*(.dtors))
    } >ram

    .eh_frame : ALIGN(8)
    {
        *(.eh_frame)
    } >ram

    .ARM.extab :        ALIGN(8)
    {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } >ram

    .ARM.exidx :        ALIGN(8)
    {
        __exidx_start = .;
        *(.ARM.exidx* .gnu.linkonce.armexidx.*)
        __exidx_end = .;
    } >ram

    .eh_framehdr : ALIGN(8)
    {
       __eh_framehdr_start = .;
       *(.eh_framehdr)
       __eh_framehdr_end = .;
    } >ram

    .gcc_except_table : ALIGN(8)
    {
       *(.gcc_except_table)
    } >ram

    /*
     * realtime text section in OCRAM
    */
    .rt_text        : ALIGN(64)
    {
    	PROVIDE(_text_rt_lma    = LOADADDR(.rt_text));
    	PROVIDE(_text_rt_start  = ADDR(.rt_text));
        KEEP (*(.rt_text .rt_text.*))
        PROVIDE(_text_rt_end  = .);
    }  > ocram AT > ram

    ._etext         :
    {
        PROVIDE(_etext = .);
    }  > ram

    .pagetable :            ALIGN(4096)
    {
        PROVIDE(_data_start = ADDR(.pagetable));
        PROVIDE(_data_lma   = LOADADDR(.pagetable));

        PROVIDE(_pagetable_start = .);
        *(.page_table)
        PROVIDE(_pagetable_end   = .);
    }  > ram

    /*
     * realtime text section in OCRAM
    */
    .rt_data          : ALIGN(64)
    {
    	PROVIDE(_data_rt_lma    = LOADADDR(.rt_data));
    	PROVIDE(_data_rt_start  = ADDR(.rt_data));

        KEEP (*(.rt_data*))

        PROVIDE(_data_rt_end  = .);
    }  > ocram AT > ram

    .data             : ALIGN(32)
    {
        *(.data* .gnu.linkonce.r.* .jcr .got .got.plt)
        *(.sdata .sdata.* .sdata*)
        *(.gnu.linkonce.s.*)
    }  > ram

    .tdata           : ALIGN(8)
    {
        *(.tdata .tdata.* .gnu.linkonce.td.*)
    } > ram

    .cli_section : ALIGN(16)
    {
        _cli_section_start = .;
        KEEP(*(cli_section))
        _cli_section_end   = .;
    }  > ram

    .gbe_phy_section : ALIGN(16)
    {
        _gbe_phy_section_start = .;
        KEEP(*(gbe_phy_section))
        _gbe_phy_section_end   = .;
    }  > ram

    /* section information for openamp rsc table */
    .resource_table : ALIGN(4)
    {
        PROVIDE(_resource_table_start = .);
        *(.resource_table)
        PROVIDE(_resource_table_end = .);
    }  > ram

    PROVIDE( _edata = . );

    .noncacheable (NOLOAD):   ALIGN(2M)
    {
        PROVIDE( _no_cache_section_start = .);
        *(.noncacheable*)
        . = ALIGN(2M);   /* only if sizeof(.noncacheable) > 0, Align take effect */
        PROVIDE(_no_cache_section_end = .);
    }  > ram

    .async_print_ring_buf (NOLOAD): ALIGN(64)
    {
        PROVIDE(_async_print_ring_buf_start = .);
        . = __async_print_ring_buf_size;
        PROVIDE(_async_print_ring_buf_end = .);
    }  > ram

    PROVIDE(_data_end = .);

    /*
     * all bss segment
     */
    .tbss (NOLOAD)   : ALIGN(64)
    {
        PROVIDE(__bss_start__ = ADDR(.tbss));
        PROVIDE(_bss_start = __bss_start__);

        *(.tbss .tbss.* .gnu.linkonce.tb.*)
        *(.tcommon)

    }  > ram

    .tbss_space (NOLOAD) : ALIGN(64)
    {
        . = . + SIZEOF(.tbss);
    }  > ram

    .bss (NOLOAD) : ALIGN(64)
    {
        *(.bss .bss.*)
        *(COMMON*)

    . = ALIGN(16);
        PROVIDE(_bss_end = .);
        PROVIDE(__bss_end__ = .);
    } > ram

    PROVIDE( _heap_start = .);
    PROVIDE( _heap_end = ADDR(.stack) - 64);

    .stack (ORIGIN(ram) + LENGTH(ram) - __stack_size) (NOLOAD): ALIGN(64)
    {
        ASSERT( _heap_end - _heap_start >= 64k, "not enough buffer for heap");
        PROVIDE(stack_start = .);
        . += __stack_size;
        PROVIDE(stack_top = .);
        PROVIDE(_sp = .);
        . = ALIGN(16);
    } > ram
}
