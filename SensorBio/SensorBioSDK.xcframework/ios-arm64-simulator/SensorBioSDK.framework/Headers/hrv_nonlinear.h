#ifndef HRV_NONLIN_H
#define HRV_NONLIN_H

#include "common.h"
#include "bioedge_math.h"
#include "circular_buffer.h"

void HRVNL_sd1sd2(circbuff_s *bbiCircBuff, uint32_t numberOfSamples, float *sd1, float *sd2);
#endif
