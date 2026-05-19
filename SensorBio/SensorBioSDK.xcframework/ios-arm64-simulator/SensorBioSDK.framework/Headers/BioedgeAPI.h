/*
 * BioedgeAPI.h — umbrella header for the BioedgeAPI C module.
 *
 * SPM auto-generates a modulemap from `publicHeadersPath: "include"`, so this
 * file isn't needed for source-form consumption. The wrapper SensorBioSDK.xcodeproj
 * (Phase 6.15b) needs an explicit umbrella for DEFINES_MODULE=YES framework-style
 * modulemap auto-generation. Append new public headers here when they're added.
 */

#ifndef BioedgeAPI_h
#define BioedgeAPI_h

#include "active_minutes.h"
#include "amidefs.h"
#include "amiigo_alg.h"
#include "amiigo_common.h"
#include "amiigo_engine.h"
#include "amiigo_utils.h"
#include "ans.h"
#include "bbi_preprocessing.h"
#include "bioedge_api.h"
#include "bioedge_math.h"
#include "circular_buffer.h"
#include "common.h"
#include "filters.h"
#include "hrv_frequencyDomain.h"
#include "hrv_nonlinear.h"
#include "hrv_timeDomain.h"
#include "hrv_timeDomainGeometric.h"

#endif /* BioedgeAPI_h */
