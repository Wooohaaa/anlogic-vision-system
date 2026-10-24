/*
 * Copyright (c) 2006-2022, RT-Thread Development Team
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2006-03-16     Bernard      the first version
 * 2006-05-25     Bernard      rewrite vsprintf
 * 2006-08-10     Bernard      add rt_show_version
 * 2010-03-17     Bernard      remove rt_strlcpy function
 *                             fix gcc compiling issue.
 * 2010-04-15     Bernard      remove weak definition on ICCM16C compiler
 * 2012-07-18     Arda         add the alignment display for signed integer
 * 2012-11-23     Bernard      fix IAR compiler error.
 * 2012-12-22     Bernard      fix rt_kprintf issue, which found by Grissiom.
 * 2013-06-24     Bernard      remove rt_kprintf if RT_USING_CONSOLE is not defined.
 * 2013-09-24     aozima       make sure the device is in STREAM mode when used by rt_kprintf.
 * 2015-07-06     Bernard      Add rt_assert_handler routine.
 * 2021-02-28     Meco Man     add RT_KSERVICE_USING_STDLIB
 * 2021-12-20     Meco Man     implement rt_strcpy()
 * 2022-01-07     Gabriel      add __on_rt_assert_hook
 * 2022-06-04     Meco Man     remove strnlen
 */

#include <rtthread.h>
#include <rthw.h>

#ifdef RT_USING_MODULE
#include <dlmodule.h>
#endif /* RT_USING_MODULE */

/* use precision */
#define RT_PRINTF_PRECISION

/**
 * @addtogroup KernelService
 */

/**@{*/

/* global errno in RT-Thread */
static volatile int __rt_errno;

#if defined(RT_USING_DEVICE) && defined(RT_USING_CONSOLE)
static rt_device_t _console_device = RT_NULL;
#endif

RT_WEAK void rt_hw_us_delay(rt_uint32_t us)
{
    (void) us;
    RT_DEBUG_LOG(RT_DEBUG_DEVICE, ("rt_hw_us_delay() doesn't support for this board."
        "Please consider implementing rt_hw_us_delay() in another file.\n"));
}

static const char* rt_errno_strs[] =
{
    "OK",
    "ERROR",
    "ETIMOUT",
    "ERSFULL",
    "ERSEPTY",
    "ENOMEM",
    "ENOSYS",
    "EBUSY",
    "EIO",
    "EINTRPT",
    "EINVAL",
    "EUNKNOW"
};

/**
 * This function return a pointer to a string that contains the
 * message of error.
 *
 * @param error the errorno code
 * @return a point to error message string
 */
const char *rt_strerror(rt_err_t error)
{
    if (error < 0)
        error = -error;

    return (error > RT_EINVAL + 1) ?
           rt_errno_strs[RT_EINVAL + 1] :
           rt_errno_strs[error];
}
RTM_EXPORT(rt_strerror);

/**
 * This function gets the global errno for the current thread.
 *
 * @return errno
 */
rt_err_t rt_get_errno(void)
{
    rt_thread_t tid;

    if (rt_interrupt_get_nest() != 0)
    {
        /* it's in interrupt context */
        return __rt_errno;
    }

    tid = rt_thread_self();
    if (tid == RT_NULL)
        return __rt_errno;

    return tid->error;
}
RTM_EXPORT(rt_get_errno);

/**
 * This function sets the global errno for the current thread.
 *
 * @param error is the errno shall be set.
 */
void rt_set_errno(rt_err_t error)
{
    rt_thread_t tid;

    if (rt_interrupt_get_nest() != 0)
    {
        /* it's in interrupt context */
        __rt_errno = error;

        return;
    }

    tid = rt_thread_self();
    if (tid == RT_NULL)
    {
        __rt_errno = error;

        return;
    }

    tid->error = error;
}
RTM_EXPORT(rt_set_errno);

/**
 * This function returns the address of the current thread errno.
 *
 * @return The errno address.
 */
int *_rt_errno(void)
{
    rt_thread_t tid;

    if (rt_interrupt_get_nest() != 0)
        return (int *)&__rt_errno;

    tid = rt_thread_self();
    if (tid != RT_NULL)
        return (int *) & (tid->error);

    return (int *)&__rt_errno;
}
RTM_EXPORT(_rt_errno);

#ifndef RT_KSERVICE_USING_STDLIB_MEMORY
/**
 * This function will set the content of memory to specified value.
 *
 * @param  s is the address of source memory, point to the memory block to be filled.
 *
 * @param  c is the value to be set. The value is passed in int form, but the function
 *         uses the unsigned character form of the value when filling the memory block.
 *
 * @param  count number of bytes to be set.
 *
 * @return The address of source memory.
 */
RT_WEAK void *rt_memset(void *s, int c, rt_ubase_t count)
{
#ifdef RT_KSERVICE_USING_TINY_SIZE
    char *xs = (char *)s;

    while (count--)
        *xs++ = c;

    return s;
#else
#define LBLOCKSIZE      (sizeof(long))
#define UNALIGNED(X)    ((long)X & (LBLOCKSIZE - 1))
#define TOO_SMALL(LEN)  ((LEN) < LBLOCKSIZE)

    unsigned int i;
    char *m = (char *)s;
    unsigned long buffer;
    unsigned long *aligned_addr;
    unsigned int d = c & 0xff;  /* To avoid sign extension, copy C to an
                                unsigned variable.  */

    if (!TOO_SMALL(count) && !UNALIGNED(s))
    {
        /* If we get this far, we know that count is large and s is word-aligned. */
        aligned_addr = (unsigned long *)s;

        /* Store d into each char sized location in buffer so that
         * we can set large blocks quickly.
         */
        if (LBLOCKSIZE == 4)
        {
            buffer = (d << 8) | d;
            buffer |= (buffer << 16);
        }
        else
        {
            buffer = 0;
            for (i = 0; i < LBLOCKSIZE; i ++)
                buffer = (buffer << 8) | d;
        }

        while (count >= LBLOCKSIZE * 4)
        {
            *aligned_addr++ = buffer;
            *aligned_addr++ = buffer;
            *aligned_addr++ = buffer;
            *aligned_addr++ = buffer;
            count -= 4 * LBLOCKSIZE;
        }

        while (count >= LBLOCKSIZE)
        {
            *aligned_addr++ = buffer;
            count -= LBLOCKSIZE;
        }

        /* Pick up the remainder with a bytewise loop. */
        m = (char *)aligned_addr;
    }

    while (count--)
    {
        *m++ = (char)d;
    }

    return s;

#undef LBLOCKSIZE
#undef UNALIGNED
#undef TOO_SMALL
#endif /* RT_KSERVICE_USING_TINY_SIZE */
}
RTM_EXPORT(rt_memset);

/**
 * This function will copy memory content from source address to destination address.
 *
 * @param  dst is the address of destination memory, points to the copied content.
 *
 * @param  src  is the address of source memory, pointing to the data source to be copied.
 *
 * @param  count is the copied length.
 *
 * @return The address of destination memory
 */
RT_WEAK void *rt_memcpy(void *dst, const void *src, rt_ubase_t count)
{
#ifdef RT_KSERVICE_USING_TINY_SIZE
    char *tmp = (char *)dst, *s = (char *)src;
    rt_ubase_t len;

    if (tmp <= s || tmp > (s + count))
    {
        while (count--)
            *tmp ++ = *s ++;
    }
    else
    {
        for (len = count; len > 0; len --)
            tmp[len - 1] = s[len - 1];
    }

    return dst;
#else

#define UNALIGNED(X, Y) \
    (((long)X & (sizeof (long) - 1)) | ((long)Y & (sizeof (long) - 1)))
#define BIGBLOCKSIZE    (sizeof (long) << 2)
#define LITTLEBLOCKSIZE (sizeof (long))
#define TOO_SMALL(LEN)  ((LEN) < BIGBLOCKSIZE)

    char *dst_ptr = (char *)dst;
    char *src_ptr = (char *)src;
    long *aligned_dst;
    long *aligned_src;
    rt_ubase_t len = count;

    /* If the size is small, or either SRC or DST is unaligned,
    then punt into the byte copy loop.  This should be rare. */
    if (!TOO_SMALL(len) && !UNALIGNED(src_ptr, dst_ptr))
    {
        aligned_dst = (long *)dst_ptr;
        aligned_src = (long *)src_ptr;

        /* Copy 4X long words at a time if possible. */
        while (len >= BIGBLOCKSIZE)
        {
            *aligned_dst++ = *aligned_src++;
            *aligned_dst++ = *aligned_src++;
            *aligned_dst++ = *aligned_src++;
            *aligned_dst++ = *aligned_src++;
            len -= BIGBLOCKSIZE;
        }

        /* Copy one long word at a time if possible. */
        while (len >= LITTLEBLOCKSIZE)
        {
            *aligned_dst++ = *aligned_src++;
            len -= LITTLEBLOCKSIZE;
        }

        /* Pick up any residual with a byte copier. */
        dst_ptr = (char *)aligned_dst;
        src_ptr = (char *)aligned_src;
    }

    while (len--)
        *dst_ptr++ = *src_ptr++;

    return dst;
#undef UNALIGNED
#undef BIGBLOCKSIZE
#undef LITTLEBLOCKSIZE
#undef TOO_SMALL
#endif /* RT_KSERVICE_USING_TINY_SIZE */
}
RTM_EXPORT(rt_memcpy);

/**
 * This function will move memory content from source address to destination
 * address. If the destination memory does not overlap with the source memory,
 * the function is the same as memcpy().
 *
 * @param  dest is the address of destination memory, points to the copied content.
 *
 * @param  src is the address of source memory, point to the data source to be copied.
 *
 * @param  n is the copied length.
 *
 * @return The address of destination memory.
 */
void *rt_memmove(void *dest, const void *src, rt_size_t n)
{
    char *tmp = (char *)dest, *s = (char *)src;

    if (s < tmp && tmp < s + n)
    {
        tmp += n;
        s += n;

        while (n--)
            *(--tmp) = *(--s);
    }
    else
    {
        while (n--)
            *tmp++ = *s++;
    }

    return dest;
}
RTM_EXPORT(rt_memmove);

/**
 * This function will compare two areas of memory.
 *
 * @param  cs is a block of memory.
 *
 * @param  ct is another block of memory.
 *
 * @param  count is the size of the area.
 *
 * @return Compare the results:
 *         If the result < 0, cs is smaller than ct.
 *         If the result > 0, cs is greater than ct.
 *         If the result = 0, cs is equal to ct.
 */
rt_int32_t rt_memcmp(const void *cs, const void *ct, rt_size_t count)
{
    const unsigned char *su1, *su2;
    int res = 0;

    for (su1 = (const unsigned char *)cs, su2 = (const unsigned char *)ct; 0 < count; ++su1, ++su2, count--)
        if ((res = *su1 - *su2) != 0)
            break;

    return res;
}
RTM_EXPORT(rt_memcmp);
#endif /* RT_KSERVICE_USING_STDLIB_MEMORY*/

#ifndef RT_KSERVICE_USING_STDLIB
/**
 * This function will return the first occurrence of a string, without the
 * terminator '\0'.
 *
 * @param  s1 is the source string.
 *
 * @param  s2 is the find string.
 *
 * @return The first occurrence of a s2 in s1, or RT_NULL if no found.
 */
char *rt_strstr(const char *s1, const char *s2)
{
    int l1, l2;

    l2 = rt_strlen(s2);
    if (!l2)
        return (char *)s1;
    l1 = rt_strlen(s1);
    while (l1 >= l2)
    {
        l1 --;
        if (!rt_memcmp(s1, s2, l2))
            return (char *)s1;
        s1 ++;
    }

    return RT_NULL;
}
RTM_EXPORT(rt_strstr);

/**
 * This function will compare two strings while ignoring differences in case
 *
 * @param  a is the string to be compared.
 *
 * @param  b is the string to be compared.
 *
 * @return Compare the results:
 *         If the result < 0, a is smaller than a.
 *         If the result > 0, a is greater than a.
 *         If the result = 0, a is equal to a.
 */
