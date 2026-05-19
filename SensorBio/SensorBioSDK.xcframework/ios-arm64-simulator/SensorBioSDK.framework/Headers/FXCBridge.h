/*
 * FXCBridge.h — SPM C-module umbrella for Philips' LibFXC C headers.
 *
 * fx_datatypes.h `#error`s without one of FX_PLATFORM_{WIN, UNIX, ARM_M3,
 * ARM_M4, MSP430} defined. Define UNIX (the iOS-correct variant) BEFORE
 * including the rest so consumers don't need to set a preprocessor flag.
 *
 * Pre-6.10i the app's bridging header `#import "fxc.h"`d these directly,
 * with FX_PLATFORM_UNIX coming in via the LibFXC.xcframework umbrella
 * header's `#define`. This umbrella replays that setup for SPM consumers.
 */

#ifndef FXCBridge_h
#define FXCBridge_h

#define FX_PLATFORM_UNIX

#include "fx_datatypes.h"
#include "fxc.h"

#endif /* FXCBridge_h */
