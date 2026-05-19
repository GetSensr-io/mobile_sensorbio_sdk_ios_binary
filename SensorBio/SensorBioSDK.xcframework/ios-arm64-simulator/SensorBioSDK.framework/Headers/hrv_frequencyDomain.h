#ifndef HRV_FREQD_H
#define HRV_FREQD_H

#include "common.h"
#include "bioedge_math.h"
#include "circular_buffer.h"
#include "bbi_preprocessing.h"

bioedge_ret_e HRVFD_calculateMetrics(circbuff_s *bbiCircBuff, uint32_t length, hrvFreqDomainResults_s *hrvFreqDomainResults);

#endif