rt_int32_t rt_strcasecmp(const char *a, const char *b)
{
    int ca, cb;

    do
    {
        ca = *a++ & 0xff;
        cb = *b++ & 0xff;
        if (ca >= 'A' && ca <= 'Z')
            ca += 'a' - 'A';
        if (cb >= 'A' && cb <= 'Z')
            cb += 'a' - 'A';
    }
    while (ca == cb && ca != '\0');

    return ca - cb;
}
RTM_EXPORT(rt_strcasecmp);

/**
 * This function will copy string no more than n bytes.
 *
 * @param  dst points to the address used to store the copied content.
 *
 * @param  src is the string to be copied.
 *
 * @param  n is the maximum copied length.
 *
 * @return The address where the copied content is stored.
 */
char *rt_strncpy(char *dst, const char *src, rt_size_t n)
{
    if (n != 0)
    {
        char *d = dst;
        const char *s = src;

        do
        {
            if ((*d++ = *s++) == 0)
            {
                /* NUL pad the remaining n-1 bytes */
                while (--n != 0)
                    *d++ = 0;
                break;
            }
        } while (--n != 0);
    }

    return (dst);
}
RTM_EXPORT(rt_strncpy);

/**
 * This function will copy string.
 *
 * @param  dst points to the address used to store the copied content.
 *
 * @param  src is the string to be copied.
 *
 * @return The address where the copied content is stored.
 */
char *rt_strcpy(char *dst, const char *src)
{
    char *dest = dst;

    while (*src != '\0')
    {
        *dst = *src;
        dst++;
        src++;
    }

    *dst = '\0';
    return dest;
}
RTM_EXPORT(rt_strcpy);

/**
 * This function will compare two strings with specified maximum length.
 *
 * @param  cs is the string to be compared.
 *
 * @param  ct is the string to be compared.
 *
 * @param  count is the maximum compare length.
 *
 * @return Compare the results:
 *         If the result < 0, cs is smaller than ct.
 *         If the result > 0, cs is greater than ct.
 *         If the result = 0, cs is equal to ct.
 */
rt_int32_t rt_strncmp(const char *cs, const char *ct, rt_size_t count)
{
    signed char __res = 0;

    while (count)
    {
        if ((__res = *cs - *ct++) != 0 || !*cs++)
            break;
        count --;
    }

    return __res;
}
RTM_EXPORT(rt_strncmp);

/**
 * This function will compare two strings without specified length.
 *
 * @param  cs is the string to be compared.
 *
 * @param  ct is the string to be compared.
 *
 * @return Compare the results:
 *         If the result < 0, cs is smaller than ct.
 *         If the result > 0, cs is greater than ct.
 *         If the result = 0, cs is equal to ct.
 */
rt_int32_t rt_strcmp(const char *cs, const char *ct)
{
    while (*cs && *cs == *ct)
    {
        cs++;
        ct++;
    }

    return (*cs - *ct);
}
RTM_EXPORT(rt_strcmp);

/**
 * This function will return the length of a string, which terminate will
 * null character.
 *
 * @param  s is the string
 *
 * @return The length of string.
 */
rt_size_t rt_strlen(const char *s)
{
    const char *sc;

    for (sc = s; *sc != '\0'; ++sc) /* nothing */
        ;

    return sc - s;
}
RTM_EXPORT(rt_strlen);

#endif /* RT_KSERVICE_USING_STDLIB */

/**
 * The  strnlen()  function  returns the number of characters in the
 * string pointed to by s, excluding the terminating null byte ('\0'),
 * but at most maxlen.  In doing this, strnlen() looks only at the
 * first maxlen characters in the string pointed to by s and never
 * beyond s+maxlen.
 *
 * @param  s is the string.
 *
 * @param  maxlen is the max size.
 *
 * @return The length of string.
 */
rt_size_t rt_strnlen(const char *s, rt_ubase_t maxlen)
{
    const char *sc;

    for (sc = s; *sc != '\0' && (rt_ubase_t)(sc - s) < maxlen; ++sc) /* nothing */
        ;

    return sc - s;
}
RTM_EXPORT(rt_strnlen);

#ifdef RT_USING_HEAP
/**
 * This function will duplicate a string.
 *
 * @param  s is the string to be duplicated.
 *
 * @return The string address of the copy.
 */
char *rt_strdup(const char *s)
{
    rt_size_t len = rt_strlen(s) + 1;
    char *tmp = (char *)rt_malloc(len);

    if (!tmp)
        return RT_NULL;

    rt_memcpy(tmp, s, len);

    return tmp;
}
RTM_EXPORT(rt_strdup);
#endif /* RT_USING_HEAP */

/**
 * This function will show the version of rt-thread rtos
 */
void rt_show_version(void)
{
    rt_kprintf("\n \\ | /\n");
    rt_kprintf("- RT -     Thread Operating System\n");
    rt_kprintf(" / | \\     %d.%d.%d build %s %s\n",
               RT_VERSION, RT_SUBVERSION, RT_REVISION, __DATE__, __TIME__);
    rt_kprintf(" 2006 - 2022 Copyright by RT-Thread team\n");
}
RTM_EXPORT(rt_show_version);

/* private function */
#define _ISDIGIT(c)  ((unsigned)((c) - '0') < 10)

/**
 * This function will duplicate a string.
 *
 * @param  n is the string to be duplicated.
 *
 * @param  base is support divide instructions value.
 *
 * @return the duplicated string pointer.
 */
#ifdef RT_KPRINTF_USING_LONGLONG
rt_inline int divide(long long *n, int base)
#else
rt_inline int divide(long *n, int base)
#endif /* RT_KPRINTF_USING_LONGLONG */
{
    int res;

    /* optimized for processor which does not support divide instructions. */
    if (base == 10)
    {
#ifdef RT_KPRINTF_USING_LONGLONG
        res = (int)(((unsigned long long)*n) % 10U);
        *n = (long long)(((unsigned long long)*n) / 10U);
#else
        res = (int)(((unsigned long)*n) % 10U);
        *n = (long)(((unsigned long)*n) / 10U);
#endif
    }
    else
    {
#ifdef RT_KPRINTF_USING_LONGLONG
        res = (int)(((unsigned long long)*n) % 16U);
        *n = (long long)(((unsigned long long)*n) / 16U);
#else
        res = (int)(((unsigned long)*n) % 16U);
        *n = (long)(((unsigned long)*n) / 16U);
#endif
    }

    return res;
}

rt_inline int skip_atoi(const char **s)
{
    int i = 0;
    while (_ISDIGIT(**s))
        i = i * 10 + *((*s)++) - '0';

    return i;
}

#define ZEROPAD     (1 << 0)    /* pad with zero */
#define SIGN        (1 << 1)    /* unsigned/signed long */
#define PLUS        (1 << 2)    /* show plus */
#define SPACE       (1 << 3)    /* space if plus */
#define LEFT        (1 << 4)    /* left justified */
#define SPECIAL     (1 << 5)    /* 0x */
#define LARGE       (1 << 6)    /* use 'ABCDEF' instead of 'abcdef' */

static char *print_number(char *buf,
                          char *end,
#ifdef RT_KPRINTF_USING_LONGLONG
                          long long  num,
#else
                          long  num,
#endif /* RT_KPRINTF_USING_LONGLONG */
                          int   base,
                          int   s,
#ifdef RT_PRINTF_PRECISION
                          int   precision,
#endif /* RT_PRINTF_PRECISION */
                          int   type)
{
    char c, sign;
#ifdef RT_KPRINTF_USING_LONGLONG
    char tmp[32];
#else
    char tmp[16];
#endif /* RT_KPRINTF_USING_LONGLONG */
    int precision_bak = precision;
    const char *digits;
    static const char small_digits[] = "0123456789abcdef";
    static const char large_digits[] = "0123456789ABCDEF";
    int i, size;

    size = s;

    digits = (type & LARGE) ? large_digits : small_digits;
    if (type & LEFT)
        type &= ~ZEROPAD;

    c = (type & ZEROPAD) ? '0' : ' ';

    /* get sign */
    sign = 0;
    if (type & SIGN)
    {
        if (num < 0)
        {
            sign = '-';
            num = -num;
        }
        else if (type & PLUS)
            sign = '+';
        else if (type & SPACE)
            sign = ' ';
    }

#ifdef RT_PRINTF_SPECIAL
    if (type & SPECIAL)
    {
        if (base == 16)
            size -= 2;
        else if (base == 8)
            size--;
    }
#endif /* RT_PRINTF_SPECIAL */

    i = 0;
    if (num == 0)
        tmp[i++] = '0';
    else
    {
        while (num != 0)
            tmp[i++] = digits[divide(&num, base)];
    }

#ifdef RT_PRINTF_PRECISION
    if (i > precision)
        precision = i;
    size -= precision;
#else
    size -= i;
#endif /* RT_PRINTF_PRECISION */

    if (!(type & (ZEROPAD | LEFT)))
    {
        if ((sign) && (size > 0))
            size--;

        while (size-- > 0)
        {
            if (buf < end)
                *buf = ' ';
            ++ buf;
        }
    }

    if (sign)
    {
        if (buf < end)
        {
            *buf = sign;
        }
        -- size;
        ++ buf;
    }

#ifdef RT_PRINTF_SPECIAL
    if (type & SPECIAL)
    {
        if (base == 8)
        {
            if (buf < end)
                *buf = '0';
            ++ buf;
        }
        else if (base == 16)
        {
            if (buf < end)
                *buf = '0';
            ++ buf;
            if (buf < end)
            {
                *buf = type & LARGE ? 'X' : 'x';
            }
            ++ buf;
        }
    }
#endif /* RT_PRINTF_SPECIAL */

    /* no align to the left */
    if (!(type & LEFT))
    {
        while (size-- > 0)
        {
            if (buf < end)
                *buf = c;
            ++ buf;
        }
    }

#ifdef RT_PRINTF_PRECISION
    while (i < precision--)
    {
        if (buf < end)
            *buf = '0';
        ++ buf;
    }
#endif /* RT_PRINTF_PRECISION */

    /* put number in the temporary buffer */
    while (i-- > 0 && (precision_bak != 0))
    {
        if (buf < end)
            *buf = tmp[i];
        ++ buf;
    }

    while (size-- > 0)
    {
        if (buf < end)
            *buf = ' ';
        ++ buf;
    }

    return buf;
}


/**
 * This function will fill a formatted string to buffer.
 *
 * @param  buf is the buffer to save formatted string.
 *
 * @param  size is the size of buffer.
 *
 * @param  fmt is the format parameters.
 *
 * @return The number of characters actually written to buffer.
 */
int rt_snprintf(char *buf, rt_size_t size, const char *fmt, ...)
{
    rt_int32_t n;
    va_list args;

    va_start(args, fmt);
    n = rt_vsnprintf(buf, size, fmt, args);
    va_end(args);

    return n;
}
RTM_EXPORT(rt_snprintf);

/**
 * This function will fill a formatted string to buffer.
 *
 * @param  buf is the buffer to save formatted string.
 *
 * @param  format is the format parameters.
 *
 * @param  arg_ptr is a list of variable parameters.
 *
 * @return The number of characters actually written to buffer.
 */
int rt_vsprintf(char *buf, const char *format, va_list arg_ptr)
{
    return rt_vsnprintf(buf, (rt_size_t) - 1, format, arg_ptr);
}
RTM_EXPORT(rt_vsprintf);

/**
 * This function will fill a formatted string to buffer
 *
 * @param  buf the buffer to save formatted string.
 *
 * @param  format is the format parameters.
 *
 * @return The number of characters actually written to buffer.
 */
int rt_sprintf(char *buf, const char *format, ...)
{
    rt_int32_t n;
    va_list arg_ptr;

    va_start(arg_ptr, format);
    n = rt_vsprintf(buf, format, arg_ptr);
    va_end(arg_ptr);

    return n;
}
RTM_EXPORT(rt_sprintf);

