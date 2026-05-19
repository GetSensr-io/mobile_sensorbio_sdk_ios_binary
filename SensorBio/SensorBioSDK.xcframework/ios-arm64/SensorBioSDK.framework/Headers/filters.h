#ifndef FILTERS_H
#define FILTERS_H

#include "common.h"
#include "circular_buffer.h"
#include "bbi_preprocessing.h"
#include "bioedge_math.h"

float iirFilter(const float input, const float *filt_coef_a, const float *filt_coef_b,
                     const uint8_t filt_order,   float *filt_input_buff,   float *filt_output_buff,
                     uint8_t *buffer_index);
void DSP_bbiDetrendingFilter(circbuff_s *bbiCircBuff, float *bbiDetrenededArrayMs, uint32_t bufferSize);

#endif
