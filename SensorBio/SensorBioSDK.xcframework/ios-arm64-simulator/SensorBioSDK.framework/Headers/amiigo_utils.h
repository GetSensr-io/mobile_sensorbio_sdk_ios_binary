/*
 * Amiigo sensor utility functions
 *
 * @date Jan 4, 2014
 * @author: dashesy
 */

#ifndef AMIIGO_UTILS_H
#define AMIIGO_UTILS_H

#include "amidefs.h"

// Index of each device in the API
#define AMIIGO_DEVICE_WRISTBAND  0
#define AMIIGO_DEVICE_SHOEPOD    1


/******************************************************************************/
typedef struct _util_chunk {
    float activity_level; // Net acceleration of the chunk
    // For each device, start and end byte in input buffer
    int32 byte_w0, byte_w1;
    int32 byte_s0, byte_s1;
    // acceleration indices of the boundary
    int32 accel0, accel1;
} PACKED util_chunk_t;

/******************************************************************************/
typedef struct _util_data_desc {
    int sample_rate;    // Sample rate of data in Hz
    int accel_count[2]; // Number of accel data
} util_data_desc_t;

/******************************************************************************/
// Count number of accelerometer log packets
// Inputs:
//   pInBuf   - input buffer; byte array of decompressed packets (order is important)
//   pnInLen  - length of input buffer (in bytes) to be processed
// Outputs:
//   Returns the error code (0 for success, positive for warning, negative for error)
//   pnInLen  - number of bytes processed from input stream.
//              if changed, invalid (or compressed) packet or stream is in the input.
//   pnCount  - number of accelerometer data in the stream
int util_accel_count(const char * pInBuf, int * pnInLen, int * pnCount);

/******************************************************************************/
// Activity separation into chunks, and optionally return net accelerations
// Inputs:
//   pDesc         - data description.
//                    pDesc->accel_count can specify any number of accel to process
//                    after that, if there are more accel data AMERR_UNPROCESED_INPUT will return
//   pInBuf[2]     - device input buffers; byte array of decompressed packes (order is important)
//   pnInLen[2]    - length of input buffer (in bytes) to be processed
//   pNetAccel[2]  - Null or Array allocated for data_desc.accel_count elements
//   pChunks       - Array allocated for pnChunksCount elements
//   pnChunksCount - number of allocated chunks in pChunks
// Outputs:
//   Returns the error code (0 for success, positive for warning, negative for error)
//   pDesc         - will be updated with number of accel data processed
//   pnInLen[2]    - number of bytes processed from input stream.
//   pNetAccel[2]  - If not Null, Array with net acceleration data
//   pChunks       - Array with pnChunksCount valid elements
//                   Each chunk will be an activity region.
//   pnChunksCount - number of valid chunks in pChunks
// Notes:
//   1- If AMERR_UNPROCESED_INPUT error is returned, pnInLen is changed
//   2- Allocate for the maximum acceptable number of chunks.
//      For every 15 seconds worth of accel data, there could be at most 1 active chunk.
//      Allocate for "data_desc.accel_count / (15 * data_desc.sample_rate) + 1" elements.
//   3- Inactive regions can be deducted from what pChunks excludes.
//      Using the fact that chunks byte boundaries in pChunks are in increasing order.
int util_stream_chunk(util_data_desc_t * pDesc, const char * pInBuf[2], int * pnInLen[2],
        float * pNetAccel[2], util_chunk_t * pChunks, int * pnChunksCount);

/******************************************************************************/
// Count number of accelerometer log packets in a file
// Inputs:
//  szInName    - input file name
// Outputs:
//  Returns the error code (0 for success, positive for warning, negative for error)
//  pnCount  - number of accelerometer data in the file
int util_file_accel_count(const char * szInName, int * pnCount);

/******************************************************************************/
// Count number of reboots in a file
// Inputs:
//   szInName - input file name; binary sensor data ofraw packes (order is important)
// Outputs:
//   Returns the error code (0 for success, positive for warning, negative for error)
//   pnCount  - number of reboots in the file
int util_file_reboot_count(const char * szInName, int * pnCount);