#ifdef RT_USING_CONSOLE

#ifdef RT_USING_DEVICE
/**
 * This function returns the device using in console.
 *
 * @return Returns the console device pointer or RT_NULL.
 */
rt_device_t rt_console_get_device(void)
{
    return _console_device;
}
RTM_EXPORT(rt_console_get_device);

/**
 * This function will set a device as console device.
 * After set a device to console, all output of rt_kprintf will be
 * redirected to this new device.
 *
 * @param  name is the name of new console device.
 *
 * @return the old console device handler on successful, or RT_NULL on failure.
 */
rt_device_t rt_console_set_device(const char *name)
{
    rt_device_t new_device, old_device;

    /* save old device */
    old_device = _console_device;

    /* find new console device */
    new_device = rt_device_find(name);

    /* check whether it's a same device */
    if (new_device == old_device) return RT_NULL;

    if (new_device != RT_NULL)
    {
        if (_console_device != RT_NULL)
        {
            /* close old console device */
            rt_device_close(_console_device);
        }

        /* set new console device */
        rt_device_open(new_device, RT_DEVICE_OFLAG_RDWR | RT_DEVICE_FLAG_STREAM);
        _console_device = new_device;
    }

    return old_device;
}
RTM_EXPORT(rt_console_set_device);
#endif /* RT_USING_DEVICE */

RT_WEAK void rt_hw_console_output(const char *str)
{
    /* empty console output */
}
RTM_EXPORT(rt_hw_console_output);

/**
 * This function will put string to the console.
 *
 * @param str is the string output to the console.
 */
void rt_kputs(const char *str)
{
    if (!str) return;

#ifdef RT_USING_DEVICE
    if (_console_device == RT_NULL)
    {
        rt_hw_console_output(str);
    }
    else
    {
        rt_device_write(_console_device, 0, str, rt_strlen(str));
    }
#else
    rt_hw_console_output(str);
#endif /* RT_USING_DEVICE */
}

/**
 * This function will print a formatted string on system console.
 *
 * @param fmt is the format parameters.
 *
 * @return The number of characters actually written to buffer.
 */
RT_WEAK int rt_kprintf(const char *fmt, ...)
{
    va_list args;
    rt_size_t length;
    static char rt_log_buf[RT_CONSOLEBUF_SIZE];

    va_start(args, fmt);
    /* the return value of vsnprintf is the number of bytes that would be
     * written to buffer had if the size of the buffer been sufficiently
     * large excluding the terminating null byte. If the output string
     * would be larger than the rt_log_buf, we have to adjust the output
     * length. */
    length = rt_vsnprintf(rt_log_buf, sizeof(rt_log_buf) - 1, fmt, args);
    if (length > RT_CONSOLEBUF_SIZE - 1)
        length = RT_CONSOLEBUF_SIZE - 1;
#ifdef RT_USING_DEVICE
    if (_console_device == RT_NULL)
    {
        rt_hw_console_output(rt_log_buf);
    }
    else
    {
        rt_device_write(_console_device, 0, rt_log_buf, length);
    }
#else
    rt_hw_console_output(rt_log_buf);
#endif /* RT_USING_DEVICE */
    va_end(args);

    return length;
}
RTM_EXPORT(rt_kprintf);
#endif /* RT_USING_CONSOLE */

#if defined(RT_USING_HEAP) && !defined(RT_USING_USERHEAP)
#ifdef RT_USING_HOOK
static void (*rt_malloc_hook)(void *ptr, rt_size_t size);
static void (*rt_free_hook)(void *ptr);

/**
 * @addtogroup Hook
 */

/**@{*/

/**
 * @brief This function will set a hook function, which will be invoked when a memory
 *        block is allocated from heap memory.
 *
 * @param hook the hook function.
 */
void rt_malloc_sethook(void (*hook)(void *ptr, rt_size_t size))
{
    rt_malloc_hook = hook;
}

/**
 * @brief This function will set a hook function, which will be invoked when a memory
 *        block is released to heap memory.
 *
 * @param hook the hook function
 */
void rt_free_sethook(void (*hook)(void *ptr))
{
    rt_free_hook = hook;
}

/**@}*/

#endif /* RT_USING_HOOK */

#if defined(RT_USING_HEAP_ISR)
#elif defined(RT_USING_MUTEX)
static struct rt_mutex _lock;
#endif

rt_inline void _heap_lock_init(void)
{
#if defined(RT_USING_HEAP_ISR)
#elif defined(RT_USING_MUTEX)
    rt_mutex_init(&_lock, "heap", RT_IPC_FLAG_PRIO);
#endif
}

rt_inline rt_base_t _heap_lock(void)
{
#if defined(RT_USING_HEAP_ISR)
    return rt_hw_interrupt_disable();
#elif defined(RT_USING_MUTEX)
    if (rt_thread_self())
        return rt_mutex_take(&_lock, RT_WAITING_FOREVER);
    else
        return RT_EOK;
#else
    rt_enter_critical();
    return RT_EOK;
#endif
}

rt_inline void _heap_unlock(rt_base_t level)
{
#if defined(RT_USING_HEAP_ISR)
    rt_hw_interrupt_enable(level);
#elif defined(RT_USING_MUTEX)
    RT_ASSERT(level == RT_EOK);
    if (rt_thread_self())
        rt_mutex_release(&_lock);
#else
    rt_exit_critical();
#endif
}

#if defined(RT_USING_SMALL_MEM_AS_HEAP)
static rt_smem_t system_heap;
rt_inline void _smem_info(rt_size_t *total,
    rt_size_t *used, rt_size_t *max_used)
{
    if (total)
        *total = system_heap->total;
    if (used)
        *used = system_heap->used;
    if (max_used)
        *max_used = system_heap->max;
}
#define _MEM_INIT(_name, _start, _size) \
    system_heap = rt_smem_init(_name, _start, _size)
#define _MEM_MALLOC(_size)  \
    rt_smem_alloc(system_heap, _size)
#define _MEM_REALLOC(_ptr, _newsize)\
    rt_smem_realloc(system_heap, _ptr, _newsize)
#define _MEM_FREE(_ptr) \
    rt_smem_free(_ptr)
#define _MEM_INFO(_total, _used, _max)  \
    _smem_info(_total, _used, _max)
#elif defined(RT_USING_MEMHEAP_AS_HEAP)
static struct rt_memheap system_heap;
void *_memheap_alloc(struct rt_memheap *heap, rt_size_t size);
void _memheap_free(void *rmem);
void *_memheap_realloc(struct rt_memheap *heap, void *rmem, rt_size_t newsize);
#define _MEM_INIT(_name, _start, _size) \
    rt_memheap_init(&system_heap, _name, _start, _size)
#define _MEM_MALLOC(_size)  \
    _memheap_alloc(&system_heap, _size)
#define _MEM_REALLOC(_ptr, _newsize)    \
    _memheap_realloc(&system_heap, _ptr, _newsize)
#define _MEM_FREE(_ptr)   \
    _memheap_free(_ptr)
#define _MEM_INFO(_total, _used, _max)   \
    rt_memheap_info(&system_heap, _total, _used, _max)
#elif defined(RT_USING_SLAB_AS_HEAP)
static rt_slab_t system_heap;
rt_inline void _slab_info(rt_size_t *total,
    rt_size_t *used, rt_size_t *max_used)
{
    if (total)
        *total = system_heap->total;
    if (used)
        *used = system_heap->used;
    if (max_used)
        *max_used = system_heap->max;
}
#define _MEM_INIT(_name, _start, _size) \
    system_heap = rt_slab_init(_name, _start, _size)
#define _MEM_MALLOC(_size)  \
    rt_slab_alloc(system_heap, _size)
#define _MEM_REALLOC(_ptr, _newsize)    \
    rt_slab_realloc(system_heap, _ptr, _newsize)
#define _MEM_FREE(_ptr) \
    rt_slab_free(system_heap, _ptr)
#define _MEM_INFO       _slab_info
#else
#define _MEM_INIT(...)
#define _MEM_MALLOC(...)     RT_NULL
#define _MEM_REALLOC(...)    RT_NULL
#define _MEM_FREE(...)
#define _MEM_INFO(...)
#endif

/**
 * @brief This function will init system heap.
 *
 * @param begin_addr the beginning address of system page.
 *
 * @param end_addr the end address of system page.
 */
RT_WEAK void rt_system_heap_init(void *begin_addr, void *end_addr)
{
    rt_ubase_t begin_align = RT_ALIGN((rt_ubase_t)begin_addr, RT_ALIGN_SIZE);
    rt_ubase_t end_align   = RT_ALIGN_DOWN((rt_ubase_t)end_addr, RT_ALIGN_SIZE);

    RT_ASSERT(end_align > begin_align);

    /* Initialize system memory heap */
    _MEM_INIT("heap", begin_addr, end_align - begin_align);
    /* Initialize multi thread contention lock */
    _heap_lock_init();
}

/**
 * @brief Allocate a block of memory with a minimum of 'size' bytes.
 *
 * @param size is the minimum size of the requested block in bytes.
 *
 * @return the pointer to allocated memory or NULL if no free memory was found.
 */
RT_WEAK void *rt_malloc(rt_size_t size)
{
    rt_base_t level;
    void *ptr;

    /* Enter critical zone */
    level = _heap_lock();
    /* allocate memory block from system heap */
    ptr = _MEM_MALLOC(size);
    /* Exit critical zone */
    _heap_unlock(level);
    /* call 'rt_malloc' hook */
    RT_OBJECT_HOOK_CALL(rt_malloc_hook, (ptr, size));
    return ptr;
}
RTM_EXPORT(rt_malloc);

/**
 * @brief This function will change the size of previously allocated memory block.
 *
 * @param rmem is the pointer to memory allocated by rt_malloc.
 *
 * @param newsize is the required new size.
 *
 * @return the changed memory block address.
 */
RT_WEAK void *rt_realloc(void *rmem, rt_size_t newsize)
{
    rt_base_t level;
    void *nptr;

    /* Enter critical zone */
    level = _heap_lock();
    /* Change the size of previously allocated memory block */
    nptr = _MEM_REALLOC(rmem, newsize);
    /* Exit critical zone */
    _heap_unlock(level);
    return nptr;
}
RTM_EXPORT(rt_realloc);

/**
 * @brief  This function will contiguously allocate enough space for count objects
 *         that are size bytes of memory each and returns a pointer to the allocated
 *         memory.
 *
 * @note   The allocated memory is filled with bytes of value zero.
 *
 * @param  count is the number of objects to allocate.
 *
 * @param  size is the size of one object to allocate.
 *
 * @return pointer to allocated memory / NULL pointer if there is an error.
 */
RT_WEAK void *rt_calloc(rt_size_t count, rt_size_t size)
{
    void *p;

    /* allocate 'count' objects of size 'size' */
    p = rt_malloc(count * size);
    /* zero the memory */
    if (p)
    {
        rt_memset(p, 0, count * size);
    }
    return p;
}
RTM_EXPORT(rt_calloc);

/**
 * @brief This function will release the previously allocated memory block by
 *        rt_malloc. The released memory block is taken back to system heap.
 *
 * @param rmem the address of memory which will be released.
 */
RT_WEAK void rt_free(void *rmem)
{
    rt_base_t level;

    /* call 'rt_free' hook */
    RT_OBJECT_HOOK_CALL(rt_free_hook, (rmem));
    /* NULL check */
    if (rmem == RT_NULL) return;
    /* Enter critical zone */
    level = _heap_lock();
    _MEM_FREE(rmem);
    /* Exit critical zone */
    _heap_unlock(level);
}
RTM_EXPORT(rt_free);

/**
* @brief This function will caculate the total memory, the used memory, and
*        the max used memory.
*
* @param total is a pointer to get the total size of the memory.
*
* @param used is a pointer to get the size of memory used.
*
* @param max_used is a pointer to get the maximum memory used.
*/
RT_WEAK void rt_memory_info(rt_size_t *total,
                            rt_size_t *used,
                            rt_size_t *max_used)
{
    rt_base_t level;

    /* Enter critical zone */
    level = _heap_lock();
    _MEM_INFO(total, used, max_used);
    /* Exit critical zone */
    _heap_unlock(level);
}
RTM_EXPORT(rt_memory_info);

