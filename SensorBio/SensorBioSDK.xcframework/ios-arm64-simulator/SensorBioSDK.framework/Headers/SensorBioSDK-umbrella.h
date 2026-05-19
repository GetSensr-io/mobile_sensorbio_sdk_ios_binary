#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "active_minutes.h"
#import "amidefs.h"
#import "amiigo_alg.h"
#import "amiigo_common.h"
#import "amiigo_engine.h"
#import "amiigo_utils.h"
#import "ans.h"
#import "bbi_preprocessing.h"
#import "BioedgeAPI.h"
#import "bioedge_api.h"
#import "bioedge_math.h"
#import "circular_buffer.h"
#import "common.h"
#import "filters.h"
#import "hrv_frequencyDomain.h"
#import "hrv_nonlinear.h"
#import "hrv_timeDomain.h"
#import "hrv_timeDomainGeometric.h"
#import "fxc.h"
#import "FXCBridge.h"
#import "fx_datatypes.h"

FOUNDATION_EXPORT double SensorBioSDKVersionNumber;
FOUNDATION_EXPORT const unsigned char SensorBioSDKVersionString[];

