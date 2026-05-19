#ifndef BIOEDGE_API_H
#define BIOEDGE_API_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

typedef enum {
    ALG_RET_OK                  = 0,
    ALG_RET_FAIL                = 1,
    ALG_RET_RESET               = 2,
    ALG_RET_NOT_INITIALISED     = 3,
    ALG_RET_BUFFER_FULL         = 4,
    ALG_RET_MEMORY_ERROR        = 5,
    ALG_RET_TIME_JUMP_BACK      = 6,
    ALG_RET_NOT_ENOUGH_DATA     = 7,
    ALG_RET_TIME_OVERFLOW       = 8,
    ALG_RET_SIGNALS_OUT_SYNC    = 9,
    ALG_RET_DATA_NOT_READY      = 10,
    ALG_RET_BUFFER_EMPTY        = 11,
    ALG_RET_BUFFER_OUT_OF_RANGE = 12,
    ALG_RET_PROFILE_ERROR       = 13,
    ALG_RET_ALG_NOT_AVAILABLE   = 14,
} bioedge_ret_e;

typedef enum {
    GENDER_NONE     = 0,
    GENDER_MALE     = 1,
    GENDER_FEMALE   = 2,
} userprofile_gender_e;

typedef enum {
    ACTIVITY_NONE       = 0, // Sleep or not worn
    ACTIVITY_SEDENTARY  = 1,
    ACTIVITY_LOW        = 2,
    ACTIVITY_MODERATE   = 3,
    ACTIVITY_ACTIVE     = 4,
} activity_minutes_bin_e;

typedef enum{
  SLEEP_UNKNOWN = 0,
  SLEEP_AWAKE   = 1,
  SLEEP_LIGHT   = 2,
  SLEEP_DEEP    = 3,
  SLEEP_REM     = 4,
} edge_sleep_stages_e;
/*******************************************/

typedef struct{
    uint8_t                 ageYears;
    userprofile_gender_e    gender;
}userprofile_s;

typedef struct{
    float meanRR;
    float minRR;
    float maxRR;
    float RMSSD;
    float SDNN;
    int32_t NN50;
    float pNN50;
    float triangularIndex;
    float HRVTI;
    float TINN;
    float SI;
    float outlierPercentage;
}hrvTimeDomainResults_s;

typedef struct{
    float SD1;
    float SD2;
    float SD2divSD1;
}hrvNonLinearResults_s;

typedef struct{
    float ulf;
    float vlf;
    float lf;
    float hf;
    float vhf;
    float LFHFRatio;
}hrvFreqDomainResults_s;

typedef struct{
    float activityLpf;
    float activityPenalisedLpf;
    bool firstSamplePushed;
    int64_t previousTimestampMs;
}activeMinutes_s;

bioedge_ret_e BIOEDGE_calculateBBIDerivedMetrics(uint16_t *bbiArrayMs, int64_t *timestampArrMs, int numberOfSamples,
    hrvTimeDomainResults_s *hrvTimeDomainResults, hrvNonLinearResults_s *hrvNonLinearResults,
    hrvFreqDomainResults_s *hrvFreqDomainResults, float *PNSScore, float *SNSScore,
    userprofile_s userprofile);

void BIOEDGE_activeMinutesInitialise(activeMinutes_s *activeMinutesHandle);
void BIOEDGE_activeMinutesAddActivityPacket(activeMinutes_s *activeMinutesHandle, int32_t activityPacket, int64_t timestampMs, activity_minutes_bin_e *activeMinuteNoExercise, activity_minutes_bin_e *activeMinuteExercise);


void BIOEDGE_sleepSetActivityBasedSleepThresholds(int32_t lowThresh, int32_t highThresh);
bioedge_ret_e BIOEDGE_sleepPushPhilips(int32_t *sleepStages, int32_t numberOfEpocs, int32_t sessionStartTimeUnixSeconds);
bioedge_ret_e BIOEDGE_sleepProcess(edge_sleep_stages_e *sleepResults, int64_t *sleepStagesTimestampMs, int32_t *numberOfEpocs);
bioedge_ret_e BIOEDGE_sleepPushActivityPackets(int32_t *activityPacket, int64_t *activityPacketTimestampMs, int32_t activityPacketLength, edge_sleep_stages_e *sleepResult);
int32_t BIOEDGE_sleepGetNumberOfStages(void);
void BIOEDGE_sleepDestroy(void);

bioedge_ret_e BIOEDGE_hrGraphFromBBI(uint16_t *bbiArrayMs, int64_t *bbiTimestampMs, float *hrReturn, int32_t arrayLength);

void BIOEDGE_getVersion(uint16_t *major, uint16_t *minor, uint16_t *patch);
int32_t BIOEDGE_getPartnerNumber(void);
#endif
