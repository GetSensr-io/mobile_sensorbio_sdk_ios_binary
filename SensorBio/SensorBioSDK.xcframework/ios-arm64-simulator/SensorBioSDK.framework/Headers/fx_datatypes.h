/**
* \addtogroup Philips WeST Software Library
* \{
*/

/**
*  \file    fx_datatypes.h
*  \author  Philips Intellectual Property & Standards, The Netherlands
*  \brief   WeST Sleep Library
*
*  \remarks (c) Copyright 2018 Koninklijke Philips N.V. All rights reserved.
*  This Software Library is provided to Biostrap USA, LLC. for use under and subject to the terms of the Evaluation License Agreement dated 22 May 2023.
*  Philips Sensing Platform, Philips and its logo are trademarks of Koninklijke Philips N.V..
*  All other names are the trademark or registered trademarks of their respective holders.
*/

/*============================================================================*/
/*  Multiple inclusion protection                                             */
/*============================================================================*/

#ifndef __FX_DATATYPES_H__
#define __FX_DATATYPES_H__

/*============================================================================*/
/*  C++ protection                                                            */
/*============================================================================*/

#ifdef __cplusplus
extern "C" {
#endif

/*============================================================================*/
/*  Include files                                                             */
/*============================================================================*/

/* System includes -----------------------------------------------------------*/
#include <stdlib.h>

#if defined( FX_PLATFORM_WIN32 )
    #define FX_INTF_EXPORT __declspec ( dllexport )
    #define FX_INTF_IMPORT __declspec ( dllimport )

#elif defined( FX_PLATFORM_UNIX )
  #define FX_INTF_EXPORT extern __attribute__ ((visibility ("default")))
  #define FX_INTF_IMPORT

#elif defined( FX_PLATFORM_ARM_M3 ) 
    #define FX_INTF_EXPORT extern
    #define FX_INTF_IMPORT 

#elif defined( FX_PLATFORM_ARM_M4 ) 
    #define FX_INTF_EXPORT extern
    #define FX_INTF_IMPORT 

#elif defined ( FX_PLATFORM_MSP430 )
    #define FX_INTF_EXPORT extern
    #define FX_INTF_IMPORT 

    /* MSP430 16-bit */
    #include "stdbool.h"
    #include "msp430.h"

#else
    /* Others */
    #error fx_datatypes.h: FX_PLATFORM_XXX constant not defined or not supported.

#endif

/* Project includes ----------------------------------------------------------*/

/* Module includes -----------------------------------------------------------*/

/*============================================================================*/
/*  Constant definitions                                                      */
/*============================================================================*/

/* Global constants ----------------------------------------------------------*/

#define FX_SINT08_MIN                         ( 0x80 )
#define FX_SINT08_MAX                         ( 0x7F )

#define FX_UINT08_MIN                         ( 0x00 )
#define FX_UINT08_MAX                         ( 0xFF )

#define FX_SINT16_MIN                         ( 0x8000 )
#define FX_SINT16_MAX                         ( 0x7FFF )

#define FX_UINT16_MIN                         ( 0x0000 )
#define FX_UINT16_MAX                         ( 0xFFFF )

#define FX_SINT32_MIN                         ( 0x80000000 )
#define FX_SINT32_MAX                         ( 0x7FFFFFFF )

#define FX_UINT32_MIN                         ( 0x00000000 )
#define FX_UINT32_MAX                         ( 0xFFFFFFFF )

#define FX_SINT64_MIN                         ( 0x8000000000000000 )
#define FX_SINT64_MAX                         ( 0x7FFFFFFFFFFFFFFF )

#define FX_UINT64_MIN                         ( 0x0000000000000000 )
#define FX_UINT64_MAX                         ( 0xFFFFFFFFFFFFFFFF )

/* Specific constants --------------------------------------------------------*/

#if defined ( FX_PLATFORM_WIN32 ) || defined ( FX_PLATFORM_ARM_M3  ) || defined ( FX_PLATFORM_ARM_M4  ) || defined ( FX_PLATFORM_UNIX )

    #define FX_TRUE                           ( 1 )
    #define FX_FALSE                          ( 0 )          

#elif defined ( FX_PLATFORM_MSP430 ) 

    /* MSP430 16-bit */

    #define FX_TRUE                           ( true )
    #define FX_FALSE                          ( false )

#endif

/*============================================================================*/
/*  Macro definitions                                                         */
/*============================================================================*/

/*============================================================================*/
/*  Type definitions                                                          */
/*============================================================================*/
typedef signed int              FX_SINT;       //  Native int (use in loops)

#if defined ( FX_PLATFORM_WIN32 ) 

    typedef void                FX_VOID;

    typedef unsigned char       FX_BOOL;       //  8-bit unsigned integer

    typedef char                FX_CHAR;       //  8-bit signed character

    typedef signed char         FX_SINT08;     //  8-bit signed integer
    typedef unsigned char       FX_UINT08;     //  8-bit unsigned integer

    typedef signed short        FX_SINT16;     // 16-bit signed integer
    typedef unsigned short      FX_UINT16;     // 16-bit unsigned integer

    typedef signed int          FX_SINT32;     // 32-bit signed integer
    typedef unsigned int        FX_UINT32;     // 32-bit unsigned integer

    typedef signed long long    FX_SINT64;     // 64-bit signed integer
    typedef unsigned long long  FX_UINT64;     // 64-bit unsigned integer

    typedef float               FX_FLOAT;      // 32-bit floating point

#elif defined ( FX_PLATFORM_ARM_M3 ) || defined ( FX_PLATFORM_ARM_M4 )

    typedef void                FX_VOID;

    typedef unsigned char       FX_BOOL;       //  8-bit unsigned integer

    typedef char                FX_CHAR;       //  8-bit signed character

    typedef signed char         FX_SINT08;     //  8-bit signed integer
    typedef unsigned char       FX_UINT08;     //  8-bit unsigned integer

    typedef signed short        FX_SINT16;     // 16-bit signed integer
    typedef unsigned short      FX_UINT16;     // 16-bit unsigned integer

    typedef signed int          FX_SINT32;     // 32-bit signed integer
    typedef unsigned int        FX_UINT32;     // 32-bit unsigned integer

    typedef signed long long    FX_SINT64;     // 64-bit signed integer
    typedef unsigned long long  FX_UINT64;     // 64-bit unsigned integer

    typedef float               FX_FLOAT;      // 32-bit floating point

#elif defined ( FX_PLATFORM_MSP430 ) 

    /* MSP430 16-bit */

    typedef void                FX_VOID;

    typedef bool                FX_BOOL;       //  8-bit

    typedef char                FX_CHAR;       //  8-bit unsigned character

    typedef signed char         FX_SINT08;     //  8-bit signed integer
    typedef unsigned char       FX_UINT08;     //  8-bit unsigned integer

    typedef signed int          FX_SINT16;     // 16-bit signed integer
    typedef unsigned int        FX_UINT16;     // 16-bit unsigned integer

    typedef signed long         FX_SINT32;     // 32-bit signed integer
    typedef unsigned long       FX_UINT32;     // 32-bit unsigned integer

    typedef signed long long    FX_SINT64;     // 64-bit signed integer
    typedef unsigned long long  FX_UINT64;     // 64-bit unsigned integer

    typedef float               FX_FLOAT;      // 32-bit floating point

#elif defined ( FX_PLATFORM_UNIX )

    typedef void                FX_VOID;

    typedef unsigned char       FX_BOOL;       //  8-bit unsigned integer

    typedef char                FX_CHAR;       //  8-bit signed character

    typedef signed char         FX_SINT08;     //  8-bit signed integer
    typedef unsigned char       FX_UINT08;     //  8-bit unsigned integer

    typedef signed short        FX_SINT16;     // 16-bit signed integer
    typedef unsigned short      FX_UINT16;     // 16-bit unsigned integer

    typedef signed int          FX_SINT32;     // 32-bit signed integer
    typedef unsigned int        FX_UINT32;     // 32-bit unsigned integer

    typedef signed long long    FX_SINT64;     // 64-bit signed integer
    typedef unsigned long long  FX_UINT64;     // 64-bit unsigned integer

    typedef float               FX_FLOAT;      // 32-bit floating point

#endif

/*============================================================================*/
/*  Error definitions                                                         */
/*============================================================================*/

    typedef FX_UINT16           FX_ERROR;

    #define FX_ERROR_NONE       ( (FX_ERROR) 0 )

/*============================================================================*/
/*  Extern data declarations                                                  */
/*============================================================================*/

/*============================================================================*/
/*  Extern function prototypes                                                */
/*============================================================================*/

/*============================================================================*/
/*  End of C++ protection                                                     */
/*============================================================================*/

#ifdef __cplusplus
}
#endif

/*============================================================================*/
/*  End of multiple inclusion protection                                      */
/*============================================================================*/

#endif

/**
* \}
* End of file.
*/