#if defined(RT_USING_SLAB) && defined(RT_USING_SLAB_AS_HEAP)
void *rt_page_alloc(rt_size_t npages)
{
    rt_base_t level;
    void *ptr;

    /* Enter critical zone */
    level = _heap_lock();
    /* alloc page */
    ptr = rt_slab_page_alloc(system_heap, npages);
    /* Exit critical zone */
    _heap_unlock(level);
    return ptr;
}

void rt_page_free(void *addr, rt_size_t npages)
{
    rt_base_t level;

    /* Enter critical zone */
    level = _heap_lock();
    /* free page */
    rt_slab_page_free(system_heap, addr, npages);
    /* Exit critical zone */
    _heap_unlock(level);
}
#endif

/**
 * This function allocates a memory block, which address is aligned to the
 * specified alignment size.
 *
 * @param  size is the allocated memory block size.
 *
 * @param  align is the alignment size.
 *
 * @return The memory block address was returned successfully, otherwise it was
 *         returned empty RT_NULL.
 */
RT_WEAK void *rt_malloc_align(rt_size_t size, rt_size_t align)
{
    void *ptr;
    void *align_ptr;
    int uintptr_size;
    rt_size_t align_size;

    /* sizeof pointer */
    uintptr_size = sizeof(void*);
    uintptr_size -= 1;

    /* align the alignment size to uintptr size byte */
    align = ((align + uintptr_size) & ~uintptr_size);

    /* get total aligned size */
    align_size = ((size + uintptr_size) & ~uintptr_size) + align;
    /* allocate memory block from heap */
    ptr = rt_malloc(align_size);
    if (ptr != RT_NULL)
    {
        /* the allocated memory block is aligned */
        if (((rt_ubase_t)ptr & (align - 1)) == 0)
        {
            align_ptr = (void *)((rt_ubase_t)ptr + align);
        }
        else
        {
            align_ptr = (void *)(((rt_ubase_t)ptr + (align - 1)) & ~(align - 1));
        }

        /* set the pointer before alignment pointer to the real pointer */
        *((rt_ubase_t *)((rt_ubase_t)align_ptr - sizeof(void *))) = (rt_ubase_t)ptr;

        ptr = align_ptr;
    }

    return ptr;
}
RTM_EXPORT(rt_malloc_align);

/**
 * This function release the memory block, which is allocated by
 * rt_malloc_align function and address is aligned.
 *
 * @param ptr is the memory block pointer.
 */
RT_WEAK void rt_free_align(void *ptr)
{
    void *real_ptr;

    /* NULL check */
    if (ptr == RT_NULL) return;
    real_ptr = (void *) * (rt_ubase_t *)((rt_ubase_t)ptr - sizeof(void *));
    rt_free(real_ptr);
}
RTM_EXPORT(rt_free_align);
#endif /* RT_USING_HEAP */

#ifndef RT_USING_CPU_FFS
#ifdef RT_USING_TINY_FFS
const rt_uint8_t __lowest_bit_bitmap[] =
{
    /*  0 - 7  */  0,  1,  2, 27,  3, 24, 28, 32,
    /*  8 - 15 */  4, 17, 25, 31, 29, 12, 32, 14,
    /* 16 - 23 */  5,  8, 18, 32, 26, 23, 32, 16,
    /* 24 - 31 */ 30, 11, 13,  7, 32, 22, 15, 10,
    /* 32 - 36 */  6, 21,  9, 20, 19
};

/**
 * This function finds the first bit set (beginning with the least significant bit)
 * in value and return the index of that bit.
 *
 * Bits are numbered starting at 1 (the least significant bit).  A return value of
 * zero from any of these functions means that the argument was zero.
 *
 * @return return the index of the first bit set. If value is 0, then this function
 * shall return 0.
 */
int __rt_ffs(int value)
{
    return __lowest_bit_bitmap[(rt_uint32_t)(value & (value - 1) ^ value) % 37];
}
#else
const rt_uint8_t __lowest_bit_bitmap[] =
{
    /* 00 */ 0, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 10 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 20 */ 5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 30 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 40 */ 6, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 50 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 60 */ 5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 70 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 80 */ 7, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* 90 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* A0 */ 5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* B0 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* C0 */ 6, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* D0 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* E0 */ 5, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0,
    /* F0 */ 4, 0, 1, 0, 2, 0, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0
};

/**
 * This function finds the first bit set (beginning with the least significant bit)
 * in value and return the index of that bit.
 *
 * Bits are numbered starting at 1 (the least significant bit).  A return value of
 * zero from any of these functions means that the argument was zero.
 *
 * @return Return the index of the first bit set. If value is 0, then this function
 *         shall return 0.
 */
int __rt_ffs(int value)
{
    if (value == 0) return 0;

    if (value & 0xff)
        return __lowest_bit_bitmap[value & 0xff] + 1;

    if (value & 0xff00)
        return __lowest_bit_bitmap[(value & 0xff00) >> 8] + 9;

    if (value & 0xff0000)
        return __lowest_bit_bitmap[(value & 0xff0000) >> 16] + 17;

    return __lowest_bit_bitmap[(value & 0xff000000) >> 24] + 25;
}
#endif /* RT_USING_TINY_FFS */
#endif /* RT_USING_CPU_FFS */

#ifndef __on_rt_assert_hook
    #define __on_rt_assert_hook(ex, func, line)         __ON_HOOK_ARGS(rt_assert_hook, (ex, func, line))
#endif

#ifdef RT_DEBUG
/* RT_ASSERT(EX)'s hook */

void (*rt_assert_hook)(const char *ex, const char *func, rt_size_t line);

/**
 * This function will set a hook function to RT_ASSERT(EX). It will run when the expression is false.
 *
 * @param hook is the hook function.
 */
void rt_assert_set_hook(void (*hook)(const char *ex, const char *func, rt_size_t line))
{
    rt_assert_hook = hook;
}

/**
 * The RT_ASSERT function.
 *
 * @param ex_string is the assertion condition string.
 *
 * @param func is the function name when assertion.
 *
 * @param line is the file line number when assertion.
 */
void rt_assert_handler(const char *ex_string, const char *func, rt_size_t line)
{
    volatile char dummy = 0;

    if (rt_assert_hook == RT_NULL)
    {
#ifdef RT_USING_MODULE
        if (dlmodule_self())
        {
            /* close assertion module */
            dlmodule_exit(-1);
        }
        else
#endif /*RT_USING_MODULE*/
        {
            rt_kprintf("(%s) assertion failed at function:%s, line number:%d \n", ex_string, func, line);
            while (dummy == 0);
        }
    }
    else
    {
        rt_assert_hook(ex_string, func, line);
    }
}
RTM_EXPORT(rt_assert_handler);
#endif /* RT_DEBUG */

/**@}*/

/*
 * Copyright (c) 2021, Meco Jianting Man <jiantingman@foxmail.com>
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2021-11-27     Meco Man     porting for rt_vsnprintf as the fully functional version
 */

/**
 * @author (c) Eyal Rozenberg <eyalroz1@gmx.com>
 *             2021-2022, Haifa, Palestine/Israel
 * @author (c) Marco Paland (info@paland.com)
 *             2014-2019, PALANDesign Hannover, Germany
 *
 * @note Others have made smaller contributions to this file: see the
 * contributors page at https://github.com/eyalroz/printf/graphs/contributors
 * or ask one of the authors. The original code for exponential specifiers was
 * contributed by Martijn Jasperse <m.jasperse@gmail.com>.
 *
 * @brief Small stand-alone implementation of the printf family of functions
 * (`(v)printf`, `(v)s(n)printf` etc., geared towards use on embedded systems with
 * a very limited resources.
 *
 * @note the implementations are thread-safe; re-entrant; use no functions from
 * the standard library; and do not dynamically allocate any memory.
 *
 * @license The MIT License (MIT)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include <stdio.h>
#include <stdint.h>
#include <limits.h>
#include <stdbool.h>

#include <rtconfig.h>
#include <rtdef.h>
#include <rtthread.h>

#if 1 //ndef RT_VER_NUM /* Doesn't use menuconfig */
// 'ntoa' conversion buffer size, this must be big enough to hold one converted
// numeric number including padded zeros (dynamically created on stack)
#ifndef PKG_VSNPRINTF_INTEGER_BUFFER_SIZE
#define PKG_VSNPRINTF_INTEGER_BUFFER_SIZE    32
#endif

// size of the fixed (on-stack) buffer for printing individual decimal numbers.
// this must be big enough to hold one converted floating-point value including
// padded zeros.
#ifndef PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE
#define PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE    32
#endif

// Support for the decimal notation floating point conversion specifiers (%f, %F)
#ifndef PKG_VSNPRINTF_SUPPORT_DECIMAL_SPECIFIERS
#define PKG_VSNPRINTF_SUPPORT_DECIMAL_SPECIFIERS
#endif

// Support for the exponential notation floating point conversion specifiers (%e, %g, %E, %G)
#ifndef PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS
#define PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS
#endif

// Support for the length write-back specifier (%n)
#ifndef PKG_VSNPRINTF_SUPPORT_WRITEBACK_SPECIFIER
#define PKG_VSNPRINTF_SUPPORT_WRITEBACK_SPECIFIER
#endif

// Default precision for the floating point conversion specifiers (the C standard sets this at 6)
#ifndef PKG_VSNPRINTF_DEFAULT_FLOAT_PRECISION
#define PKG_VSNPRINTF_DEFAULT_FLOAT_PRECISION  6
#endif

// According to the C languages standard, printf() and related functions must be able to print any
// integral number in floating-point notation, regardless of length, when using the %f specifier -
// possibly hundreds of characters, potentially overflowing your buffers. In this implementation,
// all values beyond this threshold are switched to exponential notation.
#ifndef PKG_VSNPRINTF_MAX_INTEGRAL_DIGITS_FOR_DECIMAL
#define PKG_VSNPRINTF_MAX_INTEGRAL_DIGITS_FOR_DECIMAL 9
#endif

// Support for the long long integral types (with the ll, z and t length modifiers for specifiers
// %d,%i,%o,%x,%X,%u, and with the %p specifier). Note: 'L' (long double) is not supported.
#ifndef PKG_VSNPRINTF_SUPPORT_LONG_LONG
#define PKG_VSNPRINTF_SUPPORT_LONG_LONG
#endif

// The number of terms in a Taylor series expansion of log_10(x) to
// use for approximation - including the power-zero term (i.e. the
// value at the point of expansion).
#ifndef PKG_VSNPRINTF_LOG10_TAYLOR_TERMS
#define PKG_VSNPRINTF_LOG10_TAYLOR_TERMS 4
#endif

// Be extra-safe, and don't assume format specifiers are completed correctly
// before the format string end.
#ifndef PKG_VSNPRINTF_CHECK_FOR_NUL_IN_FORMAT_SPECIFIER
#define PKG_VSNPRINTF_CHECK_FOR_NUL_IN_FORMAT_SPECIFIER
#endif
#endif /* RT_VER_NUM */

#if PKG_VSNPRINTF_LOG10_TAYLOR_TERMS <= 1
#error "At least one non-constant Taylor expansion is necessary for the log10() calculation"
#endif

///////////////////////////////////////////////////////////////////////////////

#define PRINTF_PREFER_DECIMAL     false
#define PRINTF_PREFER_EXPONENTIAL true

// The following will convert the number-of-digits into an exponential-notation literal
#define PRINTF_CONCATENATE(s1, s2) s1##s2
#define PRINTF_EXPAND_THEN_CONCATENATE(s1, s2) PRINTF_CONCATENATE(s1, s2)
#define PRINTF_FLOAT_NOTATION_THRESHOLD PRINTF_EXPAND_THEN_CONCATENATE(1e,PKG_VSNPRINTF_MAX_INTEGRAL_DIGITS_FOR_DECIMAL)

