/*
 * Amiigo common definitions
 *
 * @date Jan 4, 2014
 * @author: dashesy
 */

#ifndef AMIIGO_COMMON_H
#define AMIIGO_COMMON_H

#include <stdio.h>

#define AMERR_WARN_BADPACKET          2 // Invalid packet received but recovered
#define AMERR_WARN_BADREBOOT          1 // Unrecoverable reboot, please give me data to look at
#define AMERR_SUCCESS                 0
#define AMERR_UNKNOWN                -1 // Unknown error
#define AMERR_INVALID_PARAM          -2 // Invalid input parameter
#define AMERR_UNPROCESED_INPUT       -3 // Some input not processed due to error
#define AMERR_INVALID_PACKET         -4 // Invalid or unknown packet
#define AMERR_INVALID_CMP_PACKET     -5 // Invalid compressed packet
#define AMERR_UNEXPECTED_CMP_PACKET  -6 // Unexpected compressed packet
#define AMERR_SHORT_STREAM           -7 // Empty input stream or too few logs of interest
#define AMERR_ALLOC_OUTPUT           -8 // Not enough room allocated for output
#define AMERR_INPUT_FILE             -9 // File not found or cannot be accessed as input
#define AMERR_OUTPUT_FILE           -10 // File cannot be accessed as output

#define AMERR_EHSAN                 -88 // Please give me data to look at


#define MAX_SAMPLE_RATE    50 // Maximum valid sample rate

// common macros for use
#define MIN_OF(x, y) ((x) < (y) ? (x) : (y))
#define MIN_OF3(x, y, z) MIN_OF(MIN_OF(x, y), z)
#define MAX_OF(x, y) ((x) < (y) ? (y) : (x))
#define MAX_OF3(x, y, z) MAX_OF(MAX_OF(x, y), z)
#define SQR_OF(x) ((x)*(x))
#define CUBE_OF(x) ((x)*(x)*(x))


// Compute the packet length using packet header
int get_packet_len(const char * pPayload);

// Read a single packet from binary file
int read_packet(FILE * fp, char * buf, int * plen);

#endif // include guard
