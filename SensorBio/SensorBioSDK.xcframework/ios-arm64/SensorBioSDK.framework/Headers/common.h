#ifndef COMMON_H
#define COMMON_H

#include <stdint.h>
#include <math.h>
#include <stdio.h> //#TODO REMOVE
#include <stdlib.h> //TODO REMOVE
#include <string.h>
#include <stdbool.h>

#ifdef X86
#define static_
#else
#define static_ static
#endif

// 120 bpm = 0.5s intervals
// Max 24 hours 24*60*60/0.5
#define BBI_MAX_ALLOC_SIZE		172800

#define BIOEDGE_ALG_MAJOR   (uint16_t)2
#define BIOEDGE_ALG_MINOR   (uint16_t)0
#define BIOEDGE_ALG_PATCH   (uint16_t)1

#ifdef PARTNER_ALTER
#define PARTNER_NUMBER	1
#define ACTIVE_MINUTES_ACTIVE
#endif

// Define the partner number as o
#ifndef PARTNER_NUMBER
#define PARTNER_NUMBER	0
#define HRV_DERIVED_METRICS_ACTIVE
#define ACTIVE_MINUTES_ACTIVE
#endif

// #include <android/log.h>

// #define  LOG_TAG    "wikus_debug"

// #define  LOGD(...)  __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
// #define  LOGE(...)  __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
// // If you want you can add other log definition for info, warning etc
#endif
