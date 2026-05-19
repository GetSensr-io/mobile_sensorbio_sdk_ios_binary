/*
 * High-level implementation of Amiigo algorithm library.
 *
 * @date Jan 5, 2014
 * @author: dashesy
 */

#ifndef AMIIGO_ALG_H
#define AMIIGO_ALG_H

#include "amiigo_common.h"


#define MIN_ACTIVE_TIME    10
#define MIN_REST_TIME      5
#define WINDOWING_FACTOR   1
#define MAX_WINDOW_LEN (MIN_ACTIVE_TIME * MAX_SAMPLE_RATE)
#define WINDOW_LEN_OF(sample_rate) (MAX_WINDOW_LEN * sample_rate / (MAX_SAMPLE_RATE * WINDOWING_FACTOR))
#define WINDOW_INTERVAL_OF(sample_rate) (MAX_SAMPLE_RATE * WINDOWING_FACTOR / sample_rate)

#define BASE_NET_ACCEL   64     // Base net acceleration
#define THRESHOLD_ACTIVE 5      // Activity threshold
#define MAX_REP_PERIOD 5        // Maximum period of each rep in seconds

// Low pass filter the signal in place
// Inputs:
//   pSig        - input signal array
//   count       - length of both input and output
//   sample_rate - sample rate in Hz
// Outputs:
//   pInSig      - low-pass filtered signal
void lpf_signal_1df_i(float * pSig, int count, int sample_rate);

// Smooth signal by windowing
// Inputs:
//   pInSig      - input signal array
//   count       - length of both input and output
//   sample_rate - sample rate in Hz
// Outputs:
//   pOutSig     - smoothed out signal array
void smooth_signal_1df(const float * pInSig, float * pOutSig, int count, int sample_rate);

// Find energy of signal
// Inputs:
//   pSig        - input signal array
//   count       - length of signal
//   sample_rate - sample rate in Hz
// Outputs:
//   pOutSig     - signal energy
void energy_signal_1df(const float * pInSig, float * pOutSig, int count, int sample_rate);

// Find energy of signal in place
// Inputs:
//   pSig        - input signal array
//   count       - length of signal
//   sample_rate - sample rate in Hz
// Outputs:
//   pSig        - signal energy
void energy_signal_1df_i(float * pSig, int count, int sample_rate);

#endif // include guard
