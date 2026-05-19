#ifndef ANS_H
#define ANS_H

#include "common.h"
#include "bioedge_math.h"

bioedge_ret_e ANS_calculatePNS(userprofile_s userprofile, hrvTimeDomainResults_s hrvTimeDomainResults, hrvNonLinearResults_s hrvNonLinearResults, float *resultPNS);
bioedge_ret_e ANS_calculateSNS(userprofile_s userprofile, hrvTimeDomainResults_s hrvTimeDomainResults, hrvNonLinearResults_s hrvNonLinearResults, float *resultSNS);
#endif