/******************************************************************************/
// Count number of certain logs in a file
// Inputs:
//   szInName - input file name; binary sensor data ofraw packes (order is important)
// Outputs:
//   Returns the error code (0 for success, positive for warning, negative for error)
//   pnAccelCount  - (optional) number of accelerometer data in the file
//   pnRebootCount - (optional) number of reboots in the file
int util_file_count(const char * szInName, int * pnAccelCount, int * pnRebootCount);

/******************************************************************************/
// Read accelerometer data from a raw file
// Inputs:
//  szInName        - input file name; must be (extended) ascii
//  accel_count     - number of accel points to read
//  num_axis        - number of axis in the data
//  raw_accel       - pointer to the raw accel matrix
// Outputs:
//  Returns the error code (0 for success, positive for warning, negative for error)
int util_file_accel_read(const char * szInName, int8 *raw_accel, int accel_count, int num_axis);

/******************************************************************************/
typedef struct _util_file_desc {
    const char * szInName; // input file name; must be (extended) ascii
    int sample_rate;       // Sample rate of data in Hz
    int start_time_ms;     // Relative start times in milliseconds (relative callback time)
} util_file_desc_t;

/******************************************************************************/
typedef struct _util_sync_stats {
    int in_accel_count;     // number of accelerometer points in the input file
    int out_accel_count;    // number of accelerometer points in the output files
    int reboot_count;       // Total number of reboots
    int cold_reboot_count;  // Number of cold reboots
    int bad_reboot_count;   // Number of ill-conditioned reboots that tried to recover from
    int crap_added;         // crap added due to reboot
    int crap_removed;       // crap removed due to reboot
    int inorder_timestamps; // number of unorderly timestamps
} util_sync_stats_t;

/******************************************************************************/
typedef enum _engine_mode{
    ENGINE_MODE_PEDOMETER,
    ENGINE_MODE_CYCLING,
    ENGINE_MODE_RUNNING,
} engine_mode_t;
/******************************************************************************/
typedef enum _user_sex{
    USER_SEX_UNSPECIFIED,
    USER_SEX_MALE,
    USER_SEX_FEMALE,
} user_sex_t;

/******************************************************************************/
typedef struct _util_engine_info {
    int start_millisecond;  // the starting millisecond relative to minute mark
    int start_minute_count; // step/cadence count of the starting minute from previous calculations
    int start_minute_active;// active seconds of the starting minute from previous calculations
    int device_type;        // device type one of {AMIGO_DEVICE_WRISTBAND, AMIGO_DEVICE_SHOEPOD}
    engine_mode_t mode;     // engine mode
} util_engine_info_t;

/******************************************************************************/
typedef struct _util_accel_data {
    int8 x;
    int8 y;
    int8 z;
} util_accel_data_t;

/******************************************************************************/
typedef struct _engine_pedometer_full_stats {
    // Per minute Stats
    int steps;
    int active_seconds;
    float distance; // in meters
    float walk_cals;
} engine_pedometer_full_stats_t;

/******************************************************************************/
typedef struct _amiigo_user_info {
    int age;                // user age
    int weight;             // user weight in kg
    int height;             // user height in cm
    user_sex_t sex;         // user sex
    int rhr;                // user resting heart rate, 0 if unknown
    int walk_stride;        // user walking stride length in cm, 0 if unknown
    int run_stride;         // user walking stride length in cm, 0 if unknown
    float cff;              // used by the engine function, leave null
    float bmr;              // used by the engine function, leave null
} amiigo_user_info_t;

/******************************************************************************/
// Synchronize the data using inline timestamp and accel log count
// Inputs:
//   pDesc         - file description.
// Outputs:
//   Returns the error code (0 for success, positive for warning, negative for error)
//   On success will create an output file, same as input but with added ".syn"
//
//   pStats   - stats on the sync operation
// Notes:
//   1-  pDesc->start_time_ms is ignored by this function
int util_file_sync(util_file_desc_t * pDesc, util_sync_stats_t * pStats);