// internal flag definitions
#define FLAGS_ZEROPAD   (1U <<  0U)
#define FLAGS_LEFT      (1U <<  1U)
#define FLAGS_PLUS      (1U <<  2U)
#define FLAGS_SPACE     (1U <<  3U)
#define FLAGS_HASH      (1U <<  4U)
#define FLAGS_UPPERCASE (1U <<  5U)
#define FLAGS_CHAR      (1U <<  6U)
#define FLAGS_SHORT     (1U <<  7U)
#define FLAGS_INT       (1U <<  8U)
  // Only used with PKG_VSNPRINTF_SUPPORT_MSVC_STYLE_INTEGER_SPECIFIERS
#define FLAGS_LONG      (1U <<  9U)
#define FLAGS_LONG_LONG (1U << 10U)
#define FLAGS_PRECISION (1U << 11U)
#define FLAGS_ADAPT_EXP (1U << 12U)
#define FLAGS_POINTER   (1U << 13U)
  // Note: Similar, but not identical, effect as FLAGS_HASH
#define FLAGS_SIGNED    (1U << 14U)
  // Only used with PKG_VSNPRINTF_SUPPORT_MSVC_STYLE_INTEGER_SPECIFIERS

#ifdef PKG_VSNPRINTF_SUPPORT_MSVC_STYLE_INTEGER_SPECIFIERS

#define FLAGS_INT8 FLAGS_CHAR

#if   (SHRT_MAX   == 32767LL)
#define FLAGS_INT16       FLAGS_SHORT
#elif (INT_MAX    == 32767LL)
#define FLAGS_INT16       FLAGS_INT
#elif (LONG_MAX   == 32767LL)
#define FLAGS_INT16       FLAGS_LONG
#elif (LLONG_MAX  == 32767LL)
#define FLAGS_INT16       FLAGS_LONG_LONG
#else
#error "No basic integer type has a size of 16 bits exactly"
#endif

#if   (SHRT_MAX   == 2147483647LL)
#define FLAGS_INT32       FLAGS_SHORT
#elif (INT_MAX    == 2147483647LL)
#define FLAGS_INT32       FLAGS_INT
#elif (LONG_MAX   == 2147483647LL)
#define FLAGS_INT32       FLAGS_LONG
#elif (LLONG_MAX  == 2147483647LL)
#define FLAGS_INT32       FLAGS_LONG_LONG
#else
#error "No basic integer type has a size of 32 bits exactly"
#endif

#if   (SHRT_MAX   == 9223372036854775807LL)
#define FLAGS_INT64       FLAGS_SHORT
#elif (INT_MAX    == 9223372036854775807LL)
#define FLAGS_INT64       FLAGS_INT
#elif (LONG_MAX   == 9223372036854775807LL)
#define FLAGS_INT64       FLAGS_LONG
#elif (LLONG_MAX  == 9223372036854775807LL)
#define FLAGS_INT64       FLAGS_LONG_LONG
#else
#error "No basic integer type has a size of 64 bits exactly"
#endif

#endif // PKG_VSNPRINTF_SUPPORT_MSVC_STYLE_INTEGER_SPECIFIERS


typedef unsigned int printf_flags_t;

#define BASE_BINARY    2
#define BASE_OCTAL     8
#define BASE_DECIMAL  10
#define BASE_HEX      16

typedef uint8_t numeric_base_t;

#ifdef PKG_VSNPRINTF_SUPPORT_LONG_LONG
typedef unsigned long long printf_unsigned_value_t;
typedef long long          printf_signed_value_t;
#else
typedef unsigned long printf_unsigned_value_t;
typedef long          printf_signed_value_t;
#endif

// The printf()-family functions return an `int`; it is therefore
// unnecessary/inappropriate to use size_t - often larger than int
// in practice - for non-negative related values, such as widths,
// precisions, offsets into buffers used for printing and the sizes
// of these buffers. instead, we use:
typedef unsigned int printf_size_t;
#define PRINTF_MAX_POSSIBLE_BUFFER_SIZE INT_MAX
  // If we were to nitpick, this would actually be INT_MAX + 1,
  // since INT_MAX is the maximum return value, which excludes the
  // trailing '\0'.

#if defined(PKG_VSNPRINTF_SUPPORT_DECIMAL_SPECIFIERS) || defined(PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS)
#include <float.h>
#if FLT_RADIX != 2
#error "Non-binary-radix floating-point types are unsupported."
#endif

#if DBL_MANT_DIG == 24

#define DOUBLE_SIZE_IN_BITS 32
typedef uint32_t double_uint_t;
#define DOUBLE_EXPONENT_MASK 0xFFU
#define DOUBLE_BASE_EXPONENT 127
#define DOUBLE_MAX_SUBNORMAL_EXPONENT_OF_10 -38
#define DOUBLE_MAX_SUBNORMAL_POWER_OF_10 1e-38

#elif DBL_MANT_DIG == 53

#define DOUBLE_SIZE_IN_BITS 64
typedef uint64_t double_uint_t;
#define DOUBLE_EXPONENT_MASK 0x7FFU
#define DOUBLE_BASE_EXPONENT 1023
#define DOUBLE_MAX_SUBNORMAL_EXPONENT_OF_10 -308
#define DOUBLE_MAX_SUBNORMAL_POWER_OF_10 ((double)1e-308L)

#else
#error "Unsupported double type configuration"
#endif
#define DOUBLE_STORED_MANTISSA_BITS (DBL_MANT_DIG - 1)

typedef union {
  double_uint_t U;
  double        F;
} double_with_bit_access;

// This is unnecessary in C99, since compound initializers can be used,
// but:
// 1. Some compilers are finicky about this;
// 2. Some people may want to convert this to C89;
// 3. If you try to use it as C++, only C++20 supports compound literals
static inline double_with_bit_access get_bit_access(double x)
{
  double_with_bit_access dwba;
  dwba.F = x;
  return dwba;
}

static inline int get_sign_bit(double x)
{
  // The sign is stored in the highest bit
  return (int) (get_bit_access(x).U >> (DOUBLE_SIZE_IN_BITS - 1));
}

static inline int get_exp2(double_with_bit_access x)
{
  // The exponent in an IEEE-754 floating-point number occupies a contiguous
  // sequence of bits (e.g. 52..62 for 64-bit doubles), but with a non-trivial representation: An
  // unsigned offset from some negative value (with the extremal offset values reserved for
  // special use).
  return (int)((x.U >> DOUBLE_STORED_MANTISSA_BITS ) & DOUBLE_EXPONENT_MASK) - DOUBLE_BASE_EXPONENT;
}
#define PRINTF_ABS(_x) ( (_x) > 0 ? (_x) : -(_x) )

#endif // (PKG_VSNPRINTF_SUPPORT_DECIMAL_SPECIFIERS || PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS)

// Note in particular the behavior here on LONG_MIN or LLONG_MIN; it is valid
// and well-defined, but if you're not careful you can easily trigger undefined
// behavior with -LONG_MIN or -LLONG_MIN
#define ABS_FOR_PRINTING(_x) ((printf_unsigned_value_t) ( (_x) > 0 ? (_x) : -((printf_signed_value_t)_x) ))

// wrapper (used as buffer) for output function type
//
// One of the following must hold:
// 1. max_chars is 0
// 2. buffer is non-null
// 3. function is non-null
//
// ... otherwise bad things will happen.
typedef struct {
  void (*function)(char c, void* extra_arg);
  void* extra_function_arg;
  char* buffer;
  printf_size_t pos;
  printf_size_t max_chars;
} output_gadget_t;

// Note: This function currently assumes it is not passed a '\0' c,
// or alternatively, that '\0' can be passed to the function in the output
// gadget. The former assumption holds within the printf library. It also
// assumes that the output gadget has been properly initialized.
static inline void putchar_via_gadget(output_gadget_t* gadget, char c)
{
  printf_size_t write_pos = gadget->pos++;
    // We're _always_ increasing pos, so as to count how may characters
    // _would_ have been written if not for the max_chars limitation
  if (write_pos >= gadget->max_chars) {
    return;
  }
  if (gadget->function != NULL) {
    // No check for c == '\0' .
    gadget->function(c, gadget->extra_function_arg);
  }
  else {
    // it must be the case that gadget->buffer != NULL , due to the constraint
    // on output_gadget_t ; and note we're relying on write_pos being non-negative.
    gadget->buffer[write_pos] = c;
  }
}

// Possibly-write the string-terminating '\0' character
static inline void append_termination_with_gadget(output_gadget_t* gadget)
{
  if (gadget->function != NULL || gadget->max_chars == 0) {
    return;
  }
  if (gadget->buffer == NULL) {
    return;
  }
  printf_size_t null_char_pos = gadget->pos < gadget->max_chars ? gadget->pos : gadget->max_chars - 1;
  gadget->buffer[null_char_pos] = '\0';
}

static inline output_gadget_t discarding_gadget(void)
{
  output_gadget_t gadget;
  gadget.function = NULL;
  gadget.extra_function_arg = NULL;
  gadget.buffer = NULL;
  gadget.pos = 0;
  gadget.max_chars = 0;
  return gadget;
}

static inline output_gadget_t buffer_gadget(char* buffer, size_t buffer_size)
{
  printf_size_t usable_buffer_size = (buffer_size > PRINTF_MAX_POSSIBLE_BUFFER_SIZE) ?
    PRINTF_MAX_POSSIBLE_BUFFER_SIZE : (printf_size_t) buffer_size;
  output_gadget_t result = discarding_gadget();
  if (buffer != NULL) {
    result.buffer = buffer;
    result.max_chars = usable_buffer_size;
  }
  return result;
}

// internal secure strlen
// @return The length of the string (excluding the terminating 0) limited by 'maxsize'
// @note strlen uses size_t, but wes only use this function with printf_size_t
// variables - hence the signature.
static inline printf_size_t strnlen_s_(const char* str, printf_size_t maxsize)
{
  const char* s;
  for (s = str; *s && maxsize--; ++s);
  return (printf_size_t)(s - str);
}


// internal test if char is a digit (0-9)
// @return true if char is a digit
static inline bool is_digit_(char ch)
{
  return (ch >= '0') && (ch <= '9');
}


// internal ASCII string to printf_size_t conversion
static printf_size_t atou_(const char** str)
{
  printf_size_t i = 0U;
  while (is_digit_(**str)) {
    i = i * 10U + (printf_size_t)(*((*str)++) - '0');
  }
  return i;
}


// output the specified string in reverse, taking care of any zero-padding
static void out_rev_(output_gadget_t* output, const char* buf, printf_size_t len, printf_size_t width, printf_flags_t flags)
{
  const printf_size_t start_pos = output->pos;

  // pad spaces up to given width
  if (!(flags & FLAGS_LEFT) && !(flags & FLAGS_ZEROPAD)) {
    for (printf_size_t i = len; i < width; i++) {
      putchar_via_gadget(output, ' ');
    }
  }

  // reverse string
  while (len) {
    putchar_via_gadget(output, buf[--len]);
  }

  // append pad spaces up to given width
  if (flags & FLAGS_LEFT) {
    while (output->pos - start_pos < width) {
      putchar_via_gadget(output, ' ');
    }
  }
}


