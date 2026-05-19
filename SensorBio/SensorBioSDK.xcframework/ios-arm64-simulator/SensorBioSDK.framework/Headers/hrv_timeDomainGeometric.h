#ifndef HRV_TIMED_GEO_H
#define HRV_TIMED_GEO_H

#include "common.h"
#include "bioedge_math.h"
#include "circular_buffer.h"

float HRVTDGEO_HRVTI(circbuff_s *bbiCircBuff, float *bbiDetrendedBuffer, uint32_t numberOfSamples);
float HRVTDGEO_SI(circbuff_s *bbiCircBuff, float *bbiDetrendedBuffer, uint32_t numberOfSamples);
#endif
