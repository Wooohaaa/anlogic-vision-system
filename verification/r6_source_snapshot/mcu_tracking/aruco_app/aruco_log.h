#ifndef UA_ARUCO_LOG_H
#define UA_ARUCO_LOG_H
#include <stdarg.h>
typedef void (*ua_log_sink)(void *context,char byte);
/* Integer-only diagnostics. Unsupported formats stop with an explicit error,
 * never read a double or continue with a desynchronized va_list. No heap.
 * Supports signed/unsigned decimal, hex, pointer, string, char, %% and integer
 * l/ll/z lengths, width/zero-pad/left alignment and string precision. */
int ua_log_vformat(ua_log_sink sink,void *context,const char *format,va_list args);
#endif