// Invoked by print_integer after the actual number has been printed, performing necessary
// work on the number's prefix (as the number is initially printed in reverse order)
static void print_integer_finalization(output_gadget_t* output, char* buf, printf_size_t len, bool negative, numeric_base_t base, printf_size_t precision, printf_size_t width, printf_flags_t flags)
{
  printf_size_t unpadded_len = len;

  // pad with leading zeros
  {
    if (!(flags & FLAGS_LEFT)) {
      if (width && (flags & FLAGS_ZEROPAD) && (negative || (flags & (FLAGS_PLUS | FLAGS_SPACE)))) {
        width--;
      }
      while ((flags & FLAGS_ZEROPAD) && (len < width) && (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE)) {
        buf[len++] = '0';
      }
    }

    while ((len < precision) && (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE)) {
      buf[len++] = '0';
    }

    if (base == BASE_OCTAL && (len > unpadded_len)) {
      // Since we've written some zeros, we've satisfied the alternative format leading space requirement
      flags &= ~FLAGS_HASH;
    }
  }

  // handle hash
  if (flags & (FLAGS_HASH | FLAGS_POINTER)) {
    if (!(flags & FLAGS_PRECISION) && len && ((len == precision) || (len == width))) {
      // Let's take back some padding digits to fit in what will eventually
      // be the format-specific prefix
      if (unpadded_len < len) {
        len--; // This should suffice for BASE_OCTAL
      }
      if (len && (base == BASE_HEX || base == BASE_BINARY) && (unpadded_len < len)) {
        len--; // ... and an extra one for 0x or 0b
      }
    }
    if ((base == BASE_HEX) && !(flags & FLAGS_UPPERCASE) && (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE)) {
      buf[len++] = 'x';
    }
    else if ((base == BASE_HEX) && (flags & FLAGS_UPPERCASE) && (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE)) {
      buf[len++] = 'X';
    }
    else if ((base == BASE_BINARY) && (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE)) {
      buf[len++] = 'b';
    }
    if (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE) {
      buf[len++] = '0';
    }
  }

  if (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE) {
    if (negative) {
      buf[len++] = '-';
    }
    else if (flags & FLAGS_PLUS) {
      buf[len++] = '+';  // ignore the space if the '+' exists
    }
    else if (flags & FLAGS_SPACE) {
      buf[len++] = ' ';
    }
  }

  out_rev_(output, buf, len, width, flags);
}

// An internal itoa-like function
static void print_integer(output_gadget_t* output, printf_unsigned_value_t value, bool negative, numeric_base_t base, printf_size_t precision, printf_size_t width, printf_flags_t flags)
{
  char buf[PKG_VSNPRINTF_INTEGER_BUFFER_SIZE];
  printf_size_t len = 0U;

  if (!value) {
    if ( !(flags & FLAGS_PRECISION) ) {
      buf[len++] = '0';
      flags &= ~FLAGS_HASH;
      // We drop this flag this since either the alternative and regular modes of the specifier
      // don't differ on 0 values, or (in the case of octal) we've already provided the special
      // handling for this mode.
    }
    else if (base == BASE_HEX) {
      flags &= ~FLAGS_HASH;
      // We drop this flag this since either the alternative and regular modes of the specifier
      // don't differ on 0 values
    }
  }
  else {
    do {
      const char digit = (char)(value % base);
      buf[len++] = (char)(digit < 10 ? '0' + digit : (flags & FLAGS_UPPERCASE ? 'A' : 'a') + digit - 10);
      value /= base;
    } while (value && (len < PKG_VSNPRINTF_INTEGER_BUFFER_SIZE));
  }

  print_integer_finalization(output, buf, len, negative, base, precision, width, flags);
}

#if defined(PKG_VSNPRINTF_SUPPORT_DECIMAL_SPECIFIERS) || defined(PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS)

// Stores a fixed-precision representation of a double relative
// to a fixed precision (which cannot be determined by examining this structure)
struct double_components {
  int_fast64_t integral;
  int_fast64_t fractional;
    // ... truncation of the actual fractional part of the double value, scaled
    // by the precision value
  bool is_negative;
};

#define NUM_DECIMAL_DIGITS_IN_INT64_T 18
#define PRINTF_MAX_PRECOMPUTED_POWER_OF_10  NUM_DECIMAL_DIGITS_IN_INT64_T
static const double powers_of_10[NUM_DECIMAL_DIGITS_IN_INT64_T] = {
  1e00, 1e01, 1e02, 1e03, 1e04, 1e05, 1e06, 1e07, 1e08,
  1e09, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17
};

#define PRINTF_MAX_SUPPORTED_PRECISION NUM_DECIMAL_DIGITS_IN_INT64_T - 1


// Break up a double number - which is known to be a finite non-negative number -
// into its base-10 parts: integral - before the decimal point, and fractional - after it.
// Taken the precision into account, but does not change it even internally.
static struct double_components get_components(double number, printf_size_t precision)
{
  struct double_components number_;
  number_.is_negative = get_sign_bit(number);
  double abs_number = (number_.is_negative) ? -number : number;
  number_.integral = (int_fast64_t)abs_number;
  double remainder = (abs_number - (double) number_.integral) * powers_of_10[precision];
  number_.fractional = (int_fast64_t)remainder;

  remainder -= (double) number_.fractional;

  if (remainder > 0.5) {
    ++number_.fractional;
    // handle rollover, e.g. case 0.99 with precision 1 is 1.0
    if ((double) number_.fractional >= powers_of_10[precision]) {
      number_.fractional = 0;
      ++number_.integral;
    }
  }
  else if ((remainder == 0.5) && ((number_.fractional == 0U) || (number_.fractional & 1U))) {
    // if halfway, round up if odd OR if last digit is 0
    ++number_.fractional;
  }

  if (precision == 0U) {
    remainder = abs_number - (double) number_.integral;
    if ((!(remainder < 0.5) || (remainder > 0.5)) && (number_.integral & 1)) {
      // exactly 0.5 and ODD, then round up
      // 1.5 -> 2, but 2.5 -> 2
      ++number_.integral;
    }
  }
  return number_;
}

#ifdef PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS
struct scaling_factor {
  double raw_factor;
  bool multiply; // if true, need to multiply by raw_factor; otherwise need to divide by it
};

static double apply_scaling(double num, struct scaling_factor normalization)
{
  return normalization.multiply ? num * normalization.raw_factor : num / normalization.raw_factor;
}

static double unapply_scaling(double normalized, struct scaling_factor normalization)
{
#if defined(__GNUC__) && !defined(__ARMCC_VERSION) /* GCC */
// accounting for a static analysis bug in GCC 6.x and earlier
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmaybe-uninitialized"
#endif
  return normalization.multiply ? normalized / normalization.raw_factor : normalized * normalization.raw_factor;
#if defined(__GNUC__) && !defined(__ARMCC_VERSION) /* GCC */
#pragma GCC diagnostic pop
#endif
}

static struct scaling_factor update_normalization(struct scaling_factor sf, double extra_multiplicative_factor)
{
  struct scaling_factor result;
  if (sf.multiply) {
    result.multiply = true;
    result.raw_factor = sf.raw_factor * extra_multiplicative_factor;
  }
  else {
    int factor_exp2 = get_exp2(get_bit_access(sf.raw_factor));
    int extra_factor_exp2 = get_exp2(get_bit_access(extra_multiplicative_factor));

    // Divide the larger-exponent raw raw_factor by the smaller
    if (PRINTF_ABS(factor_exp2) > PRINTF_ABS(extra_factor_exp2)) {
      result.multiply = false;
      result.raw_factor = sf.raw_factor / extra_multiplicative_factor;
    }
    else {
      result.multiply = true;
      result.raw_factor = extra_multiplicative_factor / sf.raw_factor;
    }
  }
  return result;
}

static struct double_components get_normalized_components(bool negative, printf_size_t precision, double non_normalized, struct scaling_factor normalization, int floored_exp10)
{
  struct double_components components;
  components.is_negative = negative;
  double scaled = apply_scaling(non_normalized, normalization);

  bool close_to_representation_extremum = ( (-floored_exp10 + (int) precision) >= DBL_MAX_10_EXP - 1 );
  if (close_to_representation_extremum) {
    // We can't have a normalization factor which also accounts for the precision, i.e. moves
    // some decimal digits into the mantissa, since it's unrepresentable, or nearly unrepresentable.
    // So, we'll give up early on getting extra precision...
    return get_components(negative ? -scaled : scaled, precision);
  }
  components.integral = (int_fast64_t) scaled;
  double remainder = non_normalized - unapply_scaling((double) components.integral, normalization);
  double prec_power_of_10 = powers_of_10[precision];
  struct scaling_factor account_for_precision = update_normalization(normalization, prec_power_of_10);
  double scaled_remainder = apply_scaling(remainder, account_for_precision);
  double rounding_threshold = 0.5;

  components.fractional = (int_fast64_t) scaled_remainder; // when precision == 0, the assigned value should be 0
  scaled_remainder -= (double) components.fractional; //when precision == 0, this will not change scaled_remainder

  components.fractional += (scaled_remainder >= rounding_threshold);
  if (scaled_remainder == rounding_threshold) {
    // banker's rounding: Round towards the even number (making the mean error 0)
    components.fractional &= ~((int_fast64_t) 0x1);
  }
  // handle rollover, e.g. the case of 0.99 with precision 1 becoming (0,100),
  // and must then be corrected into (1, 0).
  // Note: for precision = 0, this will "translate" the rounding effect from
  // the fractional part to the integral part where it should actually be
  // felt (as prec_power_of_10 is 1)
  if ((double) components.fractional >= prec_power_of_10) {
    components.fractional = 0;
    ++components.integral;
  }
  return components;
}
#endif // PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS

static void print_broken_up_decimal(
  struct double_components number_, output_gadget_t* output, printf_size_t precision,
  printf_size_t width, printf_flags_t flags, char *buf, printf_size_t len)
{
  if (precision != 0U) {
    // do fractional part, as an unsigned number

    printf_size_t count = precision;

    // %g/%G mandates we skip the trailing 0 digits...
    if ((flags & FLAGS_ADAPT_EXP) && !(flags & FLAGS_HASH) && (number_.fractional > 0)) {
      while(true) {
        int_fast64_t digit = number_.fractional % 10U;
        if (digit != 0) {
          break;
        }
        --count;
        number_.fractional /= 10U;

      }
      // ... and even the decimal point if there are no
      // non-zero fractional part digits (see below)
    }

    if (number_.fractional > 0 || !(flags & FLAGS_ADAPT_EXP) || (flags & FLAGS_HASH) ) {
      while (len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE) {
        --count;
        buf[len++] = (char)('0' + number_.fractional % 10U);
        if (!(number_.fractional /= 10U)) {
          break;
        }
      }
      // add extra 0s
      while ((len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE) && (count > 0U)) {
        buf[len++] = '0';
        --count;
      }
      if (len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE) {
        buf[len++] = '.';
      }
    }
  }
  else {
    if ((flags & FLAGS_HASH) && (len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE)) {
      buf[len++] = '.';
    }
  }

  // Write the integer part of the number (it comes after the fractional
  // since the character order is reversed)
  while (len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE) {
    buf[len++] = (char)('0' + (number_.integral % 10));
    if (!(number_.integral /= 10)) {
      break;
    }
  }

  // pad leading zeros
  if (!(flags & FLAGS_LEFT) && (flags & FLAGS_ZEROPAD)) {
    if (width && (number_.is_negative || (flags & (FLAGS_PLUS | FLAGS_SPACE)))) {
      width--;
    }
    while ((len < width) && (len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE)) {
      buf[len++] = '0';
    }
  }

  if (len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE) {
    if (number_.is_negative) {
      buf[len++] = '-';
    }
    else if (flags & FLAGS_PLUS) {
      buf[len++] = '+';  // ignore the space if the '+' exists
    }
    else if (flags & FLAGS_SPACE) {
      buf[len++] = ' ';
    }
  }

  out_rev_(output, buf, len, width, flags);
}

      // internal ftoa for fixed decimal floating point
static void print_decimal_number(output_gadget_t* output, double number, printf_size_t precision, printf_size_t width, printf_flags_t flags, char* buf, printf_size_t len)
{
  struct double_components value_ = get_components(number, precision);
  print_broken_up_decimal(value_, output, precision, width, flags, buf, len);
}

#ifdef PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS

// A floor function - but one which only works for numbers whose
// floor value is representable by an int.
static int bastardized_floor(double x)
{
  if (x >= 0) { return (int) x; }
  int n = (int) x;
  return ( ((double) n) == x ) ? n : n-1;
}