/******************************************************************************/
// Activity separation into chunk files
// Inputs:
//   pDesc[]         - file descriptions
//   nCount          - length of pDesc (can be 1 or 2)
// Outputs:
//   Returns the error code (0 for success, positive for warning, negative for error)
//   On success will create multiple output files:
//    same as input but appended with ".ch<N>.<L>.<O>.<E>"
//    N is chunk number starting at 0
//    L is activity level of the chunk; 0 for inactive, 1 for inactive with pulse
//    O sample offset ** use this to adjust start_timestamp of the chunk **
//    E number of useful samples ** use this and <O> to adjust end_timestamp of the chunk **
//
//   pnChunksCount - number of chunked files created
//
// Notes:
//   1- If pulse session is in progress, chunk will continue to be inclusive
//       but that accel data will not be counted
//   2- If start_time_ms is given, associated initial samples are ignored in output
//   3- One evice may have an extra chunk, if the lengths are too different.
//       extra chunk can be used if there is pulse data in it, or it can be used to
//       further calls to this function, but every time this happens it hurts the synchronization.
int util_file_chunk(util_data_desc_t  pDesc[], int nCount, int * pnChunksCount);

/******************************************************************************/
// Analyze the recorded data by the WED device for steps and/or activities
// Inputs:
//  pDesc           - file description.
//  pInfo           - information about the current file
//  pUser           - information about the user
//  step_locs       - for debug purposes, should be NULL
// Outputs:
//  Returns the error code (0 for success, positive for warning, negative for error)
//  On success will create an output file, same as input but with added ".results"
//  The output file first line will contain the steps taken for each "minute of the day"
//  during the file period and the next lines would be different results based on engine mode
//  Step counts are separated with a ","
// Notes:
//   1-  pDesc->start_time_ms is ignored by this function
int util_amiigo_engine(const util_file_desc_t *pDesc, const util_engine_info_t *pInfo, amiigo_user_info_t *pUser, int8 *step_locs);

/******************************************************************************/
// Analyze the recorded data by the WED device for steps and/or activities
// Inputs:
//  raw_accel       - pointer to the raw data in form of (num_axis * num_points)
//  accel_count     - number of points in the data
//  sample_rate     - data sample rate in Hz
//  step_bins       - for steps this should be (2 * num_mins) where num_mins are the number of day minutes in that period
//                    array where the results would be recorded
//                    first row would be the steps per minutes and second row would be the active seconds
//                    for other activities it should be (4 * num_mins) where the first two rows would be for steps
//                    and the next two rows would be for reps and active_seconds of those activities
//  step_bins_length- number of columns in step_bins
//  step_bins_width - number of rows in step_bins
//  pInfo           - information about the session
//  step_locs       - for debug purposes, should be NULL otherwise
// Outputs:
//  Returns the error code (0 for success, positive for warning, negative for error)
//  On success will populate the step_bins with the results as stated above
// Notes:
//   1-  pDesc->start_time_ms is ignored by this function
int util_engine_analyze_raw(const int8 *raw_accel, const int accel_count,
        const int sample_rate, int *step_bins, const int step_bins_length,
        const int step_bins_width, const util_engine_info_t *pInfo, int8 *step_locs);

/******************************************************************************/
// Analyze the recorded data by the WED device for steps and/or activities
// Inputs:
//  raw_struct       - pointer to an array of accel structs
//  accel_count     - number of points in the data
//  sample_rate     - data sample rate in Hz
//  stats           - pointer to an array of stats structs, the length should be number of day minutes in that period
//  stats_length    - number of stats structs
//  pInfo           - information about the session
// Outputs:
//  Returns the error code (0 for success, positive for warning, negative for error)
//  On success will populate the stats with the results
int util_engine_analyze_raw_struct(const util_accel_data_t *raw_struct, const int accel_count,
        const int sample_rate, engine_pedometer_full_stats_t *stats, const int stats_length,
        const util_engine_info_t *pInfo, const amiigo_user_info_t *pUser);

#endif // include guard
