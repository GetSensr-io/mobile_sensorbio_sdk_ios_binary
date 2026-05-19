/*
 * Amiigo in-app engine definitions and thresholds
 *
 * @date January 28, 2015
 * @author: k1
 */
#include "amiigo_utils.h"
#ifndef AMIIGO_ENGINE_H
#define AMIIGO_ENGINE_H

///////////////////////////////////////////////////////////////////////////////
// Common Engine Values
#define MIN_RATE_ENG            10  // minimum sample rate for the engine (Hz)
#define MIN_DURATION_ENG        30  // minimum time span for engine in seconds
#define NUM_AXIS_ENG            3   // number of axis in the data
#define G_VALUE_ENG             64  // the value of g (gravity) in the WED
#define MAX_BUFFER_SIZE_ENG     20  // maximum buffer size to buffer reps

///////////////////////////////////////////////////////////////////////////////
// Pedometer Settings
#define MIN_PACE_PED            60  // minimum pace supported for pedometer
#define MAX_PACE_PED            300 // maximum pace supported by human foot
#define MAX_INACTIVE_PED        3   // maximum inactive time to cut the step counting
#define MIN_STEP_COUNT_PED      7   // minimum number of steps to start counting
#define MIN_ACCEL_RANGE_PED_Z   10  // minimum accel range for detecting bad-z
#define MAX_WALKING_PACE        140 // maximum pace to be considered as walking

// Wristband
#define MIN_ACTIVE_TIME_PED_W   4   // minimum seconds of active time to count steps
#define MIN_VARIATION_PED_W     80  // minimum average accel variation per second to be active
#define MIN_DELTA_PED_W         35  // minimum delta of max and min for being active
#define WINDOW_TIME_PED_W       2   // window length in seconds for calculating stats for wristband
#define MAX_LAG_PED_W           3   // how many window_time to consider for posture change
#define POS_THRESH_PED_W        50  // threshold for detecting a posture change
#define MIN_ACCEL_RANGE_PED_W   5   // minimum accel drop to consider step
#define MAX_FALL_PERIOD_PED_W   1   // maximum period of accel drop to consider step

// Shoepod
#define WINDOW_TIME_PED_S       5   // window length in seconds for calculating stats for shoepod
#define MIN_BIG_DELTA_PED_S     300 // minimum accumulated range in the window for being extremely active
#define MIN_SMALL_DELTA_PED_S   100 // minimum accumulated range in the window for being moderately active
#define MIN_ACCEL_RANGE_PED_S   30  // minimum accel drop to consider step
#define MAX_FALL_PERIOD_PED_S   1   // maximum period of accel drop to consider step
#define MIN_STEP_NET_S         -10  // minimum value of net to consider cycling

///////////////////////////////////////////////////////////////////////////////
// Cycling Settings
#define MIN_PACE_CYC            30  // minimum pace supported for pedometer
#define MAX_PACE_CYC            250 // maximum pace supported by human foot
#define MAX_INACTIVE_CYC        3   // maximum inactive time to cut the step counting
#define MIN_STEP_COUNT_CYC      10  // minimum number of steps to start counting
#define MIN_PEDAL_COUNT_CYC     4   // minimum number of steps to start counting
#define MIN_ACCEL_RANGE_CYC_Z   10  // minimum accel range for detecting bad-z
#define WINDOW_TIME_CYC_S       2   // window length in seconds for calculating stats for shoepod
#define MIN_VARIATION_CYC_S     70  // minimum average accel variation per second to be active
#define MIN_DELTA_CYC_S         80  // minimum delta of max and min for being active
#define MIN_ACTIVE_TIME_CYC     4   // minimum seconds of active time to count pedals
#define MIN_PEDAL_NET_S        -10  // minimum value of net to consider cycling
#define MIN_ACCEL_RANGE_CYC_S   60  // minimum net_square to drop to consider pedaling
#define MAX_LAG_CYC_S           3   // how many window_time to consider for posture change
#define POS_THRESH_CYC_S        50  // threshold for detecting a posture change
#define MAX_FALL_PERIOD_CYC     2   // maximum period of accel drop to consider step
#define MIN_WALK_TIME_CYC       15  // minimum walking time in seconds to break cycling in report

///////////////////////////////////////////////////////////////////////////////
// User settings
#define USER_DEFAULT_AGE        36  // default value for user age
#define USER_DEFAULT_WEIGHT     80  // default user weight in kg
#define USER_DEFAULT_HEIGHT     177 // default user height in kg
#define USER_DEFAULT_RHR        70  // default user resting heart rate
#define USER_MIN_RHR            40  // min user resting heart rate
#define USER_MAX_RHR            200 // max user resting heart rate

///////////////////////////////////////////////////////////////////////////////
// Negative axis indices used for showing activities other than walking
#define NON_ACTIVE_INDEX        -1  // showing non_active
#define IN_CYCLING_INDEX        -2  // engine classified the region as cycling
#define IN_CYCLING_BADZ_INDEX   -3  // engine classified cycling because of bad-z

///////////////////////////////////////////////////////////////////////////////
// Threshold structures
///////////////////////////////////////////////////////////////////////////////

typedef struct _engine_thresholds_delta {
    int big_delta;
    int small_delta;
    int z_accel_range;
} engine_thresholds_delta_t;

typedef struct _engine_thresholds_posture {
    int min_variations;
    int min_delta;
    int min_active_time;
    int max_lag;
    int min_posture_diff;
} engine_thresholds_posture_t;

typedef struct _engine_thresholds_counter {
    int min_pace;
    int max_pace;
    int max_inactive;
    int max_min_offset;
    int min_net_square;
    int min_accel_range;
    int min_offset;
    int z_accel_range;
    int min_rep_count;
} engine_thresholds_counter_t;

typedef enum _activity_names{
    ACTIVITY_TRIVIAL,
    ACTIVITY_WALKING,
    ACTIVITY_RUNNING,
    ACTIVITY_CYCLING,
} activity_names_t;

typedef struct _engine_pedometer_stats {
    float distance; // in meters
    float walk_cals;
} engine_pedometer_stats_t;

typedef struct _engine_meta_info {
    float total_cals;
    float total_distance;
    int total_steps;
    int total_active;
    int total_points;
} engine_meta_info_t;

void calculate_steps_stats(engine_pedometer_stats_t *ped_stats, const amiigo_user_info_t *pUser,
        const int step_count, const int active_seconds, int round_numbers);
#endif // include guard