// Computes the base-10 logarithm of the input number - which must be an actual
// positive number (not infinity or NaN, nor a sub-normal)
static double log10_of_positive(double positive_number)
{
  // The implementation follows David Gay (https://www.ampl.com/netlib/fp/dtoa.c).
  //
  // Since log_10 ( M * 2^x ) = log_10(M) + x , we can separate the components of
  // our input number, and need only solve log_10(M) for M between 1 and 2 (as
  // the base-2 mantissa is always 1-point-something). In that limited range, a
  // Taylor series expansion of log10(x) should serve us well enough; and we'll
  // take the mid-point, 1.5, as the point of expansion.

  double_with_bit_access dwba = get_bit_access(positive_number);
  // based on the algorithm by David Gay (https://www.ampl.com/netlib/fp/dtoa.c)
  int exp2 = get_exp2(dwba);
  // drop the exponent, so dwba.F comes into the range [1,2)
  dwba.U = (dwba.U & (((double_uint_t) (1) << DOUBLE_STORED_MANTISSA_BITS) - 1U)) |
           ((double_uint_t) DOUBLE_BASE_EXPONENT << DOUBLE_STORED_MANTISSA_BITS);
  double z = (dwba.F - 1.5);
  return (
    // Taylor expansion around 1.5:
    0.1760912590556812420           // Expansion term 0: ln(1.5)            / ln(10)
    + z     * 0.2895296546021678851 // Expansion term 1: (M - 1.5)   * 2/3  / ln(10)
#if PKG_VSNPRINTF_LOG10_TAYLOR_TERMS > 2
    - z*z   * 0.0965098848673892950 // Expansion term 2: (M - 1.5)^2 * 2/9  / ln(10)
#if PKG_VSNPRINTF_LOG10_TAYLOR_TERMS > 3
    + z*z*z * 0.0428932821632841311 // Expansion term 2: (M - 1.5)^3 * 8/81 / ln(10)
#endif
#endif
    // exact log_2 of the exponent x, with logarithm base change
    + exp2 * 0.30102999566398119521 // = exp2 * log_10(2) = exp2 * ln(2)/ln(10)
  );
}


static double pow10_of_int(int floored_exp10)
{
  // A crude hack for avoiding undesired behavior with barely-normal or slightly-subnormal values.
  if (floored_exp10 == DOUBLE_MAX_SUBNORMAL_EXPONENT_OF_10) {
    return DOUBLE_MAX_SUBNORMAL_POWER_OF_10;
  }
  // Compute 10^(floored_exp10) but (try to) make sure that doesn't overflow
  double_with_bit_access dwba;
  int exp2 = bastardized_floor(floored_exp10 * 3.321928094887362 + 0.5);
  const double z  = floored_exp10 * 2.302585092994046 - exp2 * 0.6931471805599453;
  const double z2 = z * z;
  dwba.U = ((double_uint_t)(exp2) + DOUBLE_BASE_EXPONENT) << DOUBLE_STORED_MANTISSA_BITS;
  // compute exp(z) using continued fractions,
  // see https://en.wikipedia.org/wiki/Exponential_function#Continued_fractions_for_ex
  dwba.F *= 1 + 2 * z / (2 - z + (z2 / (6 + (z2 / (10 + z2 / 14)))));
  return dwba.F;
}

static void print_exponential_number(output_gadget_t* output, double number, printf_size_t precision, printf_size_t width, printf_flags_t flags, char* buf, printf_size_t len)
{
  const bool negative = get_sign_bit(number);
  // This number will decrease gradually (by factors of 10) as we "extract" the exponent out of it
  double abs_number =  negative ? -number : number;

  int floored_exp10;
  bool abs_exp10_covered_by_powers_table;
  struct scaling_factor normalization;


  // Determine the decimal exponent
  if (abs_number == 0.0) {
    // TODO: This is a special-case for 0.0 (and -0.0); but proper handling is required for denormals more generally.
    floored_exp10 = 0; // ... and no need to set a normalization factor or check the powers table
  }
  else  {
    double exp10 = log10_of_positive(abs_number);
    floored_exp10 = bastardized_floor(exp10);
    double p10 = pow10_of_int(floored_exp10);
    // correct for rounding errors
    if (abs_number < p10) {
      floored_exp10--;
      p10 /= 10;
    }
    abs_exp10_covered_by_powers_table = PRINTF_ABS(floored_exp10) < PRINTF_MAX_PRECOMPUTED_POWER_OF_10;
    normalization.raw_factor = abs_exp10_covered_by_powers_table ? powers_of_10[PRINTF_ABS(floored_exp10)] : p10;
  }

  // We now begin accounting for the widths of the two parts of our printed field:
  // the decimal part after decimal exponent extraction, and the base-10 exponent part.
  // For both of these, the value of 0 has a special meaning, but not the same one:
  // a 0 exponent-part width means "don't print the exponent"; a 0 decimal-part width
  // means "use as many characters as necessary".

  bool fall_back_to_decimal_only_mode = false;
  if (flags & FLAGS_ADAPT_EXP) {
    int required_significant_digits = (precision == 0) ? 1 : (int) precision;
    // Should we want to fall-back to "%f" mode, and only print the decimal part?
    fall_back_to_decimal_only_mode = (floored_exp10 >= -4 && floored_exp10 < required_significant_digits);
    // Now, let's adjust the precision
    // This also decided how we adjust the precision value - as in "%g" mode,
    // "precision" is the number of _significant digits_, and this is when we "translate"
    // the precision value to an actual number of decimal digits.
    int precision_ = fall_back_to_decimal_only_mode ?
                     (int) precision - 1 - floored_exp10 :
        (int) precision - 1; // the presence of the exponent ensures only one significant digit comes before the decimal point
    precision = (precision_ > 0 ? (unsigned) precision_ : 0U);
    flags |= FLAGS_PRECISION;   // make sure print_broken_up_decimal respects our choice above
  }

  normalization.multiply = (floored_exp10 < 0 && abs_exp10_covered_by_powers_table);
  bool should_skip_normalization = (fall_back_to_decimal_only_mode || floored_exp10 == 0);
  struct double_components decimal_part_components =
    should_skip_normalization ?
    get_components(negative ? -abs_number : abs_number, precision) :
    get_normalized_components(negative, precision, abs_number, normalization, floored_exp10);

  // Account for roll-over, e.g. rounding from 9.99 to 100.0 - which effects
  // the exponent and may require additional tweaking of the parts
  if (fall_back_to_decimal_only_mode) {
    if ((flags & FLAGS_ADAPT_EXP) && floored_exp10 >= -1 && decimal_part_components.integral == powers_of_10[floored_exp10 + 1]) {
      floored_exp10++; // Not strictly necessary, since floored_exp10 is no longer really used
      precision--;
      // ... and it should already be the case that decimal_part_components.fractional == 0
    }
    // TODO: What about rollover strictly within the fractional part?
  }
  else {
    if (decimal_part_components.integral >= 10) {
      floored_exp10++;
      decimal_part_components.integral = 1;
      decimal_part_components.fractional = 0;
    }
  }

  // the floored_exp10 format is "E%+03d" and largest possible floored_exp10 value for a 64-bit double
  // is "307" (for 2^1023), so we set aside 4-5 characters overall
  printf_size_t exp10_part_width = fall_back_to_decimal_only_mode ? 0U : (PRINTF_ABS(floored_exp10) < 100) ? 4U : 5U;

  printf_size_t decimal_part_width =
    ((flags & FLAGS_LEFT) && exp10_part_width) ?
      // We're padding on the right, so the width constraint is the exponent part's
      // problem, not the decimal part's, so we'll use as many characters as we need:
      0U :
      // We're padding on the left; so the width constraint is the decimal part's
      // problem. Well, can both the decimal part and the exponent part fit within our overall width?
      ((width > exp10_part_width) ?
        // Yes, so we limit our decimal part's width.
        // (Note this is trivially valid even if we've fallen back to "%f" mode)
        width - exp10_part_width :
        // No; we just give up on any restriction on the decimal part and use as many
        // characters as we need
        0U);

  const printf_size_t printed_exponential_start_pos = output->pos;
  print_broken_up_decimal(decimal_part_components, output, precision, decimal_part_width, flags, buf, len);

  if (! fall_back_to_decimal_only_mode) {
    putchar_via_gadget(output, (flags & FLAGS_UPPERCASE) ? 'E' : 'e');
    print_integer(output,
                  ABS_FOR_PRINTING(floored_exp10),
                  floored_exp10 < 0, 10, 0, exp10_part_width - 1,
                FLAGS_ZEROPAD | FLAGS_PLUS);
    if (flags & FLAGS_LEFT) {
      // We need to right-pad with spaces to meet the width requirement
      while (output->pos - printed_exponential_start_pos < width) {
        putchar_via_gadget(output, ' ');
      }
    }
  }
}
#endif  // PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS

static void print_floating_point(output_gadget_t* output, double value, printf_size_t precision, printf_size_t width, printf_flags_t flags, bool prefer_exponential)
{
  char buf[PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE];
  printf_size_t len = 0U;

  // test for special values
  if (value != value) {
    out_rev_(output, "nan", 3, width, flags);
    return;
  }
  if (value < -DBL_MAX) {
    out_rev_(output, "fni-", 4, width, flags);
    return;
  }
  if (value > DBL_MAX) {
    out_rev_(output, (flags & FLAGS_PLUS) ? "fni+" : "fni", (flags & FLAGS_PLUS) ? 4U : 3U, width, flags);
    return;
  }

  if (!prefer_exponential &&
      ((value > PRINTF_FLOAT_NOTATION_THRESHOLD) || (value < -PRINTF_FLOAT_NOTATION_THRESHOLD))) {
    // The required behavior of standard printf is to print _every_ integral-part digit -- which could mean
    // printing hundreds of characters, overflowing any fixed internal buffer and necessitating a more complicated
    // implementation.
#ifdef PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS
    print_exponential_number(output, value, precision, width, flags, buf, len);
#endif
    return;
  }

  // set default precision, if not set explicitly
  if (!(flags & FLAGS_PRECISION)) {
    precision = PKG_VSNPRINTF_DEFAULT_FLOAT_PRECISION;
  }

  // limit precision so that our integer holding the fractional part does not overflow
  while ((len < PKG_VSNPRINTF_DECIMAL_BUFFER_SIZE) && (precision > PRINTF_MAX_SUPPORTED_PRECISION)) {
    buf[len++] = '0'; // This respects the precision in terms of result length only
    precision--;
  }

#ifdef PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS
  if (prefer_exponential)
    print_exponential_number(output, value, precision, width, flags, buf, len);
  else
#endif
    print_decimal_number(output, value, precision, width, flags, buf, len);
}

#endif  // (PKG_VSNPRINTF_SUPPORT_DECIMAL_SPECIFIERS || PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS)

// Advances the format pointer past the flags, and returns the parsed flags
// due to the characters passed
static printf_flags_t parse_flags(const char** format)
{
  printf_flags_t flags = 0U;
  do {
    switch (**format) {
      case '0': flags |= FLAGS_ZEROPAD; (*format)++; break;
      case '-': flags |= FLAGS_LEFT;    (*format)++; break;
      case '+': flags |= FLAGS_PLUS;    (*format)++; break;
      case ' ': flags |= FLAGS_SPACE;   (*format)++; break;
      case '#': flags |= FLAGS_HASH;    (*format)++; break;
      default : return flags;
    }
  } while (true);
}

