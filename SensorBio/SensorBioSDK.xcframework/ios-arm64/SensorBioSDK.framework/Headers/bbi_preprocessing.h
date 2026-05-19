#ifndef BBIPREP_API_H
#define BBIPREP_API_H

#include <stdint.h>
#include <stdbool.h>
#include "bioedge_api.h"
#include "circular_buffer.h"

typedef enum {
    meas_good           = 0,
    meas_interpolate    = 1,
    meas_movingAverage  = 2,
    meas_missing        = 3,
} bbi_measurementTag_e;

typedef struct{
    uint16_t    bbi_ms;
    uint64_t    timestampMs;
    uint8_t     measurementTag;
    float       runningMean_bpm;
}bbibuffer_s;

#define BEAT_CORRECTION_SCALE 2

void BBIPREP_initialise(void);
bioedge_ret_e BBIPREP_addSamples(uint16_t *bbiArrayMs, uint64_t *timestampArrMs, int numberOfSamples);
void BBIPREP_deInitialise(void);

bioedge_ret_e BBIPROC_calculateTimeDomainFeatures(hrvTimeDomainResults_s *hrvTimeDomainResults);
bioedge_ret_e BBIPROC_calculateNonlinearFeatures(hrvNonLinearResults_s *hrvNonLinearResults);
bioedge_ret_e BBIPROC_calculateFrequencyDomainFeatures(hrvFreqDomainResults_s *hrvFreqDomainResults);

void BBIOUTLIER_addSamples(uint16_t *bbiArrayMs, uint64_t *timestampArrMs, int numberOfSamples, circbuff_s *bbiCircBuff);

#endif
