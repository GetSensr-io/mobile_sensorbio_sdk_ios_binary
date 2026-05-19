#ifndef CIRCBUFFER_H
#define CIRCBUFFER_H

#include "common.h"
#include "bioedge_api.h"

typedef struct{
    uint8_t     *buffer;
    uint8_t     elementSize;
    uint32_t    head;
    uint32_t    tail;
    uint32_t    length;
    uint32_t    count;
    volatile bool full_status;
}circbuff_s;

bool CIRCBUFF_availableSpace(circbuff_s *circbuff);
void CIRCBUFF_reset(circbuff_s *circbuff);
bioedge_ret_e CIRCBUFF_push(circbuff_s *circbuff, uint8_t *data);
bioedge_ret_e CIRCBUFF_pop(circbuff_s *circbuff, uint8_t *data);
bioedge_ret_e CIRCBUFF_peek(circbuff_s *circbuff, uint8_t *data, uint32_t index);
bioedge_ret_e CIRCBUFF_pushAtIndex(circbuff_s *circbuff, uint8_t *data, uint32_t index);

#endif