static inline void format_string_loop(output_gadget_t* output, const char* format, va_list args)
{
#ifdef PKG_VSNPRINTF_CHECK_FOR_NUL_IN_FORMAT_SPECIFIER
#define ADVANCE_IN_FORMAT_STRING(cptr_) do { (cptr_)++; if (!*(cptr_)) return; } while(0)
#else
#define ADVANCE_IN_FORMAT_STRING(cptr_) (cptr_)++
#endif


  while (*format)
  {
    if (*format != '%') {
      // A regular content character
      putchar_via_gadget(output, *format);
      format++;
      continue;
    }
    // We're parsing a format specifier: %[flags][width][.precision][length]
    ADVANCE_IN_FORMAT_STRING(format);

    printf_flags_t flags = parse_flags(&format);

    // evaluate width field
    printf_size_t width = 0U;
    if (is_digit_(*format)) {
      width = (printf_size_t) atou_(&format);
    }
    else if (*format == '*') {
      const int w = va_arg(args, int);
      if (w < 0) {
        flags |= FLAGS_LEFT;    // reverse padding
        width = (printf_size_t)-w;
      }
      else {
        width = (printf_size_t)w;
      }
      ADVANCE_IN_FORMAT_STRING(format);
    }

    // evaluate precision field
    printf_size_t precision = 0U;
    if (*format == '.') {
      flags |= FLAGS_PRECISION;
      ADVANCE_IN_FORMAT_STRING(format);
      if (is_digit_(*format)) {
        precision = (printf_size_t) atou_(&format);
      }
      else if (*format == '*') {
        const int precision_ = va_arg(args, int);
        precision = precision_ > 0 ? (printf_size_t) precision_ : 0U;
        ADVANCE_IN_FORMAT_STRING(format);
      }
    }

    // evaluate length field
    switch (*format) {
#ifdef PKG_VSNPRINTF_SUPPORT_MSVC_STYLE_INTEGER_SPECIFIERS
      case 'I' : {
        ADVANCE_IN_FORMAT_STRING(format);
        // Greedily parse for size in bits: 8, 16, 32 or 64
        switch(*format) {
          case '8':               flags |= FLAGS_INT8;
            ADVANCE_IN_FORMAT_STRING(format);
            break;
          case '1':
            ADVANCE_IN_FORMAT_STRING(format);
          if (*format == '6') { format++; flags |= FLAGS_INT16; }
            break;
          case '3':
            ADVANCE_IN_FORMAT_STRING(format);
            if (*format == '2') { ADVANCE_IN_FORMAT_STRING(format); flags |= FLAGS_INT32; }
            break;
          case '6':
            ADVANCE_IN_FORMAT_STRING(format);
            if (*format == '4') { ADVANCE_IN_FORMAT_STRING(format); flags |= FLAGS_INT64; }
            break;
          default: break;
        }
        break;
      }
#endif
      case 'l' :
        flags |= FLAGS_LONG;
        ADVANCE_IN_FORMAT_STRING(format);
        if (*format == 'l') {
          flags |= FLAGS_LONG_LONG;
          ADVANCE_IN_FORMAT_STRING(format);
        }
        break;
      case 'h' :
        flags |= FLAGS_SHORT;
        ADVANCE_IN_FORMAT_STRING(format);
        if (*format == 'h') {
          flags |= FLAGS_CHAR;
          ADVANCE_IN_FORMAT_STRING(format);
        }
        break;
      case 't' :
        flags |= (sizeof(ptrdiff_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
        ADVANCE_IN_FORMAT_STRING(format);
        break;
      case 'j' :
        flags |= (sizeof(intmax_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
        ADVANCE_IN_FORMAT_STRING(format);
        break;
      case 'z' :
        flags |= (sizeof(size_t) == sizeof(long) ? FLAGS_LONG : FLAGS_LONG_LONG);
        ADVANCE_IN_FORMAT_STRING(format);
        break;
      default:
        break;
    }

    // evaluate specifier
    switch (*format) {
      case 'd' :
      case 'i' :
      case 'u' :
      case 'x' :
      case 'X' :
      case 'o' :
      case 'b' : {

        if (*format == 'd' || *format == 'i') {
          flags |= FLAGS_SIGNED;
        }

        numeric_base_t base;
        if (*format == 'x' || *format == 'X') {
          base = BASE_HEX;
        }
        else if (*format == 'o') {
          base =  BASE_OCTAL;
        }
        else if (*format == 'b') {
          base =  BASE_BINARY;
        }
        else {
          base = BASE_DECIMAL;
          flags &= ~FLAGS_HASH; // decimal integers have no alternative presentation
        }

        if (*format == 'X') {
          flags |= FLAGS_UPPERCASE;
        }

        format++;
        // ignore '0' flag when precision is given
        if (flags & FLAGS_PRECISION) {
          flags &= ~FLAGS_ZEROPAD;
        }

        if (flags & FLAGS_SIGNED) {
          // A signed specifier: d, i or possibly I + bit size if enabled

          if (flags & FLAGS_LONG_LONG) {
#ifdef PKG_VSNPRINTF_SUPPORT_LONG_LONG
            const long long value = va_arg(args, long long);
            print_integer(output, ABS_FOR_PRINTING(value), value < 0, base, precision, width, flags);
#endif
          }
          else if (flags & FLAGS_LONG) {
            const long value = va_arg(args, long);
            print_integer(output, ABS_FOR_PRINTING(value), value < 0, base, precision, width, flags);
          }
          else {
            // We never try to interpret the argument as something potentially-smaller than int,
            // due to integer promotion rules: Even if the user passed a short int, short unsigned
            // etc. - these will come in after promotion, as int's (or unsigned for the case of
            // short unsigned when it has the same size as int)
            const int value =
              (flags & FLAGS_CHAR) ? (signed char) va_arg(args, int) :
              (flags & FLAGS_SHORT) ? (short int) va_arg(args, int) :
              va_arg(args, int);
            print_integer(output, ABS_FOR_PRINTING(value), value < 0, base, precision, width, flags);
          }
        }
        else {
          // An unsigned specifier: u, x, X, o, b

          flags &= ~(FLAGS_PLUS | FLAGS_SPACE);

          if (flags & FLAGS_LONG_LONG) {
#ifdef PKG_VSNPRINTF_SUPPORT_LONG_LONG
            print_integer(output, (printf_unsigned_value_t) va_arg(args, unsigned long long), false, base, precision, width, flags);
#endif
          }
          else if (flags & FLAGS_LONG) {
            print_integer(output, (printf_unsigned_value_t) va_arg(args, unsigned long), false, base, precision, width, flags);
          }
          else {
            const unsigned int value =
              (flags & FLAGS_CHAR) ? (unsigned char)va_arg(args, unsigned int) :
              (flags & FLAGS_SHORT) ? (unsigned short int)va_arg(args, unsigned int) :
              va_arg(args, unsigned int);
            print_integer(output, (printf_unsigned_value_t) value, false, base, precision, width, flags);
          }
        }
        break;
      }
#ifdef PKG_VSNPRINTF_SUPPORT_DECIMAL_SPECIFIERS
      case 'f' :
      case 'F' :
        if (*format == 'F') flags |= FLAGS_UPPERCASE;
        print_floating_point(output, va_arg(args, double), precision, width, flags, PRINTF_PREFER_DECIMAL);
        format++;
        break;
#endif
#ifdef PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS
      case 'e':
      case 'E':
      case 'g':
      case 'G':
        if ((*format == 'g')||(*format == 'G')) flags |= FLAGS_ADAPT_EXP;
        if ((*format == 'E')||(*format == 'G')) flags |= FLAGS_UPPERCASE;
        print_floating_point(output, va_arg(args, double), precision, width, flags, PRINTF_PREFER_EXPONENTIAL);
        format++;
        break;
#endif  // PKG_VSNPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS
      case 'c' : {
        printf_size_t l = 1U;
        // pre padding
        if (!(flags & FLAGS_LEFT)) {
          while (l++ < width) {
            putchar_via_gadget(output, ' ');
          }
        }
        // char output
        putchar_via_gadget(output, (char) va_arg(args, int) );
        // post padding
        if (flags & FLAGS_LEFT) {
          while (l++ < width) {
            putchar_via_gadget(output, ' ');
          }
        }
        format++;
        break;
      }

      case 's' : {
        const char* p = va_arg(args, char*);
        if (p == NULL) {
          out_rev_(output, ")llun(", 6, width, flags);
        }
        else {
          printf_size_t l = strnlen_s_(p, precision ? precision : PRINTF_MAX_POSSIBLE_BUFFER_SIZE);
          // pre padding
          if (flags & FLAGS_PRECISION) {
            l = (l < precision ? l : precision);
          }
          if (!(flags & FLAGS_LEFT)) {
            while (l++ < width) {
              putchar_via_gadget(output, ' ');
            }
          }
          // string output
          while ((*p != 0) && (!(flags & FLAGS_PRECISION) || precision)) {
            putchar_via_gadget(output, *(p++));
            --precision;
          }
          // post padding
          if (flags & FLAGS_LEFT) {
            while (l++ < width) {
              putchar_via_gadget(output, ' ');
            }
          }
        }
        format++;
        break;
      }

      case 'p' : {
        width = sizeof(void*) * 2U + 2; // 2 hex chars per byte + the "0x" prefix
        flags |= FLAGS_ZEROPAD | FLAGS_POINTER;
        uintptr_t value = (uintptr_t)va_arg(args, void*);
        (value == (uintptr_t) NULL) ?
          out_rev_(output, ")lin(", 5, width, flags) :
          print_integer(output, (printf_unsigned_value_t) value, false, BASE_HEX, precision, width, flags);
        format++;
        break;
      }

      case '%' :
        putchar_via_gadget(output, '%');
        format++;
        break;

      // Many people prefer to disable support for %n, as it lets the caller
      // engineer a write to an arbitrary location, of a value the caller
      // effectively controls - which could be a security concern in some cases.
#ifdef PKG_VSNPRINTF_SUPPORT_WRITEBACK_SPECIFIER
      case 'n' : {
        if       (flags & FLAGS_CHAR)      *(va_arg(args, char*))      = (char) output->pos;
        else if  (flags & FLAGS_SHORT)     *(va_arg(args, short*))     = (short) output->pos;
        else if  (flags & FLAGS_LONG)      *(va_arg(args, long*))      = (long) output->pos;
#ifdef PKG_VSNPRINTF_SUPPORT_LONG_LONG
        else if  (flags & FLAGS_LONG_LONG) *(va_arg(args, long long*)) = (long long int) output->pos;
#endif // PKG_VSNPRINTF_SUPPORT_LONG_LONG
        else                               *(va_arg(args, int*))       = (int) output->pos;
        format++;
        break;
      }
#endif // PKG_VSNPRINTF_SUPPORT_WRITEBACK_SPECIFIER

      default :
        putchar_via_gadget(output, *format);
        format++;
        break;
    }
  }
}

// internal vsnprintf - used for implementing _all library functions
static int vsnprintf_impl(output_gadget_t* output, const char* format, va_list args)
{
  // Note: The library only calls vsnprintf_impl() with output->pos being 0. However, it is
  // possible to call this function with a non-zero pos value for some "remedial printing".
  format_string_loop(output, format, args);

  // termination
  append_termination_with_gadget(output);

  // return written chars without terminating \0
  return (int)output->pos;
}

///////////////////////////////////////////////////////////////////////////////

/**
 * This function will fill a formatted string to buffer.
 *
 * @param  buf is the buffer to save formatted string.
 *
 * @param  size is the size of buffer.
 *
 * @param  fmt is the format parameters.
 *
 * @param  args is a list of variable parameters.
 *
 * @return The number of characters actually written to buffer.
 */
#if (RTTHREAD_VERSION >= 40100) || (RTTHREAD_VERSION < 40000 && RTTHREAD_VERSION >= 30106)
int rt_vsnprintf(char *buf, rt_size_t size, const char *fmt, va_list args)
#else
rt_int32_t rt_vsnprintf(char *buf, rt_size_t size, const char *fmt, va_list args)
#endif
{
  output_gadget_t gadget = buffer_gadget(buf, size);
  return vsnprintf_impl(&gadget, fmt, args);
}

#ifdef RT_VSNPRINTF_FULL_REPLACING_VSNPRINTF
int vsnprintf(char * s, size_t n, const char * format, va_list arg)
{
  return rt_vsnprintf(s, n, format, arg);
}
#endif

#ifdef RT_VSNPRINTF_FULL_REPLACING_VSPRINTF
int vsprintf(char * s, const char * format, va_list arg)
{
  return rt_vsprintf(s, format, arg);
}
#endif