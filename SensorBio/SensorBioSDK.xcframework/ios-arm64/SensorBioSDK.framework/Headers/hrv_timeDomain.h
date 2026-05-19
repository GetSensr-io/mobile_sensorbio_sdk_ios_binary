#ifndef HRV_TIMED_H
#define HRV_TIMED_H

#include "common.h"
#include "bioedge_math.h"
#include "circular_buffer.h"

void HRVTD_minMaxMean(circbuff_s *bbiCircBuff, uint32_t numberOfSamples, float *minBBI, float *maxBBI, float *meanBBI);
float HRVTD_rmssd(circbuff_s *bbiCircBuff, float *bbiDetrendedBuffer, uint32_t numberOfSamples);
float calculateSDNN(circbuff_s *bbiCircBuff, float *bbiDetrendedBuffer, uint32_t numberOfSamples);
void calculatepNNX(circbuff_s *bbiCircBuff, float *bbiDetrendedBuffer, float diffX, uint32_t numberOfSamples, int32_t *nnx, float *pnnx);

#endif
