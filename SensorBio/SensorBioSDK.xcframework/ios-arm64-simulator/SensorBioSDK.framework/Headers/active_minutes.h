#ifndef ACTIVE_MINUTES_H
#define ACTIVE_MINUTES_H

#include "common.h"
#include "bioedge_api.h"

void AM_initialise(activeMinutes_s *activeMinutesHandle);
void AM_addActivityPacket(activeMinutes_s *activeMinutesHandle, int32_t activityPacket, int64_t timestampMs, activity_minutes_bin_e *activeMinuteExercise, activity_minutes_bin_e *activeMinuteNoExercise);
#endif
