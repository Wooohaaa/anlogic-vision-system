/*
 * FreeRTOS V202212.00
 * Copyright (C) 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * https://www.FreeRTOS.org
 * https://github.com/FreeRTOS
 *
 */

/* Standard includes. */
#include "string.h"
#include "stdio.h"

/* FreeRTOS includes. */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"

#include "al_log.h"

/* Example includes. */
#include "FreeRTOS_CLI.h"

/* Demo application includes. */
// #include "serial.h"

#ifndef configCOMMAND_INT_MAX_OUTPUT_SIZE
    #define configCOMMAND_INT_MAX_OUTPUT_SIZE 512
#endif

/* Dimensions the buffer into which input characters are placed. */
#define cmdMAX_INPUT_SIZE          50

/* Dimensions a buffer to be used by the UART driver, if the UART driver uses a
 * buffer at all. */
#define cmdQUEUE_LENGTH            25

/* DEL acts as a backspace. */
#define cmdASCII_DEL               ( 0x7F )

/* The maximum time to wait for the mutex that guards the UART to become
 * available. */
#define cmdMAX_MUTEX_WAIT          pdMS_TO_TICKS( 300 )

#ifndef configCLI_BAUD_RATE
    #define configCLI_BAUD_RATE    115200
#endif

/*-----------------------------------------------------------*/

/*
 * The task that implements the command console processing.
 */
static void prvUARTCommandConsoleTask( void * pvParameters );
void vUARTCommandConsoleStart( uint16_t usStackSize,
                               UBaseType_t uxPriority );
void vOutputString( const char * const pcMessage );

/*-----------------------------------------------------------*/

/* Const messages output by the command console. */
static const char * const pcWelcomeMessage = "FreeRTOS command server.\r\nType \"help\" to view a list of registered commands.\r\n\r\n>";
static const char * const pcEndOfOutputMessage = "\r\n[Press ENTER to execute the previous command again]\r\n\r\n>";
static const char * const pcNewLine = "\r\n";

/* Used to guard access to the UART in case messages are sent to the UART from
 * more than one task. */
static SemaphoreHandle_t xTxMutex = NULL;

/* The handle to the UART port, which is not used by all ports. */
// static xComPortHandle xPort = 0;

/*-----------------------------------------------------------*/

void vUARTCommandConsoleStart( uint16_t usStackSize,
                               UBaseType_t uxPriority )
{
    /* Create the semaphore used to access the UART Tx. */
    xTxMutex = xSemaphoreCreateMutex();
    configASSERT( xTxMutex );

    /* Create that task that handles the console itself. */
    xTaskCreate( prvUARTCommandConsoleTask, /* The task that implements the command console. */
                 "CLI",                     /* Text name assigned to the task.  This is just to assist debugging.  The kernel does not use this name itself. */
                 usStackSize,               /* The size of the stack allocated to the task. */
                 NULL,                      /* The parameter is not used, so NULL is passed. */
                 uxPriority,                /* The priority allocated to the task. */
                 NULL );                    /* A handle is not required, so just pass NULL. */
}
/*-----------------------------------------------------------*/

AL_S32 freertos_cli_Uart_init(void)
{
    /* Uart console use uart1, uart1 has been initialized during log initialization */
    return AL_OK;
}

AL_S32 freertos_cli_Write(const void* Data, AL_U32 Len)
{
    AlLog_Write(Data, Len);
    return AL_OK;
}

AL_S32 freertos_cli_Read(AL_U8 *Data, size_t Len)
{
    AL_S32 Ret = 0;

    Ret = AlLog_Recv(Data, Len);
    if( Ret != Len)
        return AL_ERROR;

    return AL_OK;
}


