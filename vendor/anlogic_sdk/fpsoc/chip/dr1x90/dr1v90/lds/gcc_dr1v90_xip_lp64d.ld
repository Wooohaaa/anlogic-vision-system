/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

OUTPUT_ARCH( "riscv" )

ENTRY( _start )

__ROM_BASE = 0x70400000;
__ROM_SIZE = 0x100000;

SECTION_ALIGN = 64;

MEMORY
{
    flash (rxai!w) : ORIGIN  = __ROM_BASE, LENGTH = __ROM_SIZE

    itcm  (rxa!w)  : ORIGIN  = 0x60000000, LENGTH = 512K
    ocm   (rxa!w)  : ORIGIN  = 0x61000000, LENGTH = 256K
    npuram  (rxa!w) : ORIGIN = 0x63e00000, LENGTH = 256K
}


SECTIONS
{
    __stack_size = DEFINED(__stack_size) ? __stack_size : 2k;

    .init :                     ALIGN(SECTION_ALIGN)
    {
        KEEP (*(SORT_NONE(.init)))
    } >flash AT>flash

    .text :                     ALIGN(8)
    {
        PROVIDE(_text_lma    = LOADADDR(.text));
        PROVIDE(_text_start  = ADDR(.text));
        *(.text.unlikely .text.unlikely.*)
        *(.text.startup .text.startup.*)
        *(.text)
        *(.gnu.linkonce.t.*)
    } >flash AT>flash

    .rodata :                   ALIGN(SECTION_ALIGN)
    {
        PROVIDE(_rodata_start = .);
        *(.rdata)
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
        /* section information for utest */
        __rt_utest_tc_tab_start = .;
        KEEP(*(UtestTcTab))
        __rt_utest_tc_tab_end = .;
        *(.gnu.linkonce.r.*)
        /* section information for usbh class */
        . = ALIGN(4);
        __usbh_class_info_start__ = .;
        KEEP(*(.usbh_class_info))
        __usbh_class_info_end__ = .;
        . = ALIGN(16);
        PROVIDE(_rodata_end = .);
    } >flash AT>flash

    .gcc_except_table :         ALIGN(8)
    {
        *(.gcc_except_table)
    } >flash AT>flash

    .fini :                    ALIGN(8)
    {
        KEEP (*(SORT_NONE(.fini)))
    } >flash AT>flash

    .preinit_array  :         ALIGN(8)
    {
        PROVIDE_HIDDEN (__preinit_array_start = .);
        KEEP (*(.preinit_array))
        PROVIDE_HIDDEN (__preinit_array_end = .);
    } >flash AT>flash

    .init_array     :         ALIGN(8)
    {
        PROVIDE_HIDDEN (__init_array_start = .);
        KEEP (*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
        KEEP (*(.init_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .ctors))
        PROVIDE_HIDDEN (__init_array_end = .);
    } >flash AT>flash

    .fini_array :             ALIGN(8)
    {
        PROVIDE_HIDDEN (__fini_array_start = .);
        KEEP (*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
        KEEP (*(.fini_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .dtors))
        PROVIDE_HIDDEN (__fini_array_end = .);
    } >flash AT>flash

    .ctors :                  ALIGN(8)
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
    } >flash AT>flash

    .dtors :                    ALIGN(8)
    {
        KEEP (*crtbegin.o(.dtors))
        KEEP (*crtbegin?.o(.dtors))
        KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .dtors))
        KEEP (*(SORT(.dtors.*)))
        KEEP (*(.dtors))
    } >flash AT>flash

    .eh_frame :                 ALIGN(8)
    {
        *(.eh_frame)
    } >flash AT>flash

    .ARM.extab :                ALIGN(8)
    {
        *(.ARM.extab* .gnu.linkonce.armextab.*)
    } >flash AT>flash

    .ARM.exidx :                ALIGN(8)
    {
        __exidx_start = .;
        *(.ARM.exidx* .gnu.linkonce.armexidx.*)
        __exidx_end = .;
    } >flash AT>flash

    .eh_framehdr :              ALIGN(8)
    {
        __eh_framehdr_start = .;
        *(.eh_framehdr)
        __eh_framehdr_end = .;
    } >flash AT>flash

    .gcc_except_table :         ALIGN(8)
    {
        *(.gcc_except_table)
    } >flash AT>flash

    PROVIDE( _etext = .);
    PROVIDE( _etext = .);

    .data :                    ALIGN(SECTION_ALIGN)
    {
        PROVIDE(_data_start = ADDR(.data));
        PROVIDE(_data_lma = LOADADDR(.data));

        *(.vtable)
        *(.data .data.*)
        *(.gnu.linkonce.d.*)
        . = ALIGN(8);
        PROVIDE( __global_pointer$ = . + 0x800 );
        *(.sdata .sdata.* .sdata*)
        *(.gnu.linkonce.s.*)
        . = ALIGN(8);
        *(.srodata.cst16)
        *(.srodata.cst8)
        *(.srodata.cst4)
        *(.srodata.cst2)
        *(.srodata .srodata.*)
    } >itcm AT>flash

    .tdata   :              ALIGN(8)
    {
        *(.tdata .tdata.* .gnu.linkonce.td.*)
    } >itcm AT>flash

    .cli_section :          ALIGN(16)
    {
        _cli_section_start = .;
        KEEP(*(cli_section))
        _cli_section_end   = .;
    } >itcm AT>flash

    .gbe_phy_section :      ALIGN(16)
    {
        _gbe_phy_section_start = .;
        KEEP(*(gbe_phy_section))
        _gbe_phy_section_end   = .;
    } >itcm AT>flash

    /* section information for openamp rsc table */
    .resource_table :       ALIGN(4)
    {
        PROVIDE(_resource_table_start = .);
        *(.resource_table)
        PROVIDE(_resource_table_end = .);
    } >itcm AT>flash

    PROVIDE( _edata = . );

    .noncacheable (NOLOAD):   ALIGN(4)
    {
        PROVIDE( _no_cache_section_start = .);
        PROVIDE( _no_cache_section_end = .);
        *(.noncacheable*)
    } >itcm AT>flash

    PROVIDE( _data_end = .);

    /*
     * all bss segment
     */
    .tbss (NOLOAD)   : ALIGN(64)
    {
        PROVIDE(__bss_start__ = ADDR(.tbss));
        PROVIDE(_bss_start = __bss_start__);

        *(.tbss .tbss.* .gnu.linkonce.tb.*)
        *(.tcommon)
    } > itcm

    .tbss_space (NOLOAD) : ALIGN(64)
    {
        . = . + SIZEOF(.tbss);
    } > itcm

    .bss (NOLOAD) : ALIGN(64)
    {
        *(.sbss*)
        *(.gnu.linkonce.sb.*)
        *(.bss .bss.*)
        *(.gnu.linkonce.b.*)
        *(COMMON)

        . = ALIGN(16);
        PROVIDE(_bss_end = .);
        PROVIDE(__bss_end__ = .);
    } > itcm

    PROVIDE( _heap_start = .);
    PROVIDE( _heap_end = ADDR(.stack) - 64);

    .stack (ORIGIN(itcm) + LENGTH(itcm) - __stack_size) (NOLOAD): ALIGN(64)
    {
        ASSERT( _heap_end - _heap_start >= 1k, "not enough buffer for heap");
        PROVIDE(stack_start = .);
        . += __stack_size;
        PROVIDE( _sp = . );
        . = ALIGN(16);
    } >itcm
}
