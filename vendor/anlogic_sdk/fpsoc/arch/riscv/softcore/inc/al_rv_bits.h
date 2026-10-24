/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __RISCV_BITS_H__
#define __RISCV_BITS_H__

#if __riscv_xlen == 64
# define SLL32                  sllw
# define STORE                  sd
# define LOAD                   ld
# define LWU                    lwu
# define LOG_REGBYTES           3
#else
# define SLL32                  sll
# define STORE                  sw
# define LOAD                   lw
# define LWU                    lw
# define LOG_REGBYTES           2
#endif /* __riscv_xlen */

#define REGBYTES                (1 << LOG_REGBYTES)

#define __STR(s)                #s
#define STRINGIFY(s)            __STR(s)

#endif