static void prvUARTCommandConsoleTask(void *pvParameters)
{
    AL_U8 cRxedChar;
    uint8_t ucInputIndex = 0;
    char *pcOutputString;
    static char cInputString[cmdMAX_INPUT_SIZE];
    static char cLastInputString[cmdMAX_INPUT_SIZE];
    BaseType_t xReturned;

    (void)pvParameters;

    // ========== INITIALIZATION SECTION ==========
    pcOutputString = FreeRTOS_CLIGetOutputBuffer();

    // Initialize UART hardware
    freertos_cli_Uart_init();

    // Display welcome message
    freertos_cli_Write(pcWelcomeMessage, strlen(pcWelcomeMessage));

    // State tracking for EOL sequences
    static AL_U8 cLastEOL = 0;

    for(;;)
    {
        // ========== CHARACTER INPUT SECTION ==========
        // Wait for a character from UART
        while (freertos_cli_Read(&cRxedChar, 1) != AL_OK);

        // Acquire UART mutex for safe output
        if(xSemaphoreTake(xTxMutex, cmdMAX_MUTEX_WAIT) != pdPASS) {
            continue; // Skip if mutex not available
        }

        // ========== CHARACTER PROCESSING SECTION ==========
        BaseType_t execute_command = pdFALSE;
        BaseType_t handle_backspace = pdFALSE;

        // Handle EOL characters (Enter key)
        if(cRxedChar == '\r' || cRxedChar == '\n') {
            // Execute command unless this is the second part of a sequence
            if(!( (cLastEOL == '\r' && cRxedChar == '\n') ||
                  (cLastEOL == '\n' && cRxedChar == '\r') )) {
                execute_command = pdTRUE;
            }
            cLastEOL = cRxedChar; // Track last EOL type
        } else {
            cLastEOL = 0; // Reset for non-EOL characters
        }

        // Handle backspace/delete key
        if(cRxedChar == '\b' || cRxedChar == cmdASCII_DEL) {
            if(ucInputIndex > 0) {
                ucInputIndex--;
                cInputString[ucInputIndex] = '\0';
                handle_backspace = pdTRUE;
            }
        }
        // Echo normal characters (not EOL or backspace)
        else if(cRxedChar != '\r' && cRxedChar != '\n') {
            freertos_cli_Write(&cRxedChar, 1);
        }

        // ========== COMMAND EXECUTION SECTION ==========
        if(execute_command) {
            // Add visual separator before command output
            freertos_cli_Write(pcNewLine, strlen(pcNewLine));

            // Use last command if input is empty
            if(ucInputIndex == 0) {
                strcpy(cInputString, cLastInputString);
            }

            // Process command and display output
            do {
                xReturned = FreeRTOS_CLIProcessCommand(
                    cInputString,
                    pcOutputString,
                    configCOMMAND_INT_MAX_OUTPUT_SIZE
                );
                freertos_cli_Write(pcOutputString, strlen(pcOutputString));
            } while(xReturned != pdFALSE);

            // Save and reset command state
            strcpy(cLastInputString, cInputString);
            ucInputIndex = 0;
            memset(cInputString, 0x00, cmdMAX_INPUT_SIZE);

            // Display command prompt
            freertos_cli_Write(pcEndOfOutputMessage, strlen(pcEndOfOutputMessage));
        }

        // ========== VISUAL FEEDBACK SECTION ==========
        // Handle backspace display
        if(handle_backspace) {
            const char backspaceSeq[] = "\b \b"; // Erase character visually
            freertos_cli_Write(backspaceSeq, strlen(backspaceSeq));
        }
        // Add printable characters to buffer
        else if(cRxedChar >= ' ' && cRxedChar <= '~' &&
                ucInputIndex < cmdMAX_INPUT_SIZE) {
            cInputString[ucInputIndex++] = cRxedChar;
        }

        // ========== CLEANUP SECTION ==========
        xSemaphoreGive(xTxMutex);
    }
}

/*-----------------------------------------------------------*/
void vOutputString( const char * const pcMessage )
{
    if( xSemaphoreTake( xTxMutex, cmdMAX_MUTEX_WAIT ) == pdPASS )
    {
        freertos_cli_Write(pcMessage, strlen( pcMessage ));
        xSemaphoreGive( xTxMutex );
    }
}
